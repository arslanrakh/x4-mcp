#!/usr/bin/env python3
"""
The `x4` object that generated code runs against, plus the reference text that
teaches an agent how to use it.

The reference lives here rather than in a doc file because it has to travel
with the tool: with a single code-execution tool the model has no schema to
introspect, so the description is the only thing standing between it and
guessing field names. It is also returned by x4.help() so the agent can re-read
it mid-session without another tool round trip.
"""

from __future__ import annotations

from dataclasses import fields

from bridge import GameBridge
from x4model import CATALOG, Player, Sector, Ship, Station, World

API_REFERENCE = """\
CONTROLS A RUNNING X4: FOUNDATIONS GAME -- READ AND WRITE.

You can inspect the player's empire AND command it: give ships orders, send
them to dock, move, attack, mine, trade, escort, and reorganise fleets. If the
player asks for something to happen in X4, DO IT HERE. Never answer with
"I cannot control the game" or with instructions to click through menus.

x4_exec runs Python in a persistent namespace on the host, connected to the
live game. Variables survive between calls, like a notebook.

HOW TO CONTROL A SHIP -- the whole pattern, copy it
    "send my Katana to the shipyard on Mars" is four lines:

        x4.refresh()                                   # 1. one bulk read
        ship = x4.find("Katana")[0]                    # 2. pick the ship
        yard = x4.find_stations(sector=ship,           # 3. find the target
                                kinds=["shipyard", "wharf"])[0]
        x4.order(ship, "DockAndWait", [{"id": yard.id}])   # 4. give the order

    Points worth knowing before you write your own:
      - Object arguments are tagged {"id": ...}. A bare number is not an
        object reference and the order will target nothing.
      - x4.order() refuses an order the ship cannot take instead of pretending
        it worked; X4 itself accepts nonsense silently and the ship just sits.
      - x4.orders() lists every order id the game knows, mods included.
      - After ordering, refresh() and read ship.order to confirm it took.

THE ONE RULE FOR READING
    x4.refresh() pulls the whole game state in a single round trip. Everything
    after it is plain local Python and costs nothing. Never loop over ships
    calling back into the game -- there is no per-object call to make, and code
    that expects one is code that will not work.

        x4.refresh()
        print([s.label for s in x4.find("Hyperion")])

STATE
    x4.player     Player
    x4.ships      list[Ship]      every ship the player owns
    x4.stations   list[Station]
    x4.sectors    list[Sector]    sectors that have an owner and are known
    x4.world      the World object holding all of the above
    x4.age        seconds since the last refresh()

LANGUAGE INDEPENDENCE -- READ THIS BEFORE MATCHING ON ANY NAME
    The game may run in any language; this one currently reports Russian. So
    `name`, `sector`, `cluster`, `owner_name` and every *_name field are
    DISPLAY ONLY. Never branch on them.

    Match on these instead, they are identical in every language:
        ship.model        canonical English model, e.g. "Hyperion"
        ship.macro        "ship_par_l_expeditionary_01_a_macro"
        ship.kind         "expeditionary"
        ship.size         "s" | "m" | "l" | "xl"
        ship.class_name   "ship_l"
        ship.race         "paranid"
        ship.role         "fight" | "trade" | "mine" | ...
        obj.owner         faction id: "player", "argon", "teladi", "xenon", ...
        obj.sector_macro  stable sector identity across sessions and languages

    Ship names are also player-editable: a ship called "Delilah's Swan Song"
    can be a Syn. Only .model tells you what it actually is.

SHIP FIELDS
    id, name, idcode, macro, model, kind, size, class_name, race, role
    hull, hull_max, hull_percent, shield_percent
    sector, sector_id, sector_macro, cluster
    owner, owner_name
    order, order_action          current AI command ("" when idle)
    commander                    id of the ship it answers to, or None
    subordinates                 list[str] of ids answering to it
    fleet, is_fleet_lead, subordinate_group, assignment
    pilot, is_docked
    .label                       human-readable, safe to print
    .matches(text)               fuzzy: name, model, idcode, macro, kind, class

STATION FIELDS
    id, name, idcode, macro, sector, sector_id, sector_macro, cluster,
    owner, owner_name, hull_percent,
    is_shipyard, is_wharf, is_equipment_dock, is_trade_station,
    is_defence_station

SECTOR FIELDS
    id, name, macro, owner, owner_name, cluster, known

LOOKUPS
    x4.find("Hyperion")            list[Ship]; matches any language or an idcode
    x4.ship(id)                    Ship by id
    x4.sector_of(ship_or_station)  Sector, resolved by macro (never by name)
    x4.sector_by_name(name)        accepts localised name or macro
    x4.sectors_of_owner("argon")   known sectors of a faction
    x4.free_ships()                ships with commander is None
    x4.fleet_of(ship)              its subordinates as Ship objects

ANY ORDER, INCLUDING THE ONES NOBODY WRAPPED
    There is no per-feature method to wait for. Every order in the game is
    driven the same way, and the parameters come from the game's own
    definition rather than from anyone's memory:

        x4.order_params("AssignCommander")
        -> 1 commander (object)     2 assignment (internal)
           3 subordinategroup       4 setgroupassignment (bool)
           5 cancelorders (bool)    6 response
           7 getnewdefaultorder     8 informfleetmanager   9 debugchance

        x4.order(ship, "AssignCommander", {
            "commander": {"id": flagship.id},
            "assignment": "interception",
            "subordinategroup": 1,
            "setgroupassignment": True,
        })

    Passing a name that is not in the definition raises rather than being
    silently dropped. Omitted parameters keep the game's own defaults.

    Fleet edits specifically: the precondition check goes on the SUBORDINATE,
    not the commander -- can_order(commander, "AssignCommander") answers a
    different question. A ship with no pilot cannot be assigned at all.
    Assignments are "attack", "interception", "defence", "trade", "mining",
    "supplyfleet", "salvage", "police"; read them off a live fleet with
    C.GetSubordinateGroupAssignment(commander_id, group).

    Always re-read the ship afterwards: orders are queued, not instant, and an
    existing queue can delay or block one.

FLEETS
    A fleet is a commander and its subordinates, and it nests: a ship can lead
    one wing while answering to another.

    Two traps, both of which produce a plausible-looking wrong answer:
      - `commander is not None` means the ship already answers to somebody.
        Recruiting it tears apart an existing wing.
      - free_ships() only checks `commander is None`, so it also returns fleet
        LEADERS. Check `not ship.subordinates` as well before treating a ship
        as spare.
      - `is_fleet_lead` is not "has subordinates" -- it is the game's fleet
        manager flag and is often False for a commander. To find out whether a
        ship leads anything, look at `subordinates`.

STATUS AND FAILURE
    x4.status()   link state: connected, ticking, savegame_loaded, paused
    The game only answers while it renders frames. With its window in the
    background the tick stalls and calls time out; the error says so. That is a
    delay, not a loss -- retry once the game is in focus.

THE WIDER UNIVERSE
    refresh() covers the player's own property only. NPC stations -- shipyards,
    wharves, trade docks -- are fetched on demand, because the galaxy holds over
    a thousand of them and filtering happens in the game:

        yard = x4.find_stations(sector=ship, kinds=["shipyard", "wharf"])
        x4.find_stations(factions=["argon"], kinds=["equipmentdock"], limit=20)

    `sector` accepts a Sector, any Ship/Station (its sector is used), or a macro.

FULL GAME API -- THERE IS NO WRAPPER YOU NEED TO WAIT FOR
    Everything the game itself can do is already reachable. X4's ffi.cdef
    declarations are global to the Lua state, so ~2000 C functions resolve
    through `C` without being redeclared, and the engine's Lua globals are in
    scope too. If this API has no method for what you want, that is not a
    limitation -- write the Lua yourself.

        x4.api("Order")        C signatures matching a pattern
        x4.structs("Order")    struct names for ffi.new
        x4.globals("Convert")  engine Lua globals (not FFI)
        x4.eval_lua(code)      run it

    WHEN A SIGNATURE IS NOT ENOUGH, READ THE GAME'S OWN CODE
    X4 ships its entire UI as readable Lua and its AI as readable XML. That is
    the authoritative recipe for any action, and it is searchable from here:

        x4.source("AssignCommander")          where and how the game does it
        x4.source("SetOrderParam", path="interactmenu")
        x4.read("ui/addons/ego_interactmenu/menu_interactmenu.lua", 540, 580)

    Do this before concluding that something is impossible. Most "the game
    does not allow it" conclusions are really "the call needs parameters the
    signature does not show". Assigning a commander looks like one CreateOrder
    call and is in fact seven positional parameters plus a queue reorder --
    obvious only once you have read the menu code.

    When you work out a recipe this way, write it into API_REFERENCE in
    server/x4api.py so the next session starts from it. See AGENTS.md.

GIVING ORDERS -- THIS IS SUPPORTED, USE IT
    x4.orders()                    the order registry from the game, mods included
    x4.can_order(ship, "DockAndWait")
    x4.order(ship, order_id, params=[...], first=True)

    Parameters are positional, exactly as the order defines them. Object
    parameters must be tagged so they arrive as engine ids, not numbers:

        yard = x4.find_stations(sector=katana, kinds=["wharf", "shipyard"])[0]
        x4.order(katana, "DockAndWait", [{"id": yard.id}])

    x4.order() refuses an order the ship cannot take rather than reporting a
    success that never happens: X4 accepts an inapplicable order silently and
    the ship simply sits there. Pass force=True to override.

    This writes to the player's game. Say what you are about to do; for
    anything they did not explicitly ask for, confirm first.

OUTPUT
    Whatever you print() is returned, plus the value of a trailing expression.
    Exceptions come back as a full traceback -- read it and fix the code
    yourself rather than asking the player.
"""


