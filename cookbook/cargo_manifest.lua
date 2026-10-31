--[[ x4mcp recipe
signature: container_id, tags -> array of {ware, amount}
tags: read, cargo, inventory
verified: Ran on a live save: the Guillemot Sentinel returned an empty physical cargo manifest.

Returns the physical cargo manifest for a ship or station. Pass an empty string for tags to include all cargo; use a specific game cargo tag to filter. Converts stable digit-string IDs to game IDs and serializes UIWareInfo entries.
]]
function(container_id, tags)
  local container = ConvertStringTo64Bit(container_id)
  tags = tags or ""
  local n = C.GetNumCargo(container, tags)
  local buf = ffi.new("UIWareInfo[?]", n)
  n = C.GetCargo(buf, n, container, tags)
  local out = {}
  for i = 0, n - 1 do
    out[#out + 1] = { ware = ffi.string(buf[i].ware), amount = buf[i].amount }
  end
  return out
end
