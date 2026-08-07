#!/usr/bin/env python3
"""
Connection to the running game.

The game is the TCP client: the X4 extension dials out to us. That direction is
deliberate -- the game may restart, reload its UI or load a savegame at any
moment, and each of those recreates the Lua state. Having the game reconnect on
its own means none of those events need handling here beyond noticing that the
socket changed.

One request is in flight per sequence number and replies are matched by it, so
several callers can share the link without stepping on each other.
"""

from __future__ import annotations

import json
import socket
import threading
import time


class GameNotConnected(RuntimeError):
    """No live link to X4. Carries a message the agent can act on."""


class GameBridge:
    HEARTBEAT_STALE = 5.0     # seconds; beyond this the game is not ticking

    def __init__(self, port: int = 8765, host: str = "127.0.0.1"):
        self.port = port
        self.host = host
        self.conn: socket.socket | None = None
        self.seq = 0
        self.replies: dict[int, dict] = {}
        self.cv = threading.Condition()
        self.last_hb: float | None = None
        self.loaded = False
        self.loaded_at: float | None = None
        self.game_time: float | None = None
        self.paused = False
        self.connects = 0
        self.hello: dict | None = None
        self.bind_error: str | None = None
        self._stop = False
        self._listener = threading.Thread(target=self._serve, daemon=True)
        self._listener.start()

    # ------------------------------------------------------------------ link

    def _serve(self):
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            srv.bind((self.host, self.port))
        except OSError as e:
            # Almost always a second copy of this server. Recorded rather than
            # raised in a daemon thread, so the agent gets a diagnosis from
            # x4_status instead of a silent "not connected".
            self.bind_error = (
                f"could not listen on {self.host}:{self.port} ({e}). Another "
                f"x4mcp server is probably already running; the game can only "
                f"talk to one.")
            return
        srv.listen(4)
        while not self._stop:
            try:
                conn, _ = srv.accept()
            except OSError:
                break
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            with self.cv:
                old = self.conn
                self.conn = conn
                self.connects += 1
                self.replies.clear()
                self.cv.notify_all()
            if old is not None:
                try:
                    old.close()
                except OSError:
                    pass
            threading.Thread(target=self._read, args=(conn,), daemon=True).start()

    def _read(self, conn: socket.socket):
        buf = b""
        try:
            while True:
                chunk = conn.recv(1 << 16)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    self._on_line(line.decode("utf-8", "replace").rstrip("\r"))
        except OSError:
            pass
        finally:
            with self.cv:
                if self.conn is conn:
                    self.conn = None
                    self.loaded = False
                    self.loaded_at = None
                self.cv.notify_all()

    def _on_line(self, line: str):
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            return
        kind = msg.get("t")
        if kind == "resp":
            with self.cv:
                self.replies[msg.get("seq")] = msg
                self.cv.notify_all()
        elif kind == "hb":
            was = self.loaded
            self.last_hb = time.time()
            self.loaded = bool(msg.get("loaded"))
            self.game_time = msg.get("game_time")
            self.paused = bool(msg.get("paused"))
            if self.loaded and not was:
                self.loaded_at = time.time()
            elif not self.loaded:
                self.loaded_at = None
        elif kind == "hello":
            self.hello = msg

    # --------------------------------------------------------------- status

    @property
    def connected(self) -> bool:
        return self.conn is not None

    @property
    def ticking(self) -> bool:
        """The game answers only while it renders frames; without focus it stalls."""
        return (self.last_hb is not None
                and time.time() - self.last_hb <= self.HEARTBEAT_STALE)

    def status(self) -> dict:
        return {
            "listening": self.bind_error is None,
            "bind_error": self.bind_error,
            "connected": self.connected,
            "ticking": self.ticking,
            "savegame_loaded": self.loaded,
            "paused": self.paused,
            "game_time": self.game_time,
            "seconds_since_heartbeat": (None if self.last_hb is None
                                        else round(time.time() - self.last_hb, 1)),
            "connects": self.connects,
            "native": (self.hello or {}).get("native"),
        }

    def require_ready(self):
        """Fail early, with a reason -- better than a timeout the agent cannot read."""
        if self.bind_error:
            raise GameNotConnected(self.bind_error)
        if not self.connected:
            raise GameNotConnected(
                "X4 is not connected. Is the game running with the x4mcp "
                "extension, and Protected UI Mode off?")
        if not self.loaded:
            raise GameNotConnected(
                "X4 is connected but no savegame is loaded (main menu).")
        if not self.ticking:
            raise GameNotConnected(
                "X4 is connected but not ticking -- its window is most likely "
                "in the background. Switch to the game and retry.")

    # ----------------------------------------------------------------- calls

    def call(self, op: str, args: dict | None = None, timeout: float = 60.0):
        self.require_ready()
        with self.cv:
            # Re-read under the lock: require_ready() only proves the link was
            # up a moment ago, and the reader thread can drop it at any time.
            conn = self.conn
            if conn is None:
                raise GameNotConnected("the game disconnected before the call went out")
            self.seq += 1
            seq = self.seq
        payload = {"t": "req", "seq": seq, "op": op, "args": args or {}}
        try:
            conn.sendall(json.dumps(payload, separators=(",", ":")).encode() + b"\n")
        except OSError as e:
            raise GameNotConnected(f"lost the link while sending {op}: {e}") from e

        deadline = time.time() + timeout
        with self.cv:
            while seq not in self.replies:
                if self.conn is not conn:
                    raise GameNotConnected(
                        f"the game reconnected while {op} was in flight; retry")
                remaining = deadline - time.time()
                if remaining <= 0:
                    raise TimeoutError(
                        f"{op} did not answer within {timeout}s. The game may be "
                        f"in the background and not rendering frames.")
                self.cv.wait(timeout=min(0.5, remaining))
            reply = self.replies.pop(seq)

        if not reply.get("ok"):
            raise RuntimeError(f"{op} failed in game: {reply.get('err')}: "
                               f"{reply.get('detail')}")
        return reply.get("data")
