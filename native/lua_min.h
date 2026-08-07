/*
  Minimal Lua 5.1 C API declarations.

  Full LuaJIT headers are not needed: the game ships lua51_64.dll with a stock
  Lua 5.1 ABI, and we only use about a dozen functions. Declaring them here
  keeps the module free of any external SDK -- a cross compiler is enough.

  Signatures verified against the export table of lua51_64.dll from X4 9.00.
*/

#ifndef X4MCP_LUA_MIN_H
#define X4MCP_LUA_MIN_H

#include <stddef.h>

typedef struct lua_State lua_State;
typedef int (*lua_CFunction)(lua_State *L);
typedef ptrdiff_t lua_Integer;
typedef double lua_Number;

#define LUA_REGISTRYINDEX (-10000)
#define LUA_GLOBALSINDEX  (-10002)

int         lua_gettop(lua_State *L);
void        lua_settop(lua_State *L, int idx);
int         lua_type(lua_State *L, int idx);

void        lua_pushnil(lua_State *L);
void        lua_pushboolean(lua_State *L, int b);
void        lua_pushinteger(lua_State *L, lua_Integer n);
void        lua_pushnumber(lua_State *L, lua_Number n);
void        lua_pushlstring(lua_State *L, const char *s, size_t len);
void        lua_pushstring(lua_State *L, const char *s);
void        lua_pushcclosure(lua_State *L, lua_CFunction fn, int n);

void        lua_createtable(lua_State *L, int narr, int nrec);
void        lua_setfield(lua_State *L, int idx, const char *k);

const char *luaL_checklstring(lua_State *L, int narg, size_t *len);
lua_Integer luaL_checkinteger(lua_State *L, int narg);
int         luaL_error(lua_State *L, const char *fmt, ...);

/* These are macros in Lua, not exported functions. */
#define lua_pushcfunction(L, f) lua_pushcclosure((L), (f), 0)
#define lua_newtable(L)         lua_createtable((L), 0, 0)

#endif /* X4MCP_LUA_MIN_H */
