--[[ x4mcp recipe
signature: ship_orders(ship_id) -> {assignment, sector, orders = [{order, state}]}
tags: read, orders, verify

What a ship is actually doing: its order queue with each entry's state, plus
its assignment and sector.

This is how you verify a write. Orders are queued rather than instant, and an
order that was created but never armed looks exactly like success from the
call site -- read the ship back instead of trusting the return value.
]]
function(ship_id)
	local ship = ConvertStringTo64Bit(tostring(ship_id))
	local lid = ConvertStringToLuaID(tostring(ship_id))
	local n = tonumber(C.GetNumOrders(ship)) or 0
	local orders = X4MCP_Json.array({})
	if n > 0 then
		local buf = ffi.new("Order3[?]", n)
		n = tonumber(C.GetOrders3(buf, n, ship)) or 0
		for i = 0, n - 1 do
			orders[#orders + 1] = {
				order = ffi.string(buf[i].orderdef),
				state = ffi.string(buf[i].state),
			}
		end
	end
	local d = helpers.comp_data(lid, {"name", "assignment", "sector"})
	return { name = d.name, assignment = d.assignment, sector = d.sector,
	         orders = orders }
end
