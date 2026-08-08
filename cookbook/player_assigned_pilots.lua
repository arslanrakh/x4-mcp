--[[ x4mcp recipe
signature: player_assigned_pilots() -> array of {name, assigned_to, skills, piloting}
tags: player, personnel, pilots, skills, query
verified: Ran on a live save: returned eight assigned pilots and their skill tables; one player-controlled pilot was included.

Lists unique AI pilots assigned to every player-owned ship, including their raw 0–15 skill values. Reads each ship's pilot component directly because GetPeople2 excludes assigned pilots.
]]
function()
  local seen, people = {}, {}
  for _, uid in ipairs(helpers.enum(C.GetNumAllFactionShips, C.GetAllFactionShips, "player")) do
    local ship = helpers.to_luaid(uid)
    local eid = GetComponentData(ship, "pilot")
    if eid and tostring(eid) ~= "0" and not seen[tostring(eid)] then
      seen[tostring(eid)] = true
      local ent = helpers.to_luaid(eid)
      local skills = {}
      for _, s in ipairs(GetComponentData(ent, "skills") or {}) do skills[s.name] = s.value end
      people[#people+1] = {
        name = GetComponentData(ent, "name"),
        assigned_to = GetComponentData(ship, "name"),
        skills = skills,
        piloting = skills.piloting or 0
      }
    end
  end
  table.sort(people, function(a, b) return a.piloting > b.piloting end)
  return people
end
