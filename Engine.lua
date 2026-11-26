-- Threat Detection Engine: listens to native threat + nameplate events and drives
-- Registry -> State -> Renderer.
local _, ns = ...
local R, S, V = ns.Registry, ns.State, ns.Renderer


local function UpdateUnit(unit)
  local plate = R.Get(unit)
  if not plate then return end
  local st = S.Update(unit)
  -- "Only show in a party or raid": solo, nothing glows (preview still works)
  -- (your pet tanking counts too: that's usually solo)
  if ns.db.onlyInGroup and not IsInGroup() and S.Mode() ~= "pet" and not ns.preview then st = { kind = "none" } end
  -- Preview mode: show a look ("secure" or "lost") on your target's nameplate.
  if ns.preview then
    local isTarget = UnitIsUnit(unit, "target")
    if ns.Readable(isTarget) and isTarget then st = { kind = ns.preview, dps = S.Mode() == "dps" } end
  end
  V.Render(plate, st, unit)
end

local function UpdateAll()
  for unit in R.Each() do UpdateUnit(unit) end
end
ns.UpdateAll = UpdateAll

-- events that can fire many times a frame in group combat: one update next frame covers them all
local queued = false
local function UpdateAllSoon()
  if queued then return end
  queued = true
  C_Timer.After(0, function() queued = false; UpdateAll() end)
end

S.onTransition = function(unit, old, new)
  ns.Dbg(unit, old.kind, "->", new.kind)
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
    C_Timer.NewTicker(0.25, UpdateAll) -- safety net for missed updates
    ns.Print("loaded. Type |cffffff00/hf|r for commands.")
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    R.Add(unit); UpdateUnit(unit)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    V.Hide(R.Remove(unit)); S.Clear(unit)
  elseif event == "UNIT_THREAT_LIST_UPDATE" and unit and R.Get(unit) then
    UpdateUnit(unit)
  -- (any other token - "target", "focus", "boss1"... - falls through to one batched update of
  -- every plate: the event names the enemy by only one of its tokens, not always its nameplate's)
  elseif event == "PLAYER_ENTERING_WORLD" then
    R.Scan(); UpdateAll()
  else
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
  local cmd = (msg or ""):lower():match("^(%S*)")
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
    if ns.debug then
      local function show(v) return ns.isSecret(v) and "<hidden>" or tostring(v) end
      local n = 0
      local tank = S.TankUnit()
      local mode = S.Mode()
      ns.Dbg("following:", tank == "pet" and "your pet" or tank == "player" and "you" or "nobody (no pet out)",
        "| glows:", mode == "pet" and "your pet's aggro" or mode == "dps" and "you, not the tank" or "you, the tank",
        "| role:", S.Role(true) or "not set")
      -- each value as the game gives it: a number / true / false, nil, <hidden>, error, or n/a
      -- (the call isn't in this client). Nothing hidden is read; this only says it's hidden.
      local function probe(fn, ...)
        if type(fn) ~= "function" then return { "n/a" } end
        local r = { pcall(fn, ...) }
        if not r[1] then return { "error" } end
        local out = {}
        for i = 2, math.max(2, #r) do out[#out + 1] = show(r[i]) end
        return out
      end
      local CS = C_Secrets or {}
      local who = tank or "player"
      for unit in R.Each() do
        n = n + 1
        local st = S.Get(unit)
        local d = probe(UnitDetailedThreatSituation, who, unit)
        ns.Dbg(unit, "-> " .. (st and st.kind or "?"),
          "| on " .. (who == "pet" and "your pet" or "you") .. "=" .. d[1],
          "status=" .. probe(UnitThreatSituation, who, unit)[1],
          "lead=" .. probe(UnitThreatLeadSituation, who, unit)[1],
          "pct=" .. (d[3] or d[1]) .. " ofLead=" .. probe(UnitThreatPercentageOfLead, who, unit)[1],
          "| secret: state=" .. probe(CS.ShouldUnitThreatStateBeSecret, who, unit)[1]
            .. " values=" .. probe(CS.ShouldUnitThreatValuesBeSecret, who, unit)[1])
      end
      ns.Dbg("nameplates tracked:", n, "| hidden answers drive the glows:",
        V.HasSecretSupport() and "yes" or "no (this client can't)")
    end
  else
    ns.Print("/hf (settings)  -  /hf icon | aggro  -  /hf debug  -  /hf tank")
    return
  end
  UpdateAll()
end
