import sys
import os
import time
import termios

DEV = '/dev/ttyUSB0'

def main():
    try:
        fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY)
        
        # Set Baudrate 1.5M
        attrs = termios.tcgetattr(fd)
        ispeed = termios.B1500000 if hasattr(termios, 'B1500000') else 4098
        ospeed = termios.B1500000 if hasattr(termios, 'B1500000') else 4098
        attrs[4] = ispeed
        attrs[5] = ospeed
        # Canonical mode off, Echo off to reduce noise
        # lflags
        attrs[3] &= ~(termios.ICANON | termios.ECHO | termios.ECHOE | termios.ISIG)
        # oflags
        attrs[1] &= ~termios.OPOST
        # iflags
        attrs[0] &= ~(termios.IXON | termios.IXOFF | termios.IXANY)
        
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        termios.tcflush(fd, termios.TCIOFLUSH)

        # Send command
        cmd = b'
df -h /
'
        os.write(fd, cmd)
        
        # Read loop
        time.sleep(0.5)
        output = b""
        while True:
            try:
                # Non-blocking read check? No, just simple blocking read with timeout logic if possible
                # But os.read is blocking. We rely on data being there.
                # Let's read a bit.
                chunk = os.read(fd, 1024)
                if not chunk: break
                output += chunk
                if b'#' in output or b'$' in output: # Prompt detected?
                     break
                if len(output) > 2000: break
            except OSError:
                break
            time.sleep(0.1)
            
        print("Output:
", output.decode(errors='replace'))
        
    except Exception as e:
        print(e)
    finally:
        if 'fd' in locals(): os.close(fd)

if __name__ == '__main__':
    main()
