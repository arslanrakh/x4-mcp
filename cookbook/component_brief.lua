--[[ x4mcp recipe
signature: component_id -> {name, owner, macro, sector}
tags: read, components, identity
verified: Ran on a live save: resolved a commander reference to the player's Grand Exchange I Headquarters.

Returns a compact identity record for any live component by stable numeric ID. Takes the ID as a digit string and converts it to a 64-bit game ID before querying.
]]
function(component_id)
  local id = ConvertStringTo64Bit(component_id)
  return {
    name = GetComponentData(id, "name"),
    owner = GetComponentData(id, "owner"),
    macro = GetComponentData(id, "macro"),
    sector = GetComponentData(id, "sector")
  }
end
