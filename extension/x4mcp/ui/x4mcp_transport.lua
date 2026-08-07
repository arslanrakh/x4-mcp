--[[
  x4mcp -- persistent transport (Milestone 1).

  The tick comes from onUpdate rather than an MD cue as the original spec
  assumed. Two reasons. MD does not run in the main menu and freezes while the
  game is paused -- and pausing is exactly when the player walks off to ask the
  agent something. onUpdate runs in both cases.

  Known limitation, measured: onUpdate stalls while the game window is in the
  background, so replies are delayed until the player returns. If that has to
  be fixed, an MD cue can be added as a second tick source -- tick() is
  idempotent and safe to call from anywhere.

  Durability. The socket lives in C static state and survives a Lua reload, so
  initialisation force-closes it -- otherwise after a UI reload we would
  inherit somebody else's half-dead socket.

  Protocol: one compact JSON document per line.
      game -> host   {"t":"hello",...} | {"t":"hb",...} | {"t":"resp","seq":N,...}
      host -> game   {"t":"req","seq":N,"op":"...","args":{...}}
]]

local DLL_PATH = ".\\extensions\\x4mcp\\x4mcp_64.dll"
local ENTRY    = "luaopen_x4mcp"

-- Defaults; overridden at load time from the environment if the variables are
-- set, since the Lua sandbox has no os.getenv and hard-coding a port into a
-- published mod is unfriendly. See X4MCP_HOST / X4MCP_GAME_PORT in the README.
local HOST     = "127.0.0.1"
local PORT     = 8765

local RECONNECT_INTERVAL = 2.0   -- seconds between connection attempts
local HEARTBEAT_INTERVAL = 1.0   -- seconds between heartbeats
local MAX_MSGS_PER_TICK  = 32    -- parse ceiling per frame, to protect the FPS

local Json = X4MCP_Json

local M = {
	native      = nil,
	load_error  = nil,
	last_try    = -1e9,
	last_hb     = -1e9,
	-- "disconnected" rather than "unknown": otherwise the very first tick
	-- mistakes a normal start for a dropped connection and lies to the log.
	last_state  = "disconnected",
	connects    = 0,
	msgs_in     = 0,
	msgs_out    = 0,
	ops         = {},
}

local function log(fmt, ...)
	local ok, s = pcall(string.format, fmt, ...)
	if not ok then s = tostring(fmt) end
	pcall(DebugError, "[x4mcp] " .. s)
end

local function now()
	local ok, t = pcall(getElapsedTime)
	if ok and type(t) == "number" then return t end
	return 0
end

--------------------------------------------------------------------------------
-- Game state for the heartbeat
--------------------------------------------------------------------------------

local C = nil
do
	local ok, ffi = pcall(require, "ffi")
	if ok then
		-- One cdef per pcall: the game may have declared some of these types
		-- before us, and a redefinition is an expected case, not an error.
		pcall(ffi.cdef, [[ typedef uint64_t UniverseID; ]])
		pcall(ffi.cdef, [[ UniverseID GetPlayerID(void); ]])
		pcall(ffi.cdef, [[ double GetCurrentGameTime(void); ]])
		pcall(ffi.cdef, [[ bool IsGamePaused(void); ]])
		C = ffi.C
	end
end

local function game_state()
	local st = { game_time = 0, paused = false, loaded = false }
	if C == nil then return st end
	local ok, v

	ok, v = pcall(function() return C.GetCurrentGameTime() end)
	if ok then st.game_time = tonumber(v) or 0 end

	ok, v = pcall(function() return C.IsGamePaused() end)
	if ok then st.paused = (v == true) end

	-- Savegame-loaded marker: in the main menu the player does not exist yet.
	ok, v = pcall(function() return C.GetPlayerID() end)
	if ok then st.loaded = (tonumber(v) or 0) ~= 0 end

	return st
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

local function send_table(t)
	if M.native == nil then return false end
	local ok, text = pcall(Json.encode, t)
	if not ok then
		log("encode failed: %s", tostring(text))
		return false
	end
	local sent, err = M.native.send(text)
	if not sent then
		log("send failed: %s", tostring(err))
		return false
	end
	M.msgs_out = M.msgs_out + 1
	return true
end

M.send = send_table

--------------------------------------------------------------------------------
-- Request handlers. Milestone 2 adds the state snapshot here.
--------------------------------------------------------------------------------

M.ops.ping = function(args)
	return { pong = true, echo = args }
end

M.ops.info = function()
	local st = game_state()
	return {
		native      = M.native and M.native._VERSION or nil,
		real_time   = now(),
		game_time   = st.game_time,
		paused      = st.paused,
		loaded      = st.loaded,
		connects    = M.connects,
		msgs_in     = M.msgs_in,
		msgs_out    = M.msgs_out,
	}
