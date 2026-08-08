--[[ x4mcp recipe
signature: compare_player_ships_defense_by_macro(macro) -> array of {name, id, hull, shield, hullpercent, shieldpercent}
tags: player, ships, comparison, shields, hull, query
verified: Ran on a live save with ship_par_s_fighter_02_b_macro: returned two Theseus Sentinel ships, each at 7,500 hull and approximately 6,860 shield, both fully repaired.

Lists every player-owned ship of a given macro and compares its observed hull and shield values. Use this to verify whether same-model ships differ in defensive configuration.
]]
function(macro)
  local out = {}
  for _, uid in ipairs(helpers.enum(C.GetNumAllFactionShips, C.GetAllFactionShips, "player")) do
    local ship = helpers.to_luaid(uid)
    if GetComponentData(ship, "macro") == macro then
      out[#out+1] = {
        id = helpers.id_str(uid),
        name = GetComponentData(ship, "name"),
        hull = GetComponentData(ship, "hull"),
        shield = GetComponentData(ship, "shield"),
        hullpercent = GetComponentData(ship, "hullpercent"),
        shieldpercent = GetComponentData(ship, "shieldpercent")
      }
    end
  end
  return out
end
