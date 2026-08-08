--[[ x4mcp recipe
signature: quote_removable_ship_equipment(ship_id, shipyard_id) -> {payout, items}
tags: shipyard, equipment, sale, pricing, query
verified: ran on this save for Hyperion ZVK-956 at the Terran shipyard: 6,196,810 credits for its shields, weapons and turrets, and that figure was what the refit actually paid. GetBuildWarePrice is also what the game's own configuration menu uses to value removed equipment (menu_ship_configuration.lua:11148, 7592).

What a shipyard will pay for the shields, weapons and turrets currently
installed on a ship. Read-only: it prices, it does not sell.

It asks that specific shipyard through GetBuildWarePrice, so the figure follows
local stock rather than an encyclopedia value, and it is the same call the
game's own configuration menu uses to value equipment in both directions --
added equipment adds to the refit price, removed equipment subtracts from it at
that identical price.

Engines and software are not covered here, and wares flagged `volatile` price
at 0 in the game's own accounting, so they are worth nothing on removal.

Note the two second arguments that look interchangeable and are not:
GetNumUpgradeSlots(ship, MACRO NAME, type) but
GetUpgradeSlotCurrentMacro(ship, MODULE ID, type, slot) -- 0 is the correct
module id for a ship, which is why the two calls below disagree on shape.
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
