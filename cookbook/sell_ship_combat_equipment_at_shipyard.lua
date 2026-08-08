--[[ x4mcp recipe
signature: sell_ship_combat_equipment_at_shipyard(ship_id, shipyard_id) -> {task_id, payout, check} | nil, reason
tags: shipyard, equipment, sale, refit, write, verification
verified: Ran on the live save for Hyperion ZVK-956: the Terran shipyard quote was 6,196,810 credits; the refit completed with shields, weapons and turrets removed while the hull remained.

Quotes the current shipyard payout for installed shields, weapons, and turrets, then submits a minimum-loadout refit with the negative quoted amount so the shipyard pays for the removed combat equipment. It does not sell the hull. Assign a captain before waiting for Equip to start, and verify the payout and final loadout afterwards.
]]
function(ship_id, shipyard_id)
  local ship = ConvertStringTo64Bit(tostring(ship_id))
  local shipyard = ConvertStringTo64Bit(tostring(shipyard_id))
  local macro = GetComponentData(ConvertStringToLuaID(tostring(ship_id)), "macro")
  local quote = cookbook.quote_removable_ship_equipment(tostring(ship_id), tostring(shipyard_id))
  if not quote or quote.payout <= 0 then return nil, "no removable combat equipment to sell" end
  local loadout = Helper.getLoadoutHelper2(
    C.GenerateShipLoadout2, C.GenerateShipLoadoutCounts2, "UILoadout2",
    shipyard, ship, macro, 0
  )
  local task = C.AddBuildTask6(
    shipyard, ship, macro, loadout, -quote.payout,
    ffi.new("CrewTransferInfo2"), false, nil, ffi.new("AddBuildTask6Container")
  )
  if task == 0 then return nil, "shipyard refused the refit" end
  return {
    task_id = tostring(task),
    payout = quote.payout,
    check = cookbook.check_ship_order_state_and_failures(tostring(ship_id))
  }
end
