#!/usr/bin/env python3
"""End-to-end check of the patched mosh-bridged: connect time to prompt, keystroke echo,
then kill the carrier ssh and verify (a) nothing is printed on the terminal, (b) the log has the reason."""
import os, pty, sys, time, select, fcntl, termios, struct, signal, subprocess, statistics, re
LOG=os.path.expanduser("~/Library/Logs/mosh-bridge.log"); mark=os.path.getsize(LOG)
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"]="xterm-256color"; os.environ["LFG_BRIDGE_QUIET_SECS"]="45"
    os.execvp("/Users/eugenechan/.local/bin/mosh-bridged", ["mosh-bridged","pro"])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
out=bytearray()
def wait_for(tok, timeout):
    end=time.time()+timeout
    while time.time()<end:
        r,_,_=select.select([fd],[],[],max(0.01,end-time.time()))
        if not r: continue
        try: d=os.read(fd,4096)
        except OSError: return None
        out.extend(d)
        if tok in out: return True
    return None
t0=time.time()
if not wait_for(b"\xe2\x9d\xaf", 60): print("no prompt in 60s"); os.kill(pid,signal.SIGKILL); sys.exit(1)
print(f"connect to prompt: {(time.time()-t0)*1000:.0f} ms")
os.write(fd, b"stty -echo; tr a-z A-Z\n"); time.sleep(1.5); wait_for(b"\x00",0.3)
rtts=[]
for i in range(30):
    tok=f"qz{i:02d}".encode(); t=time.time(); os.write(fd, tok+b"\n")
    if wait_for(tok.upper(),10) is None: print("timeout"); break
    rtts.append((time.time()-t)*1000); time.sleep(0.25)
rtts.sort(); print(f"mosh keystroke echo: n={len(rtts)} min={rtts[0]:.0f} p50={statistics.median(rtts):.0f} p90={rtts[int(len(rtts)*.9)-1]:.0f} max={rtts[-1]:.0f} ms")
# Kill the carrier ssh (child of our bridge) and watch the terminal for 8s.
bridge=subprocess.run(["pgrep","-f",f"mosh-bridge client"],capture_output=True,text=True).stdout.split()
kids=[]
for b in bridge:
    kids+=subprocess.run(["pgrep","-P",b],capture_output=True,text=True).stdout.split()
carriers=[k for k in kids if "ssh" in subprocess.run(["ps","-o","comm=","-p",k],capture_output=True,text=True).stdout]
print("carrier ssh pids:", carriers)
before=len(out)
for k in carriers: os.kill(int(k), signal.SIGKILL)
time.sleep(8)
wait_for(b"\x00",1.0)
tail=bytes(out[before:])
leak=re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[()][A-Z0-9]", b"", tail)
print("terminal bytes after kill (escape-stripped):", repr(leak[:200]))
# Type again: does the session still echo (carrier respawned)?
t=time.time(); os.write(fd,b"back\n"); ok=wait_for(b"BACK",30); print(f"echo after respawn: {'ok' if ok else 'FAILED'} ({(time.time()-t)*1000:.0f} ms)")
os.kill(pid,signal.SIGKILL)
print("--- log since start:"); print(open(LOG).read()[mark:])
