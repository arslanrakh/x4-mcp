#!/usr/bin/env python3
"""
Test rig for the x4mcp transport (Milestone 1).

The spec criterion -- "survives save/load, ui reload, alt-tab" -- is checked
through heartbeat continuity. So the server does not print every heartbeat
(there is one per second), only the gaps: when the pause exceeded the threshold
and when the stream resumed. It also sends a ping every few seconds and
measures the round trip, which shows the channel is alive in both directions
rather than game-to-host only.

Usage:  python3 test_server.py [port]
"""

import json
import socket
import sys
import threading
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
GAP_THRESHOLD = 3.0      # seconds without a heartbeat before we call it a gap
PING_INTERVAL = 5.0

_print_lock = threading.Lock()


def log(*a):
    with _print_lock:
        print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


class Session:
    def __init__(self, conn, addr):
        self.conn = conn
        self.addr = addr
        self.alive = True
        self.seq = 0
        self.pending = {}          # seq -> send timestamp
        self.last_hb = None
        self.last_gt = None        # game time of the last heartbeat
        self.gap_open = None
        self.hb_count = 0
        self.last_flags = None
        self.lock = threading.Lock()

    # -------------------------------------------------- receiving

    def reader(self):
        buf = b""
        try:
            while self.alive:
                chunk = self.conn.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    self.on_line(line.decode("utf-8", "replace").rstrip("\r"))
        except (ConnectionError, OSError) as e:
            log(f"read aborted: {e}")
        finally:
            self.alive = False

    def on_line(self, line):
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as e:
            log(f"!! undecodable JSON from game: {e}: {line[:200]}")
            return

        kind = msg.get("t")
        if kind == "hb":
            self.on_heartbeat(msg)
        elif kind == "hello":
            log(f"HELLO  native={msg.get('native')} lua={msg.get('lua')} "
                f"connect#{msg.get('connect')}")
        elif kind == "resp":
            self.on_response(msg)
        else:
            log(f"?? unknown kind {kind!r}: {line[:200]}")

    def on_heartbeat(self, msg):
        now = time.time()
        self.hb_count += 1
        gt = msg.get("game_time")

        if self.gap_open is not None:
            wall = now - self.gap_open
            # The key distinction: if game time barely moved during the gap the
            # whole simulation was stalled, and an MD cue as a second tick
            # source would not help. If it moved by roughly wall, only the UI
            # layer stopped.
            if gt is not None and self.last_gt is not None:
                sim = gt - self.last_gt
                verdict = ("simulation was stalled too" if sim < wall * 0.25
                           else "simulation kept running, only the UI stalled")
                log(f"++ tick resumed: pause {wall:.1f}s, "
                    f"game time +{sim:.1f}s -> {verdict}")
            else:
                log(f"++ tick resumed after {wall:.1f}s")
            self.gap_open = None

        self.last_hb = now
        self.last_gt = gt

        flags = (msg.get("paused"), msg.get("loaded"))
        if flags != self.last_flags:
            self.last_flags = flags
            log(f"   game state: paused={flags[0]} loaded={flags[1]} "
                f"game_time={msg.get('game_time')}")

    def on_response(self, msg):
        seq = msg.get("seq")
        sent = self.pending.pop(seq, None)
        rtt = (time.time() - sent) * 1000 if sent else float("nan")
        if msg.get("ok"):
            log(f"PONG   seq={seq} rtt={rtt:.1f}ms")
        else:
            log(f"!! error seq={seq}: {msg.get('err')} {msg.get('detail')}")

    # -------------------------------------------------- sending

    def send(self, obj):
        data = json.dumps(obj, separators=(",", ":"), ensure_ascii=False)
        try:
            with self.lock:
                self.conn.sendall(data.encode("utf-8") + b"\n")
            return True
        except (ConnectionError, OSError) as e:
            log(f"write aborted: {e}")
            self.alive = False
            return False

    def pinger(self):
        while self.alive:
            time.sleep(PING_INTERVAL)
            if not self.alive:
                break
            self.seq += 1
            self.pending[self.seq] = time.time()
            self.send({"t": "req", "seq": self.seq, "op": "ping",
                       "args": {"n": self.seq}})

    def watchdog(self):
        while self.alive:
            time.sleep(0.5)
            if self.last_hb is None:
                continue
            idle = time.time() - self.last_hb
            if idle > GAP_THRESHOLD and self.gap_open is None:
                self.gap_open = self.last_hb
                log(f"-- TICK STALLED: no heartbeat for {idle:.1f}s")

    def run(self):
        log(f"game connected from {self.addr[0]}:{self.addr[1]}")
        threads = [
            threading.Thread(target=self.pinger, daemon=True),
            threading.Thread(target=self.watchdog, daemon=True),
        ]
        for t in threads:
            t.start()
        self.reader()
        log(f"game disconnected, heartbeats received: {self.hb_count}")


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(4)
    log(f"listening on 127.0.0.1:{PORT}; waiting for the game")
    try:
        while True:
            conn, addr = srv.accept()
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            Session(conn, addr).run()
            try:
                conn.close()
            except OSError:
                pass
    except KeyboardInterrupt:
        log("stopped")
    finally:
        srv.close()


if __name__ == "__main__":
    main()
