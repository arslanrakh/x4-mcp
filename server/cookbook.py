#!/usr/bin/env python3
"""
The cookbook: Lua that was worked out once, kept as files in this repository.

Without it every session starts from zero and re-derives the same chunks --
which nine parameters AssignCommander wants, why an order has to be armed and
moved to the front of the queue, that `macro` is the hull and `sector_macro` is
the location. A recipe is that work saved: a Lua function expression, a
signature, and a note about the trap it already handles.

Recipes are plain files under cookbook/, one per recipe, so they are diffable,
reviewable, and shipped with the project rather than buried in a database.

They reach the game with nothing to synchronise. x4.lua scans the chunk being
sent for `cookbook.<name>`, prepends the definitions it finds -- transitively,
so a recipe may call another -- and sends one chunk as before. Nothing is
uploaded and kept game-side, so a savegame load, a UI reload or a reconnect,
each of which destroys the Lua state, cannot leave a stale definition behind.

This is not a wrapper layer. A recipe is Lua the agent wrote, stored verbatim,
callable and readable in full; it adds no capability and hides none.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

# A recipe name has to be a bare Lua identifier: it is used as `cookbook.<name>`
# and as the file name, and both would break on anything else.
NAME_RX = re.compile(r"^[a-z][a-z0-9_]{0,63}$")

# `cookbook.foo`, `cookbook["foo"]`, `cookbook['foo']`
REF_RX = re.compile(r"""\bcookbook\s*(?:\.\s*([A-Za-z_][A-Za-z0-9_]*)"""
                    r"""|\[\s*["']([^"'\]]+)["']\s*\])""")

# Where the game reports an error. Lua renders a loadstring chunk name as
# [string "x4mcp-eval"]:12: ... -- the bare form is matched too, in case a
# future transport names the chunk differently.
LINE_RX = re.compile(r'(?:\[string "x4mcp-eval"\]|x4mcp-eval):(\d+)')

HEADER_OPEN = "--[[ x4mcp recipe"
HEADER_CLOSE = "]]"

META_RX = re.compile(r"^([a-z_]+):\s*(.*)$")


class CookbookError(ValueError):
    """Something the caller can fix by rewriting the call."""


@dataclass
class Recipe:
    name: str
    signature: str
    description: str
    tags: list[str]
    verified: str       # how it was checked, in the author's own words
    code: str
    code_start: int     # 1-based line in the file where `code` begins
    path: Path

    def brief(self) -> dict:
        return {"name": self.name, "signature": self.signature,
                "tags": self.tags, "verified": self.verified,
                "description": self.description}

    def full(self) -> dict:
        return dict(self.brief(), code=self.code, file=str(self.path))


def _parse(path: Path) -> Recipe:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or not lines[0].startswith(HEADER_OPEN):
        raise CookbookError(f"{path.name}: first line must be '{HEADER_OPEN}'")

    close = next((i for i, ln in enumerate(lines)
                  if i > 0 and ln.strip() == HEADER_CLOSE), None)
    if close is None:
        raise CookbookError(f"{path.name}: the header is never closed with ]]")

    meta: dict[str, str] = {}
    description: list[str] = []
    in_description = False
    for line in lines[1:close]:
        if not in_description:
            if not line.strip():
                in_description = True
                continue
            m = META_RX.match(line)
            if m:
                meta[m.group(1)] = m.group(2).strip()
                continue
            in_description = True
        description.append(line)

    # Blank lines between the header and the code would otherwise shift every
    # line number reported for a failure inside this recipe.
    body = lines[close + 1:]
    skipped = 0
    while body and not body[0].strip():
        body.pop(0)
        skipped += 1

    code = "\n".join(body).rstrip()
    if not code:
        raise CookbookError(f"{path.name}: no code after the header")

    tags = [t.strip() for t in meta.get("tags", "").split(",") if t.strip()]
    return Recipe(name=path.stem,
                  signature=meta.get("signature") or f"{path.stem}(...)",
                  description="\n".join(description).strip(),
                  tags=tags, verified=meta.get("verified", ""), code=code,
                  code_start=close + 2 + skipped, path=path)


def _render(signature: str, description: str, tags: list[str],
            verified: str, code: str) -> str:
    lines = [HEADER_OPEN, f"signature: {signature}"]
    if tags:
        lines.append("tags: " + ", ".join(tags))
    lines.append(f"verified: {verified}")
    lines.append("")
    lines.extend(description.strip().splitlines())
    lines.append(HEADER_CLOSE)
    lines.append(code.strip())
    return "\n".join(lines) + "\n"


def _refs(code: str) -> list[str]:
    return [m.group(1) or m.group(2) for m in REF_RX.finditer(code)]


def _matcher(query: str):
    """Treat the query as a regex, and as plain text when it is not one."""
    if not query:
        return None
    try:
        return re.compile(query, re.I)
    except re.error:
        return re.compile(re.escape(query), re.I)


@dataclass
class _Span:
    """Where one recipe ended up in the generated prelude."""
    start: int
    end: int
    name: str
    code_start: int


class Cookbook:
    """The recipe files, read fresh on every access.

    Deliberately stateless: the files are the truth, so editing one by hand, or
    pulling someone else's, takes effect immediately with nothing to invalidate.
    A few dozen small files cost nothing to re-read.
    """

    def __init__(self, directory: Path | str, verifier=None):
        self.dir = Path(directory)
        # Called with the candidate code before a save; returns (ok, note).
        # Injected rather than imported so this module knows nothing about the
        # game link, and so it works with the game closed.
        self._verify = verifier

    # ----------------------------------------------------------------- read

    def load(self) -> tuple[dict[str, Recipe], dict[str, str]]:
        """Every recipe, plus the ones that would not parse and why.

        Broken files are reported rather than skipped: a recipe that silently
        vanishes is indistinguishable from one that was never written, and the
        agent would write it again.
        """
        recipes: dict[str, Recipe] = {}
        broken: dict[str, str] = {}
        if not self.dir.is_dir():
            return recipes, broken
        for path in sorted(self.dir.glob("*.lua")):
            try:
                recipe = _parse(path)
            except (CookbookError, OSError, UnicodeDecodeError) as e:
                broken[path.name] = str(e)
                continue
            recipes[recipe.name] = recipe
        return recipes, broken

    def search(self, query: str = "", limit: int = 500) -> list[dict]:
        recipes, _ = self.load()
        rx = _matcher(query)
        hits = [r for r in recipes.values()
                if rx is None
                or rx.search(r.name) or rx.search(r.signature)
                or rx.search(r.description) or rx.search(" ".join(r.tags))
                or rx.search(r.verified)]
        return [r.brief() for r in hits[:limit]]

    def show(self, name: str) -> dict:
        recipes, broken = self.load()
        if name in recipes:
            return recipes[name].full()
        if f"{name}.lua" in broken:
            raise CookbookError(f"{name} exists but does not parse: "
                                f"{broken[f'{name}.lua']}")
        raise CookbookError(f"no recipe named '{name}'. "
                            f"Known: {', '.join(sorted(recipes)) or '(none)'}")

    # ---------------------------------------------------------------- write

    def save(self, name: str, code: str, signature: str, description: str,
             verified: str, tags: list[str] | str = "") -> dict:
        """Write a recipe, replacing one of the same name.

        Replacing is the correct response to a recipe that misbehaved: leaving
        a wrong one in place is worse than having none, because the next
        session will trust it.

        `verified` is required, and that is the whole mechanism behind "do not
        save what you did not check". A rule that only says so is advisory; a
        field that has to be filled in, lands in the file and shows up in
        search makes the omission visible to the next reader and to the player.
        """
        name = (name or "").strip()
        if not NAME_RX.match(name):
            raise CookbookError(
                f"'{name}' is not a usable recipe name. It becomes "
                f"cookbook.<name> in Lua, so: lowercase letters, digits and "
                f"underscores, starting with a letter.")

        code = (code or "").strip()
        if not re.match(r"^function\s*\(", code):
            raise CookbookError(
                "code must be a Lua function EXPRESSION and nothing else, "
                "starting with 'function(' and ending with 'end'. Not "
                "'function name(...)', not a chunk with a return around it.")

        signature = " ".join((signature or "").split())
        if not signature:
            raise CookbookError(
                "signature is required: it is what search shows, and what a "
                "future session decides on without reading the code. "
                f"For example: {name}(ship_id, target_id) -> index | nil, reason")
        if not (description or "").strip():
            raise CookbookError(
                "description is required. Write what it does and which trap it "
                "handles -- that is the part which cannot be recovered from the "
                "code.")
        verified = " ".join((verified or "").split())
        if not verified:
            raise CookbookError(
                "verified is required: say how you checked this, in one line, "
                "from what you actually observed. For example \"ran on a live "
                "save: the ship's commander read back as the new leader\". If "
                "you only compiled it, say so -- the line is stored and read by "
                "whoever trusts this next. If you cannot fill it in, you are "
                "not ready to save.")
        if any(HEADER_CLOSE in part for part in (description, signature, verified)):
            raise CookbookError("']]' cannot appear in the header fields or the "
                                "description: it closes the header block.")

        if isinstance(tags, str):
            tags = [t.strip() for t in tags.split(",") if t.strip()]
        tags = [t for t in tags if t]

        note = "saved without compiling: the game was not reachable"
        if self._verify is not None:
            ok, note = self._verify(code)
            if not ok:
                raise CookbookError(f"the game refused to compile this: {note}")

        self.dir.mkdir(parents=True, exist_ok=True)
        path = self.dir / f"{name}.lua"
        existed = path.exists()
        path.write_text(_render(signature, description, tags, verified, code),
                        encoding="utf-8")

        return {"saved": name, "replaced": existed, "file": str(path),
                "check": note, "verified": verified,
                "use": f'x4.lua(\'return cookbook.{name}(...)\')'}

    def delete(self, name: str, reason: str) -> dict:
        """Remove a recipe. A reason is required and it is not bureaucracy:
        the deletion lands in git, and the next agent asking why the recipe is
        gone gets an answer instead of rediscovering the same failure."""
        if not (reason or "").strip():
            raise CookbookError(
                "reason is required: say what went wrong, so this is not "
                "written again. If it can be fixed, replace it with save "
                "instead of deleting it.")
        path = self.dir / f"{name}.lua"
        if not path.is_file():
            raise CookbookError(f"no recipe named '{name}'")
        path.unlink()
        return {"deleted": name, "reason": reason.strip()}

    # ------------------------------------------------------------ injection

    def prelude_for(self, code: str) -> tuple[str, list[_Span]]:
        """Lua defining every recipe the chunk mentions, or ("", []).

        Prepended per call rather than uploaded once, so there is no game-side
        state that a savegame load could leave stale, and a chunk always means
        the same thing as the files on disk.
        """
        wanted = _refs(code)
        if not wanted:
            return "", []

        recipes, _ = self.load()
        seen: set[str] = set()
        chosen: list[Recipe] = []
        pending = list(wanted)
        while pending:
            name = pending.pop(0)
            if name in seen:
                continue
            seen.add(name)
            recipe = recipes.get(name)
            if recipe is None:
                continue        # the metatable below reports it at call time
            chosen.append(recipe)
            pending.extend(_refs(recipe.code))

        # An unknown name would otherwise fail as "attempt to call a nil
        # value", which reads like a bug in the agent's own chunk.
        lines = [
            "local cookbook = setmetatable({}, { __index = function(_, k)",
            "\terror(\"no cookbook recipe named '\" .. tostring(k)",
            "\t\t.. \"' -- search the cookbook, or write the Lua yourself\", 2)",
            "end })",
        ]
        spans: list[_Span] = []
        for recipe in sorted(chosen, key=lambda r: r.name):
            body = recipe.code.split("\n")
            start = len(lines) + 1
            lines.append(f"cookbook.{recipe.name} = {body[0]}")
            lines.extend(body[1:])
            spans.append(_Span(start, len(lines), recipe.name, recipe.code_start))

        return "\n".join(lines), spans


def rewrite_error(message: str, prelude_lines: int, spans: list[_Span]) -> str:
    """Point a Lua error at the line the agent can actually edit.

    The prelude shifts every line number in the chunk, and a failure inside a
    recipe would otherwise be reported at a line of code the agent never wrote.
    Naming the recipe file is the point: it turns "my chunk is wrong" into "the
    saved recipe is wrong", which is a different fix.
    """
    def replace(m: re.Match) -> str:
        line = int(m.group(1))
        if line > prelude_lines:
            return f"your chunk, line {line - prelude_lines}"
        for span in spans:
            if span.start <= line <= span.end:
                where = span.code_start + (line - span.start)
                return (f"SAVED RECIPE cookbook/{span.name}.lua:{where} "
                        f"(fix and replace it, or delete it)")
        return f"the cookbook prelude, line {line}"

    return LINE_RX.sub(replace, message)


TOOL_DESCRIPTION = """\
SAVED LUA RECIPES FOR X4 -- THE MEMORY THIS BRIDGE KEEPS BETWEEN SESSIONS.

