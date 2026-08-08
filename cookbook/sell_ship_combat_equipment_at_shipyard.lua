--[[ x4mcp recipe
signature: sell_ship_combat_equipment_at_shipyard(ship_id, shipyard_id) -> {task_id, payout, check} | nil, reason
tags: shipyard, equipment, sale, refit, write, verification
verified: ran once on this save (Hyperion ZVK-956, quote 6,196,810, refit completed with shields, weapons and turrets removed). But the MECHANISM is NOT the game's: menu_ship_configuration.lua:11452 passes 0 as AddBuildTask6's price for a player-owned yard and the real cost otherwise, never a negative number, and the payment is made upfront with TransferPlayerMoneyTo and reconciled by build.shiptrader.xml against $build.transferredamount. Treat the payout below as unexplained.

Strips shields, weapons and turrets by submitting a minimum-loadout refit,
passing the negative of a self-computed quote as the build price.

READ THIS BEFORE USING IT. The negative price is NOT how X4 does this, and the
payout it produced has no confirmed source:

  - The game's own configuration menu passes 0 as AddBuildTask6's price when
    the shipyard is player-owned, and the real positive cost otherwise. It
    never passes a negative amount.
  - Payment is made UPFRONT by the UI with TransferPlayerMoneyTo, recorded via
    C.SetBuildTaskTransferredMoney, and reconciled inside build.shiptrader.xml,
    which computes $build.price - $build.transferredamount and only ever
    charges the player when that difference is positive. Nothing on that path
    pays a negative price out.
  - The quote itself is GetBuildWarePrice, the shipyard's BUY price for the
    ware, which is what you would pay to install it, not what a yard pays to
    remove it.

So this recipe sets its own price on a path the game does not exercise. It ran
once and the refit completed, but until someone reads the actual credit path
for removed wares, do not rely on the payout figure. cookbook.quote_removable_
ship_equipment is safe on its own -- it only reads prices.

Note also that the refit puts the ship into an Equip order, and a ship running
Equip cannot be sold. Sell equipment first, wait for Equip to clear, then sell
the hull.
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
