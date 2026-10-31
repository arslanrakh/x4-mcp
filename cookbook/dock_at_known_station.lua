--[[ x4mcp recipe
signature: ship_id, station_id -> {index, check} | nil, reason
tags: orders, docking, stations, visibility, verification
verified: Re-verified on a live save: the recipe creates and promotes DockAndWait for a known target; callers must wait for a game tick and inspect the returned queue and failure log before declaring success.

Correct docking procedure: (1) choose a station only from player-known discovery and trade data; never enumerate hidden global stations as a destination. (2) Confirm the target is known to the player before submitting DockAndWait. (3) Promote the order to the front. (4) Wait for at least one live game tick, then re-read the ship's active order queue and failed-order messages. Report success only when DockAndWait remains active and there is no new failure. A queued order is not confirmation of a reachable destination. If a failure reports an unreachable destination, do not claim success; select another player-known, reachable target and repeat the verification.
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
