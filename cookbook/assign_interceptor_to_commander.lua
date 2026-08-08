--[[ x4mcp recipe
signature: assign_interceptor_to_commander(subordinate_id, commander_id) -> order_index | nil, reason
tags: orders, fleets, interception, commander
verified: Ran on a live save: reassigned a docked Theseus Sentinel to the remaining Hyperion; GetCommander read back the intended commander ID.

Assigns a ship to a commander with the interception role, checks that the order is selectable, arms it, and promotes it to the current order. Use plain digit-string IDs.
]]
function(subordinate_id, commander_id)
  local subordinate = ConvertStringTo64Bit(subordinate_id)
  if not C.IsOrderSelectableFor("AssignCommander", subordinate) then return nil, "AssignCommander unavailable" end
  local idx = C.CreateOrder(subordinate, "AssignCommander", false)
  SetOrderParam(subordinate, idx, 1, nil, ConvertStringToLuaID(commander_id))
  SetOrderParam(subordinate, idx, 2, nil, "interception")
  SetOrderParam(subordinate, idx, 5, nil, true)
  C.EnableOrder(subordinate, idx)
  if idx ~= 1 then C.AdjustOrder(subordinate, idx, 1, true, false, false) end
  return idx
end
