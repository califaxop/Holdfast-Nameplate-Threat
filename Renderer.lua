-- Nameplate Renderer: a separate indicator anchored to Blizzard's nameplate.
-- Blizzard's health bar is never changed. The glow reuses the nameplate's own
-- selection-border art (copied, tinted), so it matches the game's look and lines up exactly.
--   stable    : green  -> the tank has aggro, safely
--   unstable  : orange -> the tank has aggro, but someone is close to taking it
--   no threat : red    -> engaged with you or your party, but it isn't on the tank
-- Each glow can be shown or not, flashing or steady, at its own strength (settings).
local _, ns = ...
local V = {}
ns.Renderer = V

local isSecret = ns.isSecret
local ShowPercent
-- Indicators are frames, and frames can't be freed: each is made once per host bar and glow
-- style, then reused (nameplates and FlareUI's / EllesmereUI's plates are recycled too).
local current = {}      -- plate -> the indicator shown on it now
local pool = setmetatable({}, { __mode = "k" }) -- host bar -> { [glow style] = indicator }
local TEXT_LEVEL = 30   -- % and "!" sit this many frame levels above the health bar (over debuff icons)

-- Where to draw: the first nameplate adapter (Adapters.lua) that finds a host for the plate -
-- EllesmereUI's plate, FlareUI's parts, the game's unit frame, or the plate itself.
-- Returns the parent frame, the bar to frame, the adapter and its parts.
local function Host(plate, unit)
  local ad, parent, bar, src = ns.Adapters.Find(plate, unit)
  return parent, bar, ad, src
end

-- the font the plate shows its level in: the adapter's (FlareUI's / EllesmereUI's), else the game's
local function PlateFont(fs, ad, src)
  local from = ad and ad.Font and ad.Font(src)
  if from and from.GetFont then
    local ok, path, size, flags = pcall(from.GetFont, from)
    if ok and type(path) == "string" and not isSecret(path) and type(size) == "number" and not isSecret(size) then
      fs:SetFont(path, math.max(8, size), flags or "")
      return
    end
  end
  if _G.SystemFont_NamePlateLevel then fs:SetFontObject(_G.SystemFont_NamePlateLevel) else fs:SetFontObject("GameFontHighlightSmall") end
end

-- Forever's nameplate target border art. Used as our glow so it matches the game's look.
local BORDER_ATLAS = "UI-HUD-CoolDownManager-Selected-yellow"

-- Make a texture with the border art, sitting exactly where Blizzard's border sits.
-- We never read the border's position (the client forbids measuring it); we just
-- anchor to it, or to the health bar if that's refused.
local function BorderTexture(parent, bar, layer, sublevel)
  local t = parent:CreateTexture(nil, layer, nil, sublevel)
  local src = bar.selectedBorder
  local atlas
  if type(src) == "table" and src.GetAtlas then
    local ok, a = pcall(src.GetAtlas, src)
    if ok and type(a) == "string" and not ns.isSecret(a) then atlas = a end
  end
  if not (atlas and pcall(t.SetAtlas, t, atlas)) then
    if not pcall(t.SetAtlas, t, BORDER_ATLAS) then return nil end
  end
  local anchored = type(src) == "table" and pcall(t.SetAllPoints, t, src)
  if not anchored then
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", bar, "TOPLEFT", -4, 4)
    t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 4, -4)
  end
  return t
end

-- Fallback when the nameplate has no selection border: a clean outline around the bar.
local function OutlineGlow(parent, bar)
  local g = { textures = {} }
  local edges = {
    { "TOPLEFT", "TOPLEFT", -2, 2, "TOPRIGHT", "TOPRIGHT", 2, 0, "h" },
    { "BOTTOMLEFT", "BOTTOMLEFT", -2, -2, "BOTTOMRIGHT", "BOTTOMRIGHT", 2, 0, "h" },
    { "TOPLEFT", "TOPLEFT", -2, 2, "BOTTOMLEFT", "BOTTOMLEFT", 0, -2, "v" },
    { "TOPRIGHT", "TOPRIGHT", 2, 2, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, -2, "v" },
  }
  for _, e in ipairs(edges) do
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetPoint(e[1], bar, e[2], e[3], e[4])
    t:SetPoint(e[5], bar, e[6], e[7], e[8])
    if e[9] == "h" then t:SetHeight(2) else t:SetWidth(2) end
    g.textures[#g.textures + 1] = t
  end
  return g
end

-- The bar's size, to run a moving glow around it (nil if the client won't say)
local function BarSize(bar)
  local ok, w, h = pcall(bar.GetSize, bar)
  if ok and type(w) == "number" and type(h) == "number" and not isSecret(w) and not isSecret(h) and w > 0 and h > 0 then return w, h end
