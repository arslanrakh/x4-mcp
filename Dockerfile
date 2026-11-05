# The server only needs Python and the MCP SDK. It reads the game's archives to
# build its catalogue at startup, so the X4 folder is mounted read-only at
# /game -- see docker-compose.yml.
FROM python:3.12-slim

WORKDIR /app

COPY server/requirements.txt server/requirements.txt
RUN pip install --no-cache-dir -r server/requirements.txt

COPY server/ server/

# The saved Lua recipes. Copied so a plain `docker run` still has them; docker
# compose mounts the host folder over this, which is what makes new ones
# survive the container.
COPY cookbook/ cookbook/

# Inside a container both listeners have to bind on all interfaces, otherwise
# the published ports reach nothing. Both ports stay fixed here; the host-side
# mapping is where they are made configurable. Binding on 0.0.0.0 does not open
# MCP to other host names: the server still accepts only localhost, 127.0.0.1
# and [::1] in Host and Origin.
ENV X4MCP_TRANSPORT=http \
    X4MCP_HTTP_HOST=0.0.0.0 \
    X4MCP_GAME_BIND=0.0.0.0 \
    X4MCP_HTTP_PORT=8766 \
    X4MCP_GAME_PORT=8765 \
    X4MCP_COOKBOOK_DIR=/app/cookbook \
    X4_DIR=/game \
    PYTHONUNBUFFERED=1

EXPOSE 8765 8766

CMD ["python", "server/x4mcp_server.py"]
