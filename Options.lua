-- Holdfast: settings window (/hf, or Esc > Options > AddOns > Holdfast), drawn in the same
-- style as XP Planner and Spell Glow (see UI.lua).
local _, ns = ...
local UI = ns.UI

local function Changed()
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
  { "aggro",    "Holding",       "It's attacking you (or your pet, when it tanks)." },
  { "nothreat", "Lost",          "It's attacking someone else." },
}
-- the same two glows when you're not the tank
local STATES_DPS = {
  { "aggro",    "Safe",    "It's attacking someone else." },
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
  track(at(UI.Selector(panel, 330, { { "auto", "Auto: my pet when it tanks, else me" }, { "me", "Me" }, { "pet", "My pet" } },
    { function() return ns.db.tank or "auto" end, function(v) ns.db.tank = v end }, Changed,
    "Click, or use the arrows, to change it."), 26, -84))
  local n1 = at(UI.Text(panel, "note", "Auto follows your pet when it's out and no role is set (solo, or a group without roles); otherwise you, as your role below says."), 26, -112)
  n1:SetWidth(W_)

  -- My role --------------------------------------------------------------------
  at(UI.Text(panel, "line", "My role"), 26, -140)
  track(at(UI.Selector(panel, 300, { { "auto", "Auto: my group-finder role" }, { "tank", "Tank" }, { "dps", "Not the tank (damage / healer)" } },
    S("role"), Changed, "Auto uses the role you picked in the group finder. With no role set (solo, or a group without roles) you're treated as when solo: your pet when it's out, else you as the tank."), 120, -136))
  local n2 = at(UI.Text(panel, "note", "Tank / solo: green while it's on you (or your pet), red with a \"!\" when it's on someone else. Not the tank: green while it's on someone else, red with a \"!\" once it's on you."), 26, -164)
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
    local rr = rowsRefresh[#rowsRefresh]
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

  -- Display ----------------------------------------------------------------
  y = y - 50
  at(UI.Section(panel, "Display", W_), 26, y); y = y - 32
  track(at(UI.Check(panel, "Only in a party or raid (or when my pet tanks)", S("onlyInGroup"), W_, Changed), 26, y))
  local iconDist
  local icon
  icon = track(at(UI.Check(panel, "\"!\" with the red glow: it's on you (as the tank: you lost it)", S("showIcon"), W_, function()
    Changed(); icon.Refresh()
  end), 26, y - 24))
  iconDist = track(at(UI.Slider(panel, "\"!\" distance", 300, 0, 40, 1, S("iconOffsetX"),
    function(v) return v .. " px" end, Changed, 1), 50, y - 50))
  local ir = icon.Refresh
  icon.Refresh = function()
    ir(); iconDist.Refresh(); iconDist:SetAlpha(ns.db.showIcon and 1 or 0.4)
  end
  local rep = track(at(UI.Check(panel, "Replace the game's aggro highlight (its flare above the bar)", S("replaceGameHighlight"), W_, Changed), 26, y - 94))
  rep:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Replace the game's aggro highlight", 1, 1, 1)
    GameTooltip:AddLine("Holdfast reads the same threat states as the game's own display (Options > Nameplates > Aggro Display), and draws them its way. With this on, the game's \"Progressive\" flare is hidden on the nameplates Holdfast draws. Its Flash and Health Bar Color options stay the game's to turn on or off.", 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
  end)
  rep:HookScript("OnLeave", function() GameTooltip:Hide() end)
  track(at(UI.Check(panel, "FlareUI style for this window (needs FlareUI)", S("flareStyle"), W_, function() UI.Restyle() end), 26, y - 122))
  track(at(UI.Check(panel, "EllesmereUI style for this window (needs EllesmereUI)", S("euiStyle"), W_, function() UI.Restyle() end), 26, y - 146))

  -- Preview ----------------------------------------------------------------
  y = y - 182
  at(UI.Section(panel, "Preview on your target", W_), 26, y); y = y - 32
  local buttons = {}
  local MODES = { { "secure", "Holding / safe" }, { "lost", "Lost / on you" } }
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

  local reset = at(UI.Button(panel, "Reset to defaults", 130, function()
    ns.ResetDB(); UI.Restyle()
    for _, w in ipairs(refreshers) do w.Refresh() end
    Changed()
  end), 26, y - 40)
  local fb = UI.Button(panel, "Report a bug / suggest", 160, function()
    UI.ShowLink("HoldfastLinkWindow", "Holdfast: bugs and ideas", "https://github.com/califaxop/holdfast-nameplate-threat/issues/new/choose")
  end)
  fb:SetPoint("LEFT", reset, "RIGHT", 8, 0)
  local hint = UI.Text(panel, "note", "/hf debug: threat data")
  hint:SetPoint("LEFT", fb, "RIGHT", 10, 0)

  panel:HookScript("OnShow", function() for _, w in ipairs(refreshers) do w.Refresh() end end)
  panel.height = -(y - 40 - 22 - 24)
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
    window = UI.Window("HoldfastOptionsWindow", 472, 600)
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
