#!/usr/bin/env python3
"""
Stub server for smoke-testing the x4mcp transport.

Speaks the same protocol the real MCP server will use: one compact JSON
document per line. Every incoming request is echoed back with an added ok
field, so the game side can confirm a full round trip.

Usage:  python3 echo_server.py [port]
"""

import json
import socket
import socketserver
import sys
import threading
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
LOG = threading.Lock()


def log(*a):
    with LOG:
        print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        peer = self.client_address
        log(f"connected {peer[0]}:{peer[1]}")
        self.connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        buf = b""
        try:
            while True:
                chunk = self.connection.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    self.on_line(line.decode("utf-8", "replace").rstrip("\r"))
        except ConnectionError as e:
            log(f"aborted: {e}")
        finally:
            log(f"disconnected {peer[0]}:{peer[1]}")

    def on_line(self, line):
        log(f"<- {line[:300]}")
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as e:
            reply = {"ok": False, "err": "bad_json", "detail": str(e)}
        else:
            reply = {
                "seq": msg.get("seq"),
                "ok": True,
                "echo": msg,
                "server_time": round(time.time(), 3),
            }
        out = json.dumps(reply, separators=(",", ":"), ensure_ascii=False)
        log(f"-> {out[:300]}")
        self.connection.sendall(out.encode("utf-8") + b"\n")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    log(f"listening on 127.0.0.1:{PORT}")
    with Server(("127.0.0.1", PORT), Handler) as srv:
        srv.serve_forever()
