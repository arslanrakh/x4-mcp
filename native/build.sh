#!/usr/bin/env bash
# Build x4mcp_64.dll on macOS or Linux (cross-compile) or in an MSYS2 shell.
#
# The DLL links against lua51_64.dll from the game folder, so the game has to be
# located first. That uses server/gamefiles.py -- the same autodetection the
# server uses -- rather than a path baked in here. Override with X4_DIR.
#
# Cross compiler:
#   macOS   brew install mingw-w64
#   Debian  apt install gcc-mingw-w64-x86-64
#   Windows use build.ps1, or an MSYS2 shell with mingw-w64-x86_64-gcc
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="$ROOT/dist/x4mcp_64.dll"
CC="${CC:-x86_64-w64-mingw32-gcc}"

command -v "$CC" >/dev/null || {
  echo "compiler not found: $CC (see the header of this script)" >&2
  exit 1
}

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

LUA_DLL="$X4_DIR/lua51_64.dll"
[ -f "$LUA_DLL" ] || { echo "not found: $LUA_DLL" >&2; exit 1; }

mkdir -p "$ROOT/dist"
"$CC" -shared -O2 -Wall -Wextra \
  -o "$OUT" \
  "$HERE/x4mcp.c" \
  "$LUA_DLL" \
  -lws2_32 \
  -static-libgcc \
  -Wl,--enable-stdcall-fixup

echo "built: $OUT"
echo "game:  $X4_DIR"
command -v file >/dev/null && file "$OUT"
