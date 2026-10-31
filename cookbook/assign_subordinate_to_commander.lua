--[[ x4mcp recipe
signature: assign_subordinate_to_commander(ship_id, commander_id, assignment, group_id) -> index | nil, reason
tags: fleets, orders, commander, assignment
verified: Ran on a live save: moved a Theseus Sentinel to its new Hyperion commander; GetCommander read back the new commander and assignment defence.

Assigns a ship to a new commander while preserving a chosen assignment and group. Checks that the assignment order is selectable, enables it, and moves it to the front of the queue.
]]
function(ship_id, commander_id, assignment, group_id)
  local ship = ConvertStringTo64Bit(ship_id)
  if not C.IsOrderSelectableFor("AssignCommander", ship) then
    return nil, "AssignCommander is not selectable"
  end
  local idx = C.CreateOrder(ship, "AssignCommander", false)
  SetOrderParam(ship, idx, 1, nil, ConvertStringToLuaID(commander_id))
  SetOrderParam(ship, idx, 2, assignment, nil)
  SetOrderParam(ship, idx, 3, group_id, nil)
  SetOrderParam(ship, idx, 4, true, nil)
  SetOrderParam(ship, idx, 5, true, nil)
  C.EnableOrder(ship, idx)
  if idx ~= 1 then C.AdjustOrder(ship, idx, 1, true, false, false) end
  return idx
end
