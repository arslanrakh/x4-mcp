--[[ x4mcp recipe
signature: set_subordinate_group_dock_at_commander(commander_id, group_id, enabled) -> boolean
tags: fleets, subordinates, docking, interception
verified: Ran on a live save: enabled automatic docking for Hyperion group 2; the game read back true.

Controls whether a commander's subordinate group automatically docks at the commander when appropriate outside combat. Verify the returned flag after setting it.
]]
function(commander_id, group_id, enabled)
  local commander = ConvertStringTo64Bit(commander_id)
  C.SetSubordinateGroupDockAtCommander(commander, group_id, enabled)
  return C.ShouldSubordinateGroupDockAtCommander(commander, group_id)
end
