--[[ x4mcp recipe
signature: clear_order_failures(ship_id) -> number
tags: orders, errors, write
verified: saved by an earlier session against this same save; NOT re-run here, because dismissing failure notices is not reversible

Dismisses all current order-failure notifications for one ship and returns how many were cleared. It clears only the failure notices; it does not remove, retry, or otherwise change the ship's orders.
]]
function(ship_id)
	local ship = ConvertStringTo64Bit(tostring(ship_id))
	local n = tonumber(C.GetNumOrderFailures(ship, false)) or 0
	if n == 0 then return 0 end
	local buf = ffi.new("OrderFailure[?]", n)
	n = tonumber(C.GetOrderFailures(buf, n, ship, false)) or 0
	for i = 0, n - 1 do
		C.RemoveOrderFailure(ship, buf[i].id)
	end
	return n
end
