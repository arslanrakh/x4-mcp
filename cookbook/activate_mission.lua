--[[ x4mcp recipe
signature: activate_mission(name_or_id) -> active mission id | nil, reason
tags: missions, write
verified: compiled by the running game; from a session that activated 'Promotion to: Honorary Assistant' and read GetActiveMissionID back

Make one of the accepted missions the active one (the one guidance points
at). Matches on the mission id first, then on an exact name.

Matching by name is offered because that is what the player says, but it is
the game's display name and therefore localised -- prefer the id from
cookbook.missions when you have it.
]]
function(name_or_id)
	local wanted = tostring(name_or_id)
	for i = 1, GetNumMissions() do
		local id, name = GetMissionDetails(i)
		local id64 = ConvertIDTo64Bit(id)
		if helpers.id_str(id64) == wanted or name == wanted then
			if C.SetActiveMission(id64) ~= true then
				return nil, "the game refused to activate " .. wanted
			end
			return helpers.id_str(C.GetActiveMissionID())
		end
	end
	return nil, "no accepted mission matching " .. wanted
end