end

local function handle_request(msg)
	local seq = msg.seq
	local op  = msg.op
	local fn  = op and M.ops[op]

	if fn == nil then
		send_table({ t = "resp", seq = seq, ok = false,
			err = "unknown_op", detail = tostring(op) })
		return
	end

	local ok, data = pcall(fn, msg.args or {})
	if ok then
		send_table({ t = "resp", seq = seq, ok = true, data = data })
	else
		send_table({ t = "resp", seq = seq, ok = false,
			err = "op_failed", detail = tostring(data) })
	end
end

local function handle_line(line)
	M.msgs_in = M.msgs_in + 1
	local msg, err = Json.decode(line)
	if msg == nil then
		log("undecodable JSON from host: %s", tostring(err))
		return
	end
	if type(msg) ~= "table" then
		log("expected an object, got %s", type(msg))
		return
	end
	if msg.t == "req" or msg.op ~= nil then
		handle_request(msg)
	end
	-- Other kinds are ignored for now: the host may send housekeeping.
end

--------------------------------------------------------------------------------
-- Connection
--------------------------------------------------------------------------------

local function ensure_native()
	if M.native ~= nil then return true end
	if M.load_error ~= nil then return false end   -- do not retry in a loop

	if package == nil then
		M.load_error = "package == nil: Protected UI Mode is on"
		log("ABORT: %s", M.load_error)
		return false
	end

	local loader, err = package.loadlib(DLL_PATH, ENTRY)
	if loader == nil then
		M.load_error = tostring(err)
		log("ABORT: package.loadlib(%s) -> %s", DLL_PATH, M.load_error)
		return false
	end

	local ok, mod = pcall(loader)
	if not ok or type(mod) ~= "table" then
		M.load_error = tostring(mod)
		log("ABORT: %s did not return a table: %s", ENTRY, M.load_error)
		return false
	end

	M.native = mod
	log("native module loaded: %s", tostring(mod._VERSION))

	if type(mod.getenv) == "function" then
		local ok_h, host = pcall(mod.getenv, "X4MCP_HOST")
		if ok_h and type(host) == "string" and host ~= "" then HOST = host end
		local ok_p, port = pcall(mod.getenv, "X4MCP_GAME_PORT")
		if ok_p and tonumber(port) then PORT = tonumber(port) end
	end

	-- The C-side socket outlives a Lua reload, so start from a clean slate.
	pcall(mod.close)
	return true
end

local function on_connected()
	M.connects = M.connects + 1
	log("connected to %s:%d (connection #%d)", HOST, PORT, M.connects)
	send_table({
		t       = "hello",
		native  = M.native._VERSION,
		lua     = _VERSION,
		connect = M.connects,
	})
	M.last_hb = -1e9   -- heartbeat right away, without waiting out the interval
end

--------------------------------------------------------------------------------
-- Tick
--------------------------------------------------------------------------------

-- Every state transition goes through here. The logic used to be spread across
-- the tick, and a drop detected inside update() reached the log silently: the
-- "not connected" branch simply recorded the new state.
local function set_state(new)
	if new == M.last_state then return end
	local was = M.last_state
	M.last_state = new
	if new == "connected" then
		on_connected()
	elseif was == "connected" then
		log("connection lost")
	end
end

local function tick_inner()
	if not ensure_native() then return end

	local t = now()

	if M.native.state() == "disconnected" then
		set_state("disconnected")
		if t - M.last_try >= RECONNECT_INTERVAL then
			M.last_try = t
			M.native.open(HOST, PORT)
			set_state(M.native.state())
		end
		return
	end

	M.native.update()
	set_state(M.native.state())
	if M.last_state ~= "connected" then return end

	local n = 0
	while n < MAX_MSGS_PER_TICK do
		local line = M.native.recv()
		if line == nil then break end
		n = n + 1
		handle_line(line)
	end

	if t - M.last_hb >= HEARTBEAT_INTERVAL then
		M.last_hb = t
		local st = game_state()
		send_table({
			t         = "hb",
			real_time = t,
			game_time = st.game_time,
			paused    = st.paused,
			loaded    = st.loaded,
		})
	end
end

-- An error inside the tick must neither take down the UI nor flood the log:
-- report once per distinct message.
local last_err_text = nil
function M.tick()
	local ok, err = pcall(tick_inner)
	if not ok then
		local text = tostring(err)
		if text ~= last_err_text then
			last_err_text = text
			log("tick error: %s", text)
		end
	end
end

--------------------------------------------------------------------------------

X4MCP = M

SetScript("onUpdate", M.tick)
log("transport registered on onUpdate, target %s:%d", HOST, PORT)
