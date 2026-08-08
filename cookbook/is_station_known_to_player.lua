--[[ x4mcp recipe
signature: is_station_known_to_player(station_id) -> boolean
tags: navigation, stations, visibility, safety, query
verified: Compiled against the live game. The direct docking failure that prompted this recipe is recorded separately; this visibility predicate has not yet been validated as its sole cause.

Checks whether a station is flagged as known to the player before direct docking. Use it as a first gate: if false, move into the station's sector or near its position before attempting to dock. Even true is not a guarantee of a usable route; always check the ship's failed-order message afterward.
]]
function(station_id)
  local station = ConvertStringTo64Bit(station_id)
  return GetComponentData(helpers.to_luaid(station), "isknown") == true
end
