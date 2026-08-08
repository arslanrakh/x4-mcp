--[[ x4mcp recipe
signature: configure_group(leader_id, group, assignment, dock_at_commander) -> fleet_group(...)
tags: fleets, write

Set a subordinate group's assignment, and whether its ships return to the
flagship when there is no fighting.

This configures the GROUP on the commander, which is a different thing from
the per-ship assignment in set_commander: ships joining the group later
inherit it. Returns the group as the game reports it afterwards.

Leave dock_at_commander nil to leave that setting alone.
]]
function(leader_id, group, assignment, dock_at_commander)
	local leader = ConvertStringTo64Bit(tostring(leader_id))
	group = tonumber(group) or 1
	if assignment ~= nil then
		C.SetSubordinateGroupAssignment(leader, group, assignment)
	end
	if dock_at_commander ~= nil then
		C.SetSubordinateGroupDockAtCommander(leader, group, dock_at_commander == true)
	end
	return cookbook.fleet_group(leader_id, group)
end
