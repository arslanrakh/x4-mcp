--[[ x4mcp recipe
signature: dock_at(ship_id, station_id) -> index | nil, reason
tags: orders, docking
verified: Ran on a live save: created a DockAndWait order for a Hyperion and read its queued destination back as the selected shipyard.

Sends a ship to dock at a station and advances the order to the front of its queue. Checks selectability before creating the order.
]]
function(ship_id, station_id)
  local ship = ConvertStringTo64Bit(ship_id)
  if not C.IsOrderSelectableFor("DockAndWait", ship) then
    return nil, "DockAndWait is not selectable"
  end
  local idx = C.CreateOrder(ship, "DockAndWait", false)
  SetOrderParam(ship, idx, 1, nil, ConvertStringToLuaID(station_id))
  C.EnableOrder(ship, idx)
  if idx ~= 1 then C.AdjustOrder(ship, idx, 1, true, false, false) end
  return idx
end
