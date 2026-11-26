-- Holdfast: shared namespace, settings and helpers.
local ADDON, ns = ...
ns.name = ADDON

ns.isSecret = issecretvalue or function() return false end
function ns.Readable(v) return v ~= nil and not ns.isSecret(v) end

ns.DEFAULTS = {
  -- the three glows: shown or not, flashing or steady, and how strong
  -- (speed: seconds per flash)
  -- as the tank: holding / lost; "unstable" is only used while your pet tanks (you catching up)
  states = {
    aggro    = { show = true, flash = false, alpha = 0.6, speed = 0.50 },  -- holding: you (or your pet) have aggro
    unstable = { show = true, flash = true,  alpha = 0.8, speed = 0.35 },  -- pet tanking: you're catching up
    nothreat = { show = true, flash = true,  alpha = 0.8, speed = 0.25 },  -- lost: it's on someone else
  },
  warnAt            = 80,    -- unstable from this % of what pulls it (when the game lets addons read threat %)
  showPercent       = false, -- threat % beside the nameplate
  showIcon          = true,  -- "!": it's on you (not the tank), or you lost it (tank); replaces the % at 100%
  replaceGameHighlight = true, -- hide the game's own aggro flare (Aggro Display: Progressive) where Holdfast draws
  percentGap        = 6,       -- the % box: distance left of the health bar (px)
  percentBgAlpha    = 0.8,     -- the % box's background opacity
  iconOffsetX       = 4,       -- the "!": distance left of the % box (or of the bar, without the %)
  onlyInGroup       = false, -- only glow while you're in a party or raid (or your pet is the tank)
  glowStyle         = "auto",  -- "auto" (the plate's border art; an outline on FlareUI / EllesmereUI plates),
                               -- "border", "outline", "pixel" (pixel lines), "autocast" (sparkles)
  tank              = "auto",  -- whose aggro the glows follow: "auto" (your pet when it's out), "me", "pet"
  colors = {
    aggro    = { 0.35, 1.00, 0.45 },  -- stable
    unstable = { 1.00, 0.50, 0.05 },  -- unstable
    nothreat = { 1.00, 0.15, 0.10 },  -- no threat
  },
  -- your role: "auto" (your group role in a group, your spec's if none; the tank when solo),
  -- "tank", or "dps" (not the tank: damage or healer)
  role = "auto",
  -- when you're not the tank: same three glows, meaning safe (aggro) / close (unstable) / on you (nothreat)
  statesDps = {
    aggro    = { show = true, flash = false, alpha = 0.6, speed = 0.50 },
    unstable = { show = true, flash = true,  alpha = 0.8, speed = 0.35 },
    nothreat = { show = true, flash = true,  alpha = 0.8, speed = 0.25 },
  },
  colorsDps = {
    aggro    = { 0.35, 1.00, 0.45 },  -- safe: it's on someone else
    unstable = { 1.00, 0.50, 0.05 },  -- close: you're near pulling it
    nothreat = { 1.00, 0.15, 0.10 },  -- on you: you pulled it
  },
}

local function Copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = Copy(x) end
  return t
end
ns.Copy = Copy

ns.debug = false
function ns.Print(...) print("|cffff7744Holdfast:|r", ...) end
function ns.Dbg(...) if ns.debug then print("|cffff7744HF|r", ...) end end

function ns.LoadDB()
  HoldfastDB = HoldfastDB or {}
  local db = HoldfastDB
  local v = db.version
  -- designs before 3: start fresh (a newer version's settings, after going back a version, are kept)
  if type(v) ~= "number" or v < 3 then wipe(db) end
  if v == 3 and db.colors then
    -- 3 -> 4: the old orange "not stable" colour becomes the "unstable" colour; settings kept
    db.colors.unstable = db.colors.unstable or db.colors.loss
    db.colors.loss = nil
  end
  if (v == 3 or v == 4) and db.states == nil then
    -- 4 -> 5: one show / flash / strength setting per glow
    db.states = {
      aggro    = { show = db.showAggroGlow ~= false, flash = false, alpha = db.aggroAlpha or 0.6 },
      unstable = { show = db.showUnstable ~= false, flash = true, alpha = db.glowAlpha or 0.8 },
      nothreat = { show = true, flash = true, alpha = db.glowAlpha or 0.8 },
    }
    db.showAggroGlow, db.showUnstable, db.aggroAlpha, db.glowAlpha = nil, nil, nil, nil
  end
  if db.flashSpeed then
    -- one shared flash speed -> one per glow (stable was 1.5x slower, no threat 0.7x)
    local mult = { aggro = 1.5, unstable = 1, nothreat = 0.7 }
    for _, set in ipairs({ db.states, db.statesDps }) do
      for k, m in pairs(mult) do
        if set and set[k] and set[k].speed == nil then set[k].speed = math.floor(db.flashSpeed * m * 100 + 0.5) / 100 end
      end
    end
    db.flashSpeed = nil
  end
  -- 3.9.0: the % moved under the level box and the "!" to the left; old placement settings go
  if db.percentSide ~= nil then
    db.percentSide, db.percentOffsetLeft, db.percentOffsetRight, db.iconGapAfterPct = nil, nil, nil, nil
    db.iconOffsetX = nil
  end
  if db.percentNudgeX ~= nil or db.percentNudgeY ~= nil then -- box under the level (test builds only)
    db.percentNudgeX, db.percentNudgeY, db.iconOffsetX = nil, nil, nil
  end
  if not db.iconV2 then db.showIcon = true; db.iconV2 = true end -- 3.9.0: the "!" now stands in for the % at 100%
  db.version = 5
  for k, d in pairs(ns.DEFAULTS) do
    if db[k] == nil then db[k] = Copy(d) end
  end
  for _, group in ipairs({ "colors", "states", "colorsDps", "statesDps" }) do
    for k, d in pairs(ns.DEFAULTS[group]) do
      if db[group][k] == nil then db[group][k] = Copy(d) end
      if group == "states" or group == "statesDps" then
        for f, x in pairs(d) do if db[group][k][f] == nil then db[group][k][f] = x end end
      end
    end
  end
  ns.db = db
end

function ns.ResetDB()
  wipe(HoldfastDB)
  ns.LoadDB()
end
