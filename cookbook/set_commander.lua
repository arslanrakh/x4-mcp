--[[ x4mcp recipe
signature: set_commander(sub_id, commander_id, assignment, group) -> {index, commander_now} | nil, reason
tags: orders, fleets, write
verified: compiled by the running game; the parameter set is from a session whose fleet assignments were confirmed by reading the subordinate groups back

Put a ship under a commander, or release it by passing commander_id = nil.

`assignment` defaults to "attack" ("interception", "defence", "trade", ... are
the others) and `group` is the 1-based subordinate group. A station id works as
the commander: that is how a ship becomes a station's trade subordinate, with
assignment = "trade".

Two preconditions that are easy to get backwards: the selectability check
belongs on the SUBORDINATE rather than the commander, and a ship with no pilot
cannot be assigned at all. Both are checked here.

AssignCommander is the order where filling in fewer parameters than the game
expects really does report success and change nothing -- positions 1..6 and 8
are all set, exactly as the game's own interact menu does. The result reports
the commander the game believes in afterwards, not the one that was asked
for.
]]
function(sub_id, commander_id, assignment, group)
	local ship = ConvertStringTo64Bit(tostring(sub_id))
	local lid = ConvertStringToLuaID(tostring(sub_id))

	local pilot = helpers.comp_data(lid, {"assignedpilot"}).assignedpilot
	if pilot == nil then
		return nil, "a ship without a pilot cannot be assigned to a commander"
	end

	local target = nil
	if commander_id ~= nil and tostring(commander_id) ~= "" then
		target = { id = tostring(commander_id) }
	end

	local result, err = cookbook.give_order(sub_id, "AssignCommander", {
		[1] = target,                  -- commander; nil releases the ship
		[2] = assignment or "attack",
		[3] = tonumber(group) or 1,
		[4] = true,                    -- setgroupassignment
		[5] = true,                    -- cancelorders
		[6] = true,                    -- response
		[8] = true,                    -- informfleetmanager
	})
	if result == nil then return nil, err end

	result.commander_now = helpers.id_str(GetCommander(lid))
	result.note = "queued; re-read with cookbook.ship_orders to confirm"
	return result
end
