--[[ x4mcp recipe
signature: player_ships(fields) -> array of {id, commander, subordinates, ...fields}
tags: read, ships, fleets

Every ship the player owns, in one round trip.

`fields` is optional and defaults to name, idcode, macro, sector, sectorid,
hullpercent; pass your own list for anything else GetComponentData knows. On
top of them you always get `id`, `commander` and `subordinates` as plain digit
strings, so a commander reference compares equal to the id it points at.

Location is `sectorid`, never `macro`: `macro` is the ship's own hull, and
grouping ships by it puts every Hyperion in one "place". `sector` next to it is
the sector's DISPLAYED name and therefore localised -- fine for the player,
useless for matching. There is no `sector_macro` on a ship in 9.0; for the
sector's macro, read `macro` off the sectorid.
]]
function(fields)
	fields = fields or {"name", "idcode", "macro", "sector", "sectorid",
	                    "hullpercent"}
	local out = {}
	for _, uid in ipairs(helpers.enum(C.GetNumAllFactionShips,
	                                  C.GetAllFactionShips, "player")) do
		local lid = helpers.to_luaid(uid)
		local d = helpers.comp_data(lid, fields)
		d.id = helpers.id_str(uid)
		d.commander = helpers.id_str(GetCommander(lid))
		d.subordinates = X4MCP_Json.array({})
		for _, sub in ipairs(GetSubordinates(lid) or {}) do
			d.subordinates[#d.subordinates + 1] = helpers.id_str(sub)
		end
		out[#out + 1] = d
	end
	return out
end
