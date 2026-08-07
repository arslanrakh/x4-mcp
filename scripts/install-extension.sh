#!/usr/bin/env bash
# Install the game extension into X4's extensions folder.
#
# The repository is the source of truth; the game folder is a build output.
# After changing anything under extension/, run this and then load a savegame
# in game -- that recreates the Lua environment and picks up the new code
# without restarting X4.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

if [ -z "${X4_DIR:-}" ]; then
  X4_DIR="$(python3 -c "
import sys
sys.path.insert(0, '$ROOT/server')
from gamefiles import find_game_dir
print(find_game_dir())
")" || {
    echo "Could not locate X4. Set X4_DIR to the folder containing 01.cat." >&2
    exit 1
  }
fi

DEST="$X4_DIR/extensions/x4mcp"
mkdir -p "$DEST/ui"

cp "$ROOT/extension/x4mcp/content.xml" "$ROOT/extension/x4mcp/ui.xml" "$DEST/"
cp "$ROOT/extension/x4mcp"/ui/*.lua "$DEST/ui/"

if [ -f "$ROOT/dist/x4mcp_64.dll" ]; then
  cp "$ROOT/dist/x4mcp_64.dll" "$DEST/"
else
  echo "warning: dist/x4mcp_64.dll is missing -- run native/build.sh" >&2
fi

echo "installed into: $DEST"
echo
echo "Next: make sure Protected UI Mode is off (see README), then start X4."
