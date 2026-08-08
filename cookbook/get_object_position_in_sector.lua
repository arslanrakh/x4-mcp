--[[ x4mcp recipe
signature: get_object_position_in_sector(object_id) -> {sector_id, x, y, z}
tags: coordinates, objects, sectors, navigation, query
verified: Ran on a live save: retrieved the hidden Terran shipyard position in The Moon sector as x=76577, y=0, z=35236.

Returns any object's coordinates in its sector, together with the sector ID. Use this before sending a ship near an undiscovered station rather than docking directly to it.
]]
function(object_id)
  local object = ConvertStringTo64Bit(object_id)
  local luaid = helpers.to_luaid(object)
  local position = C.GetObjectPositionInSector(object)
  return {
    sector_id = helpers.id_str(GetComponentData(luaid, "sectorid")),
    x = position.x,
    y = position.y,
    z = position.z
  }
end
