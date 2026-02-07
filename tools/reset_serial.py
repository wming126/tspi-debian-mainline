import sys
import os
import time
import termios
import select

DEV = '/dev/ttyUSB0'

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

        print("Sending Break...")
        termios.tcsendbreak(fd, 0)
        time.sleep(0.5)
        
        print("Sending CRs...")
        for _ in range(5):
            os.write(fd, b'\r')
            time.sleep(0.2)
            
        # Read
        output = b""
        start = time.time()
        while time.time() - start < 3.0:
            r, w, x = select.select([fd], [], [], 0.1)
            if r:
                chunk = os.read(fd, 4096)
                if not chunk: break
                output += chunk
        
        print(f"Output: {repr(output)}")

    finally:
        os.close(fd)

if __name__ == '__main__':
    main()