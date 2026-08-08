--[[ x4mcp recipe
signature: loadout_stats(ids, fields) -> array of {id, name, hull_percent, ...fields}
tags: read, ships, compare
verified: ran on a live save: two Hyperions compared, shields 72578 against 54266

Real combat statistics of ships as they are currently equipped -- not the
paper numbers of the hull. Use it to answer "which of these two is stronger".

`fields` defaults to HullValue, ShieldValue, ShieldRate, BurstDPS,
SustainedDPS, ForwardSpeed, BoostSpeed, TravelSpeed, RadarRange; the field
names are the struct's own and are case-sensitive.
]]
function(ids, fields)
	fields = fields or {"HullValue", "ShieldValue", "ShieldRate", "BurstDPS",
	                    "SustainedDPS", "ForwardSpeed", "BoostSpeed",
	                    "TravelSpeed", "RadarRange"}
	local out = {}
	for _, id in ipairs(ids or {}) do
		local stats = C.GetCurrentLoadoutStatistics5(ConvertStringTo64Bit(tostring(id)))
		local d = helpers.comp_data(ConvertStringToLuaID(tostring(id)),
		                            {"name", "hullpercent"})
		local row = { id = tostring(id), name = d.name, hull_percent = d.hullpercent }
		for _, key in ipairs(fields) do row[key] = tonumber(stats[key]) end
		out[#out + 1] = row
	end
	return out
end
