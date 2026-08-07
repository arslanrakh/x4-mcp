#!/usr/bin/env python3
"""
One-shot health check of the whole bridge against a running game.

Covers the pieces that have actually broken before: the link, the snapshot and
its referential integrity, language-independent lookup, station discovery, and
the order layer. Run it after any change that touches the game side.

Usage:  .venv/bin/python server/verify.py [url]
"""

import asyncio
import json
import sys

import mcp

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8766/mcp"

CHECKS = [
    ("snapshot", """
x4.refresh()
print(x4.summary())
"""),
    ("id integrity", """
bad = []
for s in x4.ships:
    if s.commander and not x4.ship(s.commander):
        bad.append(f"{s.label}.commander -> {s.commander}")
    bad += [f"{s.label}.sub -> {m}" for m in s.subordinates if not x4.ship(m)]
print("unresolved references:", bad or "none")
"""),
    ("language independence", """
sample = next((s for s in x4.ships if s.model and s.name), None)
for q in ([sample.model, sample.name, sample.kind] if sample else []):
    print(repr(q), "->", len(x4.find(q)), "hit(s)")
"""),
    ("fleets", """
for s in x4.ships:
    if s.subordinates:
        print(s.model, s.idcode, "->", [m.model for m in x4.fleet_of(s)])
spare = [s for s in x4.ships if not s.commander and not s.subordinates]
print("spare ships:", [(s.model, s.idcode) for s in spare])
"""),
    ("order registry", """
orders = x4.orders()
print("orders known:", len(orders))
mods = [o["id"] for o in orders if o["id"].startswith(("VRO", "kAAIT"))]
print("from mods:", mods[:6])
"""),
    ("station discovery", """
ship = x4.ships[0]
near = x4.find_stations(sector=ship, limit=10)
print(f"stations in {ship.sector}:", [(s.name, s.owner) for s in near][:5])
"""),
    ("can_order", """
ship = next(s for s in x4.ships if not s.is_docked) if any(
    not s.is_docked for s in x4.ships) else x4.ships[0]
for o in ("DockAndWait", "MoveToObject", "MiningRoutine"):
    print(f"{ship.model} {ship.idcode} can {o}:", x4.can_order(ship, o))
"""),
    ("api discovery", """
print("CreateOrder:", x4.api("^CreateOrder$"))
print("api entries:", len(x4.api("", limit=10_000)))
"""),
]


def text_of(result) -> str:
    return "".join(getattr(b, "text", "") for b in getattr(result, "content", []) or [])


async def main() -> int:
    failures = 0
    async with mcp.Client(URL) as client:
        status = json.loads(text_of(await client.call_tool("x4_status", {})))
        print(json.dumps(status, indent=1, ensure_ascii=False))
        if not (status.get("connected") and status.get("savegame_loaded")):
            print("\nNot ready: connect the game and load a savegame first.")
            return 1

        for title, code in CHECKS:
            print(f"\n--- {title} ---")
            out = text_of(await client.call_tool("x4_exec", {"code": code}))
            print(out.strip())
            if "Traceback" in out or "Error" in out:
                failures += 1

    print(f"\n{'FAILURES: ' + str(failures) if failures else 'all checks passed'}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
