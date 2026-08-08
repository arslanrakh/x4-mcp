--[[ x4mcp recipe
signature: transfer_assigned_pilot_to_station(ship_id, station_id) -> {captain_name, transferred, ship_check} | nil, reason
tags: personnel, crew, captain, transfer, stations, write, verification
verified: code re-reviewed, NOT re-run (it moves a real captain). Its success check compared the localised role name 'Unassigned', which never matches on a non-English install and would report transferred=false after a successful move; it now compares role_id == 'unassigned', confirmed as the stable id on this save.

Moves the ship's currently assigned AI pilot to a player station as unassigned personnel. Uses the instantiated pilot actor, then reads both containers back; an empty API reason alone is not treated as success. This is suitable for preserving a captain before selling or mothballing a ship.
]]
function(ship_id, station_id)
	local ship_lua = ConvertStringToLuaID(tostring(ship_id))
	local ship = ConvertStringTo64Bit(tostring(ship_id))
	local station = ConvertStringTo64Bit(tostring(station_id))
	local pilot = GetComponentData(ship_lua, "assignedaipilot")
	if pilot == nil or not IsValidComponent(pilot) then
		return nil, "ship has no assigned AI pilot"
	end
	local name = GetComponentData(pilot, "name") or ""
	local actor = {
		entity = ConvertStringTo64Bit(tostring(pilot)),
		personcontrollable = ship,
		personseed = 0
	}
	local reason = ffi.string(C.AssignHiredActor(actor, station, "", "unassigned", false))
	if reason ~= "" then return nil, reason end

	-- role_id, not role: `role` is the game's displayed name and is localised,
	-- so matching it reports a failed transfer on any non-English install.
	local transferred = false
	for _, person in ipairs(cookbook.crew(tostring(station_id))) do
		if person.name == name and person.role_id == "unassigned" then
			transferred = true
			break
		end
	end
	return {
		captain_name = name,
		transferred = transferred,
		ship_check = cookbook.check_ship_order_state_and_failures(tostring(ship_id))
	}
end