end
-- a point `d` along the edge of a w x h box grown by m on every side: x, y from its top-left,
-- and whether that stretch runs across (true) or down (false)
local function Around(d, w, h, m)
  local W, H = w + 2 * m, h + 2 * m
  d = d % (2 * (W + H))
  if d < W then return d - m, -m, true end
  d = d - W
  if d < H then return w + m, d - m, false end
  d = d - H
  if d < W then return w + m - d, h + m, true end
  return -m, h + m - (d - W), false
end

-- The animation manager: one OnUpdate for every moving glow (pixel lines, autocast sparkles) that
-- is showing, instead of one per glow. Glows join while shown and leave when hidden; with none
-- showing, the driver frame is hidden and costs nothing.
local Anim = { active = {}, n = 0, clock = 0, ticks = 0 }
V.Anim = Anim
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, el)
  Anim.clock = Anim.clock + el
  Anim.ticks = Anim.ticks + 1
  for g in pairs(Anim.active) do g.Tick(Anim.clock) end
end)
function Anim.Set(g, on)
  if not g.Tick then return end
  if on and not Anim.active[g] then
    Anim.active[g] = true; Anim.n = Anim.n + 1
  elseif not on and Anim.active[g] then
    Anim.active[g] = nil; Anim.n = Anim.n - 1
  end
  driver:SetShown(Anim.n > 0)
end

-- Pixel lines: short bars running round the plate (as in EllesmereUI's and other UIs' "pixel glow").
local function PixelGlow(holder, bar)
  local g = { textures = {} }
  local N, TH, PERIOD = 8, 2, 4
  for i = 1, N do
    local t = holder:CreateTexture(nil, "OVERLAY", nil, 6)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    g.textures[i] = t
  end
  function g.Tick(clock)
    local w, h = BarSize(bar)
    if not w then for _, t in ipairs(g.textures) do t:Hide() end return end
    local per = 2 * (w + h + 4 * 2)
    local len = math.max(4, math.min(w, h, per / N * 0.45))
    local phase = (clock % PERIOD) / PERIOD * per
    for i, t in ipairs(g.textures) do
      local x, y, across = Around(phase + (i - 1) * per / N, w, h, 2)
      t:ClearAllPoints()
      t:SetPoint("CENTER", bar, "TOPLEFT", x, -y)
      if across then t:SetSize(len, TH) else t:SetSize(TH, math.min(len, h + 4)) end
      t:Show()
    end
  end
  return g
end

-- Autocast: four sparkle trails circling the plate (as the game's autocast shine)
local function AutocastGlow(holder, bar)
  local g = { textures = {} }
  local GROUPS, SIZES, PERIOD = 4, { 7, 6, 5, 4 }, 6
  for i = 1, GROUPS * #SIZES do
    local t = holder:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetTexture("Interface\\Cooldown\\star4")
    t:SetBlendMode("ADD")
    g.textures[i] = t
  end
  function g.Tick(clock)
    local w, h = BarSize(bar)
    if not w then for _, t in ipairs(g.textures) do t:Hide() end return end
    local per = 2 * (w + h + 4 * 1)
    local phase = (clock % PERIOD) / PERIOD * per
    local k = 0
    for grp = 1, GROUPS do
      for j, size in ipairs(SIZES) do
        k = k + 1
        local t = g.textures[k]
        local x, y = Around(phase + (grp - 1) * per / GROUPS - (j - 1) * 3, w, h, 1)
        t:ClearAllPoints(); t:SetPoint("CENTER", bar, "TOPLEFT", x, -y); t:SetSize(size, size); t:Show()
      end
    end
  end
  return g
end

-- One glow, in the chosen style:
--   border   : the nameplate's own border art, tinted, plus a soft additive copy (the game's look)
--   outline  : a clean 2 px line round the bar
--   pixel    : pixel lines running round it
--   autocast : sparkles circling it
-- "auto": the border on the game's plates, the outline on FlareUI's and EllesmereUI's flat ones.
local function GlowStyle(kind)
  local st = ns.db and ns.db.glowStyle or "auto"
  if st == "auto" then return kind == "blizzard" and "border" or "outline" end
  return st
