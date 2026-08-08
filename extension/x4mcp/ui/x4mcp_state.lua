--[[
  x4mcp -- the game-side execution environment.

  There is exactly one operation, `eval`, which runs Lua sent from the host
  inside the game. That is deliberate and it is the whole architecture: X4's
  own ffi.cdef declarations are global to the Lua state, so roughly two
  thousand C functions plus every engine Lua global are already reachable from
  here. Anything this file wrapped would be a subset of that, chosen by
  whoever wrote the wrapper rather than by whoever needs it.

  Bulk reads need no special support either. A chunk that loops over ships and
  returns a table costs exactly one round trip, the same as a purpose-built
  snapshot operation would -- and it is not limited to the fields somebody
  thought to include.

  What is left below is plumbing every chunk would otherwise repeat: turning
  the game's two id representations into one string form, reading component
  fields in a batch, walking the enumerator pattern, and converting arbitrary
  results into something JSON can carry.
]]

local ffi_ok, ffi = pcall(require, "ffi")
local C = ffi_ok and ffi.C or nil

-- The game declares most of its API itself, and those declarations are global
-- to the Lua state. These few are repeated here because a chunk cannot rely on
-- which of the game's menu files have loaded yet.
if ffi_ok then
	pcall(ffi.cdef, [[ typedef uint64_t UniverseID; ]])
	pcall(ffi.cdef, [[ UniverseID GetPlayerID(void); ]])
	pcall(ffi.cdef, [[ uint32_t GetNumAllFactionShips(const char* factionid); ]])
	pcall(ffi.cdef, [[ uint32_t GetAllFactionShips(UniverseID* result, uint32_t resultlen, const char* factionid); ]])
	pcall(ffi.cdef, [[ uint32_t GetNumAllFactionStations(const char* factionid); ]])
	pcall(ffi.cdef, [[ uint32_t GetAllFactionStations(UniverseID* result, uint32_t resultlen, const char* factionid); ]])
	pcall(ffi.cdef, [[ uint32_t GetNumSectorsByOwner(const char* factionid); ]])
	pcall(ffi.cdef, [[ uint32_t GetSectorsByOwner(UniverseID* result, uint32_t resultlen, const char* factionid); ]])
	pcall(ffi.cdef, [[ uint32_t GetNumAllFactions(bool includehidden); ]])
	pcall(ffi.cdef, [[ uint32_t GetAllFactions(const char** result, uint32_t resultlen, bool includehidden); ]])
	pcall(ffi.cdef, [[ bool IsKnownToPlayer(UniverseID componentid); ]])
end

--------------------------------------------------------------------------------
-- Plumbing
--------------------------------------------------------------------------------

-- IDs reach Lua in two shapes and both must end up as the same digit string,
-- or a commander reference never matches the id it points at. The enumerators
-- return 64-bit cdata, printed by LuaJIT as "1234ULL"; GetComponentData
-- returns engine Lua ids, printed as "ID: 1234".
local function norm(v)
	local t = type(v)
	if t == "number" or t == "string" or t == "boolean" then return v end
	if v == nil then return nil end

	local s = tostring(v)
	if t == "cdata" then
		return s:match("^(-?%d+)U?LL$") or s
	end
	if t == "userdata" then
		return s:match("^ID:%s*(%d+)$") or s
	end
	return s
end

local function id_str(uid)
	if uid == nil then return nil end
	local s = norm(uid)
	if type(s) == "number" then return string.format("%d", s) end
	return s
end

-- GetComponentData wants an engine Lua id; the enumerators hand back cdata.
local function to_luaid(uid)
	local ok, v = pcall(ConvertStringToLuaID, tostring(uid))
	if ok then return v end
	return uid
end

-- Read several component fields at once. select("#") rather than a table
-- constructor: a nil in the middle of the results would truncate the list and
-- shift every following value onto the wrong key.
local function comp_data(luaid, keys)
	local out = {}
	local function grab(...)
		local n = select("#", ...)
		for i = 1, n do
			out[keys[i]] = norm((select(i, ...)))
		end
	end
	local ok = pcall(function() grab(GetComponentData(luaid, unpack(keys))) end)
	if not ok then
		for _, k in ipairs(keys) do
			local ok2, v = pcall(GetComponentData, luaid, k)
			if ok2 then out[k] = norm(v) end
		end
	end
	return out
