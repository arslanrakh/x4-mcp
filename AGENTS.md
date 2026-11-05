# Notes for agents working on x4mcp

You are an AI agent. This repository is **x4mcp**, an MCP bridge between an
agent and a running game of X4: Foundations. It has two halves: a game
extension that opens a socket from inside X4, and an MCP server that gives you
tools to read and control that game.

This file is the one set of agent instructions. `CLAUDE.md` holds a single
line, `@AGENTS.md`, so Claude Code reads it too; put new guidance here, not
there.

You are probably here for one of two reasons, and they are related.

## 1. Someone asked you to do something in the game

**Assume it is a live test of this project, not small talk.** "Send my Katana to
the shipyard on Mars" means: use the MCP tools, actually do it, and find out
whether the feature works.

So:

- **Check the connection first.** `x4_status` tells you whether the game is
  connected, whether a savegame is loaded, and whether the game is ticking.
- **Try to complete the task with the tools.** Do not answer "I cannot control
  the game" and do not explain which menus the player should click. If the
  tools are attached, you can do it.
- **Verify afterwards.** Read the ship back with another `x4.lua(...)`. An
  order that was created but never armed looks exactly like success from the
  call site.
- **There is no missing tool to wait for.** `x4.lua(code)` runs Lua inside the
  game, and the whole game API is reachable from it. If you want something the
  Python side does not offer, write the Lua.

If the game does not answer, read the error. `x4_status` distinguishes "not
connected", "no savegame loaded" and "not ticking" (the game window is in the
background — X4 only runs its UI loop while it renders). None of those mean the
bridge is broken.

## 2. You hit a problem and worked out the answer

**Write the answer back into the repository. This is the important part.**

Every time an agent rediscovers the same trap, the project has failed at
something it could have fixed once. When you solve something, ask where a future
agent would have needed to know it, and put it there:

| What you learned | Where it belongs |
|---|---|
| **Lua that works** | the **cookbook** — save it with `x4_cookbook`, it lands in `cookbook/` as a file. This is the default answer |
| A trap in the data; how to do a task in prose | `API_REFERENCE` in `server/x4api.py` — it travels in the `x4_exec` tool description and is returned by `x4.help()` |
| How you should behave (ask first, verify after) | the `x4_playbook` prompt, and `instructions=` on the server, both in `server/x4mcp_server.py` |
| A capability the tool list does not advertise | tool `title`/`description` in `server/x4mcp_server.py` |
| Anything cross-cutting | this file |

**Save generously, and save without asking.** Anything that worked and took any
working out earns a recipe — queries as much as orders, small helpers included.
Overlap with an existing recipe is not a reason to skip it: two overlapping
recipes cost nothing, and a rediscovery costs a session. The collection is meant
to grow into the hundreds, and search collapses to one line per recipe once a
result set gets wide.

**The one thing never to save is a claim you did not check.** Every recipe
carries a required `verified:` line saying how it was confirmed, in the author's
own words. "Compiled only, never run" is an honest answer and a useful one; an
assured description of something nobody saw work is how the cookbook would start
lying. That field is the entire mechanism — a rule that only lives in a prompt
is advisory, a field that lands in the file and shows up in search is not.

**A recipe that misled you is a bug in this repository.** Replace it under the
same name, or delete it with a reason, in the same turn — not next time. Leaving
it is worse than never having written it, because the next session will trust
it.

Prefer editing the **prompts** over writing a longer answer in chat. A fix in
the API reference helps every future session; an explanation in chat helps one.

Two real examples from this project's history:

- A helper returning "ships with no commander" also returned fleet *leaders*,
  so recruiting one silently tore apart a wing. The fix was not code; it was
  three lines of warning in `API_REFERENCE`.
- An agent once answered "I cannot control X4 directly" even with the tools
  attached, because the only tool was called `x4_exec` and the server
  instructions said "inspect and plan". The fix was renaming and rewriting the
  instructions to say CONTROL.

## No wrappers

**Do not add a method or an op for a game feature.** This is the project's one
architectural rule and it has been violated once already, at cost.

The whole X4 API is reachable from `x4.lua`: its `ffi.cdef` declarations are
global to the Lua state, so ~2000 C functions and every engine Lua global are
in scope. A wrapper can only ever expose the subset its author imagined, and
the agent then inherits that limit for everything nobody anticipated.

