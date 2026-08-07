#!/usr/bin/env bash
# Run the MCP server directly, without Docker.
#
# Creates a virtualenv on first use. Configuration comes from .env if present;
# see .env.example. Docker is the other option (docker compose up -d) and needs
# no Python on the host, but has to be told where the game lives.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
VENV="$ROOT/.venv"

if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/.env"
  set +a
fi

if [ ! -x "$VENV/bin/python" ]; then
  echo "creating virtualenv in $VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet -r "$ROOT/server/requirements.txt"
fi

exec "$VENV/bin/python" "$ROOT/server/x4mcp_server.py" "$@"
