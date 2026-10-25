#!/usr/bin/env python3
"""Time series: every 0.25s sample (a) ssh keystroke echo to TARGET, (b) ICMP RTT to the gateway,
(c) TCP connect RTT to the CF edge via en0. Print one line per second with the max of each."""
import os, subprocess, sys, time, socket, select, re, threading, statistics
target=sys.argv[1]; secs=int(sys.argv[2]); edge=sys.argv[3]; gw=sys.argv[4]; ip=sys.argv[5]
remote='exec python3 -u -c "import os\nwhile True:\n b=os.read(0,1)\n if not b: break\n os.write(1,b.upper())"'
p=subprocess.Popen(["ssh","-T","-o","BatchMode=yes",target,remote],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,bufsize=0)
p.stdin.write(b"a"); select.select([p.stdout],[],[],30); p.stdout.read(1)
ping=subprocess.Popen(["ping","-i","0.25",gw],stdout=subprocess.PIPE,text=True)
pings=[]
def rd():
    for l in ping.stdout:
        m=re.search(r"time=([\d.]+)",l)
        if m: pings.append((time.time(),float(m.group(1))))
threading.Thread(target=rd,daemon=True).start()
def tcp():
    s=socket.socket(); s.settimeout(3); t=time.time()
    try: s.bind((ip,0)); s.connect((edge,443)); return (time.time()-t)*1000
    except OSError: return -1
    finally: s.close()
t_end=time.time()+secs; sec=int(time.time()); echo=[]; tcps=[]
print("time      echo_p50 echo_max | gw_ping_max | en0->edge_tcp_max   (ms)")
while time.time()<t_end:
    t=time.time(); p.stdin.write(b"b"); r,_,_=select.select([p.stdout],[],[],10)
    if r: p.stdout.read(1); echo.append((time.time()-t)*1000)
    else: echo.append(10000)
    tcps.append(tcp())
    if int(time.time())!=sec:
        pg=[v for (ts,v) in pings if ts>=sec]
        print(f"{time.strftime('%H:%M:%S')}  {statistics.median(echo):7.0f} {max(echo):8.0f} | {max(pg) if pg else -1:11.1f} | {max(tcps):8.1f}")
        sec=int(time.time()); echo=[]; tcps=[]
    time.sleep(max(0,0.25-(time.time()-t)))
p.kill(); ping.kill()
