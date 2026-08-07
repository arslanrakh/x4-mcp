--[[
  x4mcp -- state collection (Milestone 2).

  Registers the "snapshot" op: one bulk read of everything the agent needs, so
  the host never has to loop back into the game per object.

  Two APIs do the work. Enumeration goes through FFI -- GetAllFactionShips and
  friends hand back every object of a faction in a single call. Per-object
  fields come from GetComponentData, the engine's own Lua helper that the game
  menus use ~300 times; it is far cheaper to call than assembling the same data
  from raw getters.

  IDs are always strings. X4 component IDs are 64 bit and a JSON number is a
  double, so passing them as numbers would silently corrupt them. The host
  treats these strings as opaque and hands them back verbatim.

  Field names here are the contract with the host and must stay stable: an
  agent that has to guess between "role", "ship_role" and "class" will spend
  its turns on AttributeError instead of on the player's question.
]]

local ffi_ok, ffi = pcall(require, "ffi")
local C = ffi_ok and ffi.C or nil

-- Each declaration separately: the game may already have declared some of
-- these, and a redefinition is expected rather than exceptional.
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
-- Value normalisation
--------------------------------------------------------------------------------

-- IDs reach us in two shapes and both have to end up as the same plain digit
-- string, otherwise a commander reference never matches the id it points at.
-- The enumerators hand back 64-bit cdata, printed by LuaJIT as "1234ULL".
-- GetComponentData hands back Lua ids, printed by the engine as "ID: 1234".
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

-- GetComponentData wants a Lua id, the enumerators give UniverseID cdata.
local function to_luaid(uid)
	local ok, v = pcall(ConvertStringToLuaID, tostring(uid))
	if ok then return v end
	return uid
end

-- Batch read with a per-key fallback. select("#") is used deliberately: a nil
-- in the middle of the results would truncate a plain table constructor and
-- silently shift every following field onto the wrong key.
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

--------------------------------------------------------------------------------
-- Enumeration
--------------------------------------------------------------------------------

local function enum_universe_ids(count_fn, list_fn, arg)
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

local function all_factions()
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

--------------------------------------------------------------------------------
-- Object descriptions
--------------------------------------------------------------------------------

local SHIP_KEYS = {
	"name", "idcode", "macro", "classid", "typename", "typestring",
	"shiptype", "shiptypename",
	"primarypurpose", "rolename", "hull", "hullmax", "hullpercent",
	"shieldpercent", "sector", "sectorid", "cluster", "owner", "ownername",
	"aicommand", "aicommandaction", "assignment", "assignmentname",
	"subordinategroup", "isfleetlead", "fleetname", "pilot", "isdocked",
}

-- classid comes back as a bare number (93), which tells an agent nothing. Ship
-- macros are strictly named "ship_<race>_<size>_<type>_...", so the hull size
-- is right there and is stable across localisations.
local function size_from_macro(macro)
	if type(macro) ~= "string" then return nil end
	return macro:match("^ship_%a+_(%a+)_") or nil
end

local STATION_KEYS = {
	"name", "idcode", "macro", "classid", "sector", "sectorid", "cluster",
	"owner", "ownername", "hull", "hullpercent", "isshipyard", "iswharf",
	"isequipmentdock", "istradestation", "isdefencestation",
}

local SECTOR_KEYS = {
	"name", "macro", "owner", "ownername", "cluster", "clusterid",
}

-- Sector identity has to survive both localisation and reloads. The localised
-- name changes with the language and the numeric id changes between sessions;
-- the sector macro does neither, so every object carries it. Resolved through
-- a cache because a fleet in one sector would otherwise re-fetch it per ship.
local sector_macro_cache = {}