end
local function MakeGlow(holder, bar, kind)
  local st = GlowStyle(kind)
  if st == "pixel" then return PixelGlow(holder, bar) end
  if st == "autocast" then return AutocastGlow(holder, bar) end
  if st == "outline" then return OutlineGlow(holder, bar) end
  local base = BorderTexture(holder, bar, "OVERLAY", 6)
  local soft = base and BorderTexture(holder, bar, "OVERLAY", 7)
  if not (base and soft) then return OutlineGlow(holder, bar) end
  soft:SetBlendMode("ADD")
  return { textures = { base, soft }, soft = soft }
end

local function TintGlow(g, c, alpha)
  for _, t in ipairs(g.textures) do
    if t.SetDesaturated then t:SetDesaturated(true) end -- the source art is yellow; strip it so our color shows true
    t:SetVertexColor(c[1], c[2], c[3], alpha)
  end
  if g.soft then g.soft:SetAlpha(alpha * 0.6) end
end

-- A flashing glow: the holder's alpha is controlled by state (or by the client when values
-- are hidden); only the inner frame flashes, so the two never fight each other.
-- The % box: XP Planner's tracker look. With FlareUI, its dark dialog background and bronze
-- frame border; without, a dark fill with a thin brown border. Background opacity is a setting.
-- Nameplates move in fractions of a pixel, and Blizzard draws the health bar without snapping
-- to the pixel grid. Ours must not snap either, or the glow and the % box jump a pixel at a time
-- while the bar glides, and seem to shake. (Fonts can't be set; they're fine.)
-- Art with fine detail (the "!") keeps the game's texel snapping, so its edges stay crisp; only
-- its position glides. Flat art (glows, bars) is drawn fully smooth, as Blizzard draws its bars.
local crisp = setmetatable({}, { __mode = "k" })
local function NoSnap(frame)
  for _, r in ipairs({ frame:GetRegions() }) do
    if r.SetSnapToPixelGrid then
      pcall(r.SetSnapToPixelGrid, r, false)
      if r.SetTexelSnappingBias and not crisp[r] then pcall(r.SetTexelSnappingBias, r, 0) end
    end
  end
  for _, c in ipairs({ frame:GetChildren() }) do NoSnap(c) end
end

-- The % box wears the same art as the nameplate's level box on the other side of the bar
-- (Forever's NameplateLevelFrame: atlas ui-hud-nameplates-levelindicator, and the yellow
-- ui-hud-nameplates-levelindicator-rectangle-selected around it while the unit is your target).
-- A client without that art gets the game's tooltip border instead.
local LEVEL_ATLAS = "ui-hud-nameplates-levelindicator"
local LEVEL_SELECTED_ATLAS = "ui-hud-nameplates-levelindicator-rectangle-selected"
local BOX_BORDER = { 0.86, 0.66, 0.36 } -- the fallback border's bronze (on grey art, so a bit brighter)
local boxes = setmetatable({}, { __mode = "k" }) -- [box frame] = { art, selected, hasLevelArt, key }
local function StyleBox(b, ad, src)
  local a = ns.db.percentBgAlpha or 0.8
  local x = boxes[b]
  if not x then
    x = {}
    x.art = b:CreateTexture(nil, "BACKGROUND")
    x.art:SetAllPoints()
    x.hasLevelArt = pcall(x.art.SetAtlas, x.art, LEVEL_ATLAS, false) and x.art:GetAtlas() ~= nil
    local sel = b:CreateTexture(nil, "OVERLAY")
    sel:SetPoint("TOPLEFT", -3, 3); sel:SetPoint("BOTTOMRIGHT", 3, -4) -- as Blizzard places it
    if pcall(sel.SetAtlas, sel, LEVEL_SELECTED_ATLAS, false) and sel:GetAtlas() then x.selected = sel else sel:Hide() end
    if x.selected then x.selected:Hide() end
    boxes[b] = x
  end
  local key = tostring(x.hasLevelArt) .. a .. (ad and ad.kind or "")
  if x.key == key then return end
  x.key = key
  if x.border then x.border:Hide() end
  -- the adapter's own look (EllesmereUI's flat box, FlareUI's level box), else the game's level box
  if ad and ad.Box and ad.Box(b, x, a, src) then return end
  if x.hasLevelArt then
    x.art:Show(); x.art:SetAlpha(a)
    b:SetBackdrop(nil)
  else
    x.art:Hide()
    b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    b:SetBackdropColor(0, 0, 0, a)
    b:SetBackdropBorderColor(BOX_BORDER[1], BOX_BORDER[2], BOX_BORDER[3], 1)
  end
  -- (no NoSnap here: drawn exactly as Blizzard draws the level box beside it, which holds still)
