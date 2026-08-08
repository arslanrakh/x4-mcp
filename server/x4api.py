#!/usr/bin/env python3
"""
The `x4` object that generated code runs against, plus the reference that
teaches an agent how to use it.

Deliberately thin. There is one way to touch the game -- x4.lua(code) -- and
nothing here wraps a game feature, because a wrapper only ever covers what its
author anticipated.

Facts about the game are asked of the running game rather than parsed from
files wherever that is possible: orders, order parameters and ship models all
come from live calls, so modded content works with nothing to maintain. Only
two things have no runtime equivalent and still read the installation: the
index of C function signatures, and searching the game's own scripts.

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
    x4.orders()                every order the game knows, asked of the game
    x4.order_params("DockAndWait")   its parameters, in SetOrderParam positions
    x4.macro_data(macro)       what the game says about a ship model
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

EVERYTHING ABOUT THE GAME COMES FROM THE GAME
    Orders, their parameters and ship models are all asked of the running game,
    never taken from a table someone maintained. That is what makes modded
    content work without anyone updating anything.

        x4.orders()                    -> 91 entries, mod orders included
        x4.order_params("AssignCommander")
        -> 1 commander  2 assignment  3 subordinategroup  4 setgroupassignment
           5 cancelorders  6 response  7 getnewdefaultorder
           8 informfleetmanager  9 debugchance
        x4.macro_data("ship_par_l_expeditionary_01_a_macro")
        -> {"name": "Hyperion", "type": "expeditionary",
            "purpose": "fight", "race": ["PAR"]}

    order_params works by creating the order disabled, asking the game to
    describe it, and removing it again -- the ship never acts on it and its
    queue is restored. Results are cached for the session.

NAMES ARE FOR THE PLAYER, NOT FOR LOGIC
    The game may run in any language and players rename their ships, so a
    displayed name tells you nothing reliable -- a ship called "Delilah's Swan
    Song" is a Syn. Branch on macro, owner, class and purpose; use names when
    talking to the player, because that is what is on their screen.

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
        # Answers obtained from the running game, cached for the session.
        self._runtime: dict = {}

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

    _ORDERS_LUA = '''
        local ffi = require("ffi")
        pcall(ffi.cdef, [[ typedef struct {
            const char* id; const char* name; const char* icon;
            const char* description; const char* category;
            const char* categoryname; bool infinite; uint32_t requiredSkill;
        } OrderDefinition; ]])
        pcall(ffi.cdef, [[ uint32_t GetNumOrderDefinitions(void);
            uint32_t GetOrderDefinitions(OrderDefinition*, uint32_t); ]])
        local n = tonumber(C.GetNumOrderDefinitions()) or 0
        if n == 0 then return {} end
        local buf = ffi.new("OrderDefinition[?]", n)
        local got = tonumber(C.GetOrderDefinitions(buf, n)) or 0
        local out = {}
        for i = 0, got - 1 do
            out[#out+1] = {
                id = ffi.string(buf[i].id),
                name = ffi.string(buf[i].name),
                description = ffi.string(buf[i].description),
                category = ffi.string(buf[i].category),
                infinite = buf[i].infinite == true,
                required_skill = tonumber(buf[i].requiredSkill),
            }
        end
        return out
    '''

    # Parameters are only exposed for an order that exists on a ship, so the
    # order is created disabled, described, and removed again. The ship never
    # acts on it and its queue is restored; `restored` proves that per call.
    _PARAMS_LUA = '''
        local ships = helpers.enum(C.GetNumAllFactionShips,
                                   C.GetAllFactionShips, "player")
        if #ships == 0 then return { error = "the player owns no ships" } end
        local ship = ships[1]
        local lid = helpers.to_luaid(ship)
        local before = tonumber(C.GetNumOrders(ship))
        local idx = tonumber(C.CreateOrder(ship, "%s", false))
        if idx == 0 then return { error = "CreateOrder refused" } end
        local out = {}
        for i, p in ipairs(GetOrderParams(lid, idx) or {}) do
            out[#out+1] = { index = i, name = tostring(p.name),
                            type = tostring(p.type) }
        end
        C.RemoveOrder(ship, idx, true, false)
        return { params = out,
                 restored = tonumber(C.GetNumOrders(ship)) == before }
    '''

    def orders(self) -> list[dict]:
        """Every order the game knows, asked of the game itself.

        Authoritative: it reflects whatever is actually loaded, so mod orders
        appear without anything having to find their files.
        """
        if "orders" not in self._runtime:
            self._runtime["orders"] = self.lua(self._ORDERS_LUA)
        return self._runtime["orders"]

    def order_params(self, order_id: str) -> list[dict]:
        """An order's parameters, in the positions SetOrderParam expects.

        Read from the running game rather than from any file, so it is correct
        for modded orders too. Costs one round trip per order, then cached.
        """
        cache = self._runtime.setdefault("params", {})
        if order_id not in cache:
            result = self.lua(self._PARAMS_LUA % order_id)
            if isinstance(result, dict) and result.get("error"):
                raise RuntimeError(f"{order_id}: {result['error']}")
            cache[order_id] = (result or {}).get("params") or []
        return cache[order_id]

    def macro_data(self, macro: str) -> dict:
        """What the game itself says about a macro: name, type, purpose, race.

        Asked of the running game, so it covers modded ships with no catalogue
        to maintain. The name is in the game's own language.
        """
        cache = self._runtime.setdefault("macros", {})
        if macro not in cache:
            got = self.lua(
                'return { GetMacroData("%s", "name", "shiptype", '
                '"primarypurpose", "makerrace") }' % macro)
            values = got if isinstance(got, list) else [got]
            cache[macro] = {
                "name": values[0] if len(values) > 0 else None,
                "type": values[1] if len(values) > 1 else None,
                "purpose": values[2] if len(values) > 2 else None,
                "race": values[3] if len(values) > 3 else None,
            }
        return cache[macro]

    def model(self, macro: str) -> str | None:
        """Model name for a ship macro, as the game reports it."""
        return self.macro_data(macro).get("name")

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
        return st

    def help(self) -> str:
        return API_REFERENCE
