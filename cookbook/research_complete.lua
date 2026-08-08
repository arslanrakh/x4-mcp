--[[ x4mcp recipe
signature: research_complete(research_id) -> boolean
tags: research, read, verify
verified: re-checked on a live save here: true for research_diplomacy_network and research_teleportation, false for a made-up id and for an empty string, so it discriminates

Returns whether the player has already completed one research item. Pass the internal research id, such as research_diplomacy_network; it checks the game's live research state without starting research or spending money.
]]
function(research_id)
	return C.HasResearched(tostring(research_id))
end