end

-- the "!": the game's quest-available icon, tinted to the glow's colour
-- The "!": the modern map's available-quest icon (atlas QuestNormal: sharper art with a dark
-- outline), or the old gossip icon on a client without it.
local QUEST_ATLAS = "QuestNormal"
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local function SetQuestArt(t)
  if not (pcall(t.SetAtlas, t, QUEST_ATLAS, false) and t:GetAtlas()) then t:SetTexture(QUEST_ICON) end
end

local function MakeFlash(f, bar, kind)
  local holder = CreateFrame("Frame", nil, f)
  holder:SetAllPoints()
  local inner = CreateFrame("Frame", nil, holder)
  inner:SetAllPoints()
  local glow = MakeGlow(inner, bar, kind)
  local anim = inner:CreateAnimationGroup()
  anim:SetLooping("BOUNCE")
  local a = anim:CreateAnimation("Alpha")
  a:SetFromAlpha(1); a:SetToAlpha(0.15); a:SetSmoothing("IN_OUT")
  -- the "!" sits on its own raised layer so the plate's debuff icons can't cover it; still a
  -- child of holder, so it shows and hides with its glow
  local top = CreateFrame("Frame", nil, holder)
  top:SetAllPoints(); top:SetFrameLevel(bar:GetFrameLevel() + TEXT_LEVEL)
  local icon = top:CreateTexture(nil, "OVERLAY")
  icon:SetSize(18, 18)
  SetQuestArt(icon)
  icon:SetDesaturated(true) -- grey, so the glow colour tints it cleanly
  crisp[icon] = true
  -- the same art again, added on top at part strength: the tint stays bright instead of dull
  local shine = top:CreateTexture(nil, "OVERLAY", nil, 1)
  shine:SetAllPoints(icon)
  SetQuestArt(shine)
  shine:SetDesaturated(true); shine:SetBlendMode("ADD"); shine:SetAlpha(0.45)
  crisp[shine] = true
  icon.shine = shine
  holder:Hide()
  return { holder = holder, glow = glow, anim = anim, alpha = a, icon = icon }
end

