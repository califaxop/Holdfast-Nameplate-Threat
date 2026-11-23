-- Threat State: for each enemy, is it attacking you (or your pet, when it tanks)? And the
-- transitions between that and not.
--
-- Native API (the game may hide the answers in some content):
--   UnitDetailedThreatSituation(unit, mob) -> isTanking, ...  (isTanking stays usable when hidden)
--   UnitThreatSituation(unit, mob)         -> nil when not on its threat list
local _, ns = ...
local S = {}
ns.State = S

local isSecret, Readable = ns.isSecret, ns.Readable
local states = {}           -- unit -> last state
S.onTransition = nil        -- function(unit, old, new)

local function GroupUnits()
  local list = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do list[#list + 1] = "raid" .. i end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do list[#list + 1] = "party" .. i end
  end
  return list
end

local function PetOut()
  local e = UnitExists("pet")
  if not Readable(e) or not e then return false end
  local dead = UnitIsDead("pet")
  return not (Readable(dead) and dead)
end

-- Whose aggro the glows follow: you, or your pet (setting "tank").
function S.TankUnit() return S.FollowedUnit and S.FollowedUnit() end

-- Your role: "tank", "dps" (not the tank) or nil (not set). Set by hand, or on Auto: the role you
-- picked in the group finder. With no role set (solo, or a group without roles) it's nil, and
-- you're treated as when solo.
function S.Role()
  local r = ns.db.role or "auto"
  if r == "tank" then return "tank" end
  if r == "dps" then return "dps" end
  if not (IsInGroup and IsInGroup()) then return nil end
  local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
  if role == "TANK" then return "tank" end
  if role == "DAMAGER" or role == "HEALER" then return "dps" end
  return nil
end

-- You count as the tank unless your role says otherwise (as when solo: enemies come to you).
function S.IsTankRole() return S.Role() ~= "dps" end

-- Which glows to show: "pet" (your pet's aggro), "tank" (yours, as the tank) or "dps" (yours, as
-- someone who doesn't want it). The two settings only meet on "Whose aggro: Auto":
--   My pet          -> your pet, whatever your role
--   Me              -> you, as your role says (your pet is ignored)
--   Auto            -> with no role set (solo, or a group without roles): your pet when it's out,
--                      else you as the tank; with a role set: you, as that role
function S.Mode()
  local t = ns.db.tank or "auto"
  if t == "pet" then return "pet" end
  local role = S.Role()
  if t == "auto" and PetOut() and role == nil then return "pet" end
  return (role == "dps") and "dps" or "tank"
end

-- The unit whose aggro the glows follow right now: "pet", "player", or nil ("My pet" with no pet out).
function S.FollowedUnit()
  local m = S.Mode()
  if m == "pet" then return PetOut() and "pet" or nil end
  return "player"
end

-- Everyone else whose threat could pull an enemy off the tank: you, your pet, your group.
local function Others(tank)
  local list = GroupUnits()
  if tank ~= "player" then list[#list + 1] = "player" end
  if tank ~= "pet" and PetOut() then list[#list + 1] = "pet" end
  return list
end

-- A state table, from your point of view (as the tank - you or your pet - or not):
--   kind = "none"      not engaged with you, your pet or your group
--        | "secure"    the tank: it's on you (holding) / not the tank: it isn't (safe)
--        | "lost"      the tank: it's not on you / not the tank: it is (you pulled it)
--        | "hidden"    the game hides it: .isTanking is the hidden "is it on you"
--   dps = not the tank; tank = "player" / "pet"
-- Is anyone (the followed unit, you, your pet, your group) on `unit`'s threat list?
-- true / false, or "?" when the game hides it.
local function Engaged(followed, unit)
  local list = Others(followed)
  table.insert(list, 1, followed)
  local hidden = false
  for _, g in ipairs(list) do
    local s = UnitThreatSituation(g, unit)
    if isSecret(s) then hidden = true elseif s ~= nil then return true end
  end
  return hidden and "?" or false
end

-- Two states only: is it attacking the one we follow (you, or your pet when it tanks)? The game's
-- "is tanking" answer, which addons can still use when it's hidden (the renderer hands the hidden
-- answer straight to the glows). As the tank: on you = holding (good), not = lost. Not the tank:
-- not on you = safe, on you = you pulled it.
local function Evaluate(unit)
  if not UnitExists(unit) then return { kind = "none" } end
  local canAttack = UnitCanAttack("player", unit)
  if Readable(canAttack) and not canAttack then return { kind = "none" } end
  local dead = UnitIsDead(unit)
  if Readable(dead) and dead then return { kind = "none" } end

  local mode = S.Mode()
  local dps = mode == "dps"
  local followed = (mode == "pet") and (PetOut() and "pet" or nil) or "player"
  if not followed then return { kind = "none" } end -- "My pet" chosen, but no pet out

  local engaged = Engaged(followed, unit)
  if engaged == false then return { kind = "none" } end
  if engaged == "?" then -- hidden: fighting at all? (out of combat it's nothing yet)
    local c = UnitAffectingCombat(unit)
    if Readable(c) and not c then return { kind = "none" } end
  end

  local isTanking = UnitDetailedThreatSituation(followed, unit)
  if isSecret(isTanking) then return { kind = "hidden", isTanking = isTanking, dps = dps, tank = followed } end
  local onYou = isTanking and true or false -- (not on its list: engaged with your group, not you)
  local kind
  if dps then kind = onYou and "lost" or "secure" else kind = onYou and "secure" or "lost" end
  return { kind = kind, dps = dps, tank = followed }
end

local HAS_AGGRO = { secure = true, insecure = true }

function S.Update(unit)
  local new = Evaluate(unit)
  local old = states[unit]
  states[unit] = new
  if S.onTransition and old and old.kind ~= new.kind then
    S.onTransition(unit, old, new, HAS_AGGRO[old.kind] and not HAS_AGGRO[new.kind] and new.kind ~= "none")
  end
  return new
end

function S.Get(unit) return states[unit] end
function S.Clear(unit) states[unit] = nil end
