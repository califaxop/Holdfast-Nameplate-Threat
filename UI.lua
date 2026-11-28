-- The threat overview's look (a window in the world, beside the nameplates): FlareUI's dialog
-- background, bronze border, heading font and colours when FlareUI is installed, EllesmereUI's
-- shell when it is, otherwise a dark panel with the game's tooltip border. The settings windows are
-- always the game's own Settings design (Settings.lua).
local _, ns = ...
local UI = {}
ns.UI = UI

local W = "Interface\\Buttons\\WHITE8X8"
local DIALOG_BG = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
-- the plain style's border: the game's own tooltip border, tinted the bronze of the default frames'
-- borders (its artwork is light grey, so the tint is a little brighter than the colour seen)
local BLIZZ_EDGE, BLIZZ_BG = "Interface\\Tooltips\\UI-Tooltip-Border", "Interface\\Tooltips\\UI-Tooltip-Background"
local BRONZE = { 0.86, 0.66, 0.36 }

-- the first of these font objects that exists and is a readable size (another addon can shrink a
-- shared one: EllesmereUI's quest tracker sets the game's tracker fonts to 1 px)
local function FontObj(...)
  for i = 1, select("#", ...) do
    local f = _G[select(i, ...)]
    if f and f.GetFont then
      local ok, path, size = pcall(f.GetFont, f)
      if ok and type(path) == "string" and type(size) == "number" and size >= 8 then return f end
    end
  end
  return _G.GameFontHighlight
end

local PALETTES = {
  flare = { title = { 1, 0.82, 0 }, dim = { 0.50, 0.50, 0.50 }, accent = { 0.65, 0.49, 0.27 } }, -- FlareUI: gold, bronze border
  plain = { title = { 1, 0.82, 0 }, dim = { 0.50, 0.50, 0.50 } },                                -- Blizzard gold
}

function UI.FlareBorder()
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("FlareUI"))
    or (IsAddOnLoaded and IsAddOnLoaded("FlareUI"))
  if not loaded then return nil end
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local path = LSM and LSM:Fetch("border", "FlareUI Frames", true)
  return path or "Interface/AddOns/FlareUI/Media/Borders/FlareUI-Frames.tga"
end

-- EllesmereUI style: EllesmereUI's own skinning API (EllesmereUI.RegisterSkin, see its SKINNING_API.md)
-- paints the overview's shell in the player's EllesmereUI theme; its title takes the UI font. It hands
-- us S once, at login, unless the player turned skinning off for us.
if type(EllesmereUI) == "table" and EllesmereUI.RegisterSkin then
  EllesmereUI.RegisterSkin("Holdfast", function(S)
    UI.euiSkin = S
    -- (ns.OnLooksChanged: the addon's own frames that follow the style)
    local function again() UI.Restyle(); if ns.OnLooksChanged then pcall(ns.OnLooksChanged) end end
    if S.OnLooksChanged then S.OnLooksChanged(again) end
    again()
  end)
end
function UI.EUI()
  local S = UI.euiSkin
  -- (no setting: the overview follows EllesmereUI whenever it's installed and skinning us)
  if S and (not S.IsEnabled or S.IsEnabled()) then return S end
end

-- the player's EllesmereUI font, as a font object (made once per font)
local euiFonts, euiN = {}, 0
local function EUIFont(S, size)
  local ok, path, flag = pcall(S.GetFont)
  if not (ok and type(path) == "string") then return nil end
  local key = path .. size .. tostring(flag)
  if not euiFonts[key] then
    euiN = euiN + 1
    local f = CreateFont("HoldfastEUIFont" .. euiN)
    f:SetFont(path, size, flag or "")
    euiFonts[key] = f
  end
  return euiFonts[key]
end

function UI.Theme()
  local S = UI.EUI()
  local flare = not S and UI.FlareBorder() ~= nil -- FlareUI's look whenever it's installed
  local p = flare and PALETTES.flare or PALETTES.plain
  local th = { flare = flare, title = p.title, dim = p.dim, accent = p.accent or BRONZE,
    headerFont = FontObj("ObjectiveTrackerHeaderFont", "GameFontNormalMed2", "GameFontNormal") }
  if S then -- EllesmereUI: white title in its font, grey notes
    th.eui = true
    th.title = { 1, 1, 1 }; th.dim = { 0.55, 0.55, 0.55 }
    th.headerFont = EUIFont(S, 14) or th.headerFont
  end
  return th
end

-- Every part registers a paint function, re-run when the style changes
local skins = {}
function UI.Skin(fn) skins[#skins + 1] = fn; fn(UI.Theme()) end
function UI.Restyle()
  local th = UI.Theme()
  for _, fn in ipairs(skins) do fn(th) end
end

local shelled = setmetatable({}, { __mode = "k" }) -- windows EllesmereUI has painted
function UI.SkinWindow(f, alpha)
  local th = UI.Theme()
  if th.eui then
    -- EllesmereUI paints the shell itself (once; it keeps it in step with the player's theme)
    if not shelled[f] then
      f:SetBackdrop(nil)
      local ok = pcall(UI.euiSkin.Shell, f)
      shelled[f] = ok
      if not ok then f:SetBackdrop({ bgFile = W }); f:SetBackdropColor(0.06, 0.06, 0.06, alpha) end
    end
    return
  end
  if th.flare then
    f:SetBackdrop({ bgFile = DIALOG_BG, edgeFile = UI.FlareBorder(), tile = false, tileSize = 0, edgeSize = 16,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(1, 1, 1, alpha)
  else
    f:SetBackdrop({ bgFile = BLIZZ_BG, edgeFile = BLIZZ_EDGE, tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.03, 0.03, 0.03, alpha)
  end
  f:SetBackdropBorderColor(th.accent[1], th.accent[2], th.accent[3], 1)
end

-- the overview's text: "title" (its heading) or "note" (small and grey). The font is set before
-- any text: WoW refuses SetText on a font string with no font.
function UI.Text(parent, role, str)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetJustifyH("LEFT")
  UI.Skin(function(th)
    if role == "title" then fs:SetFontObject(th.headerFont); fs:SetTextColor(th.title[1], th.title[2], th.title[3])
    else fs:SetFontObject("GameFontHighlightSmall"); fs:SetTextColor(th.dim[1], th.dim[2], th.dim[3]) end
  end)
  fs:SetText(str or "")
  return fs
end
