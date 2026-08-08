#!/usr/bin/env python3
"""
Everything that reads the player's X4 installation.

Nothing derived from the game is committed to this repository. The ship
catalogue and the API index are rebuilt from the local archives on every start,
which takes well under a second and means they always match the exact version,
DLC and mod set that is actually installed. Shipping prebuilt copies would be
wrong the moment somebody adds a DLC, updates the game, or installs a mod that
adds ships or orders.

The install is located automatically -- Steam libraries, GOG and Epic layouts,
Wine and CrossOver bottles, and the native Linux build -- with X4_DIR as an
explicit override for anything unusual.
"""

from __future__ import annotations

import json
import os
import platform
import re
import xml.etree.ElementTree as ET
from pathlib import Path

# ---------------------------------------------------------------- discovery

_MARKERS = ("01.cat", "01.dat")


def _looks_like_x4(path: Path) -> bool:
    return path.is_dir() and all((path / m).exists() for m in _MARKERS)


def _steam_libraries() -> list[Path]:
    """Read Steam's library list; users routinely move games to another disk."""
    roots = [
        Path.home() / ".steam/steam",
        Path.home() / ".local/share/Steam",
        Path.home() / "Library/Application Support/Steam",
        Path("C:/Program Files (x86)/Steam"),
        Path("C:/Program Files/Steam"),
    ]
    libs: list[Path] = []
    for root in roots:
        vdf = root / "steamapps" / "libraryfolders.vdf"
        if not vdf.is_file():
            continue
        libs.append(root)
        try:
            text = vdf.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for match in re.finditer(r'"path"\s*"([^"]+)"', text):
            libs.append(Path(match.group(1).replace("\\\\", "/")))
    return libs


def _candidates() -> list[Path]:
    out: list[Path] = []
    home = Path.home()

    for lib in _steam_libraries():
        out.append(lib / "steamapps/common/X4 Foundations")

    if platform.system() == "Darwin":
        # CrossOver and Whisky keep a Windows filesystem inside a bottle.
        for bottles in (home / "Library/Application Support/CrossOver/Bottles",
                        home / "Library/Application Support/Whisky/Bottles"):
            if bottles.is_dir():
                for bottle in bottles.iterdir():
                    out += list((bottle / "drive_c").glob("**/X4 Foundations*"))

    if platform.system() == "Linux":
        for prefix in (home / ".wine", home / "Games"):
            if prefix.is_dir():
                out += list(prefix.glob("**/X4 Foundations*"))
        out.append(home / "GOG Games/X4 Foundations")

    for drive in ("C:", "D:", "E:"):
        out += [
            Path(f"{drive}/Program Files/x4/X4 Foundations"),
            Path(f"{drive}/GOG Games/X4 Foundations"),
            Path(f"{drive}/Program Files (x86)/GOG Galaxy/Games/X4 Foundations"),
            Path(f"{drive}/Program Files/Epic Games/X4Foundations"),
        ]
    return out


def find_game_dir(explicit: str | Path | None = None) -> Path:
    """Locate the X4 installation, or explain how to point at it."""
    if explicit:
        path = Path(explicit).expanduser()
        if not _looks_like_x4(path):
            raise FileNotFoundError(
                f"{path} does not look like an X4 installation "
                f"(expected 01.cat and 01.dat inside)")
        return path

    env = os.environ.get("X4_DIR")
    if env:
        return find_game_dir(env)

    seen: set[Path] = set()
    for cand in _candidates():
        try:
            resolved = cand.resolve()
        except OSError:
            continue
        if resolved in seen:
            continue
        seen.add(resolved)
        if _looks_like_x4(resolved):
            return resolved

    # A glob can also match a versioned folder name; try one level of nesting.
    for cand in _candidates():
        parent = cand.parent
        if parent.is_dir():
            for child in parent.glob("X4 Foundations*"):
                if _looks_like_x4(child):
                    return child

    raise FileNotFoundError(
        "Could not find an X4: Foundations installation. Set X4_DIR to the "
        "folder that contains 01.cat, for example:\n"
        "  export X4_DIR='/path/to/X4 Foundations'")


# ------------------------------------------------------------------ archives

def cat_entries(cat_path: Path):
    """Yield (inner_path, offset, size). A .cat is a plain text index and the
    matching .dat is the payloads concatenated in the same order."""
    offset = 0
    with cat_path.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.rsplit(" ", 3)
            if len(parts) != 4:
                continue
            try:
                size = int(parts[1])
            except ValueError:
                continue
            yield parts[0], offset, size
            offset += size


def archives(game: Path) -> list[Path]:
    """Base archives first, then extensions: later entries win on conflicts,
    which is how DLC and mods override base content."""
    out: list[Path] = []
    for pattern in ("*.cat", "extensions/*/*.cat"):
        for cat in sorted(game.glob(pattern)):
            if "_sig" not in cat.name and cat.with_suffix(".dat").exists():
                out.append(cat)
    return out


def _read(dat: Path, offset: int, size: int) -> bytes:
    with dat.open("rb") as fh:
        fh.seek(offset)
        return fh.read(size)


