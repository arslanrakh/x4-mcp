--[[ x4mcp recipe
signature: stations_in_sector(sector_id) -> array of {id, name, owner, macro, x, y, z}
tags: stations, sectors, coordinates, coverage, query
verified: Ran on the live save: returned all 8 stations in Path to Profit with coordinates used to verify two 70 km satellite coverage spheres.

Returns every live faction station in a sector, including stations not yet known to the player, deduplicated across faction enumeration. Coordinates are full 3D sector positions, suitable for sensor-coverage planning.
]]
function(sector_id)
  local target = tostring(sector_id)
  local out, seen = {}, {}
  for _, faction in ipairs(helpers.factions()) do
    for _, uid in ipairs(helpers.enum(C.GetNumAllFactionStations, C.GetAllFactionStations, faction)) do
      local id = helpers.id_str(uid)
      if not seen[id] then
        local lid = helpers.to_luaid(uid)
        local actual_sector = helpers.id_str(GetComponentData(lid, "sectorid"))
        if actual_sector == target then
          seen[id] = true
          local d = helpers.comp_data(lid, {"name", "owner", "macro"})
          local p = C.GetObjectPositionInSector(uid)
          out[#out + 1] = {
            id = id,
            name = d.name,
            owner = d.owner,
            macro = d.macro,
            x = p.x,
            y = p.y,
            z = p.z
          }
        end
      end
    end
  end
  return out
end
