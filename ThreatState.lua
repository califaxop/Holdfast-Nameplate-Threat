-- Threat State: for each enemy, is it attacking you (or your pet, when it tanks), how safely, and
-- the transitions between states.
--
-- Native API (see API_COMPATIBILITY.md). The game hides two things separately:
--   threat state  UnitThreatSituation, UnitThreatLeadSituation (0-3 steps): readable in a party
--   threat values UnitDetailedThreatSituation (isTanking, status, %): hidden in a party; the
--                 hidden isTanking can still switch the glows, the hidden % can still be shown
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
  if not Readable(role) then return nil end -- (can be hidden: then no role is known)
  if role == "TANK" then return "tank" end
  if role == "DAMAGER" or role == "HEALER" then return "dps" end
  return nil
end

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

-- a readable number from a threat call, or nil (hidden, missing, or not one)
local function Num(v) if Readable(v) and type(v) == "number" then return v end end

-- The highest readable threat % (of what pulls it) among everyone else on the list who isn't
-- tanking it, and who: how close anyone is to taking it off the tank. nil when it can't be read.
local function Closest(followed, unit)
  local best, who
  for _, g in ipairs(Others(followed)) do
    local tanking, _, scaled = UnitDetailedThreatSituation(g, unit)
    local pct = Num(scaled)
    if pct and not (Readable(tanking) and tanking) and (not best or pct > best) then best, who = pct, g end
  end
  return best, who
end

-- The state of one enemy, from your point of view: as the tank (you, or your pet when it tanks)
-- or not the tank.
--   kind        "none"      not engaged with you, your pet or your group
--               "secure"    tank: it's on you, nobody close / not the tank: on someone else, you're well below
--               "unstable"  tank: it's on you, but someone is closing in or has more threat (the game's
--                           lead state 1-2, or status 2) / not the tank: you're about to pull it (status 1)
--               "lost"      tank: it's not on you / not the tank: it's on you
--               "hidden"    the game hides even the state: .isTanking is the hidden "is it on you"
--               "unknown"   the game gave no usable answer
--   dps         not the tank;  tank: "player" / "pet" (the followed unit)
--   status      UnitThreatSituation: 0 on the list, 1 above the tank (not tanking), 2 tanking with
--               someone higher, 3 tanking securely; nil: not on its list
--   lead        UnitThreatLeadSituation (tank): 0 a safe lead, 1-2 someone closing in, 3 not first
--   ownership   "followed" (it's attacking the followed unit), "other" (someone else: inferred, the
--               game only says it isn't the followed unit), nil
--   percentage  threat % of what pulls it (100 = pulls): not the tank, yours; the tank, the closest
--               other's. A number, a hidden value (shown by the game, never read), or nil
--   confidence  "values" (threat % readable), "state" (only the 0-3 states), "hidden" (only the
--               hidden yes/no), "none"
-- The pull threshold (110% of the tank's threat in melee range, 130% at range in Classic) is not
-- applied here: the game's scaled % already counts it (100 = pulls). Not yet verified on Forever.
local function Evaluate(unit)
  if not UnitExists(unit) then return { kind = "none", confidence = "none" } end
  local canAttack = UnitCanAttack("player", unit)
  if Readable(canAttack) and not canAttack then return { kind = "none", confidence = "none" } end
  local dead = UnitIsDead(unit)
  if Readable(dead) and dead then return { kind = "none", confidence = "none" } end

  local mode = S.Mode()
  local dps = mode == "dps"
  -- (not `mode == "pet" and (PetOut() and "pet" or nil) or "player"`: with no pet out, that
  -- and/or chain falls through to "player")
  local followed
  if mode == "pet" then followed = PetOut() and "pet" or nil else followed = "player" end
  if not followed then return { kind = "none", confidence = "none" } end -- "My pet" chosen, but no pet out

  local engaged = Engaged(followed, unit)
  if engaged == false then return { kind = "none", confidence = "none" } end
  if engaged == "?" then -- hidden: fighting at all? (out of combat it's nothing yet)
    local c = UnitAffectingCombat(unit)
    if Readable(c) and not c then return { kind = "none", confidence = "none" } end
  end

  local isTanking, _, scaled = UnitDetailedThreatSituation(followed, unit)
  local status = UnitThreatSituation(followed, unit)
  local st = { dps = dps, tank = followed }

  if isSecret(status) then
    -- even the state is hidden: only the hidden "is it on you" is left, for the glows to use
    if not isSecret(isTanking) then st.kind, st.confidence = "unknown", "none"; return st end
    st.kind, st.confidence, st.isTanking, st.isSecret = "hidden", "hidden", isTanking, true
    if dps then st.percentage = scaled end
    return st
  end
  if status ~= nil and type(status) ~= "number" then st.kind, st.confidence = "unknown", "none"; return st end

  local onFollowed = status ~= nil and status >= 2
  st.status = status
  st.ownership = onFollowed and "followed" or "other"
  local warnAt = ns.db.warnAt or 80
  local pct = Num(scaled)
  st.confidence = (pct or (status == nil and not isSecret(scaled))) and "values" or "state"
  st.isSecret = isSecret(scaled)

  local kind
  if dps then
    if onFollowed then kind = "lost"
    elseif status == 1 or (pct and pct >= warnAt) then kind = "unstable"
    else kind = "secure" end
    st.percentage = scaled -- yours (shown by the game when hidden)
  else
    local okL, l = pcall(UnitThreatLeadSituation, followed, unit) -- (a client without it: no lead)
    local lead = okL and Num(l) or nil
    st.lead = lead
    local closest = pct and Closest(followed, unit) -- (others' % are readable only when ours is)
    if not onFollowed then kind = "lost"
    elseif status == 2 or (lead and lead >= 1 and lead <= 2) or (closest and closest >= warnAt) then kind = "unstable"
    else kind = "secure" end
    st.percentage = closest
  end
  st.kind = kind
  return st
end

function S.Update(unit)
  local new = Evaluate(unit)
  local old = states[unit]
  states[unit] = new
  if S.onTransition and old and old.kind ~= new.kind then S.onTransition(unit, old, new) end
  return new
end

function S.Get(unit) return states[unit] end
function S.Clear(unit) states[unit] = nil end