LOOSE_ROOTS = ("aiscripts", "md", "ui", "libraries", "t", "assets")


def iter_files(game: Path, wanted, max_size: int = 8_000_000):
    """Yield (logical_path, bytes) for every game file matching `wanted`.

    Covers both packed and loose content. Mods routinely ship plain folders
    rather than .cat archives -- reading only the archives makes their ships,
    orders and scripts invisible, which shows up as a catalogue that silently
    omits half of what the player actually has installed.

    Loose files are yielded last so they override packed ones, matching how the
    game itself resolves extensions.
    """
    for cat in archives(game):
        dat = cat.with_suffix(".dat")
        for inner, offset, size in cat_entries(cat):
            if size <= max_size and wanted(inner):
                yield inner, _read(dat, offset, size)

    for ext in sorted(game.glob("extensions/*")):
        if not ext.is_dir():
            continue
        for root in LOOSE_ROOTS:
            base = ext / root
            if not base.is_dir():
                continue
            for path in base.rglob("*"):
                if not path.is_file():
                    continue
                inner = f"{root}/{path.relative_to(base).as_posix()}"
                try:
                    if path.stat().st_size > max_size or not wanted(inner):
                        continue
                    yield inner, path.read_bytes()
                except OSError:
                    continue


# ------------------------------------------------------------------ catalogue

TEXT_REF = re.compile(r"\{(\d+),(\d+)\}")
COMMENT_RE = re.compile(r"\((?:[^()]*)\)\\?")
MACRO_RE = re.compile(r"^assets/units/size_[^/]+/macros/.+_macro\.xml$")
LUA_RE = re.compile(r"^ui/.+\.(lua|xpl)$")
CDEF_RE = re.compile(r"ffi\.cdef\s*\[\[(.*?)\]\]", re.S)
FUNC_RE = re.compile(
    r"^\s*((?:const\s+)?[A-Za-z_][A-Za-z0-9_]*\s*\**)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)\s*\((.*?)\)\s*;\s*$")
TYPEDEF_RE = re.compile(r"\}\s*([A-Za-z_][A-Za-z0-9_]*)\s*;")

# X4 language ids. English is the reference because the catalogue exists to
# give stable names regardless of what the player installed.
LANGUAGE_IDS = {"en": "044", "de": "049", "fr": "033", "ru": "007",
                "es": "042", "it": "039", "pt": "055", "pl": "048",
                "zh": "086", "ko": "082", "ja": "081"}


def _resolve(text: str, texts: dict, depth: int = 0) -> str:
    if depth > 4 or not text:
        return text
    return TEXT_REF.sub(
        lambda m: _resolve(texts.get((m.group(1), m.group(2)), ""), texts, depth + 1),
        text)


def _parse_macro_name(macro: str):
    for pattern in (r"^ship_[a-z]+_([a-z]+)_(.+?)_\d+_[a-z]+_macro$",
                    r"^ship_[a-z]+_([a-z]+)_(.+?)_macro$"):
        m = re.match(pattern, macro)
        if m:
            return m.group(1), m.group(2)
    return None, None


def build_catalog(game: Path, language: str = "en") -> dict:
    """macro -> canonical name, class, race, size, type."""
    lang_file = f"t/0001-l{LANGUAGE_IDS.get(language, '044')}.xml"
    macros: dict[str, dict] = {}
    texts: dict[tuple[str, str], str] = {}

    def wanted(path: str) -> bool:
        return path == lang_file or bool(MACRO_RE.match(path))

    for inner, blob in iter_files(game, wanted):
        try:
            root = ET.fromstring(blob)
        except ET.ParseError:
            continue
        if inner == lang_file:
            for page in root.iter("page"):
                pid = page.get("id")
                if pid is None:
                    continue
                for t in page.iter("t"):
                    tid = t.get("id")
                    if tid is not None and t.text is not None:
                        texts[(pid, tid)] = t.text
        else:
            for macro in root.iter("macro"):
                name = macro.get("name")
                ident = macro.find("./properties/identification")
                if name and ident is not None:
                    macros[name] = {"class": macro.get("class"),
                                    "name_ref": ident.get("name"),
                                    "race": ident.get("makerrace")}

    catalog = {}
    for macro, info in macros.items():
        if not macro.startswith("ship_"):
            continue
        name = _resolve(info["name_ref"] or "", texts)
        name = COMMENT_RE.sub("", name).replace("\\", "").strip()
        size, kind = _parse_macro_name(macro)
        catalog[macro] = {"name": name or None, "class": info["class"],
                          "race": info["race"], "size": size, "type": kind}
    return catalog


def build_api_index(game: Path) -> dict:
    """Every C function the game declares, so the agent can discover the API."""
    functions: dict[str, dict] = {}
    structs: set[str] = set()

    for inner, blob in iter_files(game, lambda p: bool(LUA_RE.match(p))):
            text = blob.decode("utf-8", "replace")
            if "ffi.cdef" not in text:
                continue
            for body in CDEF_RE.findall(text):
                for line in body.splitlines():
                    m = FUNC_RE.match(line)
                    if m:
                        functions.setdefault(m.group(2),
                                             {"sig": line.strip(), "src": inner})
                structs.update(m.group(1) for m in TYPEDEF_RE.finditer(body))

    return {"functions": functions, "structs": sorted(structs)}


