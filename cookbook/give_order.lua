--[[ x4mcp recipe
signature: give_order(ship_id, order_id, params, front) -> {index, unset} | nil, reason
tags: orders, write

Give one ship an order, the way the game's own interact menu does it:
refuse if the order does not apply, create it disabled, fill the positional
parameters, arm it, and move it to the front of the queue.

`params` is a table keyed by the parameter POSITION, which you read with
x4.order_params(order_id) -- names are not accepted by SetOrderParam here.
Sparse is fine; only positions you name are set. An object parameter (a
station, a commander) must be passed as {id = "1234"}: a bare number is not an
object reference, and the order silently targets nothing.

Pass front = false to append instead of pre-empting the current order.

The three traps this handles: X4 accepts an inapplicable order silently and
the ship just sits there; a created order does nothing until EnableOrder; and
an order added at the back of a queue will not run until everything before it
finishes.
]]
function(ship_id, order_id, params, front)
	local ship = ConvertStringTo64Bit(tostring(ship_id))
	local ok, selectable = pcall(C.IsOrderSelectableFor, order_id, ship)
	if not ok or selectable ~= true then
		return nil, order_id .. " is not selectable for ship " .. tostring(ship_id)
	end
	local idx = tonumber(C.CreateOrder(ship, order_id, false)) or 0
	if idx == 0 then return nil, "CreateOrder refused " .. order_id end

	local unset = {}
	for position, value in pairs(params or {}) do
		if type(value) == "table" and value.id ~= nil then
			value = ConvertStringToLuaID(tostring(value.id))
		end
		local set, err = pcall(SetOrderParam, ship, idx, tonumber(position), nil, value)
		if not set then
			unset[#unset + 1] = tostring(position) .. ": " .. tostring(err)
		end
	end

	pcall(C.EnableOrder, ship, idx)
	if front ~= false and idx ~= 1 then
		pcall(C.AdjustOrder, ship, idx, 1, true, false, false)
	end
	return { index = idx, unset = unset }
end
