-- Holdfast: settings window (/hf, or Esc > Options > AddOns > Holdfast), in the game's own
-- Settings design (Settings.lua).
local _, ns = ...
local UI = ns.UI

local function Changed()
  ns.lookGen = (ns.lookGen or 0) + 1 -- every indicator restyles once
  if ns.UpdateAll then ns.UpdateAll() end
  if ns.RefreshInUse then ns.RefreshInUse() end
end
local function S(key) return { function() return ns.db[key] end, function(v) ns.db[key] = v end } end
local function pctFmt(v) return math.floor(v * 100 + 0.5) .. "%" end

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
local window

local function PageThreat(_, R)
  R:Section("Whose aggro")
  R:Selector("Show aggro for", 330, { { "auto", "Auto: my pet when it tanks, else me" }, { "me", "Me" }, { "pet", "My pet" },
      { "both", "Me and my pet" }, { "tanks", "The group's tanks (for healers)" } },
    { function() return ns.db.tank or "auto" end, function(v) ns.db.tank = v end }, Changed,
    "Auto: your pet when it's out and no role is set, else you. Me and my pet, the group's tanks: any of them holding it is good.")
  R:Selector("My role", 330, { { "auto", "Auto: my group-finder role" }, { "tank", "Tank" }, { "dps", "Not the tank (damage / healer)" } },
    S("role"), Changed, "Auto uses the role you picked in the group finder. With no role set (solo, or a group without roles) you're treated as when solo: your pet when it's out, else you as the tank.")
  R:Note("Green: holding / safe. Orange: someone is close to taking it / you're close to pulling it. Red with a \"!\": lost / it's on you.")
end

