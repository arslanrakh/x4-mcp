--[[ x4mcp recipe
signature: quote_removable_ship_equipment(ship_id, shipyard_id) -> {payout, items}
tags: shipyard, equipment, sale, pricing, query
verified: Ran on the live save for Hyperion ZVK-956 at the Terran shipyard: produced a total quote of 6,196,810 credits for its installed shields, weapons, and turrets; that amount was used to start the refit.

Calculates the current shipyard payout for all installed shield, weapon, and turret modules on one ship. It asks that exact shipyard for each ware's current price, so quotes reflect local stock rather than a fixed encyclopedia value. Engine and software removal require separate handling.
]]
function(ship_id, shipyard_id)
  local ship = ConvertStringTo64Bit(tostring(ship_id))
  local shipyard = ConvertStringTo64Bit(tostring(shipyard_id))
  local macro = GetComponentData(ConvertStringToLuaID(tostring(ship_id)), "macro")
  local payout, items = 0, X4MCP_Json.array({})
  for _, typ in ipairs({"shield", "weapon", "turret"}) do
    local slots = tonumber(C.GetNumUpgradeSlots(ship, macro, typ)) or 0
    for slot = 0, slots - 1 do
      local ptr = C.GetUpgradeSlotCurrentMacro(ship, 0, typ, slot)
      local module = ptr and ffi.string(ptr) or ""
      if module ~= "" then
        local ware = GetMacroData(module, "ware")
        local price = tonumber(C.GetBuildWarePrice(shipyard, ware)) or 0
        payout = payout + price
        items[#items + 1] = { type = typ, slot = slot, ware = ware, price = price }
      end
    end
  end
  return { payout = payout, items = items }
end
