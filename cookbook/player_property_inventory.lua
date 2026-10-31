--[[ x4mcp recipe
signature: player_property_inventory() -> {player, ships, stations}
tags: inventory, cargo, player, ships, stations, query
verified: Ran on the live save: returned the player inventory, ten ships with empty cargo, and the HQ with empty cargo.

Lists personal inventory plus cargo and local inventories for every player ship and station. Cargo is queried through the engine's UIWareInfo API; empty arrays are meaningful and distinguish no cargo from an unknown result.
]]
function()
  local function cargo(uid)
    local n = C.GetNumCargo(uid, "")
    local b = ffi.new("UIWareInfo[?]", n)
    n = C.GetCargo(b, n, uid, "")
    local out = {}
    for i = 0, n - 1 do
      local w = ffi.string(b[i].ware)
      out[#out + 1] = { ware = w, name = GetWareData(w, "name"), amount = tonumber(b[i].amount) }
    end
    return out
  end
  local out = { player = GetPlayerInventory(), ships = {}, stations = {} }
  for _, s in ipairs(cookbook.player_ships({"name", "idcode", "sector", "macro"})) do
    local uid = ConvertStringTo64Bit(s.id)
    out.ships[#out + 1] = { name = s.name, idcode = s.idcode, sector = s.sector, macro = s.macro, cargo = cargo(uid), inventory = GetInventory(ConvertStringToLuaID(s.id)) }
  end
  for _, st in ipairs(cookbook.player_stations({"name", "sector", "defencenpc"})) do
    local inv = {}
    if st.defencenpc then inv = GetInventory(st.defencenpc) end
    out.stations[#out + 1] = { name = st.name, sector = st.sector, inventory = inv, cargo = cargo(ConvertStringTo64Bit(st.id)) }
  end
  return out
end
