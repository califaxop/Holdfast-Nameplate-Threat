-- Nameplate adapters: where Holdfast draws for each nameplate system, so the renderer never needs
-- to know their insides. Tried in order; the first that finds a host for the plate is used.
-- Each adapter:
--   kind        "eui" | "flare" | "blizzard" | "generic"
--   Find(plate, unit) -> parent frame, bar frame, src (its own parts, or nil); nil when it doesn't
--               draw this plate. Everything it returns is checked to be a frame first.
--   Font(src)   -> a font string whose font the % uses, or nil (then the game's nameplate font)
--   Box(box, x, alpha, src) -> styles the % box its way and returns true; absent or false: the
--               default (the game's level-box art)
-- Their parts are other addons' undocumented frames: every read is checked or wrapped in pcall,
-- and a missing part falls through to the next adapter.
local _, ns = ...
local A = {}
ns.Adapters = A

local function Frame(x) return type(x) == "table" and type(x.GetObjectType) == "function" and x or nil end
local function Shown(x)
  if not (Frame(x) and x.IsShown) then return false end
  local ok, v = pcall(x.IsShown, x)
  return ok and not ns.isSecret(v) and v and true or false
end

-- EllesmereUI: its own plate for the unit (EllesmereNameplates_NS.plates[unit]), health bar .health
local EUI = { kind = "eui" }
function EUI.Find(_, unit)
  local EN = _G.EllesmereNameplates_NS
  local ep = type(EN) == "table" and type(EN.plates) == "table" and unit and EN.plates[unit]
  if Frame(ep) and Frame(ep.health) and Shown(ep) then return ep, ep.health, ep end
end
function EUI.Font(src) return src and (Frame(src.levelText) or Frame(src.hpText)) end
function EUI.Box(b, x, a)
  -- a flat dark box with a 1 px black edge, like its plates
  x.art:Hide(); if x.selected then x.selected:Hide() end
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b:SetBackdropColor(0, 0, 0, a)
  b:SetBackdropBorderColor(0, 0, 0, 1)
  return true
end

-- FlareUI: its parts of the game's plate (FlareUI.Nameplates.PartsFor(plate)), bar box .box
local FLARE = { kind = "flare" }
function FLARE.Find(plate)
  local NP = type(FlareUI) == "table" and FlareUI.Nameplates
  if not (type(NP) == "table" and type(NP.PartsFor) == "function") then return end
  local ok, fp = pcall(NP.PartsFor, plate)
  if not (ok and type(fp) == "table") then return end
  local bar = Frame(fp.box) or Frame(fp.health)
  local parent = Frame(fp.root) or Frame(fp.holder) or bar
  if bar and parent then return parent, bar, fp end
end
function FLARE.Font(src) return src and (Frame(src.level) or Frame(src.name)) end
function FLARE.Box(b, x, a, src)
  -- the same backdrop and border as its plate's level box
  x.art:Hide(); if x.selected then x.selected:Hide() end
  local lf, lb = src and Frame(src.levelFrame), src and Frame(src.levelBorder)
  local okB, bd = false, nil
  if lf and lf.GetBackdrop then okB, bd = pcall(lf.GetBackdrop, lf) end
  if okB and type(bd) == "table" then
    b:SetBackdrop(bd)
    local ok2, r, g, bb = pcall(lf.GetBackdropColor, lf)
    b:SetBackdropColor(ok2 and r or 0, ok2 and g or 0, ok2 and bb or 0, a)
  else
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); b:SetBackdropColor(0, 0, 0, a)
  end
  local okE, be = false, nil
  if lb and lb.GetBackdrop then okE, be = pcall(lb.GetBackdrop, lb) end
  if okE and type(be) == "table" then
    x.border = x.border or CreateFrame("Frame", nil, b, "BackdropTemplate")
    x.border:ClearAllPoints()
    x.border:SetAllPoints(b)
    x.border:SetBackdrop(be)
    local ok3, r, g, bb, ba = pcall(lb.GetBackdropBorderColor, lb)
    if ok3 and r then x.border:SetBackdropBorderColor(r, g, bb, ba or 1) end
    x.border:Show()
  end
  return true
end

-- The game's own nameplate: its unit frame and health bar (Blizzard_NamePlates)
local BLIZZ = { kind = "blizzard" }
function BLIZZ.Find(plate)
  local uf = Frame(plate.UnitFrame)
  if not uf then return end
  local bar = Frame(uf.healthBar) or (Frame(uf.HealthBarsContainer) and Frame(uf.HealthBarsContainer.healthBar))
  if bar then return uf, bar end
end

-- Anything else: the plate frame itself (a nameplate system Holdfast doesn't know)
local GENERIC = { kind = "generic" }
function GENERIC.Find(plate)
  if Frame(plate) then return plate, plate end
end

A.list = { EUI, FLARE, BLIZZ, GENERIC }

-- The adapter drawing this plate, and its parent, bar and parts.
function A.Find(plate, unit)
  for _, ad in ipairs(A.list) do
    local parent, bar, src = ad.Find(plate, unit)
    if parent then return ad, parent, bar, src end
  end
end
