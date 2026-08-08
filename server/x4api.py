#!/usr/bin/env python3
"""
The `x4` object that generated code runs against, plus the reference that
teaches an agent how to use it.

Deliberately thin. There is one way to touch the game -- x4.lua(code) -- and
everything else here either reads the game's own files from disk or reports on
the link. Nothing wraps a game feature, because a wrapper only ever covers what
its author anticipated, and the point of this bridge is that the agent is not
limited to that.

The reference lives here rather than in a doc file because it has to travel
with the tool: with a single code-execution tool the model has no schema to
introspect, so the description is all it has. x4.help() returns the same text.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from bridge import GameBridge

GENERATED = Path(__file__).resolve().parent / "generated"

API_REFERENCE = """\
CONTROLS A RUNNING X4: FOUNDATIONS GAME -- READ AND WRITE.

You can inspect the player's empire AND command it: give orders, dock, move,
attack, mine, trade, reorganise fleets, anything the game itself can do. If the
player asks for something to happen in X4, DO IT HERE. Never answer with "I
cannot control the game" or with instructions to click through menus.

x4_exec runs Python in a namespace that persists between calls, like a
notebook. The Python half is a thin client; the real work happens in Lua that
you write and send into the game.

THE ONE MECHANISM
    x4.lua(code) runs Lua inside the running game and returns what it returns.

    This is not an escape hatch, it is the interface. X4's own ffi.cdef
    declarations are global to its Lua state, so ~2000 C functions resolve
    through `C`, and every engine Lua global (GetComponentData, GetSubordinates,
    SetOrderParam, ConvertStringToLuaID, ...) is in scope. There is no wrapper
    to wait for and no capability held back.

    One call, one round trip -- so do the looping and filtering inside the Lua,
    not by calling x4.lua once per object.

        ships = x4.lua('''
            local out = {}
            for _, uid in ipairs(helpers.enum(C.GetNumAllFactionShips,
                                              C.GetAllFactionShips, "player")) do
                local lid = helpers.to_luaid(uid)
                local d = helpers.comp_data(lid, {"name", "idcode", "macro",
                                                  "sector", "hullpercent"})
                d.id = helpers.id_str(uid)
                d.commander = helpers.id_str(GetCommander(lid))
                d.subordinates = {}
                for _, s in ipairs(GetSubordinates(lid) or {}) do
                    d.subordinates[#d.subordinates+1] = helpers.id_str(s)
                end
                out[#out+1] = d
            end
            return out
        ''')

HELPERS AVAILABLE INSIDE LUA
    helpers.enum(count_fn, list_fn, arg)   the game's enumerator pattern
    helpers.factions()                     every faction id
    helpers.to_luaid(uid)                  cdata id -> engine Lua id
    helpers.id_str(anything)               either id form -> plain digit string
    helpers.comp_data(luaid, {keys})       several GetComponentData fields at once
    C, ffi                                 the game's FFI namespace and LuaJIT ffi

    IDs matter here. Enumerators return 64-bit cdata; GetComponentData returns
    engine Lua ids. They print differently, so always pass both through
    helpers.id_str before comparing or returning them -- otherwise a commander
    reference will not match the id it points at, and nothing will look wrong.

    Two shapes to expect on the way back:
      - Assigning nil to a Lua table key REMOVES it. A field that was nil in
        the game is absent from the result, not present and None. Use .get().
      - Lua sequences come back as JSON arrays and Lua maps as objects, so a
        table you build with mixed keys will arrive as an object.

DISCOVERY -- use this instead of guessing
    x4.api("Order")            C signatures matching a pattern (~2000 known)
    x4.structs("Order")        struct names for ffi.new
    x4.globals("Convert")      engine Lua globals, read from the live game
    x4.order_params("DockAndWait")   an order's parameters, named and typed
                               (read from disk; for the definitive list of
                                orders ask the game via GetOrderDefinitions)
    x4.source("AssignCommander")     search the GAME'S OWN Lua and XML
    x4.read("ui/addons/ego_interactmenu/menu_interactmenu.lua", 540, 580)

    x4.source is the important one. X4 ships its entire UI as readable Lua and
    its AI as readable XML, so the authoritative recipe for any action is on
    disk. Read it before concluding something is impossible -- most "the game
    does not allow it" turns out to be "the call needs parameters the signature
    does not show".

GIVING ORDERS
    Orders are positional, and the positions come from the game's definition:

        x4.order_params("AssignCommander")
        -> 1 commander (object)   2 assignment   3 subordinategroup
           4 setgroupassignment   5 cancelorders 6 response
           7 getnewdefaultorder   8 informfleetmanager  9 debugchance

        x4.lua('''
            local ship = ConvertStringTo64Bit("%s")
            if not C.IsOrderSelectableFor("DockAndWait", ship) then
                return "not selectable"
            end
            local idx = C.CreateOrder(ship, "DockAndWait", false)
            SetOrderParam(ship, idx, 1, nil, ConvertStringToLuaID("%s"))
            C.EnableOrder(ship, idx)
            if idx ~= 1 then C.AdjustOrder(ship, idx, 1, true, false, false) end
            return idx
        ''' % (ship_id, target_id))

    Things that will bite you:
      - Object parameters must go through ConvertStringToLuaID. A bare number
        is not an object reference and the order targets nothing.
      - Filling in fewer parameters than the order defines creates an order
        that reports success and does nothing. This is the single most common
        reason a fleet edit "works" and changes nothing.
      - Check IsOrderSelectableFor first. X4 accepts an inapplicable order
        silently and the ship just sits there.
      - For AssignCommander the check goes on the SUBORDINATE, not the
        commander, and a ship with no pilot cannot be assigned at all.
      - Orders are queued, not instant. Read the ship back to confirm.

