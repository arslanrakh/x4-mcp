/*
  x4mcp -- native bridge between Lua inside X4 and an MCP server on the host.

  Why this exists at all: in X4 9.0 the Lua sandbox provides neither io nor os,
  and ffi.C is replaced by a proxy restricted to the game's own API. The only
  remaining way out is package.loadlib, available when Protected UI Mode is
  switched off. Everything below follows from that.

  Transport is TCP over loopback. Wine hands through native macOS sockets, so
  the host server listens on an ordinary port and we avoid file exchange with
  its temp files, renames and directory polling.

  Hard requirement: NEVER block the game thread. Every socket operation is
  non-blocking, the connection is established asynchronously, and update()
  only pumps buffers before returning immediately.

  Framing is newline delimited. Messages on both sides are compact single-line
  JSON documents.

  Module API as seen from Lua:
      open(host, port)  -> true | nil, err   start a non-blocking connect
      state()           -> "disconnected" | "connecting" | "connected"
      update()          -> nready, err       pump the socket, return the number
                                             of complete messages available
      recv()            -> msg | nil         take the next complete message
      send(str)         -> true | nil, err   queue for sending
      close()
      version()         -> string
*/

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "lua_min.h"

#define X4MCP_VERSION "x4mcp-native 0.1.0"

/* Buffer ceiling. A universe snapshot is large but not unbounded: hitting a
   limit beats silently eating the game's memory. */
#define X4MCP_BUF_MAX (64u * 1024u * 1024u)

enum { X4ST_DISCONNECTED = 0, X4ST_CONNECTING = 1, X4ST_CONNECTED = 2 };

typedef struct {
    char  *data;
    size_t len;
    size_t cap;
} buf_t;

static SOCKET g_sock  = INVALID_SOCKET;
static int    g_state = X4ST_DISCONNECTED;
static int    g_wsa   = 0;
static buf_t  g_rx;
static buf_t  g_tx;
static char   g_err[256];

/* ------------------------------------------------------------------ */
/* Buffers                                                             */
/* ------------------------------------------------------------------ */

static int buf_reserve(buf_t *b, size_t need)
{
    size_t cap;
    char  *p;

    if (b->cap >= need) return 1;
    cap = b->cap ? b->cap : 4096;
    while (cap < need) {
        if (cap > X4MCP_BUF_MAX / 2) return 0;
        cap *= 2;
    }
    p = (char *)realloc(b->data, cap);
    if (!p) return 0;
    b->data = p;
    b->cap  = cap;
    return 1;
}

static int buf_append(buf_t *b, const char *s, size_t n)
{
    if (!buf_reserve(b, b->len + n)) return 0;
    memcpy(b->data + b->len, s, n);
    b->len += n;
    return 1;
}

static void buf_consume(buf_t *b, size_t n)
{
    if (n >= b->len) { b->len = 0; return; }
    memmove(b->data, b->data + n, b->len - n);
    b->len -= n;
}

static void buf_free(buf_t *b)
{
    free(b->data);
    b->data = NULL;
    b->len = b->cap = 0;
}

/* ------------------------------------------------------------------ */
/* Socket                                                              */
/* ------------------------------------------------------------------ */

static void set_err(const char *what, int code)
{
    if (code)
        _snprintf(g_err, sizeof(g_err) - 1, "%s: WSA error %d", what, code);
    else
        _snprintf(g_err, sizeof(g_err) - 1, "%s", what);
    g_err[sizeof(g_err) - 1] = 0;
}

static void drop_connection(void)
{
    if (g_sock != INVALID_SOCKET) {
        closesocket(g_sock);
        g_sock = INVALID_SOCKET;
    }
    g_state = X4ST_DISCONNECTED;
    g_rx.len = 0;
    g_tx.len = 0;
}

