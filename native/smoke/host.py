"""Stand-in for the MCP server's game link: expects a hello, sends one request,
expects the matching reply. Exits non-zero on anything else."""

import json
import socket
import sys

port = int(sys.argv[1])
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port))
srv.listen(1)
srv.settimeout(120)
conn, _ = srv.accept()
conn.settimeout(120)
lines = conn.makefile("rb")

hello = json.loads(lines.readline())
assert hello.get("t") == "hello", hello
assert str(hello.get("native", "")).startswith("x4mcp-native"), hello
print("host: hello from", hello["native"])

req = {"t": "req", "seq": 7, "op": "echo", "args": {"text": "ünïcode ok", "n": 42}}
conn.sendall(json.dumps(req, ensure_ascii=False, separators=(",", ":")).encode() + b"\n")

resp = json.loads(lines.readline())
assert resp == {"t": "resp", "seq": 7, "ok": True, "data": req["args"]}, resp
print("host: reply matched")
conn.close()
