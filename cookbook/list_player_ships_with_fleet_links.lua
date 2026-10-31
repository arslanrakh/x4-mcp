--[[ x4mcp recipe
signature: list_player_ships_with_fleet_links() -> ships
tags: query, ships, fleet, player
verified: Ran on a live save: returned eight player ships and their commander/subordinate relationships.

Returns every player-owned ship with its display information, stable numeric ID, commander link, and immediate subordinates. This exposes fleet hierarchy without relying on display names for logic.
]]
function()
  local out = {}
  for _, uid in ipairs(helpers.enum(C.GetNumAllFactionShips, C.GetAllFactionShips, "player")) do
    local lid = helpers.to_luaid(uid)
    local d = helpers.comp_data(lid, {"name", "idcode", "macro", "sector", "sectorid", "owner"})
    d.id = helpers.id_str(uid)
    d.commander = helpers.id_str(GetCommander(lid))
    d.subordinates = {}
    for _, s in ipairs(GetSubordinates(lid) or {}) do
      d.subordinates[#d.subordinates+1] = helpers.id_str(s)
    end
    out[#out+1] = d
  end
  return out
end
