--[[ x4mcp recipe
signature: deploy_objects_at_positions(ship_id, sector_id, macro, points) -> indices | nil, reason
tags: orders, deploy, satellites, scouting, write
verified: Ran on the live save: the Guillemot Sentinel accepted three Advanced Satellite deployment orders in Mercury; the first read back as started and the next two ready.

Replaces a ship's order queue with one deploy-at-position order per point. Each point is a three-number coordinate table. The game API expects the deployable macro and amount as scalar values, not single-element lists.
]]
function(ship_id, sector_id, macro, points)
  local ship = ConvertStringTo64Bit(tostring(ship_id))
  if not C.IsOrderSelectableFor("DeployObjectAtPosition", ship) then
    return nil, "DeployObjectAtPosition is not selectable"
  end
  C.RemoveAllOrders2(ship, false, false)
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
