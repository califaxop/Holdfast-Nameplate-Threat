-- Holdfast: settings window (/hf, or Esc > Options > AddOns > Holdfast), drawn in the same
-- style as XP Planner and Spell Glow (see UI.lua).
local _, ns = ...
local UI = ns.UI

local function Changed()
  ns.lookGen = (ns.lookGen or 0) + 1 -- every indicator restyles once
  if ns.UpdateAll then ns.UpdateAll() end
  if ns.RefreshInUse then ns.RefreshInUse() end
end
local function S(key) return { function() return ns.db[key] end, function(v) ns.db[key] = v end } end
local function pctFmt(v) return math.floor(v * 100 + 0.5) .. "%" end

-- Color swatch ---------------------------------------------------------------
local function OpenColorPicker(color, onChange)
  local r, g, b = color[1], color[2], color[3]
  local function apply()
    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
    color[1], color[2], color[3] = nr, ng, nb
    onChange()
  end
  local function cancel(prev)
    if prev then
      color[1] = prev.r or prev[1]; color[2] = prev.g or prev[2]; color[3] = prev.b or prev[3]
    else
      color[1], color[2], color[3] = r, g, b
    end
    onChange()
  end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
      swatchFunc = apply, cancelFunc = cancel })
  else
    ColorPickerFrame.func, ColorPickerFrame.cancelFunc = apply, cancel
    ColorPickerFrame.hasOpacity, ColorPickerFrame.previousValues = false, { r = r, g = g, b = b }
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Show()
  end
end

