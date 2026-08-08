--[[ x4mcp recipe
signature: fund_research(hq_id, research) -> {required, transferred, hq_money} | nil, reason
tags: research, hq, money, write

Top the HQ account up to exactly the estimated price of one research, moving
the shortfall from the player's own account and nothing more.

MOVES THE PLAYER'S MONEY. Say what it will cost and get agreement before
calling it. It refuses rather than partially transferring when the player
cannot cover the shortfall.
]]
function(hq_id, research)
	local hq = ConvertStringTo64Bit(tostring(hq_id))
	local required = tonumber(C.GetEstimatedResearchPrice(hq, research)) or 0
	if required == 0 then return nil, "no price for research " .. tostring(research) end
	local current = tonumber(GetAccountData(hq, "money")) or 0
	local shortage = math.max(0, required - current)
	if shortage > (tonumber(GetPlayerMoney()) or 0) then
		return nil, "the player is short " .. (shortage - GetPlayerMoney()) .. " credits"
	end
	if shortage > 0 then TransferPlayerMoneyTo(shortage, hq) end
	return { required = required, transferred = shortage,
	         hq_money = GetAccountData(hq, "money") }
end