# -------------------------------------------------------------- orchestration

SOURCE_RE = re.compile(r"^(ui/.+\.(lua|xpl)|md/.+\.xml|aiscripts/.+\.xml|libraries/.+\.xml)$")


def iter_source(game: Path):
    """Yield (archive_relative_path, text) for the game's own scripts.

    The game ships its entire UI in readable Lua and its AI in readable XML.
    That is the authoritative answer to "how does X4 itself do this", and it
    beats guessing at an API from signatures alone -- the AssignCommander
    sequence, for instance, is only obvious once you have read the menu code
    that performs it.
    """
    for inner, blob in iter_files(game, lambda p: bool(SOURCE_RE.match(p)),
                                  max_size=4_000_000):
        yield inner, blob.decode("utf-8", "replace")


def search_source(game: Path, pattern: str, limit: int = 40, context: int = 2,
                  path_filter: str | None = None) -> list[dict]:
    """Grep the game's own scripts. Returns matches with surrounding lines."""
    rx = re.compile(pattern, re.I)
    path_rx = re.compile(path_filter, re.I) if path_filter else None
    hits: list[dict] = []

    for inner, text in iter_source(game):
        if path_rx and not path_rx.search(inner):
            continue
        lines = text.splitlines()
        for i, line in enumerate(lines):
            if rx.search(line):
                lo, hi = max(0, i - context), min(len(lines), i + context + 1)
                hits.append({
                    "file": inner,
                    "line": i + 1,
                    "text": "\n".join(lines[lo:hi]),
                })
                if len(hits) >= limit:
                    return hits
    return hits


def read_source(game: Path, path: str, start: int = 1, end: int | None = None) -> str:
    """Read one of the game's own script files, optionally a line range."""
    for inner, text in iter_source(game):
        if inner == path or inner.endswith("/" + path.lstrip("/")):
            lines = text.splitlines()
            stop = len(lines) if end is None else min(len(lines), end)
            body = lines[max(0, start - 1):stop]
            return "\n".join(f"{start + n:6d}  {line}" for n, line in enumerate(body))
    raise FileNotFoundError(f"no such file in the game archives: {path}")


# Any aiscript may declare an order, not only the ones named order.*.xml --
# mods routinely use their own naming, and filtering by filename silently drops
# their orders from the table.
ORDER_FILE_RE = re.compile(r"^aiscripts/.+\.xml$")


def build_order_params(game: Path) -> dict:
    """Parameter lists for every order, read from the game's own definitions.

    X4 declares each order in aiscripts/order.*.xml with named, typed and
    commented parameters. SetOrderParam is positional, so knowing the order of
    these declarations is the difference between an order that works and one
    that is created successfully and does nothing. Generated rather than
    hard-coded, so mod orders are described exactly like stock ones.
    """
    out: dict[str, dict] = {}
    for inner, blob in iter_files(game, lambda p: bool(ORDER_FILE_RE.match(p))):
            try:
                root = ET.fromstring(blob)
            except ET.ParseError:
                continue
            orders = [root] if root.tag == "order" else list(root.iter("order"))
            for order in orders:
                oid = order.get("id")
                if not oid:
                    continue
                params = []
                for i, p in enumerate(order.findall("./params/param"), start=1):
                    params.append({
                        "index": i,          # what SetOrderParam expects
                        "name": p.get("name"),
                        "type": p.get("type"),
                        "default": p.get("default"),
                        "comment": p.get("comment"),
                    })
                out[oid] = {
                    "category": order.get("category"),
                    "file": inner,
                    "params": params,
                }
    return out


def ensure_artifacts(game: Path, cache_dir: Path, language: str = "en") -> dict:
    """Rebuild both artefacts from the installed game. Cheap enough to redo on
    every start, which removes any chance of them going stale."""
    cache_dir.mkdir(parents=True, exist_ok=True)

    index = build_api_index(game)
    (cache_dir / "api_index.json").write_text(
        json.dumps(index, indent=1, ensure_ascii=False, sort_keys=True))

    return {
        "game_dir": str(game),
        "archives": len(archives(game)),
        "api_functions": len(index["functions"]),
        "api_structs": len(index["structs"]),
        "language": language,
    }


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Rebuild game-derived artefacts.")
    ap.add_argument("--game", default=None, help="X4 folder (default: autodetect)")
    ap.add_argument("--language", default="en", choices=sorted(LANGUAGE_IDS))
    ap.add_argument("--cache", default=None, help="output directory")
    args = ap.parse_args()

    game_dir = find_game_dir(args.game)
    cache = Path(args.cache) if args.cache else Path(__file__).resolve().parent / "generated"
    print(json.dumps(ensure_artifacts(game_dir, cache, args.language), indent=1))
