--[[
  x4mcp -- JSON for the host protocol.

  Rolled by hand rather than vendored, for two reasons. First, number output
  has to be predictable: X4 component IDs are 64 bit, they do not survive a
  double, so the protocol carries them as strings and the encoder must not
  quietly mangle large values. Second, X4 gives extensions no require() for
  their own files without third-party APIs, so an extra dependency costs more
  than a hundred lines.

  Exported as the global table X4MCP_Json -- files of one addon share an
  environment, there is no module system here.
]]

local Json = {}

--------------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------------

local ESCAPES = {
	['"']  = '\\"',
	['\\'] = '\\\\',
	['\b'] = '\\b',
	['\f'] = '\\f',
	['\n'] = '\\n',
	['\r'] = '\\r',
	['\t'] = '\\t',
}

local function escape_char(c)
	local e = ESCAPES[c]
	if e then return e end
	return string.format("\\u%04x", string.byte(c))
end

local function encode_string(s)
	return '"' .. s:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function encode_number(n)
	if n ~= n or n == math.huge or n == -math.huge then
		-- JSON has no NaN or Infinity; silently substituting 0 is worse than
		-- saying so out loud.
		error("cannot encode number as JSON: " .. tostring(n))
	end
	if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
		return string.format("%d", n)
	end
	return string.format("%.14g", n)
end

-- An empty Lua table is ambiguous: {} could be [] or {}. Guessing gets it
-- wrong exactly where it hurts -- an empty subordinates list arriving as an
-- object breaks list handling on the host. So list-valued fields are tagged
-- explicitly with Json.array() and the tag wins over any heuristic.
Json.ARRAY_MT = { __jsontype = "array" }

function Json.array(t)
	return setmetatable(t or {}, Json.ARRAY_MT)
end

local function is_array(t)
	if getmetatable(t) == Json.ARRAY_MT then return true end
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" then return false end
		n = n + 1
	end
	if n == 0 then return false end
	return n == #t
end

local encode_value

local function encode_table(t, depth)
	if depth > 64 then error("JSON nesting too deep") end

	local parts = {}
	if is_array(t) then
		for i = 1, #t do
			parts[#parts + 1] = encode_value(t[i], depth + 1)
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end

	-- Sorted keys: stable output makes logs and diffs far easier to read.
	local keys = {}
	for k in pairs(t) do
		if type(k) == "string" then keys[#keys + 1] = k
		elseif type(k) == "number" then keys[#keys + 1] = tostring(k)
		end
	end
	table.sort(keys)

	for _, k in ipairs(keys) do
		local v = t[k]
		if v == nil then v = t[tonumber(k)] end
		parts[#parts + 1] = encode_string(k) .. ":" .. encode_value(v, depth + 1)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

encode_value = function(v, depth)
	local tv = type(v)
	if v == nil then return "null" end
	if tv == "boolean" then return v and "true" or "false" end
	if tv == "number" then return encode_number(v) end
	if tv == "string" then return encode_string(v) end
	if tv == "table" then return encode_table(v, depth) end
	-- cdata, function, userdata: no meaningful representation.
	error("cannot encode value of type " .. tv .. " as JSON")
end

function Json.encode(v)
	return encode_value(v, 0)
end

--------------------------------------------------------------------------------
-- Decoding
--------------------------------------------------------------------------------

local function skip_ws(s, i)
	local _, j = s:find("^[ \t\r\n]*", i)
	return j + 1
end

local parse_value

local function parse_error(s, i, msg)
	error(string.format("JSON at offset %d: %s", i, msg), 0)
end

local UNESCAPES = {
	['"'] = '"', ['\\'] = '\\', ['/'] = '/',
	b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
}

local function parse_string(s, i)
	if s:sub(i, i) ~= '"' then parse_error(s, i, "expected a string") end
	i = i + 1
	local out = {}
	while true do
		local c = s:sub(i, i)
		if c == "" then parse_error(s, i, "unterminated string") end
		if c == '"' then return table.concat(out), i + 1 end
		if c == "\\" then
			local e = s:sub(i + 1, i + 1)
			if e == "u" then
				local hex = s:sub(i + 2, i + 5)
				if not hex:match("^%x%x%x%x$") then parse_error(s, i, "malformed \\u") end
				local cp = tonumber(hex, 16)
				-- Surrogate pairs are out of scope: the protocol is ASCII/UTF-8
				-- and never emits \u above the BMP.
				if cp < 128 then out[#out + 1] = string.char(cp)
				else out[#out + 1] = "?" end
				i = i + 6
			else
				local u = UNESCAPES[e]
				if not u then parse_error(s, i, "unknown escape \\" .. e) end
				out[#out + 1] = u
				i = i + 2
			end
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
end

local function parse_number(s, i)
	local j = s:find("[^%-%+0-9eE%.]", i) or (#s + 1)
	local text = s:sub(i, j - 1)
	local n = tonumber(text)
	if n == nil then parse_error(s, i, "malformed number " .. text) end
	return n, j
end

local function parse_array(s, i)
	local out = {}
	i = skip_ws(s, i + 1)
	if s:sub(i, i) == "]" then return out, i + 1 end
	while true do
		local v
		v, i = parse_value(s, i)
		out[#out + 1] = v
		i = skip_ws(s, i)
		local c = s:sub(i, i)
		if c == "]" then return out, i + 1 end
		if c ~= "," then parse_error(s, i, "expected , or ] in array") end
		i = skip_ws(s, i + 1)
	end
end

local function parse_object(s, i)
	local out = {}
	i = skip_ws(s, i + 1)
	if s:sub(i, i) == "}" then return out, i + 1 end
	while true do
		local k, v
		k, i = parse_string(s, i)
		i = skip_ws(s, i)
		if s:sub(i, i) ~= ":" then parse_error(s, i, "expected : after key") end
		i = skip_ws(s, i + 1)
		v, i = parse_value(s, i)
		out[k] = v
		i = skip_ws(s, i)
		local c = s:sub(i, i)
		if c == "}" then return out, i + 1 end
		if c ~= "," then parse_error(s, i, "expected , or } in object") end
		i = skip_ws(s, i + 1)
	end
end

parse_value = function(s, i)
	i = skip_ws(s, i)
	local c = s:sub(i, i)
	if c == "" then parse_error(s, i, "unexpected end of input") end
	if c == "{" then return parse_object(s, i) end
	if c == "[" then return parse_array(s, i) end
	if c == '"' then return parse_string(s, i) end
	if s:sub(i, i + 3) == "true"  then return true,  i + 4 end
	if s:sub(i, i + 4) == "false" then return false, i + 5 end
	if s:sub(i, i + 3) == "null"  then return nil,   i + 4 end
	if c:match("[%-0-9]") then return parse_number(s, i) end
	parse_error(s, i, "unexpected character " .. c)
end

-- Returns value, or (nil, err) -- callers need no pcall of their own.
function Json.decode(s)
	local ok, v = pcall(function()
		local val, i = parse_value(s, 1)
		i = skip_ws(s, i)
		if i <= #s then parse_error(s, i, "trailing garbage after document") end
		return val
	end)
	if not ok then return nil, tostring(v) end
	return v
end

X4MCP_Json = Json
