--[[ x4mcp recipe
signature: research_status(hq_id) -> {modules = [...], money}
tags: read, research, hq

What the headquarters is researching and what it is short of: the production
data of each research module, plus the HQ account balance.

Research stalls waiting for wares rather than failing, so "nothing is
happening" usually means a missing input or an empty HQ account -- both are
visible here.
]]
function(hq_id)
	local hq = ConvertStringTo64Bit(tostring(hq_id))
	local n = tonumber(C.GetNumResearchModules(hq)) or 0
	local modules = X4MCP_Json.array({})
	if n > 0 then
		local buf = ffi.new("UniverseID[?]", n)
		n = tonumber(C.GetResearchModules(buf, n, hq)) or 0
		for i = 0, n - 1 do
			modules[#modules + 1] = GetProductionModuleData(
				ConvertStringTo64Bit(tostring(buf[i])))
		end
	end
	return { modules = modules, money = GetAccountData(hq, "money") }
end
