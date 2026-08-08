--[[ x4mcp recipe
signature: available_mission_offers(include_tutorials) -> array of mission offers
tags: missions, offers, read
verified: Ran on the live save and received all six Terran war offers, including Force Projection, with their titles, descriptions, difficulties and rewards.

Lists current mission offers with title, description, difficulty, type, faction and reward. GetCurrentMissionOffers yields offer components, so the recipe resolves each with GetMissionOfferDetails. Pass true to include tutorials; otherwise omit them.
]]
function(include_tutorials)
	local n = tonumber(C.GetNumCurrentMissionOffers(true)) or 0
	local out = X4MCP_Json.array({})
	if n == 0 then return out end
	local buf = ffi.new("uint64_t[?]", n)
	n = tonumber(C.GetCurrentMissionOffers(buf, n, true)) or 0
	for i = 0, n - 1 do
		local offer = ConvertStringToLuaID(tostring(buf[i]))
		local name, description, difficulty, threadtype, maintype, subtype, subtypename, faction, rewardmoney, rewardtext, briefingobjectives, activebriefingstep, briefingmissions, oppfaction, licence, missiontime, duration, abortable = GetMissionOfferDetails(offer)
		if include_tutorials == true or maintype ~= "tutorial" then
			out[#out + 1] = { id = helpers.id_str(buf[i]), name = name, description = description, difficulty = difficulty, type = maintype, subtype = subtypename, faction = faction, reward = rewardmoney, reward_text = rewardtext, time_left = missiontime, duration = duration, abortable = abortable }
		end
	end
	return out
end
