#!/usr/bin/env python3
"""
Milestone 2 verification rig.

The game is the TCP client, so this listens, waits for X4 to connect, then asks
for a snapshot and prints a summary to be compared against the in-game map.
The full JSON is written to disk so individual fields can be inspected without
another round trip.

It also runs "sample_ship" first: that returns the Lua type and value of every
field for one ship, which is how the field mapping gets calibrated without
guessing.

Usage:  python3 snapshot_tool.py [port]
"""

import json
import socket
import sys
import threading
import time
from pathlib import Path

# Importable regardless of the caller's working directory.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from x4model import World  # noqa: E402

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
OUT_DIR = Path(__file__).resolve().parent.parent / "snapshots"
SETTLE_SECONDS = 8.0     # grace period after "loaded" before the world is real


def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


class Client:
    """One connected game session."""

    def __init__(self, conn):
        self.conn = conn
        self.seq = 0
        self.buf = b""
        self.replies = {}
        self.lock = threading.Condition()
        self.alive = True
        self.loaded = False        # is a savegame active
        self.loaded_at = None      # when that first became true
        self.game_time = None
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        try:
            while self.alive:
                chunk = self.conn.recv(1 << 16)
                if not chunk:
                    break
                self.buf += chunk
                while b"\n" in self.buf:
                    line, self.buf = self.buf.split(b"\n", 1)
                    self._on_line(line.decode("utf-8", "replace").rstrip("\r"))
        except (ConnectionError, OSError) as e:
            log(f"read aborted: {e}")
        finally:
            with self.lock:
                self.alive = False
                self.lock.notify_all()

    def _on_line(self, line):
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as e:
            log(f"!! undecodable JSON ({e}); {len(line)} bytes, head: {line[:200]}")
            return
        if msg.get("t") == "resp":
            with self.lock:
                self.replies[msg.get("seq")] = msg
                self.lock.notify_all()
        elif msg.get("t") == "hello":
            log(f"HELLO native={msg.get('native')} connect#{msg.get('connect')}")
        elif msg.get("t") == "hb":
            was = self.loaded
            self.loaded = bool(msg.get("loaded"))
            self.game_time = msg.get("game_time")
            if self.loaded != was:
                self.loaded_at = time.time() if self.loaded else None
                log(f"savegame {'loaded' if self.loaded else 'unloaded'} "
                    f"(game_time={self.game_time})")

    def call(self, op, args=None, timeout=60.0):
        self.seq += 1
        seq = self.seq
        payload = {"t": "req", "seq": seq, "op": op, "args": args or {}}
        started = time.time()
        self.conn.sendall(json.dumps(payload, separators=(",", ":")).encode() + b"\n")

        deadline = started + timeout
        with self.lock:
            while seq not in self.replies and self.alive:
                if not self.lock.wait(timeout=max(0.1, deadline - time.time())):
                    if time.time() > deadline:
                        raise TimeoutError(f"{op} timed out after {timeout}s")
            if seq not in self.replies:
                raise ConnectionError("game disconnected while waiting for a reply")
            reply = self.replies.pop(seq)
        log(f"{op}: {time.time() - started:.2f}s")
        if not reply.get("ok"):
            raise RuntimeError(f"{op} failed: {reply.get('err')} {reply.get('detail')}")
        return reply.get("data")


def calibrate(client):
    """Print the Lua type of every ship field, so the mapping can be checked."""
    data = client.call("sample_ship")
    if "raw_types" not in data:
        log(f"sample_ship: {data}")
        return
    log(f"--- field types on ship {data.get('id')} ---")
    for key in sorted(data["raw_types"]):
        log(f"    {key:<20} {data['raw_types'][key]}")


def take_snapshot(client):
    data = client.call("snapshot")
    OUT_DIR.mkdir(exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    path = OUT_DIR / f"snapshot-{stamp}.json"
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False))

    raw = path.stat().st_size
    log(f"--- snapshot saved: {path} ({raw / 1024:.0f} KB) ---")
    log(f"reported counts: {data.get('counts')}")

    # "loaded" flips as soon as the player component exists, which is well
    # before the universe is populated -- a snapshot taken in that window comes
    # back empty and looks like a broken collector. Treat it as not-ready and
    # let the caller retry rather than accepting a lie.
    counts = data.get("counts") or {}
    if not any(counts.get(k) for k in ("ships", "stations", "sectors")):
        raise RuntimeError("universe still empty; the savegame is probably mid-load")

    world = World(data)
    for line in world.summary().splitlines():
        log("    " + line)

    # Referential integrity. Every commander and subordinate id must resolve to
    # a ship in this same snapshot -- if it does not, the two id encodings have
    # drifted apart again and fleet handling would silently target nothing.
    dangling = []
    for ship in world.ships:
        if ship.commander and not world.ship(ship.commander):
            dangling.append(f"{ship.label}.commander -> {ship.commander}")
        for sub in ship.subordinates:
            if not world.ship(sub):
                dangling.append(f"{ship.label}.subordinates -> {sub}")
    if dangling:
        log(f"!! {len(dangling)} unresolved id references:")
        for d in dangling[:6]:
            log(f"       {d}")
    else:
        log("    all commander/subordinate references resolve")

    # Fleet structure, which is what the acceptance scenario actually needs.
    for ship in world.ships:
        if ship.subordinates:
            members = ", ".join(m.label for m in world.fleet_of(ship))
            log(f"    fleet: {ship.label} <- {members}")

    for ship in world.ships[:4]:
        log(f"    e.g. {ship!r}")
    for station in world.stations[:2]:
        log(f"    e.g. {station!r}")
    return world


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(4)
    log(f"listening on 127.0.0.1:{PORT}; waiting for the game")

    while True:
        conn, addr = srv.accept()
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        log(f"game connected from {addr[0]}:{addr[1]}")
        client = Client(conn)
        # A failed op must not tear down the session: the game may still be
        # loading, or be an older instance without the collector. Wait for a
        # savegame, try once, and on failure keep the connection and retry.
        done = False
        waiting_logged = False
        next_try = 0.0
        while client.alive:
            settled = (client.loaded_at is not None
                       and time.time() - client.loaded_at >= SETTLE_SECONDS)
            if not done and settled and time.time() >= next_try:
                try:
                    calibrate(client)
                    take_snapshot(client)
                    done = True
                    log("--- done; connection stays open ---")
                except (RuntimeError, TimeoutError) as e:
                    log(f"!! {e}; retrying in 10s")
                    next_try = time.time() + 10
                except (ConnectionError, OSError) as e:
                    log(f"!! connection gone: {e}")
                    break
            elif not done and not client.loaded and not waiting_logged:
                waiting_logged = True
                log("waiting for a savegame to be loaded (main menu has no objects)")
            time.sleep(0.5)

        client.alive = False
        try:
            conn.close()
        except OSError:
            pass
        log("session closed; waiting for the game to reconnect")


if __name__ == "__main__":
    main()