A recipe is a Lua function that was worked out against the live game once and
stored as a file in the x4mcp repository. Calling one is free: inside any Lua
you send with x4.lua(...), `cookbook.<name>(...)` is already defined. Nothing
to import, nothing to load.

THE LOOP, IN THIS ORDER

 1. LOOK HERE FIRST, before writing new Lua for whatever the player asked.
        x4_cookbook(action="search", query="dock")
        x4_cookbook(action="search")            everything
    Search answers with names, signatures, tags, descriptions and how each was
    verified -- enough to decide. The code is one call away when you want it:
        x4_cookbook(action="show", name="dock_at")

 2. IF ONE FITS, USE IT from x4_exec:
        x4.lua('return cookbook.dock_at("%s", "%s")' % (ship_id, yard_id))
    Recipes compose: a recipe may call another as cookbook.<name>(...).

 3. IF NONE FITS, work it out the usual way -- x4.order_params, x4.source,
    x4.api, x4.lua -- do the task, and then CONFIRM IT HAPPENED by reading the
    game back. An order that was created but never armed looks exactly like
    success from the call site.

 4. SAVE IT, WITHOUT ASKING, AND SAVE GENEROUSLY. This is part of finishing
    the task, not a separate errand and not a decision to put to the player:
    it writes a file in this repository, nothing else, and git can undo it.
    Work left only in the transcript dies with this session.

    Default to saving. Anything that worked -- a query, an order, a check, a
    small helper you needed along the way -- is worth a recipe. Coverage is
    the goal: a cookbook of two hundred recipes is a better cookbook, and a
    recipe nobody ever calls costs nothing while a rediscovery costs a
    session. When in doubt, save it.
        x4_cookbook(
            action="save", name="dock_at",
            signature="dock_at(ship_id, station_id) -> index | nil, reason",
            tags="orders, docking",
            verified="ran on a live save: the Katana's order queue read back "
                     "as DockAndWait, state started",
            description="Orders a ship to dock and makes it the current order. "
                        "Checks IsOrderSelectableFor first, because X4 accepts "
                        "an inapplicable order silently and the ship just sits "
                        "there.",
            code='function(ship_id, station_id) ... end')

 5. IF A SAVED RECIPE MISLED YOU, DEAL WITH IT BEFORE YOU FINISH -- not next
    time, and not by mentioning it in your answer. Either
        x4_cookbook(action="save", name="dock_at", ...)   same name, corrected
    or
        x4_cookbook(action="delete", name="dock_at",
                    reason="CreateOrder returns 0 for stations without a dock")
    A recipe that lies is worse than no recipe, because the next session
    trusts it. Errors raised inside a recipe are reported against the recipe's
    own file and line, so you will know which of the two was at fault.

