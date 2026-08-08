--[[ x4mcp recipe
signature: move_to_sector_coordinates(ship_id, sector_id, x, y, z) -> {index, enabled, check} | nil, reason
tags: orders, navigation, coordinates, write, verification
verified: Ran on the live save: sent the Hyperion to a point 6 km from the undiscovered Terran shipyard in The Moon; MoveWait read back enabled and ready, with zero failed-order messages.

Moves a ship to an arbitrary coordinate inside a sector. The destination must be a two-element table: the sector as a Lua object ID and the coordinate as a numeric array {x, y, z}; keyed fields such as {x=..., y=..., z=...} do not arm MoveWait. Always returns the ship-specific post-order failure check.
]]
function(ship_id, sector_id, x, y, z)
  local ship = ConvertStringTo64Bit(tostring(ship_id))
  local sector64 = ConvertStringTo64Bit(tostring(sector_id))
  if not C.IsOrderSelectableFor("MoveWait", ship) then
    return nil, "MoveWait is not selectable for ship " .. tostring(ship_id)
  end
  local idx = tonumber(C.CreateOrder(ship, "MoveWait", false)) or 0
  if idx == 0 then return nil, "CreateOrder refused MoveWait" end
  local destination = {
    ConvertStringToLuaID(tostring(sector64)),
    { tonumber(x), tonumber(y), tonumber(z) }
  }
  local setok, seterr = pcall(SetOrderParam, ship, idx, 1, nil, destination)
  if not setok then
    C.RemoveOrder(ship, idx)
    return nil, "could not set destination: " .. tostring(seterr)
  end
  local enabled = C.EnableOrder(ship, idx)
  if not enabled then
    C.RemoveOrder(ship, idx)
    return nil, "MoveWait could not be enabled"
  end
  if idx ~= 1 then C.AdjustOrder(ship, idx, 1, true, false, false) end
  return { index = idx, enabled = true, check = cookbook.check_ship_order_state_and_failures(tostring(ship_id)) }
end
