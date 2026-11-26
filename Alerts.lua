-- Optional alerts (settings: Alerts): a sound and / or a message on screen when an enemy turns red
-- (as the tank: you lost it; not the tank: it's on you) and, if chosen, when it turns orange.
-- Not when an enemy first joins the fight (in a pull everything lands somewhere for a moment), and
-- at most one alert every 2 seconds, so a big pull doesn't spam.
local _, ns = ...
local AL = { shown = 0 }
ns.Alerts = AL

local GAP = 2 -- seconds between alerts
local last = -GAP
local SOUND = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959

-- the messages: the player's own (settings: alerts.text), or these
local DEFAULT = { lostTank = "Lost aggro", lostDps = "Aggro on you", unstableTank = "Losing aggro", unstableDps = "Close to pulling" }
AL.MESSAGES = { { "lostTank", "Lost it (tank)" }, { "lostDps", "On you (not the tank)" },
  { "unstableTank", "Losing it (tank)" }, { "unstableDps", "Close to pulling (not the tank)" } }
function AL.Default(key) return DEFAULT[key] end
local function Label(kind, dps)
  local key = kind .. (dps and "Dps" or "Tank")
  local t = ns.db.alerts.text and ns.db.alerts.text[key]
  return (type(t) == "string" and t ~= "") and t or DEFAULT[key]
end

local frame, text, fade
local function Message(kind, dps, unit)
  if not frame then
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(600, 40); frame:SetPoint("TOP", 0, -170); frame:SetFrameStrata("HIGH")
    text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("CENTER")
    fade = frame:CreateAnimationGroup()
    local hold = fade:CreateAnimation("Alpha"); hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(1.5); hold:SetOrder(1)
    local out = fade:CreateAnimation("Alpha"); out:SetFromAlpha(1); out:SetToAlpha(0); out:SetDuration(0.6); out:SetOrder(2)
    fade:SetScript("OnFinished", function() frame:Hide() end)
  end
  local colors = dps and ns.db.colorsDps or ns.db.colors
  local c = colors[kind == "lost" and "nothreat" or "unstable"]
  text:SetTextColor(c[1], c[2], c[3])
  local label = Label(kind, dps)
  AL.lastLabel = label -- (tests, diagnostics)
  local name = unit and ns.db.alerts.withName and UnitName(unit)
  -- (the enemy's name may be hidden: the game draws it after the message, Holdfast never reads it,
  -- so it can't be placed inside the player's text)
  if ns.isSecret(name) or (name ~= nil and name ~= false) then text:SetFormattedText("%s: %s", label, name) else text:SetText(label) end
  fade:Stop(); frame:SetAlpha(1); frame:Show(); fade:Play()
end

local function OnChange(_, p)
  local a = ns.db.alerts
  if not (a.sound or a.screen) then return end
  if p.oldKind == "none" or p.oldKind == p.kind then return end
  if not ((p.kind == "lost" and a.onLost) or (p.kind == "unstable" and a.onUnstable)) then return end
  local now = GetTime()
  if now - last < GAP then return end
  last = now
  AL.shown = AL.shown + 1
  if a.sound then PlaySound(SOUND, "Master") end
  if a.screen then Message(p.kind, p.dps, p.unit) end
end
ns.Events.On("STATE_CHANGED", OnChange)

-- the settings' Test button
function AL.Test()
  local a = ns.db.alerts
  if a.sound then PlaySound(SOUND, "Master") end
  Message("lost", false, nil) -- (no enemy: just the words)
end