local function Create(plate, parent, bar, ad, src)
  local kind = ad.kind
  -- on the plate's own unit frame (the bar's parent chain), so it moves and scales with the bar
  -- exactly; never anchored to the plate's base frame (FlareUI's / EllesmereUI's plate when they draw it)
  local f = CreateFrame("Frame", nil, parent)
  f:SetFrameLevel(bar:GetFrameLevel() + 2) -- just above the bar/border
  f.kind, f.adapter, f.src = kind, ad, src
  f.uf, f.plate, f.outer = false, plate, false
  if kind == "blizzard" then f.uf = parent end -- (the game's plate: what sits left of its bar, see LeftOf)

  f:SetAllPoints(bar)

  f.aggro    = MakeFlash(f, bar, kind)  -- stable
  f.unstable = MakeFlash(f, bar, kind)  -- unstable
  f.nothreat = MakeFlash(f, bar, kind)  -- no threat

  f.top = CreateFrame("Frame", nil, f) -- above the plate's debuff icons
  f.top:SetAllPoints(); f.top:SetFrameLevel(bar:GetFrameLevel() + TEXT_LEVEL)
  f.pctBox = CreateFrame("Frame", nil, f.top, "BackdropTemplate") -- under the level box
  f.pctBox:SetSize(30, 15)
  f.pct = f.pctBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  PlateFont(f.pct, ad, src) -- the level's font (FlareUI's / EllesmereUI's on their plates)
  f.pct:SetPoint("CENTER", 0, 0)
  f.bar = bar


  f.pct:Hide()
  NoSnap(f)
  return f
end

local function StyleFlash(fl, c, alpha, speed, showIcon)
  TintGlow(fl.glow, c, alpha)
  fl.icon:SetVertexColor(c[1], c[2], c[3])
  fl.icon:SetShown(showIcon)
  fl.icon.shine:SetVertexColor(c[1], c[2], c[3])
  fl.icon.shine:SetShown(showIcon)
  if fl.alpha:GetDuration() ~= speed then fl.alpha:SetDuration(speed) end
end

-- Questie's quest icon on this nameplate, if it's showing one: a 16 px frame (strata HIGH) with
-- an .Icon texture that Questie parents to the plate, left of the health bar.
local function QuestieIcon(plate)
  if not QuestieLoader then return nil end
  local ok, kids = pcall(function() return { plate:GetChildren() } end)
  if not ok then return nil end
  for _, c in ipairs(kids) do
    if c.Icon and c:IsShown() and c:GetFrameStrata() == "HIGH" and c.Icon.GetTexture and c.Icon:GetTexture() then return c end
  end
end

-- On the game's plates, left of the health bar sit (outward): the raid marker (22 px), the elite /
-- rare icon (20 px), then 5 px on, the enemy's buffs (a row growing left). Each shows only when it
-- has something to show. Ours go past the outermost one showing, so nothing covers anything; the
-- buff row is anchored to, so ours follow it as buffs come and go.
local function T(x) return type(x) == "table" and x or nil end
local function Shown(fr)
  if not (T(fr) and fr.IsShown) then return false end
  local ok, v = pcall(fr.IsShown, fr)
  return ok and not isSecret(v) and v and true or false
end
local function HasShownChild(fr)
  local ok, kids = pcall(function() return { fr:GetChildren() } end)
  if not ok then return false end
  for _, c in ipairs(kids) do if Shown(c) then return true end end
  return false
end
local function LeftOf(f)
  local uf = T(f.uf)
  if not uf then return nil end
  local auras = T(uf.AurasFrame)
  local buffs = auras and T(auras.BuffListFrame)
  if Shown(auras) and Shown(buffs) and HasShownChild(buffs) then return buffs, "buffs" end
  if Shown(T(uf.ClassificationFrame)) then return uf.ClassificationFrame, "elite" end
  if Shown(T(uf.RaidTargetFrame)) then return uf.RaidTargetFrame, "marker" end
end

-- the % in a small box left of the health bar (left of Questie's quest icon when there is one, and
-- past the game's marker, elite icon and buffs, see LeftOf); the "!" left of that (or of them,
-- without the %)
local function PlaceText(f, qicon)
  local db = ns.db
  local gap = db.percentGap or 6
  local outer, what = LeftOf(f)
  -- (Questie's icon reaches about as far as the marker: past the marker, step out by Questie instead)
  if outer and not (what == "marker" and qicon) then
    f.textX, f.outer = gap, outer
    local key = what .. ":" .. tostring(outer) .. ":" .. gap
    if f.placedKey == key then return end
    f.placedKey = key
    -- as tall as the level box on the right (the bar's height, 3 px above to 2 px below)
    local okH, h = pcall(f.bar.GetHeight, f.bar)
    h = (okH and type(h) == "number" and not isSecret(h) and h > 0) and (h + 5) or 15
    f.pctBox:ClearAllPoints()
    f.pctBox:SetPoint("TOPRIGHT", outer, "LEFT", -gap, h / 2)
    f.pctBox:SetPoint("BOTTOMRIGHT", outer, "LEFT", -gap, -h / 2)
    f.iconKey = nil
    return
  end
  f.outer = false
  -- step past Questie's icon so neither covers the other: how far its left edge reaches past the bar's
  local extra = 0
  if qicon then
    local ok, bl, ql = pcall(function() return f.bar:GetLeft(), qicon:GetLeft() end)
    if ok and type(bl) == "number" and type(ql) == "number" and not isSecret(bl) and not isSecret(ql) then
      local bs, qs = f.bar:GetEffectiveScale(), qicon:GetEffectiveScale()
      extra = math.max(0, math.floor((bl * bs - ql * qs) / bs + 0.5))
    else
      extra = 20 -- Questie's default spot: about 17 px out, 16 px wide
    end
  end
  f.textX = gap + extra -- how far out from the bar the % (or the "!") starts
  local key = "bar:" .. gap .. ":" .. extra
  if f.placedKey == key then return end
  f.placedKey = key
  f.pctBox:ClearAllPoints()
  -- as tall as the level box on the right: 3 px above the bar to 2 px below it
  f.pctBox:SetPoint("TOPRIGHT", f.bar, "TOPLEFT", -f.textX, 3)
  f.pctBox:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMLEFT", -f.textX, -2)
  f.iconKey = nil -- the "!" follows (see PlaceIcons)
end

-- the "!": left of the % box while the % shows, otherwise where the % would start
local function PlaceIcons(f, pctShown)
  local ix = ns.db.iconOffsetX or 4
  local key = tostring(pctShown) .. ":" .. ix .. ":" .. (f.textX or 0) .. ":" .. tostring(f.outer)
  if f.iconKey == key then return end
  f.iconKey = key
  local function placeIcon(fl)
    fl.icon:ClearAllPoints()
    if pctShown then fl.icon:SetPoint("RIGHT", f.pctBox, "LEFT", -ix, 0)
    elseif f.outer then fl.icon:SetPoint("RIGHT", f.outer, "LEFT", -(f.textX or 6), 0)
    else fl.icon:SetPoint("RIGHT", f.bar, "LEFT", -(f.textX or 6), 0) end
  end
  for _, fl in ipairs({ f.unstable, f.nothreat }) do placeIcon(fl) end
end

-- the glow settings in use: yours as the tank (or your pet's), or yours when you're not the tank
-- the game's plate: place ours again when its buffs, elite icon or raid marker come or go
-- (between our own updates)
-- Hooks can't be removed, so each game unit frame is hooked once; the hook looks up the
-- indicator on that plate when it runs (never one it captured, which may be gone by then).
local leftHooked = setmetatable({}, { __mode = "k" })   -- game unit frame -> true
local flareHooked = setmetatable({}, { __mode = "k" })  -- game unit frame -> true
local flareHidden = setmetatable({}, { __mode = "k" })  -- game unit frame -> we hid its flare
local function WatchLeft(f)
  local uf = T(f.uf)
  if not uf or leftHooked[uf] then return end
  leftHooked[uf] = true
  local plate = f.plate
  local function again()
    local cur = current[plate]
    if not (cur and cur.uf == uf) then return end
    cur.placedKey = nil
    PlaceText(cur, QuestieIcon(plate))
    PlaceIcons(cur, cur.pctBox:IsShown() and true or false)
  end
  local buffs = T(uf.AurasFrame) and T(uf.AurasFrame.BuffListFrame)
  local cls, rt = T(uf.ClassificationFrame), T(uf.RaidTargetFrame)
  for _, w in ipairs({ { buffs, "OnSizeChanged" }, { buffs, "OnShow" }, { buffs, "OnHide" },
    { cls, "OnShow" }, { cls, "OnHide" }, { rt, "OnShow" }, { rt, "OnHide" } }) do
    if w[1] and w[1].HookScript then pcall(w[1].HookScript, w[1], w[2], again) end
  end
end

-- The game's own aggro highlight (Options > Nameplates > Aggro Display: Progressive): a flare along
-- the top of the bar. On the plates we draw, ours replaces it (setting "Replace the game's aggro
-- highlight"): hidden whenever the game shows it. Its Flash and Health Bar Color options stay its own.
local FLARE_PARTS = { "aggroHighlightBase", "aggroHighlightAdditive" }
local function HideGameFlare(uf)
  for _, k in ipairs(FLARE_PARTS) do
    local t = T(uf[k])
    if t and t.Hide then pcall(t.Hide, t) end
  end
  flareHidden[uf] = true
end
-- the setting was turned off: give the game its flare back where it wants it shown now (else
-- it would stay hidden until the game next switched it on)
local function RestoreGameFlare(uf)
  if not flareHidden[uf] then return end
  flareHidden[uf] = nil
  local want = uf.aggroHighlightShown
  if isSecret(want) or want ~= true then return end
  for _, k in ipairs(FLARE_PARTS) do
    local t = T(uf[k])
    if t and t.Show then pcall(t.Show, t) end
  end
end
local function WatchGameFlare(f)
  local uf = T(f.uf)
  if not uf or flareHooked[uf] then return end
  flareHooked[uf] = true
  local plate = f.plate
  if hooksecurefunc and type(uf.UpdateAggroHighlight) == "function" then
    pcall(hooksecurefunc, uf, "UpdateAggroHighlight", function(frame)
      local cur = current[plate]
      if ns.db and ns.db.replaceGameHighlight and cur and cur.uf == frame then HideGameFlare(frame) end
    end)
  end
end

local function Sets(dps)
  local db = ns.db
  if dps then return db.statesDps, db.colorsDps end
  return db.states, db.colors
end

-- Settings that change the look bump ns.lookGen (Options), so each indicator is restyled once
-- after a change (or when it's reused for a new enemy: V.Invalidate), not on every update.
V.counters = { renders = 0, skipped = 0, styles = 0 }
local function Style(f, dps, plate)
  local key = (ns.lookGen or 0) .. (dps and "d" or "t")
  if f.styleKey == key then return end
  f.styleKey = key
  V.counters.styles = V.counters.styles + 1
  WatchLeft(f)
  PlaceText(f, plate and QuestieIcon(plate))
  StyleBox(f.pctBox, f.adapter, f.src)
  local db = ns.db
  local st, col = Sets(dps)
  StyleFlash(f.aggro, col.aggro, st.aggro.alpha, st.aggro.speed or 0.5, false)
  -- the "!" goes with the red glow: not the tank, it's on you; the tank (or your pet), you lost it
  StyleFlash(f.unstable, col.unstable, st.unstable.alpha, st.unstable.speed or 0.35, false)
  StyleFlash(f.nothreat, col.nothreat, st.nothreat.alpha, st.nothreat.speed or 0.25, db.showIcon)
end

-- on: the glow is visible; flashing: it pulses (else it stays steady)
local function ShowFlash(fl, on, flashing)
  fl.holder:SetShown(on)
  Anim.Set(fl.glow, on and true or false)
  local pulse = on and flashing
  if pulse and not fl.anim:IsPlaying() then fl.anim:Play()
  elseif not pulse and fl.anim:IsPlaying() then fl.anim:Stop() end
end

local function HideAll(f)
  ShowFlash(f.aggro, false); ShowFlash(f.unstable, false); ShowFlash(f.nothreat, false); f.pct:Hide()
end

-- The threat % in the box beside the bar (setting "showPercent"): not the tank, yours; the tank, the
-- closest other's. A hidden % is handed to the game to draw (SetFormattedText takes hidden values),
-- never read; a readable one is capped at 100. In the state's colour (white when that's hidden).
local GLOW_OF = { secure = "aggro", unstable = "unstable", lost = "nothreat" }
ShowPercent = function(f, state, colors)
  local v = state and state.percentage
  if not (ns.db.showPercent and v ~= nil) then f.pct:Hide(); return end
  if isSecret(v) then
    f.pct:SetFormattedText("%.0f%%", v)
  elseif type(v) == "number" then
    f.pct:SetFormattedText("%.0f%%", math.min(100, math.max(0, v)))
  else
    f.pct:Hide(); return
  end
  local c = colors[GLOW_OF[state.kind] or ""]
  if c then f.pct:SetTextColor(c[1], c[2], c[3]) else f.pct:SetTextColor(1, 1, 1) end
  f.pct:Show()
end

local Render
function V.Render(plate, state, unit)
  if Render(plate, state, unit) then return end -- (unchanged)
  local f = plate and current[plate]
  if not f then return end
  -- the % box follows the %: shown with it, sized to it
  local shown = f.pct:IsShown() and true or false
  f.pctBox:SetShown(shown)
  PlaceIcons(f, shown)
  if shown then
    local ok, w = pcall(f.pct.GetStringWidth, f.pct)
    -- at least the level box's width (Blizzard's 28), wider for "100%"
    f.pctBox:SetWidth(math.max(28, ((ok and type(w) == "number" and not isSecret(w)) and w or 20) + 10))
    -- the yellow outline while it's your target, like the level box
    local x = boxes[f.pctBox]
    if x and x.selected and f.kind == "blizzard" then -- (the game's level box has this outline)
      local okT, isT = pcall(UnitIsUnit, unit or "none", "target")
      x.selected:SetShown(okT and not isSecret(isT) and isT and true or false)
    end
  end
end

-- The indicator for this host bar in this glow style: reused if it was made before.
local function Acquire(plate, parent, bar, ad, src, style)
  local byStyle = pool[bar]
  if not byStyle then byStyle = {}; pool[bar] = byStyle end
  local f = byStyle[style]
  if not f then
    f = Create(plate, parent, bar, ad, src)
    f.style = style
    byStyle[style] = f
  end
  -- a recycled FlareUI / EllesmereUI plate can move to another game plate: let go of the old one
  if f.plate ~= plate and current[f.plate] == f then current[f.plate] = nil end
  f.plate, f.kind, f.adapter, f.src = plate, ad.kind, ad, src
  f.uf = (ad.kind == "blizzard") and parent or false
  f.placedKey, f.iconKey, f.styleKey, f.renderKey = nil, nil, nil, nil
  return f
end

function Render(plate, state, unit)
  if not plate then return end
  local parent, bar, ad, src = Host(plate, unit)
  if not ad then return end
  local style = GlowStyle(ad.kind)
  local f = current[plate]
  if f and (f.bar ~= bar or f.adapter ~= ad or f.style ~= style) then
    -- the plate is drawn by another UI now (or no longer), or the glow style changed
    HideAll(f); f:Hide(); current[plate] = nil; f = nil
  end
  if not f then f = Acquire(plate, parent, bar, ad, src, style); current[plate] = f end
  f:Show()
  if f.uf then
    if ns.db.replaceGameHighlight then
      WatchGameFlare(f)
      if not flareHidden[f.uf] then HideGameFlare(f.uf) end -- (the hook hides it when the game shows it again)
    else RestoreGameFlare(f.uf) end
  end
  local dps = state and state.dps or false
  Style(f, dps, plate)
  local st, col = Sets(dps)
  local what = state and state.kind or "none"

  -- nothing changed since the last update (same state, same look, same target): nothing to redraw.
  -- (A hidden answer can't be compared, so hidden states and hidden % are always passed on.)
  -- (the % only counts while it's shown; a hidden % can't be compared, so its text is just handed
  -- to the game again, which is cheap)
  local pct = state and state.percentage
  local showPct = ns.db.showPercent and pct ~= nil
  local key = nil
  if what ~= "hidden" then
    local okT, isT = pcall(UnitIsUnit, unit or "none", "target")
    key = what .. "|" .. (showPct and (isSecret(pct) and "hidden" or tostring(pct)) or "-") .. "|"
      .. tostring(okT and not isSecret(isT) and isT) .. "|" .. f.styleKey
  end
  if key and f.renderKey == key then
    if showPct and isSecret(pct) then ShowPercent(f, state, col) end
    V.counters.skipped = V.counters.skipped + 1
    return true
  end
  f.renderKey = key
  V.counters.renders = V.counters.renders + 1

  f.aggro.holder:SetAlpha(1); f.unstable.holder:SetAlpha(1); f.nothreat.holder:SetAlpha(1)

  if what == "none" or what == "unknown" then HideAll(f); return end
  ShowPercent(f, state, col)
  ShowFlash(f.unstable, false)

  if what == "hidden" then
    -- The game hides it: the hidden "is it on you" answer turns the glows (and the "!") on and off
    -- itself, without us reading it. As the tank on you is good; not the tank, it's the bad one.
    local t = state.isTanking
    if f.SetAlphaFromBoolean and (isSecret(t) or t ~= nil) then
      ShowFlash(f.aggro, st.aggro.show, st.aggro.flash)
      ShowFlash(f.nothreat, st.nothreat.show, st.nothreat.flash)
      f.aggro.holder:SetAlphaFromBoolean(t, dps and 0 or 1, dps and 1 or 0)
      f.nothreat.holder:SetAlphaFromBoolean(t, dps and 1 or 0, dps and 0 or 1)
    else
      ShowFlash(f.aggro, false); ShowFlash(f.nothreat, false)
    end
    return
  end

  -- readable: holding / safe, unstable (losing it / about to pull it), lost / on you
  ShowFlash(f.aggro, what == "secure" and st.aggro.show, st.aggro.flash)
  ShowFlash(f.unstable, what == "unstable" and st.unstable.show, st.unstable.flash)
  ShowFlash(f.nothreat, what == "lost" and st.nothreat.show, st.nothreat.flash)
end

function V.Hide(plate)
  local f = plate and current[plate]
  if f then HideAll(f); f.renderKey = nil end
end

-- the plate shows another enemy now (recycled): restyle and redraw it on its next update
function V.Invalidate(plate)
  local f = plate and current[plate]
  if f then f.styleKey, f.renderKey = nil, nil end
end

-- the glow style changed: every plate picks its indicator in the new style on its next update
-- (one made earlier in that style is reused)
function V.Rebuild()
  for plate, f in pairs(current) do HideAll(f); f:Hide(); f.renderKey = nil; current[plate] = nil end
end

-- for diagnostics and tests: the indicator on a plate; indicators made so far, and the plates showing one
function V.Indicator(plate) return current[plate] end
-- for diagnostics (/hf perf) and tests: indicators made so far, the plates showing one, and by
-- which adapter
function V.Counts()
  local made, shown, kinds = 0, 0, {}
  for _, byStyle in pairs(pool) do for _ in pairs(byStyle) do made = made + 1 end end
  for _, f in pairs(current) do shown = shown + 1; kinds[f.kind] = (kinds[f.kind] or 0) + 1 end
  return made, shown, kinds
end

V.HasSecretSupport = function() return UIParent.SetAlphaFromBoolean ~= nil end