local function sector_macro_of(luaid)
	local ok, sid = pcall(GetComponentData, luaid, "sectorid")
	if not ok or sid == nil then return nil end

	local key = norm(sid)
	local hit = sector_macro_cache[key]
	if hit ~= nil then return hit or nil end

	local ok2, macro = pcall(GetComponentData, sid, "macro")
	local value = (ok2 and type(macro) == "string" and macro ~= "") and macro or false
	sector_macro_cache[key] = value
	return value or nil
end

local function subordinate_ids(luaid)
	local out = X4MCP_Json.array({})
	local ok, subs = pcall(GetSubordinates, luaid)
	if not ok or type(subs) ~= "table" then return out end
	for _, s in ipairs(subs) do
		local sid = id_str(s)
		if sid then out[#out + 1] = sid end
	end
	return out
end

local function commander_id(luaid)
	local ok, cmd = pcall(GetCommander, luaid)
	if not ok or cmd == nil then return nil end
	if type(cmd) == "table" then
		return id_str(cmd.controllableid or cmd[1])
	end
	return id_str(cmd)
end

local function describe_ship(uid)
	local luaid = to_luaid(uid)
	local d = comp_data(luaid, SHIP_KEYS)
	return {
		id            = id_str(uid),
		name          = d.name,
		idcode        = d.idcode,
		macro         = d.macro,
		class         = d.classid,
		size          = size_from_macro(d.macro),
		type_name     = d.typename,
		type_string   = d.typestring,
		ship_type     = d.shiptype,
		ship_type_name = d.shiptypename,
		role          = d.primarypurpose,
		role_name     = d.rolename,
		hull          = d.hull,
		hull_max      = d.hullmax,
		hull_percent  = d.hullpercent,
		shield_percent = d.shieldpercent,
		sector        = d.sector,
		sector_id     = d.sectorid,
		sector_macro  = sector_macro_of(luaid),
		cluster       = d.cluster,
		owner         = d.owner,
		owner_name    = d.ownername,
		order         = d.aicommand,
		order_action  = d.aicommandaction,
		assignment    = d.assignment,
		assignment_name = d.assignmentname,
		subordinate_group = d.subordinategroup,
		is_fleet_lead = d.isfleetlead,
		fleet         = d.fleetname,
		pilot         = d.pilot,
		is_docked     = d.isdocked,
		commander     = commander_id(luaid),
		subordinates  = subordinate_ids(luaid),
	}
end

local function describe_station(uid)
	local luaid = to_luaid(uid)
	local d = comp_data(luaid, STATION_KEYS)
	return {
		id           = id_str(uid),
		name         = d.name,
		idcode       = d.idcode,
		macro        = d.macro,
		class        = d.classid,
		sector       = d.sector,
		sector_id    = d.sectorid,
		sector_macro = sector_macro_of(luaid),
		cluster      = d.cluster,
		owner        = d.owner,
		owner_name   = d.ownername,
		hull_percent = d.hullpercent,
		is_shipyard  = d.isshipyard,
		is_wharf     = d.iswharf,
		is_equipment_dock = d.isequipmentdock,
		is_trade_station  = d.istradestation,
		is_defence_station = d.isdefencestation,
	}
end

local function describe_sector(uid, owner)
	local luaid = to_luaid(uid)
	local d = comp_data(luaid, SECTOR_KEYS)
	local known = true
	if C ~= nil then
		local ok, v = pcall(C.IsKnownToPlayer, uid)
		if ok then known = (v == true) end
	end
	return {
		id         = id_str(uid),
		name       = d.name,
		macro      = d.macro,
		owner      = d.owner or owner,
		owner_name = d.ownername,
		cluster    = d.cluster,
		known      = known,
	}
end

--------------------------------------------------------------------------------
-- Collectors
--------------------------------------------------------------------------------

local function collect_ships(limit)
	local ids = enum_universe_ids(C.GetNumAllFactionShips, C.GetAllFactionShips, "player")
	local out = {}
	for i, uid in ipairs(ids) do
		if limit and i > limit then break end
		out[#out + 1] = describe_ship(uid)
	end
	return out
end

local function collect_stations(limit)
	local ids = enum_universe_ids(C.GetNumAllFactionStations, C.GetAllFactionStations, "player")
	local out = {}
	for i, uid in ipairs(ids) do
		if limit and i > limit then break end
		out[#out + 1] = describe_station(uid)
	end
	return out
end

-- Sectors are gathered per owning faction. There is no enumerator for
-- ownerless space in the exposed API, so unclaimed sectors are absent; the
-- host is told as much through "source" rather than being left to guess.
local function collect_sectors()
	local out, seen = {}, {}
	for _, faction in ipairs(all_factions()) do
		local ids = enum_universe_ids(C.GetNumSectorsByOwner, C.GetSectorsByOwner, faction)
		for _, uid in ipairs(ids) do
			local key = id_str(uid)
			if key and not seen[key] then
				seen[key] = true
				out[#out + 1] = describe_sector(uid, faction)
			end
		end
	end
	return out
end

local function collect_player()
	local p = {}
	if C == nil then return p end

	local ok, pid = pcall(C.GetPlayerID)
	if not ok then return p end
	p.id = id_str(pid)

	local ok_money, money = pcall(GetPlayerMoney)
	if ok_money then p.money = norm(money) end

	-- GetPlayerName is an FFI call returning const char*, which is awkward to
	-- guard; the player component carries the same string as ownername.
	local d = comp_data(to_luaid(pid), { "name", "ownername" })
	p.name = d.ownername or d.name
	return p
end

--------------------------------------------------------------------------------
-- Op registration
--------------------------------------------------------------------------------

local DEFAULT_SCOPE = { "player", "ships", "stations", "sectors" }

X4MCP.ops.snapshot = function(args)
	args = args or {}
	local scope = args.scope or DEFAULT_SCOPE
	local limit = args.limit
	local want = {}
	for _, s in ipairs(scope) do want[s] = true end

	-- Component ids are per-session, so a cache kept across a savegame load
	-- would map fresh ids onto stale macros.
	sector_macro_cache = {}

	local data = { source = "GetAllFactionShips/Stations, GetSectorsByOwner" }

	if want.player   then data.player   = collect_player() end
	if want.ships    then data.ships    = collect_ships(limit) end
	if want.stations then data.stations = collect_stations(limit) end
	if want.sectors  then data.sectors  = collect_sectors() end

	data.counts = {
		ships    = data.ships and #data.ships or 0,
		stations = data.stations and #data.stations or 0,
		sectors  = data.sectors and #data.sectors or 0,
	}
	return data
end

-- Anything, turned into something the JSON encoder can carry. Used by eval,
-- where the shape of the result is unknown by definition.
local function jsonable(v, depth)
	depth = depth or 0
	local t = type(v)
	if t == "nil" or t == "boolean" or t == "number" or t == "string" then return v end
	if t == "cdata" or t == "userdata" then return norm(v) end
	if t ~= "table" then return "<" .. t .. ">" end
	if depth > 6 then return "<table: too deep>" end

	local out, n = {}, 0
	for k, val in pairs(v) do
		n = n + 1
		if n > 500 then out["_truncated"] = true break end
		out[tostring(k)] = jsonable(val, depth + 1)
	end
	return out
end

-- Stations of other factions, on demand.
--
-- Deliberately not part of snapshot: the galaxy holds ~1450 stations and
-- shipping all of them on every refresh would trade a 40 KB payload for a
-- 500 KB one to answer a question that is usually about a single sector. The
-- filters run inside the game so only matches cross the wire.
X4MCP.ops.find_stations = function(args)
	args = args or {}
	local factions = args.factions
	if factions == nil or #factions == 0 then factions = all_factions() end

	local want_sector = args.sector_macro
	local known_only = args.known_only ~= false
	local limit = tonumber(args.limit) or 200

	local kindset = nil
	if args.kinds and #args.kinds > 0 then
		kindset = {}
		for _, k in ipairs(args.kinds) do kindset[k] = true end
	end

	local out = X4MCP_Json.array({})
	local scanned, matched = 0, 0

	for _, faction in ipairs(factions) do
		local ids = enum_universe_ids(C.GetNumAllFactionStations,
			C.GetAllFactionStations, faction)
		for _, uid in ipairs(ids) do
			scanned = scanned + 1
			local keep = true

			-- Cheapest filters first: a plain FFI predicate, then one cached
			-- sector lookup, and only then the full field read.
			if known_only then
				local ok, v = pcall(C.IsKnownToPlayer, uid)
				keep = ok and v == true
			end
			if keep and want_sector then
				keep = sector_macro_of(to_luaid(uid)) == want_sector
			end

			if keep then
				local st = describe_station(uid)
				if kindset then
					keep = (kindset.shipyard and st.is_shipyard == true)
						or (kindset.wharf and st.is_wharf == true)
						or (kindset.equipmentdock and st.is_equipment_dock == true)
						or (kindset.tradestation and st.is_trade_station == true)
						or (kindset.defence and st.is_defence_station == true)
						or false
				end
				if keep then
					matched = matched + 1
					if #out < limit then out[#out + 1] = st end
				end
			end
		end
	end

	return {
		stations = out,
		scanned = scanned,
		matched = matched,
		truncated = matched > #out,
	}
end

--------------------------------------------------------------------------------
-- Orders
--
-- This is the write path: the same sequence the game's own interact menu uses
-- (menu_interactmenu.lua). CreateOrder allocates a slot in the ship's queue,
-- SetOrderParam fills the parameters positionally, EnableOrder arms it.
--------------------------------------------------------------------------------

local function to_universe_id(value)
	if type(value) == "string" then
		local ok, id = pcall(ConvertStringTo64Bit, value)
		if ok then return id end
	end
	return value
end

-- Order parameters are positional and may be objects, which have to arrive as
-- engine Lua ids rather than numbers. The host tags those as {"id": "1234"};
-- anything else passes through untouched.
local function to_param(p)
	if type(p) == "table" and p.id ~= nil then
		local ok, v = pcall(ConvertStringToLuaID, tostring(p.id))
		if ok then return v end
		return nil
	end
	if p == "__nil__" then return nil end
	return p
end

X4MCP.ops.order_definitions = function()
	local ffi = require("ffi")
	pcall(ffi.cdef, [[
		typedef struct {
			const char* id;
			const char* name;
			const char* icon;
			const char* description;
			const char* category;
			const char* categoryname;
			bool infinite;
			uint32_t requiredSkill;
		} OrderDefinition;
	]])
	local n = tonumber(C.GetNumOrderDefinitions()) or 0
	if n == 0 then return { orders = X4MCP_Json.array({}) } end

	local buf = ffi.new("OrderDefinition[?]", n)
	local got = tonumber(C.GetOrderDefinitions(buf, n)) or 0
	local out = X4MCP_Json.array({})
	for i = 0, got - 1 do
		out[#out + 1] = {
			id            = ffi.string(buf[i].id),
			name          = ffi.string(buf[i].name),
			description   = ffi.string(buf[i].description),
			category      = ffi.string(buf[i].category),
			category_name = ffi.string(buf[i].categoryname),
			infinite      = buf[i].infinite == true,
			required_skill = tonumber(buf[i].requiredSkill),
		}
	end
	return { orders = out, count = got }
end

X4MCP.ops.can_order = function(args)
	local ship = to_universe_id(args and args.ship)
	local order = args and args.order
	if ship == nil or type(order) ~= "string" then
		error("can_order requires args.ship and args.order", 0)
	end
	local ok, allowed = pcall(C.IsOrderSelectableFor, order, ship)
	return { ship = tostring(args.ship), order = order,
		can_order = ok and allowed == true,
		error = (not ok) and tostring(allowed) or nil }
end

X4MCP.ops.create_order = function(args)
	args = args or {}
	local ship = to_universe_id(args.ship)
	local order = args.order
	if ship == nil or type(order) ~= "string" then
		error("create_order requires args.ship and args.order", 0)
	end

	-- X4 accepts an inapplicable order without complaint and the ship simply
	-- sits there, so refuse loudly instead of reporting a success that is not.
	local ok_sel, selectable = pcall(C.IsOrderSelectableFor, order, ship)
	if ok_sel and selectable ~= true and args.force ~= true then
		return { ok = false, err = "not_selectable",
			detail = order .. " is not applicable to this ship "
				.. "(wrong equipment, role or state). Pass force=true to try anyway." }
	end

	local idx = tonumber(C.CreateOrder(ship, order, args.default == true)) or 0
	if idx == 0 then
		return { ok = false, err = "create_failed",
			detail = "CreateOrder returned 0 for " .. order }
	end

	local failures = X4MCP_Json.array({})
	for i, p in ipairs(args.params or {}) do
		local ok_p, err_p = pcall(SetOrderParam, ship, idx, i, nil, to_param(p))
		if not ok_p then failures[#failures + 1] = "param " .. i .. ": " .. tostring(err_p) end
	end

	if args.enable ~= false then
		pcall(C.EnableOrder, ship, idx)
	end

	-- Newly created orders land at the end of the queue; move to the front so
	-- the ship acts now rather than after whatever it is already doing.
	if args.first == true and idx ~= 1 then
		pcall(C.AdjustOrder, ship, idx, 1, true, false, false)
	end

	local queued = tonumber(C.GetNumOrders(ship))
	return {
		ok = true,
		order = order,
		order_index = idx,
		queued_orders = queued,
		param_failures = failures,
	}
end

-- Environment for evaluated chunks. The whole game API is reachable from here:
-- ffi.cdef declarations are global to the LuaJIT state, so everything the
-- game's own menu files declare -- CreateOrder, EnableOrder, IsOrderSelectableFor
-- and ~2000 more -- resolves through C without us redeclaring any of it.
--
-- __index falls through to _G so the engine's Lua globals (GetComponentData,
-- SetOrderParam, GetSubordinates, ConvertStringToLuaID, ...) work too. Writes
-- land in this table rather than _G, so evaluated code cannot corrupt the
-- game's global namespace, and values persist between eval calls as a scratch
-- space.
local eval_env = setmetatable({}, { __index = _G })
eval_env.C = C
eval_env.ffi = ffi_ok and ffi or nil
eval_env.helpers = {
	norm = norm,
	id_str = id_str,
	to_luaid = to_luaid,
	comp_data = comp_data,
	enum = enum_universe_ids,
	factions = all_factions,
	sector_macro = sector_macro_of,
}

-- Arbitrary Lua from the host. This exists because every hypothesis about the
-- game API otherwise costs a full restart plus a savegame load; with eval the
-- same question is answered in milliseconds. Deliberately unguarded: this is a
-- single-player bridge on loopback, and the spec explicitly rejects a
-- deny-list. It is also how orders get given until a typed order layer exists.
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

-- Cheap probe for calibrating field types without pulling a whole snapshot.
X4MCP.ops.sample_ship = function()
	local ids = enum_universe_ids(C.GetNumAllFactionShips, C.GetAllFactionShips, "player")
	if #ids == 0 then return { note = "player owns no ships" } end
	local uid = ids[1]
	local luaid = to_luaid(uid)
	local raw = {}
	for _, k in ipairs(SHIP_KEYS) do
		local ok, v = pcall(GetComponentData, luaid, k)
		raw[k] = ok and (type(v) .. " = " .. tostring(v)) or ("ERROR: " .. tostring(v))
	end
	return { id = id_str(uid), raw_types = raw }
end

pcall(DebugError, "[x4mcp] state collector registered (snapshot, sample_ship, eval)")
