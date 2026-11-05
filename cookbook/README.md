# The cookbook

Lua that was worked out against a running game once, kept so the next session
starts from it. One file per recipe, and the files are the truth — the server
re-reads them on every access, so editing one by hand or pulling someone else's
takes effect immediately.

Agents read and write these through the `x4_cookbook` MCP tool; its description
carries the rules. This file is for humans reading the repository.

## Format

```lua
--[[ x4mcp recipe
signature: dock_at(ship_id, station_id) -> index | nil, reason
tags: orders, docking
verified: ran on a live save: the ship's order queue read back as DockAndWait

What it does, and — the part that matters — which trap it already handles.
This is what a future session reads before deciding whether to use it.
]]
function(ship_id, station_id)
	...
end
```

The header is `key: value` lines, then a blank line, then free text. The code
below it is a Lua **function expression** and nothing else; the file name minus
`.lua` is the recipe's name: lowercase letters, digits and underscores,
starting with a letter, at most 64 characters.

`verified` is required, and it carries the weight. Agents are told to save
generously — every operation that worked, queries included — so the collection
is expected to grow large and overlap itself; that is fine and intended. What
is not fine is a recipe nobody checked. Requiring one line of *how* turns "do
not save what you did not verify" from advice into something that shows up in
the file, in search results, and in review. "Compiled only, never run" is an
acceptable answer; silence is not.

On save the running game compiles the code and refuses it if it does not
compile; with no game connected the recipe is saved uncompiled and the reply
says so. Deleting a recipe takes a reason. A file edited by hand is not
compiled until a chunk uses it.

## How a recipe reaches the game

Nothing is uploaded. When a chunk sent through `x4.lua(...)` mentions
`cookbook.<name>`, the server prepends that recipe's definition — and anything
it calls, transitively — and sends one chunk as before.

That is deliberate. Loading a savegame or reloading the UI destroys X4's Lua
state without warning, so anything cached game-side would go stale silently.
This way a chunk always means exactly what the files say.

Errors are reported back against the recipe's own file and line, not against
the generated prelude, so a failure inside a saved recipe is distinguishable
from a failure in the caller's Lua.

## Rules for the code

- Runs where `x4.lua` runs: `C`, `ffi`, `helpers`, and every engine Lua global.
- Ids in and out are plain digit strings (`helpers.id_str`), never cdata.
- Return a value; on a refusal return `nil` plus a reason, so a caller can tell
  "did not apply" from "worked".
- Recipes may call each other as `cookbook.<name>(...)`.
