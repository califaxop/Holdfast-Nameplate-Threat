-- Threat Detection Engine: listens to native threat + nameplate events and drives
-- Registry -> State -> Renderer.
local _, ns = ...
local R, S, V = ns.Registry, ns.State, ns.Renderer
local Scan
local PREVIEW_PCT = { secure = 45, unstable = 90, lost = 100 }
local MODE_TEXT = { pet = "your pet's aggro", both = "you and your pet holding it", tanks = "the group's tanks holding it",
  dps = "you, not the tank", tank = "you, the tank" }
local ROSTER_EVENTS = { GROUP_ROSTER_UPDATE = true, PLAYER_ROLES_ASSIGNED = true, UNIT_PET = true }


-- performance counters (/hf perf)
local perf = { evaluations = 0, passes = 0, time = 0, checks = 0 }

local function UpdateUnit(unit)
  local plate = R.Get(unit)
  if not plate then return end
  perf.evaluations = perf.evaluations + 1
  local st = S.Update(unit)
  -- "Only show in a party or raid": solo, nothing glows (preview still works)
  -- (your pet tanking counts too: that's usually solo)
  local m = S.Mode()
  if ns.db.onlyInGroup and not IsInGroup() and m ~= "pet" and m ~= "both" and not ns.preview then st = { kind = "none" } end
  -- Preview mode: show a look ("secure", "unstable" or "lost", with a sample %) on your target's nameplate.
  if ns.preview then
    local isTarget = UnitIsUnit(unit, "target")
    if ns.Readable(isTarget) and isTarget then
      st = { kind = ns.preview, dps = m == "dps", percentage = PREVIEW_PCT[ns.preview] }
    end
  end
  V.Render(plate, st, unit)
end

local function UpdateAll()
  for unit in R.Each() do UpdateUnit(unit) end
end
ns.UpdateAll = UpdateAll

-- Updates are driven by the game's events. Those can fire many times a frame in group combat, so
-- they're merged: on the next frame each enemy named is updated once, or every plate once when a
-- change concerns them all (your role, your target, combat, the group, a pet...).
local dirty, allDirty, queued = {}, false, false
local function Flush()
  queued = false
  local t0 = debugprofilestop and debugprofilestop()
  if allDirty then UpdateAll() else for unit in pairs(dirty) do UpdateUnit(unit) end end
  wipe(dirty); allDirty = false
  perf.passes = perf.passes + 1
  if t0 then perf.time = perf.time + (debugprofilestop() - t0) end
end
local function Queue()
  if queued then return end
  queued = true
  C_Timer.After(0, Flush)
end
local function UpdateSoon(unit) dirty[unit] = true; Queue() end
local function UpdateAllSoon() allDirty = true; Queue() end

-- A safety net for a change no event reports: every plate once a second, only while you're in
-- combat (out of combat nothing changes without an event).
local net
local function SafetyNet(on)
  if on and not net then
    net = C_Timer.NewTicker(1, function() perf.checks = perf.checks + 1; UpdateAllSoon() end)
  elseif not on and net then
    net:Cancel(); net = nil
  end
end

-- Diagnostics: what the game's threat calls answer for one enemy, each as a value, nil, <hidden>,
-- error (the call failed) or n/a (not in this client). Nothing hidden is read; it only says so.
local function show(v) return ns.isSecret(v) and "<hidden>" or tostring(v) end
local function probe(fn, ...)
  if type(fn) ~= "function" then return { "n/a" } end
  local r = { pcall(fn, ...) }
  if not r[1] then return { "error" } end
  local out = {}
  for i = 2, math.max(2, #r) do out[#out + 1] = show(r[i]) end
  return out
end
local function ThreatLine(unit)
  local who = S.TankUnit() or "player"
  local CS = C_Secrets or {}
  local d = probe(UnitDetailedThreatSituation, who, unit)
  return "on " .. (who == "pet" and "your pet" or "you") .. "=" .. d[1]
    .. " status=" .. probe(UnitThreatSituation, who, unit)[1]
    .. " lead=" .. probe(UnitThreatLeadSituation, who, unit)[1]
    .. " pct=" .. (d[3] or d[1]) .. " ofLead=" .. probe(UnitThreatPercentageOfLead, who, unit)[1]
    .. " | secret: state=" .. probe(CS.ShouldUnitThreatStateBeSecret, who, unit)[1]
    .. " values=" .. probe(CS.ShouldUnitThreatValuesBeSecret, who, unit)[1]
end
-- who it's attacking: "on tank (party2)", "on you", or "on unknown (inferred)"
local function Owner(st)
  if st and st.kind == "none" then return "not engaged" end
  if not (st and st.ownership) then return "on ?" end
  return "on " .. (st.ownership == "player" and "you" or st.ownership == "pet" and "your pet" or st.ownership)
    .. (st.ownerUnit and st.ownerUnit ~= "player" and st.ownerUnit ~= "pet" and (" (" .. st.ownerUnit .. ")") or "")
    .. (st.ownerObserved == false and " (inferred)" or "")
end
-- every tracked enemy now (/hf scan, and when /hf debug is turned on)
Scan = function()
  local mode = S.Mode()
  local f = S.Followed(mode)
  ns.Print("following:", #f == 0 and "nobody (no pet out)" or table.concat(f, ", "),
    "| glows:", MODE_TEXT[mode] or mode,
    "| role:", S.Role() or "not set", "|", InCombatLockdown() and "in combat" or "out of combat",
    "|", IsInGroup() and "in a group" or "solo")
  local n = 0
  for unit in R.Each() do
    n = n + 1
    local st = S.Get(unit)
    ns.Print(unit, "-> " .. (st and st.kind or "?") .. " (" .. (st and st.confidence or "?") .. ")", "|", Owner(st), "|", ThreatLine(unit))
  end
  ns.Print("nameplates tracked:", n, "| hidden answers drive the glows:",
    V.HasSecretSupport() and "yes" or "no (this client can't)")
end

-- with /hf debug on: each change, with what the game answered at that moment
S.onTransition = function(unit, old, new)
  if ns.debug then ns.Dbg(unit, old.kind, "->", new.kind, "|", Owner(new), "|", ThreatLine(unit)) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, unit)
  if event == "ADDON_LOADED" then
    if unit ~= ns.name then return end
    ns.LoadDB(); R.Scan(); ns.CreateOptions()
    for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
      "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
      "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE",
      "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UNIT_PET", "PLAYER_ROLES_ASSIGNED" }) do
      ev:RegisterEvent(e)
    end
    SafetyNet(InCombatLockdown and InCombatLockdown()) -- (a /reload in combat)
    ns.Print("loaded. Type |cffffff00/hf|r for commands.")
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    V.Invalidate(R.Add(unit)); UpdateUnit(unit) -- (at once: a plate appearing shows its glow straight away)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    V.Hide(R.Remove(unit)); S.Clear(unit)
  elseif event == "UNIT_THREAT_LIST_UPDATE" and unit and R.Get(unit) then
    UpdateSoon(unit)
  -- (any other token - "target", "focus", "boss1"... - falls through to one batched update of
  -- every plate: the event names the enemy by only one of its tokens, not always its nameplate's)
  elseif event == "PLAYER_ENTERING_WORLD" then
    S.RosterChanged(); R.Scan(); UpdateAll()
  else
    -- the group, its roles or a pet changed (summoned, dismissed, died, replaced): look again
    if ROSTER_EVENTS[event] then S.RosterChanged() end
    if event == "PLAYER_REGEN_DISABLED" then SafetyNet(true) elseif event == "PLAYER_REGEN_ENABLED" then SafetyNet(false) end
    UpdateAllSoon()
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local TOGGLES = { icon = "showIcon" }

SLASH_HOLDFAST1 = "/hf"
SLASH_HOLDFAST2 = "/holdfast"
SlashCmdList.HOLDFAST = function(msg)
  local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  local db = ns.db
  if cmd == "" or cmd == "config" or cmd == "options" then
    local ok, e = pcall(ns.OpenOptions)
    if not ok then ns.Print("settings error: " .. tostring(e)) end
    return
  elseif TOGGLES[cmd] then
    db[TOGGLES[cmd]] = not db[TOGGLES[cmd]]
    ns.Print(cmd .. " " .. (db[TOGGLES[cmd]] and "on" or "off"))
  elseif cmd == "aggro" then
    db.states.aggro.show = not db.states.aggro.show
    ns.Print("stable glow " .. (db.states.aggro.show and "on" or "off"))
  elseif cmd == "tank" then
    -- probe: can an addon tell "I'm tanking but losing it" (threat status 2) while values are hidden?
    local sec = ns.isSecret
    local function show(v) if sec(v) then return "hidden" end return tostring(v) end
    local function try(label, fn)
      local ok, a, b, c = pcall(fn)
      if not ok then print("  " .. label .. ": error (" .. tostring(a):gsub("^.-:%d+: ", "") .. ")")
      else print("  " .. label .. ": " .. show(a) .. (b ~= nil and (", " .. show(b)) or "") .. (c ~= nil and (", " .. show(c)) or "")) end
    end
    local u = "target"
    if not UnitExists(u) then ns.Print("target a mob you're tanking first"); return end
    ns.Print("losing-aggro probe on your target (" .. (InCombatLockdown() and "in combat" or "out of combat") .. ", " .. (IsInGroup() and "in a group" or "solo") .. "):")
    try("UnitThreatSituation", function() return UnitThreatSituation("player", u) end)
    try("status == 2 test", function() local s = UnitThreatSituation("player", u); return s == 2 end)
    try("status as boolean via SetAlphaFromBoolean", function()
      local t = HoldfastProbeFrame or CreateFrame("Frame", "HoldfastProbeFrame"); t:SetAlphaFromBoolean(UnitThreatSituation("player", u) == 2, 1, 0); return t:GetAlpha() end)
    try("GetThreatStatusColor(status)", function() return GetThreatStatusColor(UnitThreatSituation("player", u) or 0) end)
    try("UnitThreatPercentageOfLead", function() return UnitThreatPercentageOfLead and UnitThreatPercentageOfLead("player", u) end)
    try("mob is targeting me", function() return UnitIsUnit(u .. "target", "player") end)
    try("mob's target name", function() return UnitName(u .. "target") end)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(u)
    local hb = plate and plate.UnitFrame and (plate.UnitFrame.healthBar or plate.UnitFrame.HealthBar)
    try("nameplate health bar color", function() return hb and hb:GetStatusBarColor() end)
    local ti = TargetFrame and (TargetFrame.threatIndicator or (TargetFrame.TargetFrameContainer and TargetFrame.TargetFrameContainer.Flash))
    try("target frame threat glow shown", function() return ti and ti:IsShown() end)
    try("target frame threat glow color", function() return ti and ti:GetVertexColor() end)
    try("threat numeric text (target frame)", function()
      local t = TargetFrameNumericalThreat or (TargetFrame and TargetFrame.threatNumericIndicator)
      return t and t:IsShown(), t and t.text and t.text:GetText() end)
  elseif cmd == "tip" then
    -- can an addon read the threat line Blizzard puts in unit tooltips? (data API, and the tooltip on screen)
    local sec = ns.isSecret
    local function show(v) if sec(v) then return "hidden" end return tostring(v) end
    ns.Print("tooltip probe (" .. (InCombatLockdown() and "in combat" or "out of combat") .. "):")
    local function lineHasThreat(t) return type(t) == "string" and (t:find("%%") or t:lower():find("threat")) end
    for _, unit in ipairs({ "target", "mouseover", "nameplate1", "nameplate2" }) do
      if UnitExists(unit) then
        if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then print("  data API: not in this client"); break end
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        if not ok then print("  " .. unit .. ": refused (" .. tostring(data) .. ")")
        elseif data == nil then print("  " .. unit .. ": no data")
        elseif sec(data) then print("  " .. unit .. ": hidden")
        else
          local lines, found = data.lines or {}, nil
          for i, l in ipairs(lines) do
            local okT, t = pcall(function() return l.leftText end)
            local okR, r = pcall(function() return l.rightText end)
            if (okT and sec(t)) or (okR and sec(r)) then found = found or ("line " .. i .. " hidden") end
            if okT and not sec(t) and lineHasThreat(t) then found = "line " .. i .. ": " .. t .. (okR and r and (" | " .. show(r)) or "") end
            if okR and not sec(r) and lineHasThreat(r) then found = "line " .. i .. ": " .. show(t) .. " | " .. r end
          end
          print(format("  %s: %d line(s), threat line: %s", unit, #lines, found or "none found"))
        end
      end
    end
    -- the tooltip on screen (hover an enemy while typing this, or bind it to a macro)
    if GameTooltip and GameTooltip:IsShown() then
      for i = 1, GameTooltip:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
          local fs = _G["GameTooltipText" .. side .. i]
          local ok, t = pcall(function() return fs and fs:GetText() end)
          if ok and (sec(t) or lineHasThreat(t)) then print(format("  on screen, line %d (%s): %s", i, side:lower(), show(t))) end
        end
      end
    else
      print("  on screen: no tooltip shown (make a macro with /hf tip and press it while hovering an enemy)")
    end
    return
  elseif cmd == "debug" then
    ns.debug = not ns.debug
    ns.Print("debug " .. (ns.debug and "ON" or "OFF"))
    if ns.debug then Scan() end
  elseif cmd == "scan" then
    Scan()
  elseif cmd == "perf" then
    local n = 0
    for _ in R.Each() do n = n + 1 end
    local made, shown, kinds = V.Counts()
    local list = {}
    for k, c in pairs(kinds) do list[#list + 1] = k .. " " .. c end
    table.sort(list)
    local c, A = V.counters, V.Anim
    ns.Print(format("nameplates tracked %d | indicators made %d, showing %d (%s)", n, made, shown,
      #list > 0 and table.concat(list, ", ") or "none"))
    ns.Print(format("threat evaluations %d | redraws %d, unchanged %d | restyles %d", perf.evaluations, c.renders, c.skipped, c.styles))
    ns.Print(format("update passes %d, average %.3f ms | moving glows animating %d, animation frames %d",
      perf.passes, perf.passes > 0 and perf.time / perf.passes or 0, A.n, A.ticks))
    ns.Print("safety check: " .. (net and format("every second in combat (%d so far)", perf.checks) or "off (out of combat)")
      .. "  -  /hf perf reset to start counting again")
    if arg == "reset" then
      perf.evaluations, perf.passes, perf.time, perf.checks = 0, 0, 0, 0
      c.renders, c.skipped, c.styles, A.ticks = 0, 0, 0, 0
      ns.Print("counters reset")
    end
    return
  else
    ns.Print("/hf (settings)  -  /hf icon | aggro  -  /hf debug  -  /hf scan  -  /hf perf  -  /hf tank")
    return
  end
  ns.lookGen = (ns.lookGen or 0) + 1 -- (a setting changed: every plate restyles)
  UpdateAll()
end