local function Swatch(parent, key, colorsFn)
  colorsFn = colorsFn or function() return ns.db.colors end
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(16, 16)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  local hover = false
  local function paint(th)
    th = th or UI.Theme()
    local c = ns.db and colorsFn()[key]
    if c then b:SetBackdropColor(c[1], c[2], c[3]) end
    b:SetBackdropBorderColor(UI.RGB(hover and th.title or th.accent))
  end
  UI.Skin(paint)
  b.Refresh = function() paint() end
  b:SetScript("OnClick", function()
    OpenColorPicker(colorsFn()[key], function() b.Refresh(); Changed() end)
  end)
  b:SetScript("OnEnter", function(self)
    hover = true; paint()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Click to change the color"); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() hover = false; paint(); GameTooltip:Hide() end)
  return b
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local STATES = {
  { "aggro",    "Holding",   "It's attacking you (or your pet, when it tanks), and nobody is close to taking it." },
  { "unstable", "Losing it", "It's attacking you (or your pet), but someone is close to taking it, or already has more threat." },
  { "nothreat", "Lost",      "It's attacking someone else." },
}
-- the same three glows when you're not the tank
local STATES_DPS = {
  { "aggro",    "Safe",    "It's attacking someone else, and you're well below pulling it." },
  { "unstable", "Close",   "It's attacking someone else, but you're close to pulling it." },
  { "nothreat", "On you",  "You pulled it: it's attacking you." },
}
local editSet = "tank" -- which settings the Glows table edits: "tank" or "dps"
local W_ = 420 -- content width

local function BuildPanel(panel)
  local refreshers = {}
  local function track(w) refreshers[#refreshers + 1] = w; return w end
  local function at(w, x, y) w:SetPoint("TOPLEFT", x, y); return w end

  local title = at(UI.Text(panel, "title", "Holdfast"), 26, -20)
  UI.Text(panel, "note", "Threat glows on enemy nameplates."):SetPoint("LEFT", title, "RIGHT", 10, -1)

  -- Whose aggro ------------------------------------------------------------
  at(UI.Section(panel, "Choose whose aggro to show", W_), 26, -54)
  track(at(UI.Selector(panel, 330, { { "auto", "Auto: my pet when it tanks, else me" }, { "me", "Me" }, { "pet", "My pet" },
      { "both", "Me and my pet" }, { "tanks", "The group's tanks (for healers)" } },
    { function() return ns.db.tank or "auto" end, function(v) ns.db.tank = v end }, Changed,
    "Click, or use the arrows, to change it."), 26, -84))
  local n1 = at(UI.Text(panel, "note", "Auto: your pet when it's out and no role is set, else you. Me and my pet, the group's tanks: any of them holding it is good."), 26, -112)
  n1:SetWidth(W_)

  -- My role --------------------------------------------------------------------
  at(UI.Text(panel, "line", "My role"), 26, -140)
  track(at(UI.Selector(panel, 300, { { "auto", "Auto: my group-finder role" }, { "tank", "Tank" }, { "dps", "Not the tank (damage / healer)" } },
    S("role"), Changed, "Auto uses the role you picked in the group finder. With no role set (solo, or a group without roles) you're treated as when solo: your pet when it's out, else you as the tank."), 120, -136))
  local n2 = at(UI.Text(panel, "note", "Green: holding / safe. Orange: someone is close to taking it / you're close to pulling it. Red with a \"!\": lost / it's on you."), 26, -164)
  n2:SetWidth(W_)

  -- Glows ------------------------------------------------------------------
  local G0 = -206
  at(UI.Section(panel, "Glows", W_), 26, G0)
  local rowsRefresh = {}
  local setSwitch = track(at(UI.Toggle(panel, 230, { { "tank", "Settings for: Tank / solo" }, { "dps", "Settings for: Not the tank" } },
    { function() return editSet end, function(v) editSet = v end },
    function() for _, f in ipairs(rowsRefresh) do f() end end,
    "Each has its own glows. Tank / solo is used when you're the tank, when you're solo, and while your pet tanks. Click to switch which one you're editing."), 26, G0 - 30))
  -- which set is in use right now
  local inUse = UI.Text(panel, "note", "")
  inUse:SetPoint("LEFT", setSwitch, "RIGHT", 12, 0)
  local function InUseText()
    local St = ns.State
    local ok, mode = pcall(St.Mode)
    if not ok then return "" end
    if mode == "dps" then return "In use: Not the tank" end
    if mode == "pet" then return "In use: Tank / solo (your pet)" end
    if mode == "both" then return "In use: Tank / solo (you and your pet)" end
    if mode == "tanks" then return "In use: Tank / solo (the group's tanks)" end
    local inGroup = IsInGroup and IsInGroup()
    return inGroup and "In use: Tank / solo (you tank)" or "In use: Tank / solo (solo)"
  end
  inUse.Refresh = function() inUse:SetText(InUseText()) end
  ns.RefreshInUse = inUse.Refresh
  track(inUse)
  local COL_SHOW, COL_FLASH, COL_STR, COL_INT = 150, 188, 226, 330
  at(UI.Text(panel, "note", "Show"), 26 + COL_SHOW - 4, G0 - 60)
  at(UI.Text(panel, "note", "Flash"), 26 + COL_FLASH - 4, G0 - 60)
  at(UI.Text(panel, "note", "Strength"), 26 + COL_STR, G0 - 60)
  at(UI.Text(panel, "note", "Interval"), 26 + COL_INT, G0 - 60)
  local y = G0 - 78
  for i, st in ipairs(STATES) do
    local key = st[1]
    local function s() return (editSet == "dps") and ns.db.statesDps[key] or ns.db.states[key] end
    local function colors() return (editSet == "dps") and ns.db.colorsDps or ns.db.colors end
    local function label() return (editSet == "dps") and STATES_DPS[i] or st end
    local sw = track(at(Swatch(panel, key, colors), 26, y - 4))
    local name = UI.Text(panel, "line", st[2]); name:SetPoint("LEFT", sw, "RIGHT", 8, 0)
    local hit = CreateFrame("Frame", nil, panel)
    hit:SetPoint("TOPLEFT", name, "TOPLEFT", -2, 2); hit:SetPoint("BOTTOMRIGHT", name, "BOTTOMRIGHT", 2, -2)
    hit:SetScript("OnEnter", function(self)
      local l = label()
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(l[2]); GameTooltip:AddLine(l[3], 1, 1, 1, true); GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local str = track(at(UI.Slider(panel, "", 92, 0.05, 1, 0.05,
      { function() return s().alpha end, function(v) s().alpha = v end }, pctFmt, Changed), 26 + COL_STR, y + 14))
    local int = track(at(UI.Slider(panel, "", 92, 0.1, 1.5, 0.05,
      { function() return s().speed or 0.35 end, function(v) s().speed = v end },
      function(v) return format("%.2fs", v) end, Changed), 26 + COL_INT, y + 14))
    local show
    local flash = track(at(UI.Check(panel, "", { function() return s().flash end, function(v) s().flash = v end }, 20,
      function() Changed(); if show then show.Refresh() end end), 26 + COL_FLASH, y - 2))
    show = track(at(UI.Check(panel, "", { function() return s().show end, function(v) s().show = v end }, 20, function()
      Changed(); show.Refresh()
    end), 26 + COL_SHOW, y - 2))
    local r = show.Refresh
    show.Refresh = function()
      r(); flash.SetActive(s().show); str:SetAlpha(s().show and 1 or 0.4)
      int:SetAlpha((s().show and s().flash) and 1 or 0.4)
    end
    -- switching which settings are edited: relabel and reload this row
    rowsRefresh[#rowsRefresh + 1] = function()
      name:SetText(label()[2]); sw.Refresh(); show.Refresh(); flash.Refresh(); str.Refresh(); int.Refresh()
    end
    local sr = sw.Refresh
    sw.Refresh = function() sr(); name:SetText(label()[2]) end
    y = y - 32
  end
  -- glow style (every state)
  at(UI.Text(panel, "line", "Glow style"), 26, y - 10)
  track(at(UI.Selector(panel, 300, {
      { "auto", "Auto (matches your nameplates)" }, { "border", "Nameplate border" }, { "outline", "Outline" },
      { "pixel", "Pixel lines" }, { "autocast", "Autocast sparkles" } },
    S("glowStyle"), function() ns.Renderer.Rebuild(); Changed() end,
    "How the glow looks, for every state. Auto: the game's nameplate border, or a clean outline on FlareUI's and EllesmereUI's flat nameplates. Pixel lines and Autocast sparkles move round the plate."), 120, y - 6))

  -- Preview (left column, under the glows) ----------------------------------
  y = y - 50
  at(UI.Section(panel, "Preview on your target", W_), 26, y); y = y - 32
  local buttons = {}
  local MODES = { { "secure", "Holding / safe" }, { "unstable", "Losing it / close" }, { "lost", "Lost / on you" } }
  local function SetPreview(mode)
    ns.preview = (ns.preview ~= mode) and mode or nil
    for i, m in ipairs(MODES) do buttons[i].SetLabel(ns.preview == m[1] and "Stop" or m[2]) end
    if ns.preview then ns.Print("preview on: target an enemy with its nameplate visible.") end
    Changed()
  end
  for i, m in ipairs(MODES) do
    buttons[i] = at(UI.Button(panel, m[2], 128, function() SetPreview(m[1]) end), 26 + (i - 1) * 136, y)
  end
  panel:HookScript("OnHide", function() if ns.preview then SetPreview(ns.preview) end end)

  -- Overview (left column, under the preview) -------------------------------
  y = y - 50
  at(UI.Section(panel, "Threat overview", W_), 26, y); y = y - 32
  track(at(UI.Check(panel, "Show the overview window (/hf overview)",
    { function() return ns.db.overview.show end, function(v) ns.Overview.Show(v) end }, W_), 26, y))
  track(at(UI.Selector(panel, 260, ns.Overview.FILTERS,
    { function() return ns.db.overview.filter end, function(v) ns.db.overview.filter = v end },
    function() ns.Overview.Refresh() end, "Which enemies it lists, most dangerous first."), 26, y - 28))
  local leftY = y - 60

  -- Right column: display, alerts, overview ---------------------------------
  local X = 26 + W_ + 40 -- (the right column's left edge)
  y = -54
  at(UI.Section(panel, "Display", W_), X, y); y = y - 32
  track(at(UI.Check(panel, "Only in a party or raid (or when my pet tanks)", S("onlyInGroup"), W_, Changed), X, y)); y = y - 24
  -- the threat %
  local pctOn, pctDist, pctBg
  pctOn = track(at(UI.Check(panel, "Threat % beside the nameplate", S("showPercent"), W_, function()
    Changed(); pctOn.Refresh()
  end), X, y))
  pctDist = track(at(UI.Slider(panel, "% distance", 150, 0, 40, 1, S("percentGap"),
    function(v) return v .. " px" end, Changed, 1), X + 24, y - 26))
  pctBg = track(at(UI.Slider(panel, "% box opacity", 150, 0, 1, 0.05, S("percentBgAlpha"), pctFmt, Changed), X + 204, y - 26))
  local pr = pctOn.Refresh
  pctOn.Refresh = function()
    pr(); pctDist.Refresh(); pctBg.Refresh()
    pctDist:SetAlpha(ns.db.showPercent and 1 or 0.4); pctBg:SetAlpha(ns.db.showPercent and 1 or 0.4)
  end
  local pn = at(UI.Text(panel, "note", "Not the tank: your threat, as a % of what pulls it. The tank: the closest other's. In groups the game hides the number from addons; Holdfast lets the game draw it."), X + 24, y - 66)
  pn:SetWidth(W_ - 24)
  y = y - 104
  track(at(UI.Slider(panel, "Warn at (% of pulling it)", 300, 50, 100, 5, S("warnAt"),
    function(v) return v .. "%" end, Changed, 1), X, y))
  local wn = at(UI.Text(panel, "note", "Used where the game lets addons read threat % (mostly solo). In groups, orange follows the game's own \"closing in\" and \"about to pull\" states."), X, y - 40)
  wn:SetWidth(W_)
  y = y - 76
  local iconDist
  local icon
  icon = track(at(UI.Check(panel, "\"!\" with the red glow: it's on you (as the tank: you lost it)", S("showIcon"), W_, function()
    Changed(); icon.Refresh()
  end), X, y))
  iconDist = track(at(UI.Slider(panel, "\"!\" distance", 300, 0, 40, 1, S("iconOffsetX"),
    function(v) return v .. " px" end, Changed, 1), X + 24, y - 26))
  local ir = icon.Refresh
  icon.Refresh = function()
    ir(); iconDist.Refresh(); iconDist:SetAlpha(ns.db.showIcon and 1 or 0.4)
  end
  local rep = track(at(UI.Check(panel, "Replace the game's aggro highlight (its flare above the bar)", S("replaceGameHighlight"), W_, Changed), X, y - 70))
  rep:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Replace the game's aggro highlight", 1, 1, 1)
    GameTooltip:AddLine("Holdfast reads the same threat states as the game's own display (Options > Nameplates > Aggro Display), and draws them its way. With this on, the game's \"Progressive\" flare is hidden on the nameplates Holdfast draws. Its Flash and Health Bar Color options stay the game's to turn on or off.", 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
  end)
  rep:HookScript("OnLeave", function() GameTooltip:Hide() end)

  -- Alerts -----------------------------------------------------------------
  y = y - 106
  at(UI.Section(panel, "Alerts", W_), X, y); y = y - 32
  local function A(key) return { function() return ns.db.alerts[key] end, function(v) ns.db.alerts[key] = v end } end
  track(at(UI.Check(panel, "Sound", A("sound"), 120, Changed), X, y))
  track(at(UI.Check(panel, "Message on screen", A("screen"), 180, Changed), X + 124, y))
  at(UI.Button(panel, "Test", 70, function() ns.Alerts.Test() end), X + 350, y + 2)
  track(at(UI.Check(panel, "When it turns red (you lost it / it's on you)", A("onLost"), W_, Changed), X, y - 24))
  track(at(UI.Check(panel, "When it turns orange (losing it / close to pulling it)", A("onUnstable"), W_, Changed), X, y - 48))
  -- the messages: yours, or the default (empty); for each, the enemy's name after it or not, and
  -- a Test button
  y = y - 80
  at(UI.Text(panel, "line", "Messages"), X, y)
  local nh = UI.Text(panel, "note", "Add Target Name")
  nh:SetPoint("TOP", panel, "TOPLEFT", X + 333, y - 2)
  y = y - 22
  for _, m in ipairs(ns.Alerts.MESSAGES) do
    local key = m[1]
    at(UI.Text(panel, "note", m[2]), X + 12, y - 3):SetWidth(150)
    track(at(UI.Edit(panel, 146, { function() return ns.db.alerts.text[key] or "" end,
      function(v) ns.db.alerts.text[key] = (v ~= "") and v or nil end }, ns.Alerts.Default(key)), X + 166, y))
    track(at(UI.Check(panel, "", { function() return ns.db.alerts.names[key] ~= false end,
      function(v) ns.db.alerts.names[key] = v end }, 22), X + 322, y))
    at(UI.Button(panel, "Test", 50, function() ns.Alerts.Test(key) end), X + 362, y + 1)
    y = y - 24
  end
  local an = at(UI.Text(panel, "note", "Your text replaces the default (shown in grey when empty). Add Target Name: the enemy's name goes after it, in white. Test: shows it, with your target's name. At most one alert every 2 seconds, and not when an enemy first joins the fight."), X, y - 4)
  an:SetWidth(W_)

  y = math.min(y - 40, leftY)

  local reset = at(UI.Button(panel, "Reset to defaults", 130, function()
    ns.ResetDB(); UI.Restyle()
    for _, w in ipairs(refreshers) do w.Refresh() end
    Changed()
  end), 26, y)
  local fb = UI.Button(panel, "Report a bug / suggest", 160, function()
    UI.ShowLink("HoldfastLinkWindow", "Holdfast: bugs and ideas", "https://github.com/califaxop/holdfast-nameplate-threat/issues/new/choose")
  end)
  fb:SetPoint("LEFT", reset, "RIGHT", 8, 0)
  local hint = UI.Text(panel, "note", "/hf status, /hf threat: what Holdfast sees")
  hint:SetPoint("LEFT", fb, "RIGHT", 10, 0)

  panel:HookScript("OnShow", function() for _, w in ipairs(refreshers) do w.Refresh() end end)
  panel.height = -(y - 22 - 24)
  return panel
end

---------------------------------------------------------------------------
-- Esc > Options > AddOns entry, and the /hf window
---------------------------------------------------------------------------
local window

function ns.CreateOptions()
  local p = CreateFrame("Frame"); p.name = "Holdfast"
  pcall(function()
    local t = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16); t:SetText("Holdfast")
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(200, 24); b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12); b:SetText("Open Holdfast settings")
    b:SetScript("OnClick", function()
      if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel, true) end
      if not (window and window:IsShown()) then ns.OpenOptions() end
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
      Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(p, p.name))
    elseif InterfaceOptions_AddCategory then
      InterfaceOptions_AddCategory(p)
    end
  end)
end

function ns.OpenOptions()
  if not window then
    window = UI.Window("HoldfastOptionsWindow", 26 + W_ + 40 + W_ + 26, 600) -- (two columns)
    window:SetPoint("CENTER")
  UI.SetHost(window) -- pop-ups (the bug / idea link) sit over this window
    local ok, e = pcall(BuildPanel, window)
    if not ok then window:Hide(); window = nil; ns.Print("settings failed: " .. tostring(e)); return end
    window:SetHeight(window.height or 600)
    window:Hide()
  end
  UI.Restyle()
  -- shrink to fit smaller screens
  window:SetScale(math.max(0.5, math.min(1, (UIParent:GetHeight() - 40) / window:GetHeight())))
  window:SetShown(not window:IsShown())
end
