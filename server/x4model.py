#!/usr/bin/env python3
"""
Object model for an X4 snapshot (Milestone 2).

The point of this layer is stable attribute names. The agent writes code
against these objects, and if a field is called "role" here, "ship_role" there
and "class" somewhere else, every generated snippet dies on AttributeError
instead of answering the player. So the names below are the contract, they
mirror the Lua collector one to one, and a missing field is None rather than an
absent attribute.

IDs stay strings throughout. X4 component IDs are 64 bit; turning them into
numbers anywhere in the pipeline would silently corrupt them.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field, fields
from pathlib import Path
from typing import Any, Iterator

# Macro -> canonical name, class, race, size, type. Regenerated from the
# player's own installation at startup by gamefiles.ensure_artifacts, so it
# always matches their version, DLC and mods. The running game only ever sends
# the macro, so nothing here depends on the installed language.
CATALOG: dict[str, dict] = {}


def load_catalog(path: str | Path | None = None) -> int:
    """(Re)load the catalogue. Returns how many entries are known."""
    global CATALOG
    target = Path(path) if path else (
        Path(__file__).resolve().parent / "generated" / "catalog.json")
    try:
        CATALOG = json.loads(Path(target).read_text())
    except (OSError, json.JSONDecodeError):
        CATALOG = {}
    return len(CATALOG)


load_catalog()


def _coerce(value: Any) -> Any:
    """The game sends booleans as 0/1 in some fields and true/false in others."""
    return value


@dataclass
class Ship:
    id: str
    name: str | None = None
    idcode: str | None = None
    macro: str | None = None
    ship_class: str | None = None          # "class" is reserved in Python
    size: str | None = None                # s / m / l / xl, parsed from the macro
    type_name: str | None = None
    type_string: str | None = None
    ship_type: str | None = None
    ship_type_name: str | None = None
    role: str | None = None
    role_name: str | None = None
    hull: float | None = None
    hull_max: float | None = None
    hull_percent: float | None = None
    shield_percent: float | None = None
    sector: str | None = None
    sector_id: str | None = None
    sector_macro: str | None = None
    cluster: str | None = None
    owner: str | None = None
    owner_name: str | None = None
    order: str | None = None
    order_action: str | None = None
    assignment: str | None = None
    assignment_name: str | None = None
    subordinate_group: Any = None
    is_fleet_lead: bool | None = None
    fleet: str | None = None
    pilot: str | None = None
    is_docked: bool | None = None
    commander: str | None = None
    subordinates: list[str] = field(default_factory=list)

    # ------------------------------------------------ language-independent view
    #
    # Everything below comes from the macro via the offline catalogue, so it
    # reads the same whatever language the game is installed in. Logic should
    # use these; the localised fields above are for showing the player.

    @property
    def _cat(self) -> dict:
        return CATALOG.get(self.macro or "", {})

    @property
    def model(self) -> str | None:
        """Canonical English model name, e.g. "Hyperion"."""
        return self._cat.get("name")

    @property
    def race(self) -> str | None:
        return self._cat.get("race")

    @property
    def class_name(self) -> str | None:
        """Engine class string, e.g. "ship_l" -- unlike the numeric class id."""
        return self._cat.get("class")

    @property
    def kind(self) -> str | None:
        """Macro-level type, e.g. "expeditionary"."""
        return self._cat.get("type") or self.ship_type

    @property
    def label(self) -> str:
        """What a human would call this ship in chat."""
        base = self.name or self.model or self.id
        if self.model and self.name and self.model != self.name:
            base = f"{self.name}/{self.model}"
        return f"{base} ({self.idcode})" if self.idcode else base

    def matches(self, text: str) -> bool:
        """True if the player could plausibly mean this ship by `text`.

        Deliberately generous: the player may type the English model name while
        the game runs in another language, or paste an idcode, or name the
        macro. Matching only the localised name is what breaks across setups.
        """
        low = (text or "").lower().strip()
        if not low:
            return False
        haystack = (self.name, self.model, self.idcode, self.macro,
                    self.kind, self.class_name)
        return any(low in (h or "").lower() for h in haystack)

    def __repr__(self) -> str:
        size = f" {self.size.upper()}" if self.size else ""
        order = self.order or "idle"
        return f"<Ship{size} {self.label} in {self.sector} order={order}>"


@dataclass
class Station:
    id: str
    name: str | None = None
    idcode: str | None = None
    macro: str | None = None
    station_class: str | None = None
    sector: str | None = None
    sector_id: str | None = None
    sector_macro: str | None = None
    cluster: str | None = None
    owner: str | None = None
    owner_name: str | None = None
    hull_percent: float | None = None
    is_shipyard: bool | None = None
    is_wharf: bool | None = None
    is_equipment_dock: bool | None = None
    is_trade_station: bool | None = None
    is_defence_station: bool | None = None

    @property
    def label(self) -> str:
        if self.name and self.idcode:
            return f"{self.name} ({self.idcode})"
        return self.name or self.idcode or self.id

    def __repr__(self) -> str:
        return f"<Station {self.label} in {self.sector}>"


@dataclass
class Sector:
    id: str
    name: str | None = None
    macro: str | None = None
    owner: str | None = None
    owner_name: str | None = None
    cluster: str | None = None
    known: bool = True

    def __repr__(self) -> str:
        return f"<Sector {self.name} owner={self.owner}>"


@dataclass
class Player:
    id: str | None = None
    name: str | None = None
    money: float | None = None

    def __repr__(self) -> str:
        return f"<Player {self.name} money={self.money}>"


# Snapshot key -> dataclass field. Only renames are listed; everything else
# maps by the same name. Keeping this explicit means a field the game stops
# sending shows up as None instead of blowing up construction.
_RENAMES = {
    Ship: {"class": "ship_class"},
    Station: {"class": "station_class"},
    Sector: {},
    Player: {},
}


def _build(cls, raw: dict) -> Any:
    renames = _RENAMES[cls]
    allowed = {f.name for f in fields(cls)}
    kwargs = {}
    for key, value in raw.items():
        name = renames.get(key, key)
        if name in allowed:
            kwargs[name] = _coerce(value)
    if "id" not in kwargs:
        kwargs["id"] = raw.get("id") or "?"
    return cls(**kwargs)


class World:
    """A loaded snapshot. Everything here is local; no calls back into the game."""

    def __init__(self, data: dict | None = None):
        self.player = Player()
        self.ships: list[Ship] = []
        self.stations: list[Station] = []
        self.sectors: list[Sector] = []
        self.source: str | None = None
        if data:
            self.load(data)

    def load(self, data: dict) -> "World":
        self.source = data.get("source")
        if data.get("player"):
            self.player = _build(Player, data["player"])
        self.ships = [_build(Ship, r) for r in data.get("ships") or []]
        self.stations = [_build(Station, r) for r in data.get("stations") or []]
        self.sectors = [_build(Sector, r) for r in data.get("sectors") or []]
        return self

    # ---------------------------------------------------------------- lookups

    def ship(self, ship_id: str) -> Ship | None:
        return next((s for s in self.ships if s.id == ship_id), None)

    def sector_by_name(self, name: str) -> Sector | None:
        """Accepts the localised name or the macro, so callers need not know
        which language the game is running in."""
        low = (name or "").lower().strip()
        for s in self.sectors:
            if (s.name or "").lower() == low or (s.macro or "").lower() == low:
                return s
        return next((s for s in self.sectors
                     if low and low in (s.name or "").lower()), None)

    def sector_of(self, obj: Ship | Station) -> Sector | None:
        """Resolve by macro first: ids are per-session, names are localised."""
        if obj.sector_macro:
            found = next((s for s in self.sectors
                          if s.macro == obj.sector_macro), None)
            if found:
                return found
        if obj.sector_id:
            found = next((s for s in self.sectors if s.id == obj.sector_id), None)
            if found:
                return found
        return self.sector_by_name(obj.sector or "")

    def find_ships(self, text: str) -> list[Ship]:
        """Match on anything the player might say -- localised name, English
        model, idcode, macro or type."""
        return [s for s in self.ships if s.matches(text)]

    def sectors_of_owner(self, faction: str) -> list[Sector]:
        return [s for s in self.sectors if s.owner == faction and s.known]

    def free_ships(self) -> list[Ship]:
        """Ships that answer to nobody -- safe to pull into a new fleet."""
        return [s for s in self.ships if not s.commander]

    def fleet_of(self, flagship: Ship) -> Iterator[Ship]:
        for sid in flagship.subordinates:
            found = self.ship(sid)
            if found:
                yield found

    # ---------------------------------------------------------------- summary

    def summary(self) -> str:
        by_sector: dict[str, int] = {}
        for s in self.ships:
            by_sector[s.sector or "?"] = by_sector.get(s.sector or "?", 0) + 1
        top = sorted(by_sector.items(), key=lambda kv: -kv[1])[:8]
        owners: dict[str, int] = {}
        for s in self.sectors:
            owners[s.owner or "?"] = owners.get(s.owner or "?", 0) + 1

        lines = [
            f"player: {self.player.name!r} money={self.player.money}",
            f"ships: {len(self.ships)}   stations: {len(self.stations)}   "
            f"sectors: {len(self.sectors)}",
            f"with a commander: {sum(1 for s in self.ships if s.commander)}   "
            f"fleet leads: {sum(1 for s in self.ships if s.is_fleet_lead)}",
            "ships per sector (top): " + ", ".join(f"{k}={v}" for k, v in top),
            "sectors per owner: " + ", ".join(
                f"{k}={v}" for k, v in sorted(owners.items(), key=lambda kv: -kv[1])[:10]),
        ]
        return "\n".join(lines)