/* Returns 1 if the socket is still usable (connected or still connecting). */
static int pump_connecting(void)
{
    fd_set wr, ex;
    struct timeval tv;
    int    n, err = 0, len = sizeof(err);

    FD_ZERO(&wr); FD_SET(g_sock, &wr);
    FD_ZERO(&ex); FD_SET(g_sock, &ex);
    tv.tv_sec = 0; tv.tv_usec = 0;

    n = select(0, NULL, &wr, &ex, &tv);
    if (n == 0) return 1;                      /* still connecting */
    if (n == SOCKET_ERROR) {
        set_err("select", WSAGetLastError());
        drop_connection();
        return 0;
    }
    if (FD_ISSET(g_sock, &ex)) {
        getsockopt(g_sock, SOL_SOCKET, SO_ERROR, (char *)&err, &len);
        set_err("connect", err);
        drop_connection();
        return 0;
    }
    if (FD_ISSET(g_sock, &wr)) {
        if (getsockopt(g_sock, SOL_SOCKET, SO_ERROR, (char *)&err, &len) == 0 && err != 0) {
            set_err("connect", err);
            drop_connection();
            return 0;
        }
        g_state = X4ST_CONNECTED;
    }
    return 1;
}

static int pump_tx(void)
{
    while (g_tx.len > 0) {
        int sent = send(g_sock, g_tx.data, (int)g_tx.len, 0);
        if (sent == SOCKET_ERROR) {
            int e = WSAGetLastError();
            if (e == WSAEWOULDBLOCK) return 1;
            set_err("send", e);
            drop_connection();
            return 0;
        }
        if (sent == 0) return 1;
        buf_consume(&g_tx, (size_t)sent);
    }
    return 1;
}

static int pump_rx(void)
{
    char tmp[16384];
    for (;;) {
        int got = recv(g_sock, tmp, (int)sizeof(tmp), 0);
        if (got > 0) {
            if (!buf_append(&g_rx, tmp, (size_t)got)) {
                set_err("receive buffer overflow", 0);
                drop_connection();
                return 0;
            }
            continue;
        }
        if (got == 0) {                        /* server closed the connection */
            set_err("peer closed connection", 0);
            drop_connection();
            return 0;
        }
        {
            int e = WSAGetLastError();
            if (e == WSAEWOULDBLOCK) return 1;
            set_err("recv", e);
            drop_connection();
            return 0;
        }
    }
}

static int count_messages(void)
{
    size_t i;
    int    n = 0;
    for (i = 0; i < g_rx.len; ++i)
        if (g_rx.data[i] == '\n') ++n;
    return n;
}

/* ------------------------------------------------------------------ */
/* Functions exposed to Lua                                            */
/* ------------------------------------------------------------------ */

static int l_open(lua_State *L)
{
    const char        *host = luaL_checklstring(L, 1, NULL);
    int                port = (int)luaL_checkinteger(L, 2);
    struct sockaddr_in addr;
    u_long             nonblock = 1;
    int                rc;

    if (!g_wsa) {
        WSADATA wsa;
        if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
            lua_pushnil(L);
            lua_pushstring(L, "WSAStartup failed");
            return 2;
        }
        g_wsa = 1;
    }

    drop_connection();

    g_sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (g_sock == INVALID_SOCKET) {
        set_err("socket", WSAGetLastError());
        lua_pushnil(L);
        lua_pushstring(L, g_err);
        return 2;
    }

    if (ioctlsocket(g_sock, FIONBIO, &nonblock) == SOCKET_ERROR) {
        set_err("ioctlsocket", WSAGetLastError());
        drop_connection();
        lua_pushnil(L);
        lua_pushstring(L, g_err);
        return 2;
    }

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port   = htons((u_short)port);
    addr.sin_addr.s_addr = inet_addr(host);
    if (addr.sin_addr.s_addr == INADDR_NONE) {
        /* Numeric addresses only, deliberately: name resolution blocks, and
           the only address that makes sense here is loopback. */
        drop_connection();
        lua_pushnil(L);
        lua_pushstring(L, "host must be a numeric IPv4 address, e.g. 127.0.0.1");
        return 2;
    }

    rc = connect(g_sock, (struct sockaddr *)&addr, sizeof(addr));
    if (rc == 0) {
        g_state = X4ST_CONNECTED;
    } else {
        int e = WSAGetLastError();
        if (e == WSAEWOULDBLOCK || e == WSAEINPROGRESS || e == WSAEALREADY) {
            g_state = X4ST_CONNECTING;
        } else {
            set_err("connect", e);
            drop_connection();
            lua_pushnil(L);
            lua_pushstring(L, g_err);
            return 2;
        }
    }

    g_err[0] = 0;
    lua_pushboolean(L, 1);
    return 1;
}

