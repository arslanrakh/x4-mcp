--[[ x4mcp recipe
signature: unit_cargo(ship_id) -> [{ware, amount}]
tags: query, cargo, drones, units
verified: Ran on the live save against Guillemot Sentinel; correctly returned no ordinary unit cargo. Satellite stock is queried separately through GetAllSatellites.

Returns ordinary unit cargo such as drones. Does not return deployables such as satellites; use satellite_ammo for those.
]]
function(ship_id)
  local ship = ConvertStringTo64Bit(ship_id)
  local n = C.GetNumUnitCargo(ship, false)
  local buf = ffi.new("UIWareInfo[?]", n)
  n = C.GetUnitCargo(buf, n, ship, false)
  local out = {}
  for i = 0, n - 1 do
    out[#out + 1] = {
      ware = ffi.string(buf[i].ware),
      amount = tonumber(buf[i].amount)
    }
  end
  return out
end