THE ONLY REASON NOT TO SAVE IS THAT IT IS NOT TRUE YET
    Volume is not a problem here; a wrong recipe is. So the bar is honesty,
    not importance. Hold off only when

      - the task only half worked, or you never read the game back;
      - you cannot say in one line how you checked it;
      - it rested on an assumption you never resolved ("probably the Mars
        shipyard").

    None of these mean "give up on saving". They mean finish the check first,
    or save it with a `verified` line that says exactly how far you got --
    "compiled only, never run" is an honest recipe; a confident description of
    something you never saw work is not.

    A recipe that overlaps an existing one is fine. Prefer improving the
    existing one under the SAME name when yours is plainly better, but never
    let that stop you from saving: two overlapping recipes are cheap, and the
    next session losing a day is not.

    Read-only queries earn a recipe on the same terms as writes. Small helpers
    do too -- if you needed it once, someone needs it again.

MAKE IT GENERAL
    Parameters, not the ids you happened to be holding: no ship, station,
    faction, sector or mission id baked into the body, and no assumption about
    this player, this save or this DLC set. What was specific to today's
    request becomes an argument.

    Name it for what it does -- `dock_at`, not `send_the_katana_to_mars`.

ACTIONS
    search   query (optional; name, signature, tags, text and verified; regex)
    show     name
    save     name, code, signature, description, verified, tags
    delete   name, reason

WHAT THE CODE MUST BE
  - `code` is a Lua FUNCTION EXPRESSION and nothing else:
        function(a, b) ... end
    Not `function name(a, b)`, not a chunk, no `return` wrapped around it.
  - It runs in the environment x4.lua runs in: `C`, `ffi`, `helpers`, and every
    engine Lua global (GetComponentData, SetOrderParam, ConvertStringToLuaID).
  - Take and return ids as plain digit strings -- helpers.id_str -- never
    cdata, so results survive the trip back and compare against each other.
  - Return something. On a refusal return nil and a reason string, so a caller
    can tell "did not apply" from "worked".
  - On save, the running game compiles the code and the save is refused if it
    does not compile. Compiling is not working: it proves the syntax, nothing
    about the game.

WHAT TO WRITE IN `description`
    What a future session needs and cannot get from reading the code: what it
    is for, and which trap it already handles. "Checks IsOrderSelectableFor
    first, because X4 accepts an inapplicable order silently" is worth more
    than any restatement of the lines below it. Caveats belong here too --
    anything that would make someone regret calling it.

WHAT TO WRITE IN `verified`
    One line, required, from what you actually observed -- not what you
    intended. "Ran on a live save: GetCommander read back as the new leader"
    is verification. "Should work" is not. If all you did was compile it, say
    that; the line is stored in the file and shown in search, and the next
    session weighs it before trusting the recipe.
"""
