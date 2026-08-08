# x4mcp

An MCP bridge that lets an AI agent read **and control** a running game of
[X4: Foundations](https://www.egosoft.com/games/x4/info_en.php).

Ask your agent "how are my fleets organised?" or "send the Katana to the
shipyard on Mars", and it queries the live game and gives the order.

```
> how many ships do I have and how are my fleets organised?

[X4 MCP | live game | connected, savegame loaded | snapshot 0.1s old]
8 ships, 1 station, 124 known sectors

Hyperion NQI-361 commands Katana JBK-764, Hyperion ZVK-956,
                          Theseus Sentinel NHW-472, Theseus Sentinel KPU-455
  └ Hyperion ZVK-956 commands Kukri ZNM-847
2 ships answer to nobody: Guillemot Sentinel KFG-438, Syn LVK-346
```

Works on Windows, and on macOS/Linux where X4 runs under CrossOver, Wine or
Proton — the game half is a normal Windows DLL either way.

## Contents

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Protected UI Mode](#protected-ui-mode)
- [Install](#install)
- [Connect your agent](#connect-your-agent)
- [What the agent can do](#what-the-agent-can-do)
- [The cookbook](#the-cookbook)
- [Configuration](#configuration)
- [Building the DLL](#building-the-dll)
- [Development](#development)
- [Limitations](#limitations)
- [Safety](#safety)

## How it works

```
agent ──MCP/HTTP :8766── x4mcp server ──TCP :8765── x4mcp_64.dll ── Lua in X4
```

X4 9.0 gives extensions a heavily restricted Lua sandbox: no `io`, no `os`, and
`ffi.C` replaced by a proxy that only allows the game's own API. File-based
bridges cannot work. The one route out is `package.loadlib`, available when
Protected UI Mode is off, which loads a small native DLL owning a non-blocking
TCP socket.

The **game is the client**: it dials out to the server and reconnects on its
own. Savegame loads and UI reloads both recreate the Lua state, and because the
game reconnects there is nothing to handle on either side.

Everything the game itself can do is reachable. X4's `ffi.cdef` declarations are
global to the Lua state, so roughly 2000 C functions resolve without being
redeclared — the same API its own interface uses to give orders.

## Requirements

- X4: Foundations 9.0 or newer
- **Protected UI Mode switched off** — see below
- Either Docker, or Python 3.11+
- A C toolchain only if you want to rebuild the DLL; a prebuilt one is included

## Protected UI Mode

This mode exists to stop third-party UI mods from touching your system, and
this bridge is exactly the kind of thing it blocks. With it on, the Lua sandbox
has no `package` at all and no extension can load a native library. Turning it
off is a deliberate decision — do it only if you trust what you are running.

**Do not use the in-game toggle.** It hot-reloads the interface, which with
heavy UI mods installed regularly leaves you staring at an empty menu. Quit the
game instead and add one line to `config.xml` in your X4 user folder, just
before `</root>`:

```xml
<uisafemode>false</uisafemode>
```

The user folder is `Documents/Egosoft/X4/<id>/` on Windows, or the same path
inside the Wine prefix elsewhere. If the line is not there yet, the mode is on.

## Install

### 1. The game extension

**Windows**

```powershell
.\scripts\install-extension.ps1
```

**macOS / Linux**

```bash
./scripts/install-extension.sh
```

Both locate X4 automatically — Steam libraries (including ones moved to another
drive), GOG, Epic, CrossOver and Whisky bottles, Wine prefixes. Set `X4_DIR` if
your install is somewhere unusual. You can also copy `extension/x4mcp` plus
`dist/x4mcp_64.dll` into X4's `extensions` folder by hand.

### 2. The server

```bash
cp .env.example .env             # X4_DIR only needed if autodetection fails
./scripts/run-server.sh          # macOS/Linux, creates a venv on first run
.\scripts\run-server.ps1         # Windows
```

**With Docker** — set `X4_DIR` in `.env` first, since the container cannot
autodetect a path on your host:

```bash
docker compose up -d
```

> **Docker caveat.** The game connects *into* the server, so it has to reach the
> container's published port. On macOS with X4 under CrossOver and OrbStack
> publishing the port, it does not: the game retries forever while the same
> server run directly on the host is reached immediately. If `x4_status` reports
> `connected: false` while X4 is running and ticking, this is why — run the
> server directly instead. Docker is fine on Linux, where published ports live
> on the host's own network stack.

On start the server locates X4 and indexes the ~2000 C function signatures its
scripts declare, into `server/generated/`. That takes under a second and
happens every time, so it always matches your version, DLC and mods. Everything
else — the order list, order parameters, ship models — is asked of the running
game rather than parsed from files. Nothing game-derived is committed here.

## Connect your agent

The server speaks MCP over streamable HTTP at `http://127.0.0.1:8766/mcp`.

```bash
# Codex (the CLI and the desktop app share ~/.codex/config.toml)
codex mcp add x4 --url http://127.0.0.1:8766/mcp

# Claude Code
claude mcp add --transport http x4 http://127.0.0.1:8766/mcp
```

For Claude Desktop, add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "x4": { "url": "http://127.0.0.1:8766/mcp" }
  }
}
```

HTTP rather than stdio on purpose: only one process can own the game port, so
with stdio every client session would spawn its own server and all but the first
would fail to bind. One long-running server also survives client restarts, and
can be restarted without touching the client.

## What the agent can do

Three tools:

| Tool | Purpose |
|---|---|
| `x4_exec(code)` | Run Python against the live game, in a namespace that persists between calls |
| `x4_cookbook(...)` | Search, read, save and delete the saved Lua recipes |
| `x4_status()` | Link health: connected, ticking, savegame loaded |

There is no tool per game feature, and that is the design. X4's `ffi.cdef`
declarations are global to its Lua state, so **`x4.lua(code)` already reaches
everything the game can do** — a wrapper could only ever expose the subset its
author imagined. The full API reference travels inside the `x4_exec`
description instead, because with one code-execution tool there is no schema
for a model to introspect.

```python
x4.lua('''                                    # one chunk, one round trip
    local out = {}
    for _, uid in ipairs(helpers.enum(C.GetNumAllFactionShips,
                                      C.GetAllFactionShips, "player")) do
        local d = helpers.comp_data(helpers.to_luaid(uid), {"name", "idcode"})
        d.id = helpers.id_str(uid)
        out[#out+1] = d
    end
    return out
''')
x4.orders()                                   # every order, mods included
x4.order_params("DockAndWait")                # asked of the running game
x4.source("AssignCommander")                  # search the game's own scripts
x4.api("Order")                               # search the game's C API
```

## The cookbook

Working out how to do something in X4 is most of the effort, and it used to be
thrown away at the end of every session. Recipes are that work kept: Lua
functions, verified against a running game, stored as files in
[cookbook/](cookbook/).

```
> put the Kukri in the Beta wing of Sol's Iron Vanguard

[X4 MCP | cookbook] 2 of 15 recipes matching 'commander' — .../cookbook
set_commander(sub_id, commander_id, assignment, group) -> {index, commander_now}
    Put a ship under a commander, or release it...
```

The agent is told to look here before writing new Lua, to save what it works
out, and to **replace or delete a recipe that misled it** rather than leave it.
Using one costs nothing: any chunk that mentions `cookbook.<name>` gets that
recipe's definition prepended automatically, transitively, with no state kept
inside the game — which matters, because loading a savegame destroys X4's Lua
state without warning. Errors are reported against the recipe's own file and
line, so a bad recipe is distinguishable from a bad caller.

They are ordinary files: readable in a diff, editable by hand, and shareable —
a recipe someone else worked out arrives with a `git pull`.

### Language independence

The game may be installed in any language, so displayed names are treated as
display only. Logic runs on stable identifiers — `macro`, `owner`, `class`,
`sectorid` — while `name` and `sector` are for talking to the player, since
that is what is on their screen.

That matters more than it sounds. A ship named "Delilah's Swan Song" is a Syn;
in a Russian install a Hyperion is "Гиперион". Matching on the displayed name
finds neither.

## Configuration

Everything is set through the environment, or a `.env` file that both Docker
Compose and the run scripts read. See [.env.example](.env.example) for the full
list with examples per platform.

| Variable | Default | Meaning |
|---|---|---|
| `X4_DIR` | autodetect | X4 folder containing `01.cat`; required for Docker |
| `X4MCP_GAME_PORT` | `8765` | Port the game connects to |
| `X4MCP_HTTP_PORT` | `8766` | Port your agent connects to |
| `X4MCP_LANGUAGE` | `en` | Language for canonical ship names |
| `X4MCP_HTTP_HOST` | `127.0.0.1` | MCP bind address |
| `X4MCP_TRANSPORT` | `http` | `http` or `stdio` |
| `X4MCP_COOKBOOK_DIR` | `./cookbook` | Where saved Lua recipes are kept |

The game side reads `X4MCP_HOST` and `X4MCP_GAME_PORT` too, from the
environment X4 itself runs in; without them it uses the defaults.

## Building the DLL

A prebuilt `dist/x4mcp_64.dll` is included and works with every X4 install: it
imports `lua51_64.dll` by name rather than binding to one copy. Rebuild it only
if you change the C source.

```bash
./native/build.sh          # macOS/Linux cross-compile, or an MSYS2 shell
```
```powershell
.\native\build.ps1         # Windows
```

Needs MinGW-w64: `brew install mingw-w64`, `apt install gcc-mingw-w64-x86-64`,
or `pacman -S mingw-w64-x86_64-gcc` under MSYS2.

## Development

The repository is the source of truth; the game folder is a build output.

```bash
# edit extension/x4mcp/ui/*.lua
./scripts/install-extension.sh
# then load a savegame in game -- that recreates the Lua environment and picks
# up the new code in ~40s, without restarting X4
```

Faster still: `x4.lua(...)` runs Lua inside the game with no reload at all,
which is how most of this was developed.

```bash
.venv/bin/python server/verify.py   # end-to-end check against a running game
```

## Limitations

- **The tick stops while the game window is in the background.** X4 only runs
  its UI loop while rendering, so requests queue and are answered when you
  switch back. Nothing is lost; replies are delayed. `x4_status` reports this
  as `ticking: false`.
- The exposed API has no galaxy-wide sector enumerator, so unowned sectors have
  to be reached another way.
- A recipe compiles at save time, but nothing can prove it still *works* after
  a game or mod update. That is what the replace-or-delete rule is for.

## Safety

`x4_exec` runs arbitrary Python on your machine and `x4.lua` runs arbitrary Lua
inside your game. That is the design — it is what lets the agent do anything the
game can do. Two consequences worth stating plainly:

- Keep a backup save while experimenting. An agent can reorganise your fleets
  or empty your account as easily as it can answer a question.
- Ship names, station names and mission text come from the game and reach the
  agent's context. Treat them as untrusted input, the same as any web page.

## Contributing

[AGENTS.md](AGENTS.md) is the working guide — how the pieces fit, how to
iterate without restarting the game every time, and the traps that cost real
debugging. It is addressed to AI agents, since much of this is written by them,
but it is the fastest way in for anyone.

One convention worth calling out: when you work out how to do something through
this bridge, write it back. Working Lua goes in the [cookbook](cookbook/) — save
it with the `x4_cookbook` tool and the file lands in this repository. Prose that
does not fit in a recipe, such as a trap or a rule of thumb, goes into
`API_REFERENCE` in `server/x4api.py`, which travels inside the tool description.
Either way the next agent starts where you finished instead of rediscovering it.

## License

MIT — see [LICENSE](LICENSE).
