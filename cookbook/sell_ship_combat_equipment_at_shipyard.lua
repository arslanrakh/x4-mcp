--[[ x4mcp recipe
signature: sell_ship_combat_equipment_at_shipyard(ship_id, shipyard_id) -> {task_id, payout, check} | nil, reason
tags: shipyard, equipment, sale, refit, write, verification
verified: ran on this save (Hyperion ZVK-956, 6,196,810 credits, refit completed with shields, weapons and turrets removed). The mechanism was then traced through the game's own code and matches: menu_ship_configuration.lua:7592 subtracts removed equipment from the refit price at the same GetBuildWarePrice used here, and build.shiptrader.xml:728-731 refunds the player when the resulting price is negative.

Strips shields, weapons and turrets by submitting a minimum-loadout refit
priced at the negative of what the removed equipment is worth, so the shipyard
pays you for it. Returns the build task id and the payout.

The negative price looks like a trick and is not: it is exactly what the game
does. menu_ship_configuration.lua:7584-7610 builds a refit price by ADDING new
equipment at GetBuildWarePrice and SUBTRACTING removed equipment at the same
price, so a refit that only removes things has a negative total. The shipyard
script then settles it -- build.shiptrader.xml computes

    missingpayment = build.price - build.transferredamount

and, when that is negative, transfers -missingpayment from the shipyard to the
player. Nothing is paid upfront for a negative total, so transferredamount
stays 0 and the refund is the whole amount. The engine's own assertion there
reads "$buildprice le 0 or $buildprice ge $transferredmoney" -- a non-positive
build price is an anticipated case, not an exploit.

Two conditions that decide whether you get paid at all:

  - THIS ONLY PAYS AT A SHIPYARD YOU DO NOT OWN. Every price path in the
    configuration menu is wrapped in `if not menu.isplayerowned`, and the
    settlement block in build.shiptrader is guarded by `not this.isplayerowned`.
    Refit at your own yard and the price is 0 by design: no charge, no refund.
  - Wares flagged `volatile` are priced at 0 (menu_ship_configuration.lua:11147),
    so they are never credited. Shields, weapons and turrets are not volatile.

Afterwards the ship carries an Equip order, and a ship running Equip CANNOT be
sold. Sell the equipment, wait for Equip to clear, then sell the hull with
cookbook.sell_crewless_ship_at_shipyard.
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
