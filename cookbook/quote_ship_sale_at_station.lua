--[[ x4mcp recipe
signature: quote_ship_sale_at_station(ship_id, station_id) -> {price, sellable, station_accepts} | nil, reason
tags: ships, sale, quote, shipyard, read
verified: Ran on the live save for Hyperion ZVK-956 and the Terran Shipyard: returned 5,177,762.96 credits; ship was sellable and accepted.

Reads the current sale value through the same GetTotalValue call used by X4's map sell window. It does not sell or transfer money. The returned amount can change with the station economy, so quote it immediately before any sale.
]]
function(ship_id, station_id)
  local ship = ConvertStringTo64Bit(tostring(ship_id))
  local station = ConvertStringTo64Bit(tostring(station_id))
  local sellable = GetComponentData(ConvertStringToLuaID(tostring(ship_id)), "issellable")
  local accepts = C.CanContainerBuildShip(station, ship)
  if not sellable then return nil, "ship is not sellable" end
  if not accepts then return nil, "station cannot buy this ship class" end
  return { price = GetTotalValue(ship, true, station), sellable = sellable, station_accepts = accepts }
end
