#!/usr/bin/env python3
"""Transparent TCP proxy to the real lfg host that swallows the RESPONSE to a
specific session's message sends.

The request is forwarded in full — the server really receives and processes it —
and the reply is then dropped on the floor and the client socket closed. That is
the exact shape of Eugene's daily bug: a send whose bytes landed and whose answer
never came back. URLSession reports networkConnectionLost / timedOut while the
message IS delivered.

Scans EVERY request on a connection, not just the first: URLSession reuses
connections, so a first-request-only proxy silently passes the send through.
"""
import asyncio, re

UP_HOST, UP_PORT = "127.0.0.1", 8766
LISTEN_PORT = 8799
TARGET_SID = "00000000-0000-0000-0000-000000000000"  # observe-only: drop nothing
DROP = re.compile((r"POST /api/sessions/%s/send" % TARGET_SID).encode())
# Give upstream time to actually process before the client notices the drop.
KILL_AFTER = 1.5

def log(*a):
    print(*a, flush=True)

async def handle(cr, cw):
    try:
        ur, uw = await asyncio.open_connection(UP_HOST, UP_PORT)
    except Exception as e:
        log(f"upstream connect failed: {e}")
        cw.close(); return

    state = {"dropping": False}

    def kill():
        log("DROP: closing client socket with no response")
        try: cw.close()
        except Exception: pass
        try: uw.close()
        except Exception: pass

    async def c2u():
        buf = b""
        try:
            while True:
                b = await cr.read(65536)
                if not b:
                    break
                uw.write(b); await uw.drain()
                buf = (buf + b)[-8192:]
                for line in re.findall(rb"(?:GET|POST|PUT|DELETE|PATCH) [^\r\n]{0,120}", b):
                    log(f"REQ {line!r}")
                if DROP.search(buf):
                    buf = b""
                    state["dropping"] = True
                    log("DROP: matched a send to the target session — forwarded "
                        "upstream, response will be swallowed")
                    asyncio.get_running_loop().call_later(KILL_AFTER, kill)
        except Exception:
            pass

    async def u2c():
        try:
            while True:
                b = await ur.read(65536)
                if not b:
                    break
                if state["dropping"]:
                    first = b.split(b"\r\n", 1)[0][:40]
                    log(f"DROP: swallowed {len(b)} response bytes ({first!r})")
                    continue
                cw.write(b); await cw.drain()
        except Exception:
            pass

    await asyncio.gather(c2u(), u2c())
    try: cw.close()
    except Exception: pass

async def main():
    srv = await asyncio.start_server(handle, "0.0.0.0", LISTEN_PORT)
    log(f"drop-response proxy on :{LISTEN_PORT} -> {UP_HOST}:{UP_PORT} "
        f"(dropping sends to {TARGET_SID})")
    async with srv:
        await srv.serve_forever()

asyncio.run(main())
