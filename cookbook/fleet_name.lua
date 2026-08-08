--[[ x4mcp recipe
signature: fleet_name(flagship_id, name) -> current name
tags: fleets, write, read
verified: read path ran on a live save over three flagships; the set path is from the session that named those three fleets

Read a fleet's name, or set it by passing `name`.

The name belongs to the FLAGSHIP, not to any group or record of its own, so
this is called with the commanding ship's id. Returns what the game reports
afterwards, which is how you confirm it took.
]]
function(flagship_id, name)
	local flagship = ConvertStringTo64Bit(tostring(flagship_id))
	if name ~= nil then C.SetFleetName(flagship, tostring(name)) end
	return ffi.string(C.GetFleetName(flagship))
end
