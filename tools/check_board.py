import os
import termios
import tty
import select
import time

DEV = '/dev/ttyUSB0'
BAUD = 1500000

def run_cmd(fd, cmd):
    os.write(fd, cmd.encode() + b'\n')
    time.sleep(1)
    output = b""
    while True:
        r, w, x = select.select([fd], [], [], 0.5)
        if r:
            chunk = os.read(fd, 4096)
            if chunk:
                output += chunk
            else:
                break
        else:
            break
    return output.decode(errors='replace')

def main():
    if not os.path.exists(DEV):
        print(f"Error: {DEV} not found.")
        return

    try:
        fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        attrs = termios.tcgetattr(fd)
        # Use numerical value for 1.5M baud if B1500000 is not defined in termios
        speed = getattr(termios, 'B1500000', 4098) 
        attrs[4] = speed
        attrs[5] = speed
        tty.setraw(fd)
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        termios.tcflush(fd, termios.TCIOFLUSH)

        print("Checking connection...")
        os.write(fd, b'\n')
        time.sleep(0.5)
        
        print("Running: uname -a")
        print(run_cmd(fd, "uname -a"))
        
        print("Running: lsblk")
        print(run_cmd(fd, "lsblk"))
        
        print("Running: df -h")
        print(run_cmd(fd, "df -h"))

    except Exception as e:
        print(f"Error: {e}")
    finally:
        if 'fd' in locals():
            os.close(fd)

if __name__ == '__main__':
    main()