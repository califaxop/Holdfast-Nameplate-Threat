-- A mock of the game API, just enough for Holdfast's files to load and run (tests/run_tests.py).
-- Hidden ("secret") values are tables marked secret; the real client's rules are stricter
-- (it errors on comparing or testing one), so these tests can't prove a hidden value is never read.
-- MOCK.hidden: the game hides threat state and values (both); MOCK.hiddenValues: values only
-- (isTanking, %), the state (0-3 steps) readable - as seen in a party on Forever.
MOCK = { threat = {}, hidden = false, hiddenValues = false, inGroup = false, role = "NONE", pet = false, petDead = false,
  euiShown = false, registered = {}, timers = {}, hooks = 0, hookFns = {} }

function MOCK.Secret(v) return { secret = true, v = v } end
issecretvalue = function(v) return type(v) == "table" and v.secret == true end
local function sec(v) if MOCK.hidden or MOCK.hiddenValues then return MOCK.Secret(v) end return v end
local function secState(v) if MOCK.hidden then return MOCK.Secret(v) end return v end

-- frames ----------------------------------------------------------------------------------
local frames = {}
local function obj()
  local o = { _scripts = {}, _shown = true, _alpha = 1 }
  frames[#frames + 1] = o
  return setmetatable(o, { __index = function(t, k)
    local m = MOCK.methods[k]
    if m then return m end
    if not k:find("^%u") then return nil end -- fields (lower case, "_x"): unset; methods: Upper case
    if k:find("^Create") then return function() return obj() end end
    if k:find("^Get") then return function() return nil end end
    return function() end
  end })
end
MOCK.obj = obj
MOCK.methods = {
  Show = function(s) s._shown = true end, Hide = function(s) s._shown = false end,
  SetShown = function(s, v) s._shown = v and true or false end,
  IsShown = function(s) return s._shown end, IsVisible = function(s) return s._shown end,
  SetAlpha = function(s, a) s._alpha = a end, GetAlpha = function(s) return s._alpha end,
  SetAlphaFromBoolean = function(s, v, a, b)
    if issecretvalue(v) then s._alpha = "game" else s._alpha = v and a or b end
  end,
  SetScript = function(s, n, f) s._scripts[n] = f end,
  HookScript = function(s, n, f) MOCK.hooks = MOCK.hooks + 1 end,
  GetFrameLevel = function() return 5 end, GetHeight = function() return 768 end, GetWidth = function() return 120 end,
  GetSize = function() return 120, 12 end, GetStringWidth = function() return 20 end,
  GetDuration = function(s) return s._dur or 0 end, SetDuration = function(s, d) s._dur = d end,
  IsPlaying = function(s) return s._p end, Play = function(s) s._p = true end, Stop = function(s) s._p = false end,
  SetText = function(s, v) s._text = v end, GetText = function(s) return s._text end,
  SetAtlas = function(s, a) s._atlas = a end, GetAtlas = function(s) return s._atlas end,
  RegisterEvent = function(s, e) MOCK.registered[e] = true; s._events = s._events or {}; s._events[e] = true end,
  GetValue = function() return 1 end, HasFocus = function() return false end, GetChecked = function(s) return s._checked end,
  GetEffectiveScale = function() return 1 end, IsForbidden = function() return false end,
  NumLines = function() return 0 end,
  SetFormattedText = function(s, fmt, v)
    if issecretvalue(v) then s._text = "<game>" else s._text = string.format(fmt, v) end
  end,
  SetTextColor = function(s, r, g, b) s._color = { r, g, b } end,
}
CreateFrame = function() return obj() end
CreateFont = function() return obj() end
UIParent = obj(); GameTooltip = obj(); GameTooltip._shown = false; ColorPickerFrame = obj()
hooksecurefunc = function(t, m, fn)
  MOCK.hooks = MOCK.hooks + 1
  MOCK.hookFns[t] = MOCK.hookFns[t] or {}
  local list = MOCK.hookFns[t][m] or {}; MOCK.hookFns[t][m] = list; list[#list + 1] = fn
end
function MOCK.HookCount() return MOCK.hooks end
function MOCK.RunHooks(t, m) for _, fn in ipairs((MOCK.hookFns[t] or {})[m] or {}) do fn(t) end end

-- the nameplate: the game's unit frame with its health bar and aggro flare
MOCK.plate = obj(); MOCK.plate.namePlateUnitToken = "nameplate1"
local uf = obj(); MOCK.plate.UnitFrame = uf
uf.healthBar = obj(); uf.aggroHighlightBase = obj(); uf.aggroHighlightAdditive = obj()
uf.UpdateAggroHighlight = function() end
C_NamePlate = { GetNamePlateForUnit = function(u) if u == "nameplate1" then return MOCK.plate end end,
  GetNamePlates = function() return { MOCK.plate } end }
-- EllesmereUI's plate for the same unit (drawn only while MOCK.euiShown)
local ep = obj(); ep.health = obj()
ep.IsShown = function() return MOCK.euiShown end
EllesmereNameplates_NS = { plates = { nameplate1 = ep } }

-- units and threat ------------------------------------------------------------------------
UnitExists = function(u) if u == "pet" then return MOCK.pet end return true end
UnitIsDead = function(u) if u == "pet" then return MOCK.petDead end return false end
UnitCanAttack = function() return true end
UnitAffectingCombat = function() return true end
UnitIsUnit = function(a, b) return MOCK.same and MOCK.same(a, b) or false end
UnitName = function() return "Mob" end
IsInGroup = function() return MOCK.inGroup end
-- the group: MOCK.members others (party1..), MOCK.raid for a raid (raid1 is you), MOCK.roles[unit]
IsInRaid = function() return MOCK.raid or false end
GetNumSubgroupMembers = function() return MOCK.members or 1 end
GetNumGroupMembers = function() return (MOCK.members or 1) + 1 end
UnitGroupRolesAssigned = function(u) if u == "player" then return MOCK.role end return (MOCK.roles or {})[u] or "NONE" end
InCombatLockdown = function() return false end
UnitDetailedThreatSituation = function(who)
  local t = MOCK.threat[who]; if not t then return nil end
  return sec(t.tanking), sec(t.status), sec(t.pct or 50)
end
UnitThreatSituation = function(who)
  local t = MOCK.threat[who]; if not t then return nil end
  return secState(t.status)
end
UnitThreatLeadSituation = function(who)
  local t = MOCK.threat[who]; if not t or t.lead == nil then return nil end
  return secState(t.lead)
end
GetThreatStatusColor = function() return 1, 0, 0 end

-- the rest --------------------------------------------------------------------------------
C_Timer = { NewTicker = function() end, After = function(_, fn) MOCK.timers[#MOCK.timers + 1] = fn end }
-- join or leave a group (the game sends GROUP_ROSTER_UPDATE, which refreshes Holdfast's roster)
function MOCK.Group(on) MOCK.inGroup = on; MOCK.Fire("GROUP_ROSTER_UPDATE"); MOCK.RunTimers() end
function MOCK.RunTimers() local t = MOCK.timers; MOCK.timers = {}; for _, fn in ipairs(t) do fn() end end
format = string.format; tinsert = table.insert; strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
UISpecialFrames = {}; SlashCmdList = {}
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }
PRINTS = {}; print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end PRINTS[#PRINTS + 1] = table.concat(t, " ") end

function MOCK.Fire(event, ...)
  for _, f in ipairs(frames) do
    if f._events and f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end
function MOCK.Start()
  MOCK.Fire("ADDON_LOADED", "Holdfast")
  NS.OpenOptions(); NS.OpenOptions()
  MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
end

-- what the plate shows: each glow shown ("~": the game decides its alpha from a hidden answer;
-- "!": with the "!")
function MOCK.Glows()
  local f = NS.Renderer.Indicator(MOCK.plate)
  if not f then return "" end
  local out = {}
  for _, k in ipairs({ "aggro", "unstable", "nothreat" }) do
    local fl = f[k]
    if fl.holder._shown and fl.holder._alpha ~= 0 then
      out[#out + 1] = k .. (fl.holder._alpha == "game" and "~" or "") .. (fl.icon._shown and "!" or "")
    end
  end
  return table.concat(out, " ")
end
function MOCK.Look()
  NS.UpdateAll()
  local st = NS.State.Get("nameplate1")
  local g = MOCK.Glows()
  return (st and st.kind or "?") .. (g ~= "" and (" " .. g) or "")
end
-- the % beside the plate: its text ("<game>": a hidden % the game draws), or "" when not shown
function MOCK.Pct()
  local f = NS.Renderer.Indicator(MOCK.plate)
  return (f and f.pct._shown and f.pctBox._shown) and f.pct._text or ""
end
