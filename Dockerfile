# The server only needs Python and the MCP SDK. It reads the game's archives to
# build its catalogue at startup, so the X4 folder is mounted read-only at
# /game -- see docker-compose.yml.
FROM python:3.12-slim

WORKDIR /app

COPY server/requirements.txt server/requirements.txt
RUN pip install --no-cache-dir -r server/requirements.txt

COPY server/ server/

# Inside a container the MCP listener has to bind on all interfaces, otherwise
# the published port reaches nothing. Both ports stay fixed here; the host-side
# mapping is where they are made configurable.
ENV X4MCP_TRANSPORT=http \
    X4MCP_HTTP_HOST=0.0.0.0 \
    X4MCP_HTTP_PORT=8766 \
    X4MCP_GAME_PORT=8765 \
    X4_DIR=/game \
    PYTHONUNBUFFERED=1

EXPOSE 8765 8766

CMD ["python", "server/x4mcp_server.py"]
