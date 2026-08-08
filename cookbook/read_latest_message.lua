--[[ x4mcp recipe
signature: read_latest_message(category) -> {id, category, title, text, source, time} | nil
tags: read, log, write
verified: re-checked on a live save: index 0 of the empty category is 'TER - War Against the Xenon' at t=1911, the OLDEST of 21 entries, so the previous version returned the wrong message. It now takes the last index and returns the newest.

The newest entry of the player's log, and MARKS IT READ. `category` is
"highprio", "lowprio", or "" for both.

The trap this exists to record: the game lists messages OLDEST FIRST, so
reading index 0 -- the obvious way to write this -- returns the first message
of the save, not the latest, and nothing about the result looks wrong. Take the
last index instead.

It marks the message read, so it is not a plain query. Use
cookbook.messages(category, count) to look without touching anything.
]]
function(category)
	category = category or ""
	local n = tonumber(C.GetNumMessages(category, false)) or 0
	if n == 0 then return nil end
	local buf = ffi.new("MessageInfo[?]", n)
	local got = tonumber(C.GetMessages(buf, n, 0, n, category)) or 0
	if got == 0 then return nil end

	local i = got - 1        -- oldest first, so the newest is last
	local entry = {
		id = tostring(buf[i].id),
		category = ffi.string(buf[i].category),
		title = ffi.string(buf[i].title),
		text = ffi.string(buf[i].text),
		source = ffi.string(buf[i].source),
		time = tonumber(buf[i].time),
	}
	C.SetMessageRead(buf[i].id, entry.category)
	return entry
end
