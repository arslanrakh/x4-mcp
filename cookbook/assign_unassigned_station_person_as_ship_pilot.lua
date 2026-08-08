--[[ x4mcp recipe
signature: assign_unassigned_station_person_as_ship_pilot(station_id, ship_id, person_name) -> {assigned_name, transferred, ship_check} | nil, reason
tags: personnel, crew, captain, assignment, stations, ships, write, verification
verified: Ran on the live save: moved Olmanckussut from HQ unassigned personnel back to Hyperion; his name read back as the assigned ship pilot and he no longer appeared at HQ. Hyperion had no failed-order messages.

Finds a named unassigned person on a player station and appoints them as the AI pilot of a ship. It first checks the assignment, then reads both the ship pilot and station personnel back. The visible transfer may apply on the next game tick, so verify after a short delay before treating it as complete.
]]
function(station_id, ship_id, person_name)
  local station = ConvertStringTo64Bit(tostring(station_id))
  local ship = ConvertStringTo64Bit(tostring(ship_id))
  local roles = ffi.new("PeopleInfo[64]")
  local count = tonumber(C.GetPeople2(roles, 64, station, true)) or 0
  local seed = nil
  for i = 0, count - 1 do
    if ffi.string(roles[i].id) == "unassigned" then
      local buf = ffi.new("NPCSeed[256]")
      local n = tonumber(C.GetRoleTierNPCs(buf, 256, station, roles[i].id, 0)) or 0
      for j = 0, n - 1 do
        if ffi.string(C.GetPersonName(buf[j], station)) == tostring(person_name) then
          seed = buf[j]
          break
        end
      end
    end
  end
  if not seed then return nil, "unassigned person not found on station" end
  local actor = { entity = nil, personcontrollable = station, personseed = seed }
  local check = ffi.string(C.AssignHiredActor(actor, ship, "aipilot", nil, true))
  if check ~= "" then return nil, check end
  local reason = ffi.string(C.AssignHiredActor(actor, ship, "aipilot", nil, false))
  if reason ~= "" then return nil, reason end
  local pilot = GetComponentData(ConvertStringToLuaID(tostring(ship_id)), "assignedaipilot")
  local assigned_name = pilot and GetComponentData(pilot, "name") or nil
  local remains = false
  for _, person in ipairs(cookbook.crew(tostring(station_id))) do
    if person.name == tostring(person_name) then remains = true break end
  end
  return {
    assigned_name = assigned_name,
    transferred = assigned_name == tostring(person_name) and not remains,
    ship_check = cookbook.check_ship_order_state_and_failures(tostring(ship_id))
  }
end
