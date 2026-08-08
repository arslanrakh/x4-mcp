--[[ x4mcp recipe
signature: protect_station(ship_id, station_id, radius) -> {index, unset} | nil, reason
tags: orders, defence, stations, write
verified: Ran on the live save: Sol's Iron Vanguard flagship accepted ProtectStation for the player headquarters and the order read back as started.

Orders a ship to protect one station indefinitely within a radius in metres, through cookbook.give_order -- so the selectability check, the object reference and the queue placement all come from there.

It does NOT confirm the order afterwards. Read the ship back with cookbook.ship_orders and look for ProtectStation in the queue: an order that was created but never took looks identical from here.
]]
function(ship_id, station_id, radius)
	return cookbook.give_order(tostring(ship_id), "ProtectStation", {
		[1] = { id = tostring(station_id) },
		[2] = tonumber(radius) or 20000,
	}, true)
end