Nor is there a performance argument. `x4.lua` is already a bulk mechanism — a
chunk that loops inside the game costs exactly one round trip, the same as a
purpose-built snapshot operation, and is not restricted to fields somebody
chose in advance.

So the game side has exactly one operation that touches the game, `eval`
(`ping` and `info` in the transport are link health checks). When something is hard,
the fix is a **recipe in the cookbook**, or a better discovery path
(`x4.source`, `x4.api`, `x4.order_params`) — never a new wrapper.

The cookbook is not a loophole in that rule. A recipe is Lua an agent wrote,
stored verbatim, readable in full and callable by anyone; it adds no capability
and takes none away. A wrapper is code between the agent and the game that only
its author can change.

## Architecture

```
agent ──MCP/HTTP :8766── x4mcp server ──TCP :8765── x4mcp_64.dll ── Lua in X4
```

X4 9.0 gives extensions a restricted Lua sandbox: **no `io`, no `os`, no
`package`** when Protected UI Mode is on, and `ffi.C` replaced by a proxy that
only allows the game's own API. Arbitrary C functions such as `fopen` or
`CreateFileA` raise "Access to FFI function is restricted". A file-based bridge
is therefore impossible.

The one route out is `package.loadlib`, which exists only when Protected UI Mode
is **off**. It loads `x4mcp_64.dll`, a small native library that owns a
non-blocking TCP socket. Everything else follows from that constraint.

The **game is the TCP client**: it dials out to the server and reconnects by
itself. That is deliberate. Loading a savegame and reloading the UI both destroy
and recreate the Lua state; because the game reconnects, neither needs handling.

| Piece | File | Role |
|---|---|---|
| Native transport | `native/x4mcp.c` | Non-blocking socket, newline-framed JSON. Never blocks the game thread. |
| Lua transport | `extension/x4mcp/ui/x4mcp_transport.lua` | Tick on `onUpdate`, heartbeat, reconnect, request dispatch |
| Lua execution environment | `extension/x4mcp/ui/x4mcp_state.lua` | the single `eval` op, id plumbing, JSON-safe conversion |
| Lua JSON | `extension/x4mcp/ui/x4mcp_json.lua` | Encoder/decoder, written by hand for control over numbers |
| Bridge | `server/bridge.py` | Listener, request/reply correlation, link health |
| Game files | `server/gamefiles.py` | Install autodetection, archive and loose-file reading, artefact generation |
| Agent-facing API | `server/x4api.py` | The `x4` object **and `API_REFERENCE`** |
| Cookbook | `server/cookbook.py` | Recipe files, injection into a chunk, error mapping, **and the `x4_cookbook` tool text** |
| MCP server | `server/x4mcp_server.py` | Tools, prompt, persistent code session |
| Recipes | `cookbook/*.lua` | Saved Lua, one per file. Committed on purpose |

Around them: `scripts/` installs the extension and runs the server (`.sh` and
`.ps1` for each), `native/build.sh` and `build.ps1` rebuild the DLL, `dist/`
holds the prebuilt DLL (committed on purpose, see `.gitignore`), and
`Dockerfile` with `docker-compose.yml` is the container route.

### The cookbook

Saved Lua, one file per recipe, under `cookbook/`. Format and rules are in
[cookbook/README.md](cookbook/README.md); the workflow the agent is pushed
through lives in `TOOL_DESCRIPTION` in `server/cookbook.py`.

Recipes are injected, not uploaded. `x4.lua` scans the chunk for
`cookbook.<name>`, prepends those definitions and anything they call, and sends
one chunk. Nothing is cached game-side, because loading a savegame or reloading
the UI destroys the Lua state — a cached definition would go stale invisibly.

The prelude shifts line numbers, so `rewrite_error` maps a failure back to
either "your chunk, line N" or the recipe's own file and line. That distinction
is the whole point: it tells an agent whether to fix its call or fix the
recipe. `verify.py` writes a deliberately broken recipe and checks the blame
lands on the right line of the right file.

### The tick

Everything game-side runs from `SetScript("onUpdate", ...)` rather than an MD
cue. MD does not run in the main menu and freezes while the game is paused —
and pausing is exactly when a player walks off to ask you something. The cost is
that the tick stalls while the game window is in the background. If that ever
has to be fixed, an MD cue can be added as a second tick source; `M.tick()` is
idempotent for that reason.

### Generated data is never committed

