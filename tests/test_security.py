"""
The two listeners must not trust whoever connects.

The game link adopts a connection only after the game's hello, so a web page
or any other local process cannot drop the game or answer in its place. The
MCP endpoint refuses Host and Origin values other than loopback names, so a
web page cannot reach x4_exec through DNS rebinding, also when the server binds
0.0.0.0 inside Docker.

No game is needed: a socket that speaks the extension's protocol stands in for
it.
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))

from bridge import GameBridge  # noqa: E402


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for(predicate, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.02)
    return False


def line(msg: dict) -> bytes:
    return json.dumps(msg).encode() + b"\n"


HELLO = {"t": "hello", "native": "x4mcp-native test", "lua": "Lua 5.1", "connect": 1}
HB = {"t": "hb", "loaded": True, "game_time": 12.5, "paused": False}


@pytest.fixture
def bridge():
    b = GameBridge(port=free_port())
    b.HELLO_TIMEOUT = 1.0
    assert wait_for(lambda: b.bind_error is None)
    time.sleep(0.05)
    yield b
    b._stop = True


def connect(b: GameBridge) -> socket.socket:
    return socket.create_connection(("127.0.0.1", b.port), timeout=2)


def test_game_hello_is_adopted_with_lines_sent_alongside(bridge):
    game = connect(bridge)
    game.sendall(line(HELLO) + line(HB))
    assert wait_for(lambda: bridge.connected and bridge.loaded)
    assert bridge.hello["native"] == "x4mcp-native test"
    assert bridge.game_time == 12.5
    game.close()


def test_http_request_is_rejected(bridge):
    page = connect(bridge)
    page.sendall(b"POST / HTTP/1.1\r\nHost: evil.example\r\n\r\n"
                 + line({"t": "resp", "seq": 1, "ok": True}))
    assert wait_for(lambda: bridge.rejected == 1)
    assert not bridge.connected
    assert page.recv(1) == b""          # closed by the bridge
    page.close()


def test_silent_connection_times_out(bridge):
    idle = connect(bridge)
    assert wait_for(lambda: bridge.rejected == 1, timeout=3)
    assert not bridge.connected
    idle.close()


def test_stranger_does_not_displace_the_game(bridge):
    game = connect(bridge)
    game.sendall(line(HELLO) + line(HB))
    assert wait_for(lambda: bridge.connected)
    first = bridge.conn

    page = connect(bridge)
    page.sendall(b"GET / HTTP/1.1\r\nHost: evil.example\r\n\r\n")
    assert wait_for(lambda: bridge.rejected == 1)
    assert bridge.conn is first and bridge.connects == 1
    page.close()
    game.close()


def test_game_reconnect_replaces_the_old_link(bridge):
    old = connect(bridge)
    old.sendall(line(HELLO))
    assert wait_for(lambda: bridge.connects == 1)
    new = connect(bridge)
    new.sendall(line(dict(HELLO, connect=2)))
    assert wait_for(lambda: bridge.connects == 2)
    assert bridge.hello["connect"] == 2
    assert old.recv(1) == b""
    old.close()
    new.close()


# --------------------------------------------------------------------- MCP

INIT = json.dumps({
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {"protocolVersion": "2025-06-18", "capabilities": {},
               "clientInfo": {"name": "test", "version": "0"}},
}).encode()


@pytest.fixture(params=["127.0.0.1", "0.0.0.0"])
def mcp_server(request, tmp_path):
    port = free_port()
    env = dict(os.environ, X4MCP_COOKBOOK_DIR=str(tmp_path))
    proc = subprocess.Popen(
        [sys.executable, str(ROOT / "server" / "x4mcp_server.py"),
         "--transport", "http", "--host", request.param,
         "--http-port", str(port), "--game-port", str(free_port()),
         "--game-dir", str(tmp_path / "no-game")],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def up():
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return True
        except OSError:
            return False

    assert wait_for(up, timeout=30), "MCP server did not start"
    yield port
    proc.terminate()
    proc.wait(timeout=10)


def post(port: int, host: str, origin: str | None = None) -> int:
    headers = {"Host": host, "Content-Type": "application/json",
               "Accept": "application/json, text/event-stream"}
    if origin:
        headers["Origin"] = origin
    req = urllib.request.Request(f"http://127.0.0.1:{port}/mcp", data=INIT,
                                 headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code


def test_loopback_host_is_served(mcp_server):
    assert post(mcp_server, f"127.0.0.1:{mcp_server}") == 200
    assert post(mcp_server, f"localhost:{mcp_server}",
                f"http://localhost:{mcp_server}") == 200


def test_rebound_host_is_refused(mcp_server):
    assert post(mcp_server, f"evil.example:{mcp_server}") == 421


def test_foreign_origin_is_refused(mcp_server):
    assert post(mcp_server, f"127.0.0.1:{mcp_server}",
                "http://evil.example") == 403
