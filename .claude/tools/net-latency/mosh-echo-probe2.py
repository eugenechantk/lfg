#!/usr/bin/env python3
"""Keystroke round trip through mosh-bridged, login shell + `tr a-z A-Z`: type a lowercase line,
wait for its uppercase echo (only the server produces uppercase; prediction shows lowercase)."""
import os, pty, sys, time, select, fcntl, termios, struct, statistics, signal
target = sys.argv[1]; n = int(os.environ.get("N","30")); extra = sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"]="xterm-256color"
    os.execvp("/Users/eugenechan/.local/bin/mosh-bridged", ["mosh-bridged"]+extra+[target])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
def wait_for(tok, timeout):
    end=time.time()+timeout; buf=b""
    while time.time()<end:
        r,_,_=select.select([fd],[],[],max(0.01,end-time.time()))
        if not r: continue
        try: d=os.read(fd,4096)
        except OSError: return None
        buf+=d
        if tok in buf: return buf
    return None
t0=time.time()
if wait_for(b"\xe2\x9d\xaf", 40) is None: print("no shell prompt in 40s"); os.kill(pid,signal.SIGKILL); sys.exit(1)
print(f"connect to prompt: {(time.time()-t0)*1000:.0f} ms")
os.write(fd, b"stty -echo; tr a-z A-Z\n"); time.sleep(1.5); wait_for(b"\x00", 0.5)
rtts=[]
for i in range(n):
    tok=f"qz{i:02d}".encode(); t=time.time(); os.write(fd, tok+b"\n")
    if wait_for(tok.upper(),10) is None: print("timeout"); break
    rtts.append((time.time()-t)*1000); time.sleep(0.25)
os.kill(pid,signal.SIGKILL)
rtts.sort(); print(f"n={len(rtts)} min={rtts[0]:.0f} p50={statistics.median(rtts):.0f} p90={rtts[int(len(rtts)*.9)-1]:.0f} max={rtts[-1]:.0f} ms")
