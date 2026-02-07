import os
import termios
import tty
import select
import time
import fcntl

DEV = '/dev/ttyUSB0'

def run_interaction(fd):
    # Set non-blocking
    fl = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)

    def write_all(data):
        os.write(fd, data)
        time.sleep(0.5)

    def read_all(timeout=1.0):
        res = b""
        start = time.time()
        while time.time() - start < timeout:
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                try:
                    chunk = os.read(fd, 4096)
                    if chunk:
                        res += chunk
                        start = time.time()
                except OSError:
                    break
        return res.decode(errors='replace')

    print("--- Sending Enter ---")
    write_all(b"\n")
    out = read_all()
    print(f"Output: {repr(out)}")

    if "login:" in out.lower():
        print("--- Sending Username ---")
        write_all(b"root\n")
        out = read_all()
        print(f"Output: {repr(out)}")

    if "password:" in out.lower() or "Password:" in out:
        print("--- Sending Password ---")
        write_all(b"root\n")
        out = read_all()
        print(f"Output: {repr(out)}")

    print("--- Running commands ---")
    for cmd in ["uname -a", "lsblk", "df -h"]:
        print(f"\nExecuting: {cmd}")
        write_all(cmd.encode() + b"\n")
        print(read_all(timeout=2.0))

def main():
    if not os.path.exists(DEV):
        print(f"Error: {DEV} not found.")
        return

    fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY)
    try:
        attrs = termios.tcgetattr(fd)
        speed = getattr(termios, 'B1500000', 4098) 
        attrs[4] = speed
        attrs[5] = speed
        attrs[0] = 0
        attrs[1] = 0
        attrs[2] &= ~termios.CSIZE
        attrs[2] |= termios.CS8
        attrs[2] &= ~termios.CRTSCTS
        attrs[3] = 0
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        termios.tcflush(fd, termios.TCIOFLUSH)

        run_interaction(fd)
    finally:
        os.close(fd)

if __name__ == "__main__":
    main()