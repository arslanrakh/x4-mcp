--[[ x4mcp recipe
signature: deploy_satellites_at_positions(ship_id, sector_id, points, satellite_macro) -> orders | nil, reason
tags: orders, satellites, deployables, navigation
verified: Ran on the live save for Guillemot Sentinel: replaced its MoveWait order with four DeployObjectAtPosition orders in Brennan's Triumph; after a game tick, order one was started and three were ready.

Replaces a ship's queue with one Advanced/standard satellite deployment order per specified sector position. Uses the game's DeployObjectAtPosition order and verifies the queue is created; callers must check satellite stock and route reachability first.
]]
function(ship_id, sector_id, points, satellite_macro)
  local ship = ConvertStringTo64Bit(ship_id)
  local sector = ConvertStringToLuaID(sector_id)
  for i = C.GetNumOrders(ship), 1, -1 do
    C.RemoveOrder(ship, i, true, false)
  end
  for i, p in ipairs(points) do
    if not C.IsOrderSelectableFor("DeployObjectAtPosition", ship) then
      return nil, "DeployObjectAtPosition is not selectable"
    end
    local idx = C.CreateOrder(ship, "DeployObjectAtPosition", false)
    if idx == 0 then return nil, "could not create order " .. i end
    SetOrderParam(ship, idx, 1, nil, {sector, {p[1], p[2], p[3]}})
    SetOrderParam(ship, idx, 2, nil, satellite_macro)
    SetOrderParam(ship, idx, 3, nil, 1)
    C.EnableOrder(ship, idx)
    if idx ~= i then C.AdjustOrder(ship, idx, i, true, false, false) end
  end
  local n = C.GetNumOrders(ship)
  local buf = ffi.new("Order[?]", n)
  n = C.GetOrders(buf, n, ship)
  local out = {}
  for i = 0, n - 1 do
    out[#out + 1] = {
      queueidx = tonumber(buf[i].queueidx),
      order = ffi.string(buf[i].orderdef),
      state = ffi.string(buf[i].state)
    }
  end
  return out
end
