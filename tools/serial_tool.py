import sys
import os
import time
import termios
import tty
import select
import fcntl

DEV = '/dev/ttyUSB0'
BAUD = 1500000

def set_nonblocking(fd):
    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

def main():
    try:
        fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    except Exception as e:
        print(f"Error opening {DEV}: {e}")
        return

    try:
        # Get current attributes
        attrs = termios.tcgetattr(fd)
        
        # Set input/output speed
        ispeed = termios.B1500000 if hasattr(termios, 'B1500000') else 4098
        ospeed = termios.B1500000 if hasattr(termios, 'B1500000') else 4098
        
        # Set raw mode
        tty.setraw(fd)
        
        # Update attributes
        attrs[2] &= ~termios.CRTSCTS # Disable hardware flow control
        attrs[4] = ispeed
        attrs[5] = ospeed
        termios.tcsetattr(fd, termios.TCSANOW, attrs)

        # Clear buffers
        termios.tcflush(fd, termios.TCIOFLUSH)

        # Send a newline to get a prompt
        os.write(fd, b'\n')
        time.sleep(0.5)

        cmds = [
            "ls -l /dev/mmcblk1*", # Check devs
            "mount /dev/mmcblk1p1 /boot",
            "ls -F /boot/",
            "echo 'PARTUUID=79E1528E-B733-49B3-9F4D-6C533713F4EE / ext4 defaults 0 1' > /etc/fstab",
            "echo 'PARTUUID=5B46A0C1-D804-466B-ACB5-E0587059946F /boot ext4 defaults 0 2' >> /etc/fstab",
            "cat /etc/fstab",
            "echo ', +' | sfdisk -N 2 --force /dev/mmcblk1", 
            "partprobe", # Try partprobe instead of reboot if possible
            "resize2fs /dev/mmcblk1p2",
            "df -h /"
        ]

        output_log = b""
        
        for cmd in cmds:
            print(f"Sending: {cmd}")
            # Robust write
            data_to_write = cmd.encode() + b'\n'
            while data_to_write:
                r, w, x = select.select([], [fd], [], 1.0)
                if w:
                    try:
                        n = os.write(fd, data_to_write)
                        data_to_write = data_to_write[n:]
                    except BlockingIOError:
                        continue
                else:
                    print("Timeout waiting to write")
                    break
            
            # Read loop with timeout
            start = time.time()
            while time.time() - start < 3.0: # 3 sec timeout per command
                r, w, x = select.select([fd], [], [], 0.1)
                if r:
                    chunk = os.read(fd, 1024)
                    if chunk:
                        output_log += chunk
            
            time.sleep(0.5)

        print("\n--- Device Output ---")
        print(output_log.decode(errors='replace'))

    finally:
        os.close(fd)

if __name__ == '__main__':
    main()