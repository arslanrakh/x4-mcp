--[[ x4mcp recipe
signature: fleet_group(leader_id, group) -> {assignment, docks_at_commander, members}
tags: read, fleets, verify
verified: ran on a live save: group 2 of two fleets read back as interception with docks_at_commander true

What one subordinate group of a fleet contains and how it is configured:
its members (id and name), its assignment, and whether it docks at the
commander outside combat.

Use it to confirm a set_commander actually landed. `group` is 1-based; the
game shows them as Alpha, Beta, ...
]]
function(leader_id, group)
	local leader = ConvertStringTo64Bit(tostring(leader_id))
	group = tonumber(group) or 1
	local n = tonumber(C.GetNumSubordinatesOfGroup(leader, group)) or 0
	local members = X4MCP_Json.array({})
	if n > 0 then
		local buf = ffi.new("UniverseID[?]", n)
		n = tonumber(C.GetSubordinatesOfGroup(buf, n, leader, group)) or 0
		for i = 0, n - 1 do
			members[#members + 1] = {
				id = helpers.id_str(buf[i]),
				name = helpers.comp_data(helpers.to_luaid(buf[i]), {"name"}).name,
			}
		end
	end
	return {
		group = group,
		assignment = ffi.string(C.GetSubordinateGroupAssignment(leader, group)),
		docks_at_commander = C.ShouldSubordinateGroupDockAtCommander(leader, group) == true,
		members = members,
	}
end