LANGUAGE INDEPENDENCE
    The game may run in any language and players rename their ships, so
    displayed names are for showing the player, never for logic. Match on
    macro, owner, class, and on the canonical names in the catalogue:

        x4.model("ship_par_l_expeditionary_01_a_macro")   -> "Hyperion"
        x4.catalog()["ship_par_l_expeditionary_01_a_macro"]
        -> {"name": "Hyperion", "class": "ship_l", "race": "paranid",
            "size": "l", "type": "expeditionary"}

    The catalogue is generated from the player's own game files at startup, so
    it covers their exact DLC and mods.

STATUS AND FAILURE
    x4.status()   connected, ticking, savegame_loaded, paused
    The game only answers while it renders frames; with its window in the
    background the tick stalls and calls time out. That is a delay, not a loss.
    A Lua error comes back as a message -- read it and fix your chunk.

WHEN YOU WORK SOMETHING OUT
    Write the recipe into API_REFERENCE in server/x4api.py so the next session
    starts from it rather than rediscovering it. See AGENTS.md.
"""


class X4:
    """One way into the game, plus read-only knowledge about it."""

    def __init__(self, bridge: GameBridge, game_dir: str | None = None):
        self._bridge = bridge
        self._game_dir = game_dir
        # Lazily loaded generated tables, keyed by filename.
        self._cache: dict[str, dict] = {}

    # ------------------------------------------------------ the mechanism

    def lua(self, code: str, timeout: float = 120.0):
        """Run Lua inside the game. Returns the value(s) it returns.

        This is the interface, not a fallback. Loop and filter inside the chunk:
        one call is one round trip whatever the chunk does.
        """
        data = self._bridge.call("eval", {"code": code}, timeout=timeout)
        results = data.get("results") or []
        if len(results) == 1:
            return results[0]
        return results

    # Older name, kept because it reads well next to Python code.
    eval_lua = lua

    # -------------------------------------------------------- game files

    def _load(self, name: str, default: dict) -> dict:
        if name not in self._cache:
            try:
                self._cache[name] = json.loads((GENERATED / name).read_text())
            except (OSError, json.JSONDecodeError):
                self._cache[name] = default
        return self._cache[name]

    def api(self, pattern: str = "", limit: int = 40) -> list[str]:
        """Search the game's C API by name or signature."""
        index = self._load("api_index.json", {"functions": {}, "structs": []})
        rx = re.compile(pattern, re.I) if pattern else None
        hits = [info["sig"]
                for name, info in sorted(index.get("functions", {}).items())
                if rx is None or rx.search(name) or rx.search(info["sig"])]
        if len(hits) > limit:
            hits = hits[:limit] + [f"... {len(hits) - limit} more; narrow the pattern"]
        return hits

    def structs(self, pattern: str = "") -> list[str]:
        index = self._load("api_index.json", {"functions": {}, "structs": []})
        rx = re.compile(pattern, re.I) if pattern else None
        return [n for n in index.get("structs", [])
                if rx is None or rx.search(n)]

    def globals(self, pattern: str = "") -> list[str]:
        """Engine Lua globals, enumerated from the live game."""
        names = str(self.lua(
            "local out={} for k,v in pairs(_G) do "
            "if type(v)=='function' then out[#out+1]=k end end "
            "table.sort(out) return table.concat(out, ' ')")).split()
        if pattern:
            rx = re.compile(pattern, re.I)
            names = [n for n in names if rx.search(n)]
        return names

    def order_params(self, order_id: str | None = None):
        """Parameters of an order, from the game's own definition.

        SetOrderParam is positional, so `index` is the number to pass. Omit the
        argument to list every order the game knows, mods included.
        """
        table = self._load("order_params.json", {})
        if order_id is None:
            return sorted(table)
        return table.get(order_id, {})

    def catalog(self) -> dict:
        """macro -> canonical name, class, race, size, type."""
        return self._load("catalog.json", {})

    def model(self, macro: str) -> str | None:
        """Canonical English model name for a ship macro, e.g. "Hyperion"."""
        return (self.catalog().get(macro) or {}).get("name")

    def source(self, pattern: str, limit: int = 12, context: int = 3,
               path: str | None = None) -> list[dict]:
        """Search the game's own Lua and XML for how X4 does something."""
        from gamefiles import find_game_dir, search_source
        return search_source(find_game_dir(self._game_dir), pattern,
                             limit=limit, context=context, path_filter=path)

    def read(self, path: str, start: int = 1, end: int | None = None) -> str:
        """Read one of the game's own script files, with line numbers."""
        from gamefiles import find_game_dir, read_source
        return read_source(find_game_dir(self._game_dir), path, start, end)

    # ------------------------------------------------------------ meta

    def status(self) -> dict:
        st = self._bridge.status()
        st["catalog_ships"] = len(self.catalog())
        st["orders_described"] = len(self.order_params() or [])
        return st

    def help(self) -> str:
        return API_REFERENCE
