-- The game's side of the link, reduced to the calls the extension makes:
-- package.loadlib, open, update, send, recv, close. Echoes one request.
local dll, port = arg[1], tonumber(arg[2])
local open = assert(package.loadlib(dll, "luaopen_x4mcp"))
local m = open()
print("lua: loaded " .. m.version())

local deadline = os.time() + 60
local function in_time() assert(os.time() < deadline, "timed out") end

-- Connect, retrying while the stand-in server starts, as the game does.
while m.state() ~= "connected" do
  if m.state() == "disconnected" then m.open("127.0.0.1", port) end
  m.update()
  in_time()
end
assert(m.send('{"t":"hello","native":"' .. m.version() .. '"}'))

local req
repeat
  local n, err = m.update()
  assert(m.state() == "connected", "link down: " .. tostring(err))
  if n > 0 then req = m.recv() end
  in_time()
until req

local seq = assert(req:match('"seq":(%d+)'))
local args = assert(req:match('"args":(%b{})'))
assert(m.send('{"t":"resp","seq":' .. seq .. ',"ok":true,"data":' .. args .. '}'))

-- The server closes the link once it has checked the reply.
while m.state() == "connected" do
  m.update()
  in_time()
end
m.close()
print("lua: smoke ok")
