--[[ x4mcp recipe
signature: append_satellites_at_positions(ship_id, sector_id, points, satellite_macro) -> indices | nil, reason
tags: orders, deployables, satellites, queue
verified: Ran on a live save: Guillemot Sentinel kept its four Brennan’s Triumph orders at queue positions 1–4 while three new deployment orders appeared at positions 5–7.

Appends Advanced Satellite deployment orders without touching earlier orders. Use this when a ship already has an active route and the player asks to add another sector afterward. Each point is {x,y,z}; caller must ensure stock and coverage geometry.
]]
function(ship_id, sector_id, points, satellite_macro)
  local ship = ConvertStringTo64Bit(ship_id)
  local sector = ConvertStringToLuaID(sector_id)
  if not C.IsOrderSelectableFor("DeployObjectAtPosition", ship) then
    return nil, "deployment order unavailable"
  end
  local created = {}
  for _, p in ipairs(points) do
    local idx = C.CreateOrder(ship, "DeployObjectAtPosition", false)
    if idx == 0 then
      return nil, "could not create deployment order"
    end
    SetOrderParam(ship, idx, 1, nil, {sector, {p[1], p[2], p[3]}})
    SetOrderParam(ship, idx, 2, nil, satellite_macro)
    SetOrderParam(ship, idx, 3, nil, 1)
    C.EnableOrder(ship, idx)
    created[#created + 1] = idx
  end
  return created
end
