--[[ x4mcp recipe
signature: dock_at_known_station(ship_id, station_id) -> {index, check} | nil, reason
tags: orders, docking, stations, visibility, verification
verified: Ran on the live save: after the Terran shipyard in The Moon became known, Hyperion received DockAndWait; read back enabled and ready with no failed-order message.

Direct-docks a ship at a station only after the station is known to the player. It promotes DockAndWait to the front and returns the ship-specific queue and failed-order check. If the station is unknown, use move_to_sector_coordinates near it first.
]]
function(ship_id, station_id)
  if not cookbook.is_station_known_to_player(tostring(station_id)) then
    return nil, "station is not known to the player; move near it before direct docking"
  end
  local result, reason = cookbook.give_order(
    tostring(ship_id), "DockAndWait", { [1] = { id = tostring(station_id) } }, true
  )
  if not result then return nil, reason end
  return { index = result.index, check = cookbook.check_ship_order_state_and_failures(tostring(ship_id)) }
end
