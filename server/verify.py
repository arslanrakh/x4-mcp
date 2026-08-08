#!/usr/bin/env python3
"""
One-shot health check of the bridge against a running game.

Everything here goes through x4.lua, the same way an agent would do it. That is
the point: if these checks need a helper the agent does not have, the helper is
in the wrong place.

Usage:  .venv/bin/python server/verify.py [url]
"""

import asyncio
import json
import sys

import mcp

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8766/mcp"

# One Lua chunk, one round trip, arbitrary fields -- written by the caller
# rather than fixed by the bridge.
READ_SHIPS = '''
ships = x4.lua("""
    local out = {}
    for _, uid in ipairs(helpers.enum(C.GetNumAllFactionShips,
                                      C.GetAllFactionShips, "player")) do
        local lid = helpers.to_luaid(uid)
        local d = helpers.comp_data(lid, {"name", "idcode", "macro", "sector",
                                          "hullpercent", "aicommand"})
        d.id = helpers.id_str(uid)
        d.commander = helpers.id_str(GetCommander(lid))
        d.subs = {}
        for _, s in ipairs(GetSubordinates(lid) or {}) do
            d.subs[#d.subs+1] = helpers.id_str(s)
        end
        out[#out+1] = d
    end
    return out
""")
print("ships read:", len(ships))
'''

CHECKS = [
    ("bulk read written in lua", READ_SHIPS + '''
for s in ships[:4]:
    print(f"  {x4.model(s['macro']) or '?':22} {s['idcode']}  {s['sector']}")
'''),
    ("id consistency", '''
by_id = {s["id"]: s for s in ships}
# .get(): assigning nil to a Lua table key removes it, so fields that were
# nil in the game are simply absent here rather than present and null.
bad = [f"{s['idcode']} -> {s.get('commander')}" for s in ships
       if s.get("commander") and s["commander"] not in by_id]
bad += [f"{s['idcode']} -> {m}" for s in ships for m in s.get("subs", [])
        if m not in by_id]
print("unresolved references:", bad or "none")
'''),
    ("fleets", '''
for s in ships:
    if s.get("subs"):
        names = [x4.model(by_id[m]["macro"]) for m in s["subs"]]
        print(" ", x4.model(s["macro"]), s["idcode"], "->", names)
'''),
    ("ship models, asked of the game", '''
print("macro ->", x4.macro_data(ships[0]["macro"]))
'''),
    ("orders, asked of the game", '''
orders = x4.orders()
print("orders known:", len(orders))
mods = [o["id"] for o in orders if o["id"].startswith(("VRO", "kAAIT"))]
print("mod orders:", mods)
print("AssignCommander:",
      [(x["index"], x["name"]) for x in x4.order_params("AssignCommander")][:4])
if mods:
    print("a mod order's params:",
          [(x["index"], x["name"]) for x in x4.order_params(mods[-1])])
'''),
    ("reading the game's own source", '''
hits = x4.source("IsOrderSelectableFor", limit=2, context=0)
for h in hits:
    print(" ", h["file"] + ":" + str(h["line"]))
'''),
    ("api discovery", '''
print("api entries:", len(x4.api("", limit=10_000)))
print(x4.api("^IsOrderSelectableFor$"))
'''),
    ("cookbook: every saved recipe still compiles in this game", '''
names = [r["name"] for r in x4.cookbook.search()]
print("recipes:", len(names))
broken = []
for name in names:
    code = x4.cookbook.show(name)["code"]
    kind = x4.lua("local recipe = %s\\nreturn type(recipe)" % code)
    if kind != "function":
        broken.append(name)
print("do not compile:", broken or "none")
'''),
    ("cookbook: a recipe runs, and composes with another", '''
crewed = x4.lua('return cookbook.player_ships({"idcode"})')
print("player_ships ->", len(crewed), "ships,", crewed[0]["idcode"])
print("set_commander reaches give_order:",
      x4.lua("return type(cookbook.give_order) .. \\" \\" .. type(cookbook.set_commander)"))
'''),
    ("cookbook: a failure inside a recipe is blamed on the recipe", '''
# The prelude shifts every line number, so an error inside a recipe would
# otherwise be reported against a line of the caller's chunk that is innocent.
x4.cookbook.save("verify_probe", "function()\\n\\tlocal t = nil\\n\\treturn t.x\\nend",
                 "verify_probe() -> never returns",
                 "Deliberately broken; written and removed by verify.py.",
                 verified="not verified: it is meant to fail")
try:
    x4.cookbook.save("verify_probe2", "function() return 1 end", "s()", "d",
                     verified="")
    print("BUG: a save with no verification was accepted")
except ValueError as e:
    print("save without `verified` refused:", str(e).split(":")[0])
saved = x4.cookbook.show("verify_probe")
guilty = open(saved["file"]).read().splitlines().index("\\treturn t.x") + 1
try:
    x4.lua("return cookbook.verify_probe()")
    print("BUG: the broken recipe did not fail")
except RuntimeError as e:
    print(e)
    want = "cookbook/verify_probe.lua:%d" % guilty
    assert want in str(e), "expected the error to point at " + want
    print("blamed the right line of the right file:", want)
finally:
    print(x4.cookbook.delete("verify_probe", "temporary, written by verify.py"))
'''),
    ("writing: precondition check", '''
first = ships[0]["id"]
print("can dock:", x4.lua(
    'return C.IsOrderSelectableFor("DockAndWait", ConvertStringTo64Bit("%s"))' % first))
print("can mine:", x4.lua(
    'return C.IsOrderSelectableFor("MiningRoutine", ConvertStringTo64Bit("%s"))' % first))
'''),
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
