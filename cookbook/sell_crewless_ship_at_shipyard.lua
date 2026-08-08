--[[ x4mcp recipe
signature: sell_crewless_ship_at_shipyard(ship_id, shipyard_id) -> {quoted, paid, player_owned_after, owner_after} | nil, reason
tags: ships, sale, shipyard, personnel, money, write, verification
verified: Ran on the live save: after moving Olmanckussut to HQ, sold Hyperion ZVK-956 to the Terran Shipyard. The balance rose from 5,941,635 to 11,119,346 credits; ownership changed to terran.

Implements X4's map sell action for a crewless ship: reads the live shipyard quote, transfers that exact quoted sale amount, then changes ownership. Refuses ships with an assigned AI pilot so the captain is not lost. Always confirms the balance increase and ownership change; do not call this for a ship you intend to keep.
]]
function(ship_id, shipyard_id)
  local ship = ConvertStringTo64Bit(tostring(ship_id))
  local ship_lua = ConvertStringToLuaID(tostring(ship_id))
  local shipyard = ConvertStringTo64Bit(tostring(shipyard_id))
  if not GetComponentData(ship_lua, "isplayerowned") then return nil, "ship is not player-owned" end
  if not GetComponentData(ship_lua, "issellable") then return nil, "ship is not sellable" end
  if not C.CanContainerBuildShip(shipyard, ship) then return nil, "shipyard will not accept this ship class" end
  local pilot = GetComponentData(ship_lua, "assignedaipilot")
  if pilot and IsValidComponent(pilot) then return nil, "transfer the assigned pilot first" end
  local quoted = GetTotalValue(ship, true, shipyard)
  local before = GetPlayerMoney()
  TransferMoneyToPlayer(quoted, shipyard, "sellship")
  C.SellPlayerShip(ship, shipyard)
  local after = GetPlayerMoney()
  return {
    quoted = quoted,
    paid = after - before,
    player_owned_after = GetComponentData(ship_lua, "isplayerowned"),
    owner_after = GetComponentData(ship_lua, "owner")
  }
end
