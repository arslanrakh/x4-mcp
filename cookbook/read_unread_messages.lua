--[[ x4mcp recipe
signature: read_unread_messages() -> array of {category, title, text, source}
tags: messages, log, read, write
verified: saved by an earlier session against this same save; NOT re-run here because it marks messages read. Its central claim -- that GetMessages does not filter by read state -- was confirmed separately

Reads every unread high- and low-priority player message, marks each one as read, and returns its contents. Verifies unread state from each MessageInfo record rather than assuming the count query filters GetMessages results.

This MARKS THE MESSAGES READ as a side effect, so it cannot be used as a plain query. Use cookbook.messages(category, count, true) to look at unread mail without touching it.
]]
function()
	local out = X4MCP_Json.array({})
	for _, category in ipairs({"highprio", "lowprio"}) do
		local n = tonumber(C.GetNumMessages(category, false)) or 0
		if n > 0 then
			local buf = ffi.new("MessageInfo[?]", n)
			local got = tonumber(C.GetMessages(buf, n, 0, n, category)) or 0
			for i = 0, got - 1 do
				if tostring(buf[i].isread) == "false" then
					out[#out + 1] = {
						category = category,
						title = ffi.string(buf[i].title),
						text = ffi.string(buf[i].text),
						source = ffi.string(buf[i].source),
					}
					C.SetMessageRead(buf[i].id, category)
				end
			end
		end
	end
	return out
end
