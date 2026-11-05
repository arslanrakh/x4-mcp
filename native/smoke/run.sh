#!/bin/sh
# Inside the smoke image: the stand-in server, then the game side under Wine.
set -eu
PORT=8765
python3 host.py "$PORT" &
HOST=$!
wine lua.exe smoke.lua x4mcp_64.dll "$PORT"
wait "$HOST"
