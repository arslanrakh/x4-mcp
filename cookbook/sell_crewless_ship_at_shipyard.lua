--[[ x4mcp recipe
signature: sell_crewless_ship_at_shipyard(ship_id, shipyard_id) -> {quoted, paid, player_owned_after, owner_after} | nil, reason
tags: ships, sale, shipyard, personnel, money, write, verification
verified: the sale itself ran on this save earlier (balance 5,941,635 -> 11,119,346, owner changed to terran). The two preconditions added since were read out of the game's own menu.buttonSellShips and createSellShipsContext in menu_map.lua, not guessed, and the code recompiled here.

Sells one ship to a shipyard, following menu.buttonSellShips in the game's own
map UI: read the live quote, transfer that amount from the shipyard to the
player, then hand the ship over.

Paying before the sale looks backwards and is exactly what the game does --
TransferMoneyToPlayer first, C.SellPlayerShip second. SellPlayerShip returns
void, so it reports nothing at all; the only way to know it worked is to read
`owner` back afterwards, which this does.

The blockers, taken from the game's own sell dialog:

  - An "Equip" order in the queue makes a ship UNSELLABLE. The dialog greys it
    out and excludes it from the total. This matters when selling equipment
    first: a refit puts the ship into Equip, so you cannot sell the hull until
    that finishes.
  - Modded ships can be sold, but the mods are lost. The game shows a warning;
    `mods_lost` here reports the same thing rather than refusing.

Refusing a ship with an assigned pilot is this recipe's own policy, not the
game's -- transfer the captain first with
cookbook.transfer_assigned_pilot_to_station if you want to keep them.
]]
function(ship_id, shipyard_id)
	local ship = ConvertStringTo64Bit(tostring(ship_id))
	local ship_lua = ConvertStringToLuaID(tostring(ship_id))
	local shipyard = ConvertStringTo64Bit(tostring(shipyard_id))

	if not GetComponentData(ship_lua, "isplayerowned") then return nil, "ship is not player-owned" end
	if not GetComponentData(ship_lua, "issellable") then return nil, "ship is not sellable" end
	if not C.CanContainerBuildShip(shipyard, ship) then return nil, "shipyard will not accept this ship class" end

	-- The game's sell dialog greys out any ship running Equip and leaves it
	-- out of the total. Without this check the money moves and the ship stays.
	local n = tonumber(C.GetNumOrders(ship)) or 0
	if n > 0 then
		local buf = ffi.new("Order[?]", n)
		n = tonumber(C.GetOrders(buf, n, ship)) or 0
		for i = 0, n - 1 do
			if ffi.string(buf[i].orderdef) == "Equip" then
				return nil, "the ship is being refitted (Equip order); wait for it to finish"
			end
		end
	end

	local pilot = GetComponentData(ship_lua, "assignedaipilot")
	if pilot and IsValidComponent(pilot) then return nil, "transfer the assigned pilot first" end

	local quoted = GetTotalValue(ship, true, shipyard)
	local before = GetPlayerMoney()
	TransferMoneyToPlayer(quoted, shipyard, "sellship")
	C.SellPlayerShip(ship, shipyard)

	-- SellPlayerShip is void: ownership is the only evidence it happened.
	local owner = GetComponentData(ship_lua, "owner")
	return {
		quoted = quoted,
		paid = GetPlayerMoney() - before,
		sold = GetComponentData(ship_lua, "isplayerowned") ~= true,
		owner_after = owner,
		mods_lost = GetComponentData(ship_lua, "hasanymod") == true,
	}
end
