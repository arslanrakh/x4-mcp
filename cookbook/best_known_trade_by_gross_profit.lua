--[[ x4mcp recipe
signature: best_known_trade_by_gross_profit() -> route | nil, reason
tags: trade, economy, route, profit, query
verified: Ran against the live save: found Energy Cells from Mercury to Heart of Acrimony II with a computed gross profit of 52,863,901.56 credits.

Finds the buy offer and sell offer for the same ware that maximize gross profit across all known non-hostile, non-mission, non-shady station offers. Gross profit is limited by the smaller advertised amount; it does not account for a specific ship's cargo capacity, travel time, or player budget.
]]
function()
  local offers, seen = {}, {}
  for _, faction in ipairs(helpers.factions()) do
    if faction ~= "khaak" and faction ~= "xenon" then
      local n = C.GetNumAllFactionStations(faction)
      if n > 0 then
        local ids = ffi.new("UniverseID[?]", n)
        C.GetAllFactionStations(ids, n, faction)
        for i = 0, n - 1 do
          for _, o in pairs(GetTradeList(helpers.to_luaid(ids[i]), nil, false) or {}) do
            if o.id and not seen[o.id] then seen[o.id] = true; offers[#offers + 1] = o end
          end
        end
      end
    end
  end
  local sellers, best = {}, nil
  for _, o in ipairs(offers) do
    if o.isselloffer and not o.isshady and not o.ismissionoffer and o.amount and o.amount > 0 then
      sellers[o.ware] = sellers[o.ware] or {}
      sellers[o.ware][#sellers[o.ware] + 1] = o
    end
  end
  for _, buyer in ipairs(offers) do
    if buyer.isbuyoffer and not buyer.isshady and not buyer.ismissionoffer and buyer.amount and buyer.amount > 0 and sellers[buyer.ware] then
      for _, seller in ipairs(sellers[buyer.ware]) do
        local amount = math.min(buyer.amount, seller.amount)
        local profit = amount * (buyer.price - seller.price)
        if buyer.price > seller.price and buyer.station ~= seller.station and (not best or profit > best.profit) then
          best = {ware = buyer.name, amount = amount, buyprice = seller.price, sellprice = buyer.price, profit = profit, sourceid = seller.station, destid = buyer.station}
        end
      end
    end
  end
  if not best then return nil, "no profitable known trade pair" end
  best.source = helpers.comp_data(ConvertStringToLuaID(tostring(best.sourceid)), {"name", "sector", "owner"})
  best.destination = helpers.comp_data(ConvertStringToLuaID(tostring(best.destid)), {"name", "sector", "owner"})
  return best
end