`server/generated/` holds the API index — ~2000 C function signatures scraped
from the game's own scripts — and nothing else; it is rebuilt from the player's
archives at every server start, in under a second. Committing it would ship one
machine's game version, DLC and mod set to everybody else. Do not add it to git.

`cookbook/` is the opposite case and **is** committed: it is written by agents,
not derived from anyone's installation, and sharing it is the point.

## Setup

```bash
cp .env.example .env          # set X4_DIR if autodetection fails, required for Docker
./scripts/install-extension.sh   # or .ps1 on Windows
docker compose up -d          # or ./scripts/run-server.sh
```

Then point an agent at `http://127.0.0.1:8766/mcp`. See `README.md` for the
per-client commands.

**Protected UI Mode must be off**, or the extension cannot load the DLL at all.
Do not use the in-game toggle — it hot-reloads the interface and with heavy UI
mods installed regularly leaves an empty menu. Quit the game and add
`<uisafemode>false</uisafemode>` to `config.xml` in the X4 user folder.

Configuration is entirely through environment variables (`.env`): `X4_DIR`,
`X4MCP_GAME_PORT`, `X4MCP_HTTP_PORT`, `X4MCP_HTTP_HOST`, `X4MCP_TRANSPORT`,
`X4MCP_COOKBOOK_DIR` and `X4MCP_LANGUAGE`. The last is now only recorded in
`x4_status`: live calls replaced the ship catalogue whose language it selected.
The game side reads `X4MCP_HOST` and `X4MCP_GAME_PORT` from the environment X4
itself runs in. The install scripts read `X4_DIR` from the shell environment
and ignore `.env`.

## Development loop

Restarting X4 costs about two and a half minutes. Avoid it.

1. **Fastest — no reload at all.** `x4.lua(code)` runs Lua inside the
   running game. `C` is the FFI namespace, the engine's Lua globals
   (`GetComponentData`, `SetOrderParam`, `ConvertStringToLuaID`) are in scope,
   and `helpers` holds this project's own utilities. Use it to test any
   hypothesis about the game API. Most work needs nothing else.
2. **Changed Lua in `extension/`?** Run `./scripts/install-extension.sh`, then
   ask the player to **load a savegame from the in-game menu**. That recreates
   the menus environment and re-runs the extension's Lua — roughly 40 seconds,
   no process restart.
3. **Changed the server?** Just restart it. The game reconnects on its own
   within a couple of seconds.
4. **Changed the C?** `./native/build.sh`, reinstall, and restart X4 — the DLL
   is loaded into the process and cannot be swapped live. The build needs
   MinGW-w64 and the game folder, since it links against `lua51_64.dll` there.

Check Lua syntax before asking for a reload; a wasted reload costs the player a
minute:

```bash
luajit -bl extension/x4mcp/ui/x4mcp_state.lua >/dev/null
```

Game-side logging goes through `DebugError`. Launch X4 with
`-debug all -logfile x4mcp.log`; the file lands in the X4 user folder
(`Documents/Egosoft/X4/<id>/`), not one level up.

End-to-end check against a live game. It also compiles every saved recipe, so
run it after touching the cookbook:

```bash
.venv/bin/python server/verify.py
```

Without a game you can still check that the server starts. It runs with no X4
found (it logs that and skips the API index) and answers MCP on the HTTP port:

```bash
python3 -m py_compile server/*.py
./scripts/run-server.sh --http-port 18766 --game-port 18765   # Ctrl-C to stop
```

There are no unit tests; `verify.py` against a live game is the test.

## Hard-won knowledge

These cost real debugging. Do not rediscover them.

**The game's working directory is not its install folder.** Started the normal
way — Steam, GOG, a desktop shortcut — X4's cwd is `/` (or `C:\`). Any relative
path passed to `package.loadlib` resolves against the wrong place, the DLL never
loads, and the bridge silently never connects: no error the player can see, no
socket, nothing. This was invisible during early development because the game
was being launched with an explicit `--workdir`.

The installer therefore puts `x4mcp_64.dll` **next to X4.exe** as well as in the
extension folder, and the transport tries a bare filename first: for a bare
name the OS loader searches the executable's own directory whatever the cwd is,
while a name containing a separator does not get that treatment.

If the bridge is connected but the game is not, check this first — the symptom
is a live game process with **no network file descriptors at all**
(`lsof -a -p <pid> -i` returns nothing).

