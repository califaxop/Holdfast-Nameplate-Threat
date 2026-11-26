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

-- Your group, cached until it changes (S.RosterChanged: roster, roles, pets, loading screens):
-- each member and each member's pet, with whether the member is a tank (group-finder role).
-- You and your own pet aren't in it (they're "player" and "pet").
local roster, rosterBy
local function BuildRoster()
  local list, by = {}, {}
  local function add(u, isPet)
    local e = UnitExists(u)
    if not (Readable(e) and e) then return end
    local me, mine = UnitIsUnit(u, "player"), UnitIsUnit(u, "pet")
    if (Readable(me) and me) or (Readable(mine) and mine) then return end -- (raidN includes you)
    local role = (not isPet) and UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
    local m = { unit = u, tank = Readable(role) and role == "TANK" or false, pet = isPet or false }
    list[#list + 1] = m; by[u] = m
  end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do add("raid" .. i); add("raidpet" .. i, true) end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do add("party" .. i); add("partypet" .. i, true) end
  end
  return list, by
end
local function Roster()
  if not roster then roster, rosterBy = BuildRoster() end
  return roster
end
function S.RosterChanged() roster, rosterBy = nil, nil end

local function PetOut()
  local e = UnitExists("pet")
  if not Readable(e) or not e then return false end
  local dead = UnitIsDead("pet")
  return not (Readable(dead) and dead)
end

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

-- Which glows to show, from "Whose aggro" (setting tank) and "My role":
--   "pet"    My pet: your pet holding it
--   "both"   Me and my pet: you or your pet holding it
--   "tanks"  The group's tanks: any group tank (or you, as the tank) holding it - for healers
--   "tank"   you holding it, as the tank;  "dps"  you, not the tank (you don't want it)
-- Auto: with no role set (solo, or a group without roles), your pet when it's out, else you as
-- the tank; with a role set, you, as that role. Me: you, as your role says.
function S.Mode()
  local t = ns.db.tank or "auto"
  if t == "pet" or t == "both" or t == "tanks" then return t end
  local role = S.Role()
  if t == "auto" and PetOut() and role == nil then return "pet" end
  return (role == "dps") and "dps" or "tank"
end

-- The units whose holding it counts (the first is the main one, whose hidden yes/no switches the
-- glows when even the state is hidden). Empty: "My pet" with no pet out.
function S.Followed(mode)
  mode = mode or S.Mode()
  if mode == "pet" then return PetOut() and { "pet" } or {} end
  if mode == "both" then return PetOut() and { "player", "pet" } or { "player" } end
  if mode == "tanks" then
    local list = {}
    if S.Role() == "tank" then list[1] = "player" end
    for _, m in ipairs(Roster()) do if m.tank then list[#list + 1] = m.unit end end
    if #list == 0 then list[1] = "player" end -- no tank roles in the group: you, as when solo
    return list
  end
  return { "player" }
end
function S.TankUnit() return S.Followed()[1] end

-- Everyone who could be on an enemy's list: you, your pet, your group and their pets.
local function Everyone()
  local list = { "player" }
  if PetOut() then list[2] = "pet" end
  for _, m in ipairs(Roster()) do list[#list + 1] = m.unit end
  return list
end

S.Everyone = Everyone -- (diagnostics: /hf threat)

-- Who a unit is, as an owner: "player", "pet", "tank" (a group tank), "member", "member pet"
local function OwnerKind(u)
  if u == "player" or u == "pet" then return u end
  local m = rosterBy and rosterBy[u]
  if not m then return "member" end
  return m.pet and "member pet" or (m.tank and "tank" or "member")
end

-- a readable number from a threat call, or nil (hidden, missing, or not one)
local function Num(v) if Readable(v) and type(v) == "number" then return v end end

-- The highest readable threat % (of what pulls it) among the others on the list (not `skip`), who
-- aren't tanking it: how close anyone is to taking it. nil when it can't be read.
local function Closest(everyone, skip, unit)
  local best
  for _, g in ipairs(everyone) do
    if not skip[g] then
      local tanking, _, scaled = UnitDetailedThreatSituation(g, unit)
      local pct = Num(scaled)
      if pct and not (Readable(tanking) and tanking) and (not best or pct > best) then best = pct end
    end
  end
  return best
end

-- the game's lead state for a unit (tank: 0 a safe lead, 1-2 someone closing in, 3 not first)
local function Lead(u, unit)
  local ok, l = pcall(UnitThreatLeadSituation, u, unit) -- (a client without it: no lead)
  return ok and Num(l) or nil
end

-- The state of one enemy, from your point of view: as the tank (you, your pet, you and your pet,
-- or the group's tanks: "the followed") or not the tank.
--   kind        "none"      not engaged with you, your pet or your group
--               "secure"    the followed hold it, nobody close / not the tank: on someone else, you're well below
--               "unstable"  the followed hold it, but someone is closing in or has more threat (the game's
--                           lead state 1-2, or status 2) / not the tank: you're about to pull it (status 1)
--               "lost"      the followed don't hold it / not the tank: it's on you
--               "hidden"    the game hides even the state: .isTanking is the hidden "is it on" the main one
--               "unknown"   the game gave no usable answer
--   dps         not the tank;  tank: the unit holding it (when one of the followed), else the main one
--   status      UnitThreatSituation of the main followed unit: 0 on the list, 1 above the tank (not
--               tanking), 2 tanking with someone higher, 3 tanking securely; nil: not on its list
--   lead        UnitThreatLeadSituation of the unit holding it (when one of the followed)
--   ownership   who it's attacking: "player", "pet", "tank" (a group tank), "member", "member pet",
--               or "unknown" (nobody in your group: someone outside it, a guardian, or hidden)
--   ownerUnit   that unit's token; ownerObserved: true when the game said so (a status of 2-3),
--               false when it's inferred ("unknown")
--   percentage  threat % of what pulls it (100 = pulls): not the tank, yours; the tank, the closest
--               other's. A number, a hidden value (shown by the game, never read), or nil
--   confidence  "values" (threat % readable), "state" (only the 0-3 states), "hidden" (only the
--               hidden yes/no), "none"
-- The pull threshold (110% of the tank's threat in melee range, 130% at range in Classic) is not
-- applied here: the game's scaled % already counts it (100 = pulls). Not yet verified on Forever.
local function Evaluate(unit)
  local none = { kind = "none", confidence = "none" }
  if not UnitExists(unit) then return none end
  local canAttack = UnitCanAttack("player", unit)
  if Readable(canAttack) and not canAttack then return none end
  local dead = UnitIsDead(unit)
  if Readable(dead) and dead then return none end

  local mode = S.Mode()
  local dps = mode == "dps"
  local followed = S.Followed(mode)
  local main = followed[1]
  if not main then return none end -- "My pet" chosen, but no pet out
  local inF = {}
  for _, u in ipairs(followed) do inF[u] = true end

  -- one pass over everyone: their state on this enemy, and who it's attacking
  local everyone = Everyone()
  local status, secret, engaged, holder = {}, {}, false, nil
  for _, u in ipairs(everyone) do
    local s = UnitThreatSituation(u, unit)
    if isSecret(s) then secret[u] = true
    elseif type(s) == "number" then
      status[u], engaged = s, true
      if s >= 2 and (not holder or inF[u]) then holder = u end
    end
  end
  if not engaged then
    if not next(secret) then return none end
    local c = UnitAffectingCombat(unit) -- all hidden: fighting at all? (out of combat it's nothing yet)
    if Readable(c) and not c then return none end
  end

  local st = { dps = dps, tank = main }
  if secret[main] then
    -- even the state is hidden: only the hidden "is it on" the main one is left, for the glows
    local isTanking, _, scaled = UnitDetailedThreatSituation(main, unit)
    if not isSecret(isTanking) then st.kind, st.confidence = "unknown", "none"; return st end
    st.kind, st.confidence, st.isTanking, st.isSecret = "hidden", "hidden", isTanking, true
    st.ownership = "unknown"; st.ownerObserved = false
    if dps then st.percentage = scaled end
    return st
  end

  st.status = status[main]
  st.ownerUnit, st.ownerObserved = holder, holder ~= nil
  st.ownership = holder and OwnerKind(holder) or "unknown"
  local _, _, scaled = UnitDetailedThreatSituation(main, unit)
  local pct = Num(scaled)
  st.confidence = (pct or (status[main] == nil and not isSecret(scaled))) and "values" or "state"
  st.isSecret = isSecret(scaled)
  local warnAt = ns.db.warnAt or 80

  if dps then
    local s = status.player
    if s and s >= 2 then st.kind = "lost"
    elseif s == 1 or (pct and pct >= warnAt) then st.kind = "unstable"
    else st.kind = "secure" end
    st.percentage = scaled -- yours (shown by the game when hidden)
    return st
  end

  -- as the tank: held by one of the followed?
  if not (holder and inF[holder]) then st.kind = "lost"; return st end
  st.tank = holder
  local hs = status[holder]
  local lead = Lead(holder, unit)
  st.lead = lead
  local closest = pct and Closest(everyone, inF, unit) -- (others' % are readable only when ours is)
  if hs == 2 or (lead and lead >= 1 and lead <= 2) or (closest and closest >= warnAt) then st.kind = "unstable"
  else st.kind = "secure" end
  st.percentage = closest
  return st
end

function S.Update(unit)
  local new = Evaluate(unit)
  local old = states[unit]
  states[unit] = new
  if S.onTransition and old and (old.kind ~= new.kind or old.ownerUnit ~= new.ownerUnit) then S.onTransition(unit, old, new) end
  return new
end

function S.Get(unit) return states[unit] end
function S.Clear(unit) states[unit] = nil end
