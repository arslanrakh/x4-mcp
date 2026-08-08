--[[ x4mcp recipe
signature: move_to_sector(ship_id, sector_id) -> order_index | nil, reason
tags: orders, navigation, sectors, visibility
verified: Ran on a live save: the Hyperion received a MoveToObject order to The Moon sector; read-back showed the order enabled, started, and with no failed-order messages.

Sends a ship to a sector without directly targeting an undiscovered station. Use before attempting to dock at a station that is not visible on the player's map; verify order state and failures afterward.
]]
function(ship_id, sector_id)
  local ship = ConvertStringTo64Bit(ship_id)
  if not C.IsOrderSelectableFor("MoveToObject", ship) then return nil, "MoveToObject unavailable" end
  local idx = C.CreateOrder(ship, "MoveToObject", false)
  SetOrderParam(ship, idx, 1, nil, ConvertStringToLuaID(sector_id))
  C.EnableOrder(ship, idx)
  if idx ~= 1 then C.AdjustOrder(ship, idx, 1, true, false, false) end
  return idx
end
