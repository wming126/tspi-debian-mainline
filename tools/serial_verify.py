import sys
import os
import time
import termios
import tty
import select
import fcntl

DEV = '/dev/ttyUSB0'
BAUD = 1500000

def main():
    fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY) # Blocking mode for simplicity
    
    try:
        attrs = termios.tcgetattr(fd)
        ispeed = termios.B1500000 if hasattr(termios, 'B1500000') else 4098
        ospeed = termios.B1500000 if hasattr(termios, 'B1500000') else 4098
        tty.setraw(fd)
        attrs[2] &= ~termios.CRTSCTS
        attrs[4] = ispeed
        attrs[5] = ospeed
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        termios.tcflush(fd, termios.TCIOFLUSH)

        # Disable bracketed paste and echo to clean up output
        os.write(fd, b"bind 'set enable-bracketed-paste off'
")
        time.sleep(0.2)
        os.write(fd, b"stty -echo
") 
        time.sleep(0.2)

        cmds = [
            "mount /dev/mmcblk1p1 /boot",
            "cat /etc/fstab",
            "df -h /",
            "resize2fs /dev/mmcblk1p2",
            "df -h /"
        ]

        for cmd in cmds:
            print(f"CMD: {cmd}")
            os.write(fd, cmd.encode() + b'
')
            time.sleep(1.0) # Wait for execution
            
            # Read all available
            while True:
                r, w, x = select.select([fd], [], [], 0.1)
                if r:
                    try:
                        chunk = os.read(fd, 4096)
                        if not chunk: break
                        print(chunk.decode(errors='replace').replace('', ''), end='')
                    except OSError:
                        break
                else:
                    break
            print("
----------------")

    finally:
        os.close(fd)

if __name__ == '__main__':
    main()
