#!/usr/bin/env bash
# Build x4mcp_64.dll on macOS or Linux (cross-compile) or in an MSYS2 shell.
#
# X4 does not need to be installed: the DLL imports lua51_64.dll by name, and
# the import library comes from lua51_64.def. The output carries no timestamp,
# so the same compiler gives the same bytes on every run.
#
# This builds with whatever MinGW-w64 you have. The committed dist/x4mcp_64.dll
# comes from the pinned toolchain in native/Dockerfile instead (reproduce.sh),
# and CI checks that it matches the source byte for byte.
#
# Cross compiler:
#   macOS   brew install mingw-w64
#   Debian  apt install gcc-mingw-w64-ucrt64   (CC=x86_64-w64-mingw32ucrt-gcc)
#   Windows use build.ps1, or an MSYS2 shell with mingw-w64-x86_64-gcc
#
# Environment: CC picks the compiler, DLLTOOL the matching dlltool (derived from
# CC by default), OUT the output path (default dist/x4mcp_64.dll).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="${OUT:-$ROOT/dist/x4mcp_64.dll}"
CC="${CC:-x86_64-w64-mingw32-gcc}"
DLLTOOL="${DLLTOOL:-${CC%gcc}dlltool}"

for tool in "$CC" "$DLLTOOL"; do
  command -v "$tool" >/dev/null || {
    echo "not found: $tool (see the header of this script)" >&2
    exit 1
  }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$(dirname "$OUT")"
# dlltool names symbols after the -l path, so it runs inside $TMP with a bare
# file name: a temp directory in the path would change the output every run.
(cd "$TMP" && "$DLLTOOL" -d "$HERE/lua51_64.def" -D lua51_64.dll -l liblua51_64.a)

# Compiled from inside native/ by its relative name, so no absolute path of
# this checkout ends up in the binary.
(
  cd "$HERE"
  "$CC" -shared -O2 -Wall -Wextra \
    -o "$OUT" \
    x4mcp.c \
    "$TMP/liblua51_64.a" \
    -lws2_32 \
    -static-libgcc \
    -Wl,--enable-stdcall-fixup \
    -Wl,--no-insert-timestamp
)

echo "built: $OUT"
command -v file >/dev/null && file "$OUT" || true
