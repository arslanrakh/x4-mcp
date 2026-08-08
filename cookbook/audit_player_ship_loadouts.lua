--[[ x4mcp recipe
signature: audit_player_ship_loadouts() -> array of ship name, macro, and current loadout statistics
tags: player, ships, loadout, weapons, shields, engines, audit, query
verified: Ran on a live save: returned eight player ships. It distinguished two Theseus Sentinel loadouts with equal hull, shields, and DPS but different boost, travel, radar, and shield recharge values.

Audits all player-owned ships by asking the game for each ship's current loadout statistics: DPS, hull, shields, speed, travel performance, storage, missiles, docks, and capacity. Excludes the player's space suit.
]]
function()
  local out = {}
  for _, uid in ipairs(helpers.enum(C.GetNumAllFactionShips, C.GetAllFactionShips, "player")) do
    local ship = helpers.to_luaid(uid)
    local macro = GetComponentData(ship, "macro")
    if macro ~= "ship_arg_xs_spacesuit_01_a_macro" then
      out[#out+1] = {
        id = helpers.id_str(uid),
        name = GetComponentData(ship, "name"),
        macro = macro,
        stats = Helper.convertLoadoutStats(C.GetCurrentLoadoutStatistics5(uid))
      }
    end
  end
  return out
end
