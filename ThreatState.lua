-- Threat State: the game's own threat states for each enemy (what its nameplate aggro display
-- uses), and their transitions.
--
-- Native API (the game may hide the answers in some content):
--   UnitThreatLeadSituation(unit, mob) -> 0-3: how far ahead of the next highest (3 = not first)
--   UnitThreatSituation(unit, mob)     -> 0-3, or nil when not on its threat list:
--     0 = not tanking, lower threat   1 = not tanking, higher threat (about to pull)
--     2 = tanking, someone is close    3 = tanking securely
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
--        | "secure"    the tank holds it safely / you're well below the tank
--        | "insecure"  someone's closing in on the tank / you're about to pull it
--        | "lost"      the tank lost it / it's on you
--        | "hidden"    the game hides the state: .step is the hidden step (see Step)
--   dps = not the tank; tank = "player" / "pet"
-- The threat state the game's own aggro display uses (a step, 0-3), from your point of view:
--   As the tank (you, or your pet): UnitThreatLeadSituation - how far ahead of the next highest
--     you are. 0 = safely ahead, 1-2 = someone's closing in, 3 = you're not first (lost).
--   Not the tank: UnitThreatSituation("player") - 0 = well below the tank, 1 = about to pull it,
--     2-3 = it's on you.
-- These steps are hidden less often than the threat % (a separate restriction in the game); when
-- they are hidden too, the renderer turns the hidden step into the right glow without reading it.
local function Step(followed, unit, dps)
  if dps then return UnitThreatSituation("player", unit) end
  if UnitThreatLeadSituation then return UnitThreatLeadSituation(followed, unit) end
  -- (no lead state in this client: from the detailed status: 3 safe, 2 someone close, else lost)
  local _, status = UnitDetailedThreatSituation(followed, unit)
  if isSecret(status) then return status end
  if status == 3 then return 0 elseif status == 2 then return 2 elseif status ~= nil then return 3 end
end

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

-- readable step -> state kind
local function KindOf(step, dps)
  if dps then
    if step == nil or step == 0 then return "secure" end
    if step == 1 then return "insecure" end
    return "lost" -- 2 or 3: it's on you
  end
  if step == 0 then return "secure" end
  if step == 1 or step == 2 then return "insecure" end
  return "lost"
end

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

  local step = Step(followed, unit, dps)
  if isSecret(step) then
    -- the hidden "is it on you" flag too, for clients that can't turn a hidden step into a glow
    local isTanking = UnitDetailedThreatSituation(followed, unit)
    return { kind = "hidden", step = step, isTanking = isTanking, dps = dps, tank = followed }
  end
  return { kind = KindOf(step, dps), step = step, dps = dps, tank = followed }
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
