--[[ x4mcp recipe
signature: crew(container_id) -> array of {name, role, skill}
tags: read, people

Everyone aboard one ship or station: the pilot or station manager first, then
the crew by role and skill tier.

The people API is not a flat list. Roles come from GetPeople2, each role has
skill tiers from GetRoleTiers, and only then does GetRoleTierNPCs return the
seeds you can name. Roles with no tiers hold nobody except "unassigned", which
has to be asked for separately -- that last case is why an obvious loop
returns an empty crew for a fully staffed ship.

A ship reporting only its captain is a normal answer, not a bug: every service
and marine tier can legitimately have amount 0.
]]
function(container_id)
	local container = ConvertStringTo64Bit(tostring(container_id))
	local lid = ConvertStringToLuaID(tostring(container_id))
	local out = X4MCP_Json.array({})

	-- A ship reports its pilot, a station its manager; ask for both.
	local person = GetComponentData(lid, "assignedaipilot")
	if person == nil then person = GetComponentData(lid, "tradenpc") end
	if person ~= nil and IsValidComponent(person) then
		local name, postname = GetComponentData(person, "name", "postname")
		out[#out + 1] = { name = name or "", role = postname or "commander" }
	end

	local roles = ffi.new("PeopleInfo[64]")
	local count = tonumber(C.GetPeople2(roles, 64, container, true)) or 0
	for i = 0, count - 1 do
		local role_id = ffi.string(roles[i].id)
		local role_name = ffi.string(roles[i].name)
		local tiers = tonumber(roles[i].numtiers) or 0
		local seeds, found = nil, 0
		if tiers > 0 then
			local tierdata = ffi.new("RoleTierData[?]", tiers)
			tiers = tonumber(C.GetRoleTiers(tierdata, tiers, container, roles[i].id)) or 0
			for j = 0, tiers - 1 do
				local amount = tonumber(tierdata[j].amount) or 0
				if amount > 0 then
					seeds = ffi.new("NPCSeed[?]", amount)
					found = tonumber(C.GetRoleTierNPCs(seeds, amount, container,
						roles[i].id, tierdata[j].skilllevel)) or 0
					for k = 0, found - 1 do
						out[#out + 1] = { name = ffi.string(C.GetPersonName(seeds[k], container)),
						                  role = role_name, skill = tierdata[j].skilllevel }
					end
				end
			end
		elseif role_id == "unassigned" then
			seeds = ffi.new("NPCSeed[256]")
			found = tonumber(C.GetRoleTierNPCs(seeds, 256, container, roles[i].id, 0)) or 0
			for k = 0, found - 1 do
				out[#out + 1] = { name = ffi.string(C.GetPersonName(seeds[k], container)),
				                  role = role_name }
			end
		end
	end
	return out
end
