--[[ x4mcp recipe
signature: clear_ship_order_failures(ship_id) -> number_remaining
tags: orders, failures, cleanup, diagnostics
verified: Ran on a live save: removed the failed DockAt message from the Hyperion and read back zero remaining order failures.

Removes every visible failed-order message attached to a ship, then returns the number still remaining. Use after reading and recording the failure reason; clearing a message does not repair the underlying order.
]]
function(ship_id)
  local ship = ConvertStringTo64Bit(ship_id)
  local n = C.GetNumOrderFailures(ship, true)
  local failures = ffi.new("OrderFailure[?]", n)
  n = C.GetOrderFailures(failures, n, ship, true)
  for i = 0, n - 1 do
    C.RemoveOrderFailure(ship, failures[i].id)
  end
  return C.GetNumOrderFailures(ship, true)
end
