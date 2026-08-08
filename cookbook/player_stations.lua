--[[ x4mcp recipe
signature: player_stations(fields) -> array of {id, ...fields}
tags: read, stations
verified: ran on a live save: returned the player HQ with sector 'Grand Exchange I' and sectorid 168365580

Every station the player owns. Same shape and the same defaults idea as
cookbook.player_ships: `fields` is optional, `id` is always added as a digit
string.

Only the player's own property -- other factions' stations are not enumerated
here.

`sectorid` is the location; `sector` beside it is the displayed, localised
name. A station has no `sector_macro` field in 9.0 either.
]]
function(fields)
	fields = fields or {"name", "macro", "sector", "sectorid", "hullpercent"}
	local out = {}
	for _, uid in ipairs(helpers.enum(C.GetNumAllFactionStations,
	                                  C.GetAllFactionStations, "player")) do
		local d = helpers.comp_data(helpers.to_luaid(uid), fields)
		d.id = helpers.id_str(uid)
		out[#out + 1] = d
	end
	return out
end