**A container's published port may be unreachable from the game.** The game
dials *into* the server, so with the server in Docker it has to reach the
published port. Measured on macOS with X4 under CrossOver and OrbStack: it never
connects, while the identical server run on the host is reached within seconds.
The tick was verified alive during the test (the game logged `connection lost`
when the host server went away), so this is not the background-stall problem.
Run the server directly on such setups.

**The sector of an object is `sectorid`, not `macro` and not `sector_macro`.**
`macro` is the object's own hull, so grouping by it puts every Hyperion in one
"place" — a filter written that way matched nothing while looking perfectly
reasonable. `sector` beside it is the sector's *displayed* name and therefore
localised. Verified against 9.0 on both a ship and a station:
`GetComponentData` returns `sector`, `sectorid` and `cluster`, and there is no
`sector_macro` field at all. For the sector's macro, read `macro` off the
`sectorid`.

`helpers.comp_data` silently drops keys the game does not know, so asking for a
field that does not exist looks like "this object has no sector" rather than
like a typo.

**Ask the game, not the disk.** Orders, order parameters and ship models all
come from live calls now, and that is not a preference: a mod deployed as
Windows symlinks by a manager running under Wine is invisible from the host
side (zero-byte files with a stray "?" in the name), while the game reads it
fine. Parsing files silently omitted `kAAIT_MoveAvoid` and its parameters;
asking the game returns them.

Order parameters are only exposed for an order that exists on a ship, so
x4.order_params creates it disabled, describes it, and removes it -- the ship
never acts on it and its queue is restored. Verified per call.

Only two things still read the installation, because no runtime equivalent
exists: the index of C signatures (ffi cdefs cannot be enumerated) and
searching the game's own scripts.

**IDs arrive in two shapes.** Enumerators return 64-bit cdata, printed by LuaJIT
as `1234ULL`. `GetComponentData` returns engine Lua ids, printed as `ID: 1234`.
`norm()` in `x4mcp_state.lua` reduces both to the same digit string. If that
ever breaks, `commander` stops matching the `id` it points at, fleet handling
targets nothing, and the result still looks perfectly healthy. `verify.py`
checks referential integrity for exactly this reason.

**An empty Lua table is ambiguous.** `{}` could be `[]` or `{}`. List-valued
fields are tagged with `X4MCP_Json.array()`; without it an empty
`subordinates` arrives as an object and breaks list handling on the host.

**`loaded` goes true before the universe exists.** The heartbeat flips as soon
as the player component appears, well before ships are populated. A snapshot
taken in that window returns zero of everything and looks like a broken
collector. Wait, or re-request.

**`is_fleet_lead` is not "has subordinates".** It is the game's fleet-manager
flag and is often `False` for a ship commanding four others. To find out whether
a ship leads anything, look at `subordinates`.

**X4 accepts inapplicable orders silently.** The ship simply sits there and the
failure goes to the debug log. Always check `C.IsOrderSelectableFor(order, ship)`
first — `cookbook.give_order` does this and refuses rather than reporting a
success that never happens.

**Order parameters are positional, and object arguments need tagging.** A bare
number is not an object reference: the order targets nothing and reports
success. Pass `{id = "1234"}` to `cookbook.give_order`, which converts with
`ConvertStringToLuaID`.

**The game's own cdefs are visible to us.** `ffi.cdef` declarations are global to
the LuaJIT state, so everything X4's menu files declare — `CreateOrder`,
`EnableOrder`, `IsOrderSelectableFor` and ~2000 more — resolves through `C`
without being redeclared. `x4.api("pattern")` searches them. Note that
`SetOrderParam` is a **global Lua function**, not an FFI one; it is not in `C`.

**Displayed names are worthless for logic.** The game may run in any language,
and players rename ships. A ship called "Delilah's Swan Song" is a Syn; in a
Russian install a Hyperion is "Гиперион". Match on `macro`, `owner`, `class`
and `purpose`, and locate things by `sectorid`. Use displayed names only when
talking to the player, because that is what is on their screen.

**Sector ids change between sessions.** Resolve a sector by its macro (read
`macro` off the `sectorid`, as above), then by id, and only then by name.

## Writing style

Comments and log messages are English throughout, including in the Lua and C.
Explain *why* a thing is done, not what the line does — most of the odd-looking
code here is odd because of a constraint documented above, and a comment that
does not carry the constraint is worse than none.