local function PageGlows(p, R)
  R:Section("Glows")
  local rowsRefresh = {}
  local inUse
  local function InUseText()
    local ok, mode = pcall(ns.State.Mode)
    if not ok then return "" end
    if mode == "dps" then return "In use: Not the tank" end
    if mode == "pet" then return "In use: Tank / solo (your pet)" end
    if mode == "both" then return "In use: Tank / solo (you and your pet)" end
    if mode == "tanks" then return "In use: Tank / solo (the group's tanks)" end
    return (IsInGroup and IsInGroup()) and "In use: Tank / solo (you tank)" or "In use: Tank / solo (solo)"
  end
  local set, setRow = R:Toggle("Settings for", 200, { { "tank", "Tank / solo" }, { "dps", "Not the tank" } },
    { function() return editSet end, function(v) editSet = v end },
    function() for _, f in ipairs(rowsRefresh) do f() end end,
    "Each has its own glows. Tank / solo is used when you're the tank, when you're solo, and while your pet tanks.")
  inUse = UI.Note(setRow, "")
  inUse:SetPoint("LEFT", set, "RIGHT", 12, 0)
  ns.RefreshInUse = function() inUse:SetText(InUseText()) end
  R:Track({ Refresh = ns.RefreshInUse })

  -- the table: colour, name; Show, Flash; Strength, Interval
  local COL_SHOW, COL_FLASH, COL_STR, COL_INT = 196, 240, 290, 480
  local hy = R:Space(18)
  for _, h in ipairs({ { "Show", COL_SHOW + 15 }, { "Flash", COL_FLASH + 15 }, { "Strength", COL_STR + 65 }, { "Interval", COL_INT + 60 } }) do
    local t = UI.Note(p, h[1]); t:SetPoint("TOP", p, "TOPLEFT", h[2], hy)
  end
  for i, st in ipairs(STATES) do
    local key = st[1]
    local function s() return (editSet == "dps") and ns.db.statesDps[key] or ns.db.states[key] end
    local function colors() return (editSet == "dps") and ns.db.colorsDps or ns.db.colors end
    local function label() return (editSet == "dps") and STATES_DPS[i] or st end
    local row = R:Row("", function() return label()[3] end)
    row.label:ClearAllPoints(); row.label:SetPoint("LEFT", 66, 0); row.label:SetPoint("RIGHT", row, "LEFT", COL_SHOW - 6, 0)
    local sw = R:Track(UI.Swatch(row, function() return colors()[key] end, Changed)); sw:SetPoint("LEFT", 37, 0)
    local str = R:Track(UI.Slider(row, 130, 0.05, 1, 0.05,
      { function() return s().alpha end, function(v) s().alpha = v end }, pctFmt, Changed))
    str:SetPoint("LEFT", COL_STR, 0)
    local int = R:Track(UI.Slider(row, 120, 0.1, 1.5, 0.05,
      { function() return s().speed or 0.35 end, function(v) s().speed = v end },
      function(v) return format("%.2fs", v) end, Changed))
    int:SetPoint("LEFT", COL_INT, 0)
    local show
    local flash = R:Track(UI.Check(row, { function() return s().flash end, function(v) s().flash = v end },
      function() Changed(); show.Refresh() end))
    flash:SetPoint("LEFT", COL_FLASH, 0)
    show = R:Track(UI.Check(row, { function() return s().show end, function(v) s().show = v end }, function()
      Changed(); show.Refresh()
    end))
    show:SetPoint("LEFT", COL_SHOW, 0)
    local r = show.Refresh
    show.Refresh = function()
      r(); flash.SetActive(s().show); str.SetActive(s().show); int.SetActive(s().show and s().flash)
      row.label:SetText(label()[2])
    end
    -- switching which settings are edited: relabel and reload this row
    rowsRefresh[#rowsRefresh + 1] = function() sw.Refresh(); flash.Refresh(); str.Refresh(); int.Refresh(); show.Refresh() end
  end
  R:Selector("Glow style", 330, {
      { "auto", "Auto (matches your nameplates)" }, { "border", "Nameplate border" }, { "outline", "Outline" },
      { "pixel", "Pixel lines" }, { "autocast", "Autocast sparkles" } },
    S("glowStyle"), function() ns.Renderer.Rebuild(); Changed() end,
    "How the glow looks, for every state. Auto: the game's nameplate border, or a clean outline on FlareUI's and EllesmereUI's flat nameplates. Pixel lines and Autocast sparkles move round the plate.")

  R:Section("Preview on your target")
  local buttons = {}
  local MODES = { { "secure", "Holding / safe" }, { "unstable", "Losing it / close" }, { "lost", "Lost / on you" } }
  local function SetPreview(mode)
    ns.preview = (ns.preview ~= mode) and mode or nil
    for i, m in ipairs(MODES) do buttons[i]:SetText(ns.preview == m[1] and "Stop" or m[2]) end
    if ns.preview then ns.Print("preview on: target an enemy with its nameplate visible.") end
    Changed()
  end
  local row = R:Row("Show", "Target an enemy with its nameplate visible. Click again to stop.")
  for i, m in ipairs(MODES) do
    buttons[i] = UI.Button(row, m[2], 128, function() SetPreview(m[1]) end)
    buttons[i]:SetPoint("LEFT", R.ctrl + (i - 1) * 134, 0)
  end
  p:HookScript("OnHide", function() if ns.preview then SetPreview(ns.preview) end end)
end

local function PageDisplay(_, R)
  R:Section("Display")
  R:Check("Only in a party or raid", S("onlyInGroup"), Changed, "Or when your pet tanks.")
  R:Section("Threat %")
  local pctDist, pctBg
  local pctOn = R:Check("Threat % beside the nameplate", S("showPercent"), function() Changed(); R.Refresh() end,
    "Not the tank: your threat, as a % of what pulls it. The tank: the closest other's. In groups the game hides the number from addons; Holdfast lets the game draw it.")
  pctDist = R:Slider("% distance", 0, 40, 1, S("percentGap"), function(v) return v .. " px" end, Changed, nil, 1)
  pctBg = R:Slider("% box opacity", 0, 1, 0.05, S("percentBgAlpha"), pctFmt, Changed)
  local pr = pctOn.Refresh
  pctOn.Refresh = function() pr(); pctDist.SetActive(ns.db.showPercent); pctBg.SetActive(ns.db.showPercent) end
  R:Slider("Warn at (% of pulling it)", 50, 100, 5, S("warnAt"), function(v) return v .. "%" end, Changed,
    "Used where the game lets addons read threat % (mostly solo). In groups, orange follows the game's own \"closing in\" and \"about to pull\" states.", 1)
  R:Section("\"!\" icon")
  local iconDist
  local icon = R:Check("\"!\" with the red glow", S("showIcon"), function() Changed(); R.Refresh() end,
    "It's on you (as the tank: you lost it).")
  iconDist = R:Slider("\"!\" distance", 0, 40, 1, S("iconOffsetX"), function(v) return v .. " px" end, Changed, nil, 1)
  local ir = icon.Refresh
  icon.Refresh = function() ir(); iconDist.SetActive(ns.db.showIcon) end
  R:Section("The game's highlight")
  R:Check("Replace the game's aggro highlight", S("replaceGameHighlight"), Changed,
    "Holdfast reads the same threat states as the game's own display (Options > Nameplates > Aggro Display), and draws them its way. With this on, the game's \"Progressive\" flare above the bar is hidden on the nameplates Holdfast draws. Its Flash and Health Bar Color options stay the game's to turn on or off.")
end

local function PageAlerts(p, R)
  local function A(key) return { function() return ns.db.alerts[key] end, function(v) ns.db.alerts[key] = v end } end
  R:Section("Alerts")
  R:Check("Sound", A("sound"), Changed)
  R:Check("Message on screen", A("screen"), Changed)
  R:Check("When it turns red", A("onLost"), Changed, "You lost it / it's on you.")
  R:Check("When it turns orange", A("onUnstable"), Changed, "Losing it / close to pulling it.")
  R:Button("Try it", "Test", 96, function() ns.Alerts.Test() end, "Plays the alert as it is now, with your target's name.")
  R:Section("Messages")
  local hy = R:Space(18)
  local h = UI.Note(p, "Add Target Name"); h:SetPoint("TOP", p, "TOPLEFT", R.ctrl + 211, hy)
  for _, m in ipairs(ns.Alerts.MESSAGES) do
    local key = m[1]
    local e, row = R:Edit(m[2], 180, { function() return ns.db.alerts.text[key] or "" end,
      function(v) ns.db.alerts.text[key] = (v ~= "") and v or nil end }, ns.Alerts.Default(key))
    local c = R:Track(UI.Check(row, { function() return ns.db.alerts.names[key] ~= false end,
      function(v) ns.db.alerts.names[key] = v end }, Changed))
    c:SetPoint("LEFT", e, "RIGHT", 10, 0)
    UI.Button(row, "Test", 60, function() ns.Alerts.Test(key) end):SetPoint("LEFT", c, "RIGHT", 16, 0)
  end
  R:Note("Your text replaces the default (shown in grey when empty). Add Target Name: the enemy's name goes after it, in white. Test: shows it, with your target's name. At most one alert every 2 seconds, and not when an enemy first joins the fight.")
end

local function PageOverview(_, R)
  R:Section("Threat overview")
  R:Check("Show the overview window", { function() return ns.db.overview.show end, function(v) ns.Overview.Show(v) end }, nil,
    "A small window listing the enemies on your nameplates, most dangerous first. Also /hf overview.")
  R:Selector("List", 260, ns.Overview.FILTERS,
    { function() return ns.db.overview.filter end, function(v) ns.db.overview.filter = v end },
    function() ns.Overview.Refresh() end, "Which enemies it lists, most dangerous first.")
end

local function PageStatus(_, R)
  R:Section("Commands")
  R:Note("/hf status, /hf threat: what Holdfast sees.  /hf overview: the threat overview.  /hf report: the bug report.")
  R:Section("Reset")
  R:Button("Reset to defaults", "Defaults", 96, function()
    ns.ResetDB(); UI.Restyle(); window.Refresh(); Changed()
  end, "Every setting back to its default.")
end

local function BuildWindow()
  window = UI.Settings({ name = "HoldfastOptionsWindow", title = "Holdfast", logo = "Interface\\AddOns\\Holdfast\\media\\Logo",
    tagline = "Threat glows on enemy nameplates.", bug = function() ns.ShowBugReport() end,
    pages = {
      { "Threat", "Whose aggro to show, and your role.", PageThreat },
      { "Glows", "The glow for each threat state, its style, and a preview.", PageGlows },
      { "Display", "When Holdfast shows, the threat %, the \"!\" and the game's own highlight.", PageDisplay },
      { "Alerts", "A sound or a message when you lose it or are about to.", PageAlerts },
      { "Overview", "The small window listing the enemies on your nameplates.", PageOverview },
      { "Status", "The commands, and starting afresh.", PageStatus },
    },
    categories = { { "Holdfast", { 1, 2, 3, 4, 5 } }, { "Help", { 6 } } } })
end

---------------------------------------------------------------------------
-- Esc > Options > AddOns entry, and the /hf window
---------------------------------------------------------------------------
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

-- Report a bug (the title bar's button, /hf report)
local BUG = { name = "HoldfastReportWindow", title = "Holdfast Bugs & Feedback",
  repo = "https://github.com/califaxop/holdfast-nameplate-threat/issues/new",
  included = "Included: Holdfast's version, the game client, your class and level, its settings, the nameplates showing and whether you're grouped. Never: your name, realm, guild or other players.",
  build = function() return ns.BugReport() end }
function ns.ShowBugReport(kind)
  local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  BUG.version = get and get(ns.name, "Version") or nil
  return UI.ShowBugReport(BUG, kind)
end

function ns.OpenOptions()
  if not window then
    local ok, e = pcall(BuildWindow)
    if not ok then if window then window:Hide() end; window = nil; ns.Print("settings failed: " .. tostring(e)); return end
  end
  UI.ToggleWindow(window)
  return window
end