end

-- The game's enumerators all share one shape: a count function, and a fill
-- function taking (buffer, length, arg).
local function enum(count_fn, list_fn, arg)
	if C == nil then return {} end
	local ok, n = pcall(count_fn, arg)
	if not ok or n == nil or tonumber(n) == 0 then return {} end
	n = tonumber(n)
	local buf = ffi.new("UniverseID[?]", n)
	local ok2, got = pcall(list_fn, buf, n, arg)
	if not ok2 then return {} end
	local out = {}
	for i = 0, tonumber(got) - 1 do
		out[#out + 1] = buf[i]
	end
	return out
end

local function factions()
	if C == nil then return {} end
	local ok, n = pcall(C.GetNumAllFactions, false)
	if not ok or tonumber(n or 0) == 0 then return {} end
	n = tonumber(n)
	local buf = ffi.new("const char*[?]", n)
	local ok2, got = pcall(C.GetAllFactions, buf, n, false)
	if not ok2 then return {} end
	local out = {}
	for i = 0, tonumber(got) - 1 do
		if buf[i] ~= nil then out[#out + 1] = ffi.string(buf[i]) end
	end
	return out
end

-- A Lua table is either a sequence or a map and JSON needs to know which.
-- Getting this wrong turns a list of ships into an object keyed "1", "2", ...
-- which every caller then indexes incorrectly.
local function is_sequence(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" then return false end
		n = n + 1
	end
	return n > 0 and n == #t
end

-- Anything, turned into something the JSON encoder can carry faithfully.
local function jsonable(v, depth)
	depth = depth or 0
	local t = type(v)
	if t == "nil" or t == "boolean" or t == "number" or t == "string" then return v end
	if t == "cdata" or t == "userdata" then return norm(v) end
	if t ~= "table" then return "<" .. t .. ">" end
	if depth > 8 then return "<table: too deep>" end

	if is_sequence(v) then
		local out = X4MCP_Json.array({})
		for i = 1, math.min(#v, 20000) do
			out[i] = jsonable(v[i], depth + 1)
		end
		return out
	end

	local out, n = {}, 0
	for k, val in pairs(v) do
		n = n + 1
		if n > 20000 then out["_truncated"] = true break end
		out[tostring(k)] = jsonable(val, depth + 1)
	end
	return out
end

--------------------------------------------------------------------------------
-- Execution environment
--------------------------------------------------------------------------------

-- Chunks run in their own environment. __index falls through to _G so the
-- whole game API is in scope, while assignments land here rather than in _G,
-- so evaluated code cannot corrupt the game's globals. Values persist between
-- calls, which makes this a usable scratch space across a session.
local eval_env = setmetatable({}, { __index = _G })
eval_env.C = C
eval_env.ffi = ffi_ok and ffi or nil
eval_env.helpers = {
	norm = norm,
	id_str = id_str,
	to_luaid = to_luaid,
	comp_data = comp_data,
	enum = enum,
	factions = factions,
	jsonable = jsonable,
}

X4MCP.ops.eval = function(args)
	local code = args and args.code
	if type(code) ~= "string" then
		error("eval requires args.code as a string", 0)
	end
	local chunk, err = loadstring(code, "x4mcp-eval")
	if chunk == nil then
		error("compile error: " .. tostring(err), 0)
	end
	setfenv(chunk, eval_env)

	-- select() rather than a table constructor: a nil anywhere in the results
	-- would truncate the list and hide everything after it.
	local function collect(ok, ...)
		if not ok then
			error("runtime error: " .. tostring((select(1, ...))), 0)
		end
		local n = select("#", ...)
		local out = X4MCP_Json.array({})
		for i = 1, n do out[i] = jsonable((select(i, ...))) end
		return { n = n, results = out }
	end
	return collect(pcall(chunk))
end

pcall(DebugError, "[x4mcp] eval environment registered")
