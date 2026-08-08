--[[ x4mcp recipe
signature: missions() -> array of accepted missions with id, name, description, reward
tags: read, missions
verified: ran on a live save: 4 accepted missions with names and rewards

The player's ACCEPTED missions, with their full text.

Deliberately not the offers on a mission board: those come from a different
enumerator. GetMissionDetails returns a long positional tuple, and the useful
values are scattered through it -- that unpacking is the part worth keeping.
]]
function()
	local out = {}
	for i = 1, GetNumMissions() do
		local id, name, description, difficulty, threadtype, maintype,
		      subtype, subtypename, faction, reward, rewardtext,
		      _, _, _, _, _, timeleft, _, abortable = GetMissionDetails(i)
		out[#out + 1] = {
			id = helpers.id_str(ConvertIDTo64Bit(id)),
			name = name, description = description,
			difficulty = difficulty, thread_type = threadtype,
			category = maintype, type = subtype, type_name = subtypename,
			faction = faction, reward = reward, reward_text = rewardtext,
			time_left = timeleft, abortable = abortable,
		}
	end
	return out
end
