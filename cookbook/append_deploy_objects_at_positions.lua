--[[ x4mcp recipe
signature: append_deploy_objects_at_positions(ship_id, sector_id, macro, points) -> indices
verified: Ran on the live save: appended three Venus and then three Mars advanced-satellite orders; the scout's queue read back one started plus five ready orders.

Appends deploy-at-position orders without clearing the current queue.
]]
function(ship_id, sector_id, macro, points)
  local ship = ConvertStringTo64Bit(tostring(ship_id))
  local sector = ConvertStringToLuaID(tostring(sector_id))
  local indices = {}
  for _, point in ipairs(points) do
    local idx = C.CreateOrder(ship, "DeployObjectAtPosition", false)
    SetOrderParam(ship, idx, 1, nil, {sector, {point[1], point[2], point[3]}})
    SetOrderParam(ship, idx, 2, nil, macro)
    SetOrderParam(ship, idx, 3, nil, 1)
    C.EnableOrder(ship, idx)
    indices[#indices + 1] = idx
  end
  return indices
end
