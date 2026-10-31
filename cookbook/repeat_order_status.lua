--[[ x4mcp recipe
signature: repeat_order_status(ship_id) -> {current_index, loop_index, loop_active, order_count, current_order_id}
tags: orders, repeat-orders, query
verified: Ran on a live save: the Earth Okinawa reported active loop index 1, current index 2, and two queued steps.

Reads a ship's current queue position and whether a Repeat Orders loop is active. Uses the required bool output pointer for GetOrderQueueFirstLoopIdx.
]]
function(ship_id)
  local uid = ConvertStringTo64Bit(ship_id)
  local valid = ffi.new("bool[1]")
  local loopidx = C.GetOrderQueueFirstLoopIdx(uid, valid)
  local current = C.GetOrderQueueCurrentIdx(uid)
  return {
    current_index = tonumber(current),
    loop_index = tonumber(loopidx),
    loop_active = valid[0] and true or false,
    order_count = tonumber(C.GetNumOrders(uid)),
    current_order_id = helpers.id_str(C.GetOrderID(uid, current))
  }
end
