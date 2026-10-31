--[[ x4mcp recipe
signature: player_faction_relation(faction_id) -> {value, status, boosted}
tags: query, faction, reputation, relation
verified: Ran on a live save: returned Argon Federation relation value -15, status 1, and no temporary boost.

Returns the player's current reputation with a faction from the live RelationDetails record. Use a faction ID, not its localized display name.
]]
function(faction_id)
  local r = C.GetFactionRelationStatus2(faction_id)
  return {
    value = r.relationValue,
    status = r.relationStatus,
    boosted = r.isBoostedValue
  }
end
