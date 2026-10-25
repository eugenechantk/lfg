#!/usr/bin/env python3
"""Run a cloudflared *client* (``access ssh``) with its edge connection pinned to the Wi-Fi interface.

Both lfg Macs run Surfshark. The tunnel daemons already dodge it with
``--edge-bind-address`` (see cloudflared-edge-bind-run.sh), but the client side —
``cloudflared access ssh`` behind every ``ssh pro`` / ``ssh air`` ProxyCommand — has
no such flag, and Surfshark's Bypasser does not catch it (measured 2026-10-17: the
access client's socket had the utun source address even with Cloudflared.app in
the bypass list). So every keystroke to the other Mac first crossed the VPN exit:
~170 ms edge RTT instead of ~10 ms, and every VPN hiccup killed the ssh carrier.

cloudflared honours ``HTTPS_PROXY``. This wrapper starts a tiny HTTP CONNECT proxy
on loopback whose outbound sockets are bound to the interface's address — macOS
scopes a socket's route to the interface owning its source address, so the flow
leaves via en0, not the utun default route — points HTTPS_PROXY at it and execs
cloudflared with stdio untouched (the ssh stream still goes straight through
cloudflared; only its TLS connection to the edge takes the detour via loopback).

Falls back to a plain exec (VPN path) when the interface has no address or cannot
reach the edge on 443 within 2 s (kill-switch firewall, captive portal), so a
session always comes up — just slower. Nothing here needs root.

    cloudflared-en0-connect.py [--iface en0] [--log FILE] -- /path/to/cloudflared access ssh --hostname ...

Set LFG_CF_DIRECT=0 to disable the detour (A/B testing).
"""
import os
import select
import socket
import subprocess
import sys
import threading
import time


def log(path, msg):
    if not path:
        return
    try:
        with open(path, "a") as f:
            f.write(f"{time.strftime('%F %T')} cf-direct[{os.getpid()}]: {msg}\n")
    except OSError:
        pass


def iface_ip(iface):
    try:
        out = subprocess.run(["ipconfig", "getifaddr", iface], capture_output=True, text=True, timeout=3).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""
    return out if out.count(".") == 3 else ""


def hostname_from_argv(argv):
    for i, a in enumerate(argv):
        if a == "--hostname" and i + 1 < len(argv):
            return argv[i + 1]
        if a.startswith("--hostname="):
            return a.split("=", 1)[1]
    return ""


def can_reach(bind_ip, host, port=443, timeout=2.0):
    """One bound TCP connect to the edge. Proves the interface route works right now."""
    try:
        infos = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
    except socket.gaierror:
        return False
    for family, stype, proto, _, addr in infos[:2]:
        s = socket.socket(family, stype, proto)
        s.settimeout(timeout)
        try:
            s.bind((bind_ip, 0))
            s.connect(addr)
            return True
        except OSError:
            continue
        finally:
            s.close()
    return False


def pump(a, b):
    """Copy a -> b until EOF, then half-close b."""
    try:
        while True:
            chunk = a.recv(65536)
            if not chunk:
                break
            b.sendall(chunk)
    except OSError:
        pass
    try:
        b.shutdown(socket.SHUT_WR)
    except OSError:
        pass


def handle(conn, bind_ip, logpath):
    conn.settimeout(10)
    try:
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = conn.recv(4096)
            if not chunk:
                return
            head += chunk
            if len(head) > 16384:
                return
        line = head.split(b"\r\n", 1)[0].decode("latin-1")
        parts = line.split()
        if len(parts) < 2 or parts[0] != "CONNECT":
            conn.sendall(b"HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n")
            return
        host, _, port = parts[1].rpartition(":")
        up = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        up.settimeout(10)
        try:
            up.bind((bind_ip, 0))
            up.connect((host, int(port or 443)))
        except OSError as e:
            log(logpath, f"CONNECT {host}:{port} via {bind_ip} failed: {e}")
            conn.sendall(b"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n")
            up.close()
            return
        for s in (conn, up):
            s.settimeout(None)
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        conn.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
        t = threading.Thread(target=pump, args=(up, conn), daemon=True)
        t.start()
        pump(conn, up)
        t.join()
        up.close()
    finally:
        conn.close()


def serve(listener, bind_ip, parent_pipe, logpath):
    """Accept until the parent (cloudflared) closes its end of the pipe."""
    listener.setblocking(False)
    while True:
        r, _, _ = select.select([listener, parent_pipe], [], [])
        if parent_pipe in r:
            return  # cloudflared exited; its inherited write end closed
        if listener in r:
            try:
                conn, _ = listener.accept()
            except OSError:
                continue
            threading.Thread(target=handle, args=(conn, bind_ip, logpath), daemon=True).start()


def main():
    args = sys.argv[1:]
    iface = "en0"
    logpath = os.environ.get("LFG_CF_DIRECT_LOG", os.path.expanduser("~/Library/Logs/cloudflared-direct.log"))
    while args and args[0] != "--":
        if args[0] == "--iface" and len(args) > 1:
            iface = args[1]
            args = args[2:]
        elif args[0] == "--log" and len(args) > 1:
            logpath = args[1]
            args = args[2:]
        else:
            sys.exit(f"cloudflared-en0-connect: unknown option {args[0]}")
    if not args or args[0] != "--" or len(args) < 2:
        sys.exit(__doc__)
    cmd = args[1:]

    ip = iface_ip(iface)
    host = hostname_from_argv(cmd)
    if os.environ.get("LFG_CF_DIRECT", "1") == "0":
        reason = "disabled by LFG_CF_DIRECT=0"
    elif not ip:
        reason = f"no IPv4 address on {iface}"
    elif not host:
        reason = "no --hostname in argv"
    elif not can_reach(ip, host):
        reason = f"{iface} {ip} cannot reach {host}:443 directly"
    else:
        reason = ""
    if reason:
        log(logpath, f"VPN path for {host or '?'}: {reason}")
        os.execvp(cmd[0], cmd)

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(("127.0.0.1", 0))
    listener.listen(16)
    port = listener.getsockname()[1]
    rfd, wfd = os.pipe()
    os.set_inheritable(wfd, True)  # cloudflared inherits it across exec; EOF on exit stops the proxy
    pid = os.fork()
    if pid == 0:
        os.close(wfd)
        try:
            serve(listener, ip, rfd, logpath)
        finally:
            os._exit(0)
    os.close(rfd)
    listener.close()
    env = dict(os.environ)
    env["HTTPS_PROXY"] = env["https_proxy"] = f"http://127.0.0.1:{port}"
    env.pop("NO_PROXY", None)
    env.pop("no_proxy", None)
    log(logpath, f"direct path for {host} via {iface} {ip} (proxy 127.0.0.1:{port})")
    os.execvpe(cmd[0], cmd, env)


if __name__ == "__main__":
    main()
