#!/usr/bin/env bash
# Build x4mcp_64.dll with the pinned toolchain in native/Dockerfile, as CI does.
#
#   native/reproduce.sh            rebuild dist/x4mcp_64.dll
#   native/reproduce.sh --check    build and compare with dist/x4mcp_64.dll
#   native/reproduce.sh --smoke    also load the DLL under Wine (see smoke/)
#
# Needs Docker. --smoke runs an amd64 image (Wine runs x86-64 code); on an arm64
# machine that needs emulation and buildx.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DIST="$ROOT/dist/x4mcp_64.dll"
check=0
smoke=0
for a in "$@"; do
  case "$a" in
    --check) check=1 ;;
    --smoke) smoke=1 ;;
    *) echo "usage: $0 [--check] [--smoke]" >&2; exit 2 ;;
  esac
done

build() {
  docker build -f "$HERE/Dockerfile" --target "$1" -t "x4mcp-dll-$1" "$ROOT"
}

build build
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cid="$(docker create x4mcp-dll-build)"
docker cp "$cid:/out/x4mcp_64.dll" "$TMP/x4mcp_64.dll" >/dev/null
docker rm "$cid" >/dev/null
sum() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$1" | cut -d' ' -f1; }
echo "built:  $(sum "$TMP/x4mcp_64.dll")"

if [ "$check" = 1 ]; then
  echo "dist:   $(sum "$DIST")"
  if ! cmp -s "$TMP/x4mcp_64.dll" "$DIST"; then
    echo "dist/x4mcp_64.dll does not match a build of native/. Run native/reproduce.sh and commit the result." >&2
    exit 1
  fi
  echo "dist/x4mcp_64.dll matches the source"
else
  cp "$TMP/x4mcp_64.dll" "$DIST"
  echo "wrote:  $DIST"
fi

if [ "$smoke" = 1 ]; then
  build smoke
  docker run --rm x4mcp-dll-smoke
fi
