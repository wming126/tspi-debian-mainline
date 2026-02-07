import sys
import os
import time
import termios
import select

DEV = '/dev/ttyUSB0'

def send_cmd(fd, cmd):
    full_cmd = cmd.encode() + b'\r\n'
    os.write(fd, full_cmd)
    time.sleep(0.5)
    
def read_until_prompt(fd, timeout=2):
    output = b""
    start = time.time()
    while time.time() - start < timeout:
        r, w, x = select.select([fd], [], [], 0.1)
        if r:
            chunk = os.read(fd, 4096)
            if not chunk: break
            output += chunk
    return output.decode(errors='replace')

def main():
    fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY)
    try:
        # Serial setup (1.5M baud)
        attrs = termios.tcgetattr(fd)
        ispeed = termios.B1500000 if hasattr(termios, 'B1500000') else 4098
        ospeed = termios.B1500000 if hasattr(termios, 'B1500000') else 4098
        attrs[4] = ispeed
        attrs[5] = ospeed
        attrs[3] &= ~(termios.ICANON | termios.ECHO) # No echo
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        termios.tcflush(fd, termios.TCIOFLUSH)

        # Login checks (assuming already logged in from previous turn, but sending Enter ensures prompt)
        send_cmd(fd, "") 
        print(read_until_prompt(fd))

        # Check Environment
        cmds = [
            "modprobe libcomposite",
            "ls /sys/class/udc",
            "mount | grep configfs"
        ]

        for cmd in cmds:
            print(f"Sending: {cmd}")
            send_cmd(fd, cmd)
            print(read_until_prompt(fd))

    finally:
        os.close(fd)

if __name__ == '__main__':
    main()
