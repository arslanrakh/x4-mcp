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

# Parsed rather than sourced. Sourcing runs the file as shell, so an unquoted
# value with spaces -- which every real X4_DIR has, "C:/Program Files/..." or
# "~/Library/Application Support/..." -- is split into words and executed.
if [ -f "$ROOT/.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
      *=*) ;;
      *) continue ;;
    esac
    key=${line%%=*}
    value=${line#*=}
    case "$key" in
      [A-Za-z_]*) ;;
      *) continue ;;
    esac
    case "$value" in
      \"*\") value=${value#\"}; value=${value%\"} ;;
      \'*\') value=${value#\'}; value=${value%\'} ;;
    esac
    export "$key=$value"
  done < "$ROOT/.env"
fi

if [ ! -x "$VENV/bin/python" ]; then
  echo "creating virtualenv in $VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet -r "$ROOT/server/requirements.txt"
fi

exec "$VENV/bin/python" "$ROOT/server/x4mcp_server.py" "$@"