class X4:
    """Facade the generated code sees. Deliberately small and stable."""

    def __init__(self, bridge: GameBridge, game_dir: str | None = None):
        self._bridge = bridge
        self._world = World()
        self._refreshed_at: float | None = None
        self._game_dir = game_dir

    # ------------------------------------------------------------- refresh

    def refresh(self, limit: int | None = None) -> World:
        """One bulk read of the whole game state."""
        import time
        args: dict = {}
        if limit:
            args["limit"] = limit
        data = self._bridge.call("snapshot", args, timeout=120.0)
        self._world = World(data)
        self._refreshed_at = time.time()
        return self._world

    @property
    def age(self) -> float | None:
        import time
        if self._refreshed_at is None:
            return None
        return round(time.time() - self._refreshed_at, 1)

    def _need(self) -> World:
        if self._refreshed_at is None:
            raise RuntimeError("call x4.refresh() first -- no snapshot loaded yet")
        return self._world

    # --------------------------------------------------------------- state

    @property
    def world(self) -> World:
        return self._need()

    @property
    def player(self) -> Player:
        return self._need().player

    @property
    def ships(self) -> list[Ship]:
        return self._need().ships

    @property
    def stations(self) -> list[Station]:
        return self._need().stations

    @property
    def sectors(self) -> list[Sector]:
        return self._need().sectors

    # ------------------------------------------------------------- lookups

    def find(self, text: str) -> list[Ship]:
        return self._need().find_ships(text)

    def ship(self, ship_id: str) -> Ship | None:
        return self._need().ship(ship_id)

    def sector_of(self, obj):
        return self._need().sector_of(obj)

    def sector_by_name(self, name: str):
        return self._need().sector_by_name(name)

    def sectors_of_owner(self, faction: str) -> list[Sector]:
        return self._need().sectors_of_owner(faction)

    def free_ships(self) -> list[Ship]:
        return self._need().free_ships()

    def fleet_of(self, ship: Ship) -> list[Ship]:
        return list(self._need().fleet_of(ship))

    # -------------------------------------------------------- introspection

    def help(self) -> str:
        return API_REFERENCE

    def schema(self, cls=Ship) -> list[str]:
        return [f.name for f in fields(cls)]

    def status(self) -> dict:
        st = self._bridge.status()
        st["snapshot_age_seconds"] = self.age
        st["catalog_ships"] = len(CATALOG)
        return st

    def summary(self) -> str:
        return self._need().summary()

    # ------------------------------------------------------- wider universe

    def find_stations(self, sector=None, kinds=None, factions=None,
                      known_only: bool = True, limit: int = 200) -> list[Station]:
        """Stations beyond the player's own -- shipyards, wharves, docks.

        Not part of refresh() on purpose: the galaxy holds well over a thousand
        stations and shipping them all on every snapshot would cost far more
        than it buys. Filtering happens inside the game.

        `sector` accepts a Sector, a Ship/Station (its sector is used), or a
        sector macro string.
        """
        macro = None
        if sector is not None:
            # Order matters: a Ship and a Station carry BOTH `macro` (their own
            # hull) and `sector_macro`. Reading `macro` first quietly filtered
            # by the ship's model instead of its location and always matched
            # nothing.
            macro = getattr(sector, "sector_macro", None) \
                or getattr(sector, "macro", None) \
                or str(sector)
        args = {
            "sector_macro": macro,
            "kinds": list(kinds) if kinds else None,
            "factions": list(factions) if factions else None,
            "known_only": known_only,
            "limit": limit,
        }
        data = self._bridge.call("find_stations",
                                 {k: v for k, v in args.items() if v is not None},
                                 timeout=120.0)
        from x4model import _build
        return [_build(Station, r) for r in data.get("stations") or []]

    # -------------------------------------------------------------- orders

    def orders(self) -> list[dict]:
        """The order registry, straight from the game -- mod orders included."""
        data = self._bridge.call("order_definitions", {}, timeout=60.0)
        return data.get("orders") or []

    def order_params(self, order_id: str) -> dict:
        """What an order takes, read from the game's own definition.

        SetOrderParam is positional, so `index` here is the number to pass.
        This is generated from aiscripts/order.*.xml, so mod orders are
        described exactly like stock ones.

            x4.order_params("AssignCommander")
            -> {"category": "navigation", "params": [
                 {"index": 1, "name": "commander", "type": "object",
                  "comment": "New commander. No commander means remove ..."},
                 ...]}
        """
        import json
        from pathlib import Path
        path = Path(__file__).resolve().parent / "generated" / "order_params.json"
        try:
            table = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            return {}
        return table.get(order_id, {})

    def can_order(self, ship, order: str) -> bool:
        ship_id = getattr(ship, "id", ship)
        data = self._bridge.call("can_order", {"ship": str(ship_id), "order": order})
        return bool(data.get("can_order"))

    def _positional(self, order_id: str, params) -> list:
        """Turn named parameters into the positional list SetOrderParam wants.

        Names come from the game's own order definition, so this works for
        every order including ones added by mods, and nothing about any
        particular order is encoded here.
        """
        if params is None:
            return []
        if isinstance(params, (list, tuple)):
            return list(params)

        spec = self.order_params(order_id).get("params") or []
        if not spec:
            raise RuntimeError(
                f"no parameter definition found for {order_id}; pass a "
                f"positional list, or read it with x4.source({order_id!r})")

        index_of = {p["name"]: p["index"] for p in spec}
        unknown = [k for k in params if k not in index_of]
        if unknown:
            raise RuntimeError(
                f"{order_id} has no parameter(s) {unknown}. Known: "
                f"{[p['name'] for p in spec]}")

        # "__nil__" is the wire form of nil: skipped parameters must stay unset
        # rather than become false or zero.
        out = ["__nil__"] * max(index_of[k] for k in params)
        for name, value in params.items():
            out[index_of[name] - 1] = value
        return out

    def order(self, ship, order: str, params=None,
              first: bool = True, enable: bool = True, force: bool = False) -> dict:
        """Give a ship an order. This changes the player's game.

        `params` may be a dict of names, resolved through the game's own order
        definition, or a positional list. Object arguments must be tagged so
        they arrive as engine ids rather than numbers: {"id": station.id}.

            x4.order(katana, "DockAndWait", {"destination": {"id": yard.id}})
            x4.order(ship, "AssignCommander", {
                "commander": {"id": flagship.id},
                "assignment": "interception",
                "subordinategroup": 1,
                "setgroupassignment": True,
            })
        """
        ship_id = getattr(ship, "id", ship)
        args = {
            "ship": str(ship_id),
            "order": order,
            "params": self._positional(order, params),
            "first": first,
            "enable": enable,
            "force": force,
        }
        data = self._bridge.call("create_order", args, timeout=60.0)
        if not data.get("ok"):
            raise RuntimeError(f"{data.get('err')}: {data.get('detail')}")
        return data

    # ------------------------------------------------------- API discovery

    def api(self, pattern: str = "", limit: int = 40) -> list[str]:
        """Search the game's C API by name or signature.

        The whole surface -- around two thousand functions -- is callable from
        eval_lua, because the game's own ffi.cdef declarations are global to
        the Lua state. This is how you find out what exists.
        """
        import re
        index = _api_index()
        rx = re.compile(pattern, re.I) if pattern else None
        hits = [info["sig"] for name, info in sorted(index.get("functions", {}).items())
                if rx is None or rx.search(name) or rx.search(info["sig"])]
        if len(hits) > limit:
            hits = hits[:limit] + [f"... {len(hits) - limit} more; narrow the pattern"]
        return hits

    def source(self, pattern: str, limit: int = 12, context: int = 3,
               path: str | None = None) -> list[dict]:
        """Search the game's OWN scripts for how X4 does something.

        This is the answer to "the API has no wrapper for what I need". X4
        ships its entire UI as readable Lua and its AI as readable XML, so the
        authoritative recipe for any action is in there. Signatures alone are
        rarely enough -- assigning a commander, for example, turns out to need
        seven positional parameters and a queue reorder, which no signature
        tells you.

            x4.source("AssignCommander")
            x4.source("SetOrderParam", path="interactmenu")
        """
        from gamefiles import find_game_dir, search_source
        return search_source(find_game_dir(self._game_dir), pattern,
                             limit=limit, context=context, path_filter=path)

    def read(self, path: str, start: int = 1, end: int | None = None) -> str:
        """Read one of the game's own script files, with line numbers."""
        from gamefiles import find_game_dir, read_source
        return read_source(find_game_dir(self._game_dir), path, start, end)

    def structs(self, pattern: str = "") -> list[str]:
        import re
        names = _api_index().get("structs", [])
        rx = re.compile(pattern, re.I) if pattern else None
        return [n for n in names if rx is None or rx.search(n)]

    def globals(self, pattern: str = "") -> list[str]:
        """Engine Lua globals available inside eval_lua, read from the live game."""
        code = ("local out={} for k,v in pairs(_G) do "
                "if type(v)=='function' then out[#out+1]=k end end "
                "table.sort(out) return table.concat(out, ' ')")
        names = str(self.eval_lua(code)).split()
        if pattern:
            import re
            rx = re.compile(pattern, re.I)
            names = [n for n in names if rx.search(n)]
        return names

    # -------------------------------------------------------- escape hatch

    def eval_lua(self, code: str, timeout: float = 30.0):
        """Run Lua inside the game. Returns the returned value(s).

        `C` is the game's FFI namespace and every function x4.api() lists is
        callable through it. Engine Lua globals are in scope as well.
        """
        data = self._bridge.call("eval", {"code": code}, timeout=timeout)
        results = data.get("results") or []
        if len(results) == 1:
            return results[0]
        return results


_API_INDEX: dict | None = None


def _api_index() -> dict:
    """Loaded lazily: the index is generated at startup, after this import."""
    global _API_INDEX
    if _API_INDEX is None:
        import json
        from pathlib import Path
        path = Path(__file__).resolve().parent / "generated" / "api_index.json"
        try:
            loaded = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            loaded = {"functions": {}, "structs": []}
        _API_INDEX = loaded
    return _API_INDEX
