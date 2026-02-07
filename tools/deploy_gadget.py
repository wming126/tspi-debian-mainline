import sys
import os
import time
import termios
import select

DEV = '/dev/ttyUSB0'

def send_cmd(fd, cmd):
    os.write(fd, cmd.encode() + b'\r')
    time.sleep(0.1)

def read_response(fd, timeout=2.0):
    output = b""
    start = time.time()
    while time.time() - start < timeout:
        r, w, x = select.select([fd], [], [], 0.1)
        if r:
            chunk = os.read(fd, 4096)
            if not chunk: break
            output += chunk
    return output.decode(errors='replace')

def check_login(fd):
    # Wake up
    for _ in range(3):
        send_cmd(fd, "")
        time.sleep(0.5)
    
    out = read_response(fd, timeout=2.0)
    print(f"[Raw] {repr(out)}")
    
    if "login:" in out:
        print("Login prompt detected. Logging in...")
        send_cmd(fd, "root")
        time.sleep(1.0)
        out = read_response(fd, timeout=2.0)
        print(f"[Raw Password Check] {repr(out)}")
        
        if "Password:" in out:
            send_cmd(fd, "root")
            time.sleep(1.0)
            out = read_response(fd, timeout=2.0)
            
    # Verify we have a shell
    send_cmd(fd, "echo STATUS_CHECK")
    out = read_response(fd, timeout=2.0)
    print(f"[Shell Check] {repr(out)}")
    
    if "STATUS_CHECK" in out:
        print("Shell access confirmed.")
        return True
        
    return False

def main():
    fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY)
    try:
        attrs = termios.tcgetattr(fd)
        ispeed = termios.B1500000 if hasattr(termios, 'B1500000') else 4098
        ospeed = termios.B1500000 if hasattr(termios, 'B1500000') else 4098
        attrs[4] = ispeed
        attrs[5] = ospeed
        # Raw mode
        tty_mode = attrs
        tty_mode[3] &= ~(termios.ICANON | termios.ECHO)
        termios.tcsetattr(fd, termios.TCSANOW, tty_mode)
        termios.tcflush(fd, termios.TCIOFLUSH)

        # Ensure login
        if not check_login(fd):
            print("Could not get root prompt. Aborting.")
            return

        # Script to setup RNDIS
        script_lines = [
            "#!/bin/bash",
            "set -e",
            "modprobe libcomposite",
            "mkdir -p /sys/kernel/config/usb_gadget/g1",
            "cd /sys/kernel/config/usb_gadget/g1",
            "echo 0x1d6b > idVendor",
            "echo 0x0104 > idProduct",
            "echo 0x0100 > bcdDevice",
            "echo 0x0200 > bcdUSB",
            "mkdir -p strings/0x409",
            "echo 'fedcba9876543210' > strings/0x409/serialnumber",
            "echo 'Rockchip' > strings/0x409/manufacturer",
            "echo 'RK3566 RNDIS' > strings/0x409/product",
            "mkdir -p configs/c.1/strings/0x409",
            "echo 'RNDIS' > configs/c.1/strings/0x409/configuration",
            "echo 250 > configs/c.1/MaxPower",
            "mkdir -p functions/rndis.usb0",
            "ln -s functions/rndis.usb0 configs/c.1/",
            "UDC_NAME=$(ls /sys/class/udc | head -n 1)",
            "echo $UDC_NAME > UDC",
            "sleep 1",
            "ifconfig usb0 192.168.7.2 netmask 255.255.255.0 up",
            "echo 'USB Gadget RNDIS configured. IP: 192.168.7.2'"
        ]
        
        print("Writing setup script...")
        send_cmd(fd, "cat <<'EOF' > /root/setup_gadget.sh")
        time.sleep(0.5)
        
        for line in script_lines:
            send_cmd(fd, line)
        
        send_cmd(fd, "EOF")
        print(read_response(fd, timeout=2))

        print("Making script executable...")
        send_cmd(fd, "chmod +x /root/setup_gadget.sh")
        print(read_response(fd))

        print("Running script...")
        send_cmd(fd, "/root/setup_gadget.sh")
        print(read_response(fd, timeout=5))

        print("Checking IP...")
        send_cmd(fd, "ip a show usb0")
        print(read_response(fd))

    finally:
        os.close(fd)

if __name__ == '__main__':
    main()
