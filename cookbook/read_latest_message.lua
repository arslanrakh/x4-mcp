--[[ x4mcp recipe
signature: read_latest_message(category) -> {id, title, text, source, category} | nil
tags: messages, notifications, read-state
verified: Ran on a live save: read the newest Terran Protectorate message and marked it read in the high-priority category.

Reads the newest message in a category and immediately marks it as read. Use an empty category string for the global newest message.
]]
function(category)
  category = category or ""
  local buf = ffi.new("MessageInfo[1]")
  local n = C.GetMessages(buf, 1, 0, 1, category)
  if n == 0 then return nil end
  local entry = {
    id = tostring(buf[0].id),
    category = ffi.string(buf[0].category),
    title = ffi.string(buf[0].title),
    text = ffi.string(buf[0].text),
    source = ffi.string(buf[0].source)
  }
  C.SetMessageRead(buf[0].id, entry.category)
  return entry
end
