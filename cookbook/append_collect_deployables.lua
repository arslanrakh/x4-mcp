--[[ x4mcp recipe
signature: append_collect_deployables(ship_id, deployable_ids) -> order_index | nil, reason
tags: orders, collect, deployables, satellites, queue
verified: Ran on a live save: appended a CollectDeployables order for four player Advanced Satellites in Black Hole Sun IV and V; it read back as the active order with no failures.

Appends one CollectDeployables order for specified player-owned deployable object IDs without clearing existing orders. Checks that the order is selectable and arms it; callers must verify the queue afterward.
]]
function(ship_id, deployable_ids)
  local ship = ConvertStringTo64Bit(ship_id)
  if not C.IsOrderSelectableFor("CollectDeployables", ship) then
    return nil, "CollectDeployables is not selectable"
  end
  local idx = C.CreateOrder(ship, "CollectDeployables", false)
  if idx <= 0 then
    return nil, "CreateOrder failed"
  end
  for _, deployable_id in ipairs(deployable_ids) do
    SetOrderParam(ship, idx, 1, nil, ConvertStringToLuaID(tostring(deployable_id)))
  end
  C.EnableOrder(ship, idx)
  return idx
end