static int l_state(lua_State *L)
{
    const char *s = "disconnected";
    if (g_state == X4ST_CONNECTING) s = "connecting";
    else if (g_state == X4ST_CONNECTED) s = "connected";
    lua_pushstring(L, s);
    return 1;
}

static int l_update(lua_State *L)
{
    if (g_state == X4ST_DISCONNECTED) {
        lua_pushinteger(L, 0);
        lua_pushstring(L, g_err[0] ? g_err : "not connected");
        return 2;
    }

    if (g_state == X4ST_CONNECTING) {
        if (!pump_connecting()) {
            lua_pushinteger(L, 0);
            lua_pushstring(L, g_err);
            return 2;
        }
        if (g_state != X4ST_CONNECTED) {
            lua_pushinteger(L, 0);
            return 1;
        }
    }

    if (!pump_tx() || !pump_rx()) {
        lua_pushinteger(L, count_messages());
        lua_pushstring(L, g_err);
        return 2;
    }

    lua_pushinteger(L, count_messages());
    return 1;
}

static int l_recv(lua_State *L)
{
    size_t i;
    for (i = 0; i < g_rx.len; ++i) {
        if (g_rx.data[i] == '\n') {
            size_t line = i;
            /* trailing \r, in case the server ever writes CRLF */
            if (line > 0 && g_rx.data[line - 1] == '\r') --line;
            lua_pushlstring(L, g_rx.data, line);
            buf_consume(&g_rx, i + 1);
            return 1;
        }
    }
    lua_pushnil(L);
    return 1;
}

static int l_send(lua_State *L)
{
    size_t      n = 0;
    const char *s = luaL_checklstring(L, 1, &n);

    if (g_state == X4ST_DISCONNECTED) {
        lua_pushnil(L);
        lua_pushstring(L, "not connected");
        return 2;
    }
    if (!buf_append(&g_tx, s, n) || !buf_append(&g_tx, "\n", 1)) {
        lua_pushnil(L);
        lua_pushstring(L, "send buffer overflow");
        return 2;
    }
    /* The connection may not be established yet -- then we just accumulate in
       the buffer and update() flushes it later. */
    if (g_state == X4ST_CONNECTED && !pump_tx()) {
        lua_pushnil(L);
        lua_pushstring(L, g_err);
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int l_close(lua_State *L)
{
    drop_connection();
    g_err[0] = 0;
    lua_pushboolean(L, 1);
    return 1;
}

static int l_version(lua_State *L)
{
    lua_pushstring(L, X4MCP_VERSION);
    return 1;
}

/* The Lua sandbox has no os.getenv, so this is the only way for the game side
   to be configured without editing its source. Used for the bridge port. */
static int l_getenv(lua_State *L)
{
    const char *name = luaL_checklstring(L, 1, NULL);
    char  buf[1024];
    DWORD n = GetEnvironmentVariableA(name, buf, (DWORD)sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushlstring(L, buf, (size_t)n);
    return 1;
}

/* ------------------------------------------------------------------ */

__declspec(dllexport) int luaopen_x4mcp(lua_State *L)
{
    lua_createtable(L, 0, 8);

    lua_pushcfunction(L, l_open);    lua_setfield(L, -2, "open");
    lua_pushcfunction(L, l_state);   lua_setfield(L, -2, "state");
    lua_pushcfunction(L, l_update);  lua_setfield(L, -2, "update");
    lua_pushcfunction(L, l_recv);    lua_setfield(L, -2, "recv");
    lua_pushcfunction(L, l_send);    lua_setfield(L, -2, "send");
    lua_pushcfunction(L, l_close);   lua_setfield(L, -2, "close");
    lua_pushcfunction(L, l_version); lua_setfield(L, -2, "version");
    lua_pushcfunction(L, l_getenv);  lua_setfield(L, -2, "getenv");

    lua_pushstring(L, X4MCP_VERSION);
    lua_setfield(L, -2, "_VERSION");

    return 1;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)inst; (void)reserved;
    if (reason == DLL_PROCESS_DETACH) {
        drop_connection();
        buf_free(&g_rx);
        buf_free(&g_tx);
        if (g_wsa) { WSACleanup(); g_wsa = 0; }
    }
    return TRUE;
}
