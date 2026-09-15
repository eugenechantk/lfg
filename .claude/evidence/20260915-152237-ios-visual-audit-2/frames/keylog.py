import sys, time, tty, termios, os
# Raw-mode key logger: records host receive time of every byte arriving on the pty, echoes it.
log = open(sys.argv[1], "a", buffering=1)
fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
tty.setraw(fd)
try:
    while True:
        b = os.read(fd, 1)
        t = time.time()
        if not b or b == b"\x03" or b == b"q":
            break
        os.write(1, b)
        log.write(f"{t:.6f} {b!r}\n")
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
