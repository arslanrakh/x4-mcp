--[[ x4mcp recipe
signature: check_ship_order_state_and_failures(ship_id) -> {orders, failures}
tags: orders, verification, diagnostics, failures
verified: Ran on a live save after a failed docking order: the queue was empty and the attached failure message reported that the destination could not be reached.

Reads a ship's active orders and every attached order-failure message. Run immediately after issuing an order; an order creation return value alone does not prove it remains active.
]]
function(ship_id)
  local ship = ConvertStringTo64Bit(ship_id)
  local out = { orders = {}, failures = {} }
  local n = C.GetNumOrders(ship)
  local orders = ffi.new("Order[?]", n)
  n = C.GetOrders(orders, n, ship)
  for i = 0, n - 1 do
    out.orders[#out.orders+1] = {
      id = ffi.string(orders[i].orderdef),
      state = ffi.string(orders[i].state),
      enabled = orders[i].enabled
    }
  end
  n = C.GetNumOrderFailures(ship, true)
  local failures = ffi.new("OrderFailure[?]", n)
  n = C.GetOrderFailures(failures, n, ship, true)
  for i = 0, n - 1 do
    out.failures[#out.failures+1] = {
      order = ffi.string(failures[i].orderdef),
      message = ffi.string(failures[i].message),
      inloop = failures[i].wasinloop
    }
  end
  return out
end
