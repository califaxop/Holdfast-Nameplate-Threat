-- The threat overview (optional; settings: Overview, or /hf overview): a small window listing the
-- enemies on your nameplates, most dangerous first (red, then orange, then hidden, then green):
-- name, state, who it's attacking, threat % and how sure Holdfast is. Filters: all, only orange,
-- only red, attacking you, attacking others. Nothing is built or updated while it's off.
local _, ns = ...
local O = {}
ns.Overview = O

local MAX_ROWS = 10
local ROW_H, W = 16, 300
local RANK = { lost = 1, unstable = 2, hidden = 3, unknown = 4, secure = 5 }
local STATE_TEXT = {
  tank = { secure = "holding", unstable = "losing it", lost = "lost", hidden = "hidden", unknown = "?" },
  dps = { secure = "safe", unstable = "close", lost = "on you", hidden = "hidden", unknown = "?" },
}
local OWNER_TEXT = { player = "you", pet = "your pet", tank = "tank", member = "member", ["member pet"] = "a pet", unknown = "?" }
local FILTERS = {
  all = function() return true end,
  unstable = function(st) return st.kind == "unstable" end,
  lost = function(st) return st.kind == "lost" end,
  me = function(st) return st.ownerUnit == "player" end,
  others = function(st) return st.ownerUnit ~= nil and st.ownerUnit ~= "player" end,
}
O.FILTERS = { { "all", "All enemies" }, { "unstable", "Only orange" }, { "lost", "Only red" },
  { "me", "Attacking me" }, { "others", "Attacking others" } }

local win, rows, empty, ticker

local function Build()
  local UI = ns.UI
  win = CreateFrame("Frame", "HoldfastOverview", UIParent, "BackdropTemplate")
  win:SetSize(W, 40)
  win:SetFrameStrata("MEDIUM")
  win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton"); win:SetClampedToScreen(true)
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.db.overview.pos = { p, rp, x, y }
  end)
  local pos = ns.db.overview.pos
  if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else win:SetPoint("RIGHT", -60, 80) end
  UI.Skin(function() UI.SkinWindow(win, 0.85) end)
  local title = UI.Text(win, "title", "Threat")
  title:SetPoint("TOPLEFT", 10, -8)
  win.filterText = UI.Text(win, "note", "")
  win.filterText:SetPoint("LEFT", title, "RIGHT", 8, 0)
  local close = CreateFrame("Button", nil, win)
  close:SetSize(18, 18); close:SetPoint("TOPRIGHT", -4, -4)
  local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  x:SetPoint("CENTER"); x:SetText("\195\151")
  close:SetScript("OnClick", function() O.Show(false) end)
  rows = {}
  for i = 1, MAX_ROWS do
    local r = {}
    local y = -28 - (i - 1) * ROW_H
    for _, col in ipairs({ { "name", 10, 110, "LEFT" }, { "state", 124, 62, "LEFT" }, { "owner", 190, 60, "LEFT" },
      { "pct", 250, 40, "RIGHT" } }) do
      local fs = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("TOPLEFT", col[2], y); fs:SetWidth(col[3]); fs:SetJustifyH(col[4]); fs:SetWordWrap(false)
      r[col[1]] = fs
    end
    rows[i] = r
  end
  empty = UI.Text(win, "note", "No enemies engaged.")
  empty:SetPoint("TOPLEFT", 10, -28)
end

-- the list, now (twice a second while shown, and on every state change)
function O.Refresh()
  if not (win and win:IsShown()) then return end
  local filter = FILTERS[ns.db.overview.filter] or FILTERS.all
  local list = {}
  for unit in ns.Registry.Each() do
    local st = ns.State.Get(unit)
    if st and RANK[st.kind] and filter(st) then list[#list + 1] = { unit = unit, st = st } end
  end
  -- most dangerous first; then a readable % (higher first); else by nameplate
  table.sort(list, function(a, b)
    local ra, rb = RANK[a.st.kind], RANK[b.st.kind]
    if ra ~= rb then return ra < rb end
    local pa, pb = a.st.percentage, b.st.percentage
    if type(pa) == "number" and type(pb) == "number" and not ns.isSecret(pa) and not ns.isSecret(pb) and pa ~= pb then return pa > pb end
    return a.unit < b.unit
  end)
  for i, r in ipairs(rows) do
    local e = list[i]
    for _, fs in pairs(r) do fs:SetShown(e ~= nil) end
    if e then
      local st, dps = e.st, e.st.dps
      local name = UnitName(e.unit)
      if ns.isSecret(name) or name ~= nil then r.name:SetFormattedText("%s", name) else r.name:SetText("?") end -- (a hidden name: drawn by the game)
      r.state:SetText(STATE_TEXT[dps and "dps" or "tank"][st.kind] or st.kind)
      local colors = dps and ns.db.colorsDps or ns.db.colors
      local c = colors[st.kind == "secure" and "aggro" or st.kind == "unstable" and "unstable" or st.kind == "lost" and "nothreat" or ""]
      if c then r.state:SetTextColor(c[1], c[2], c[3]) else r.state:SetTextColor(0.7, 0.7, 0.7) end
      r.owner:SetText((OWNER_TEXT[st.ownership] or "?") .. (st.ownerObserved == false and "*" or ""))
      local pct = st.percentage
      if ns.isSecret(pct) then r.pct:SetFormattedText("%.0f%%", pct)
      elseif type(pct) == "number" then r.pct:SetFormattedText("%.0f%%", math.min(100, math.max(0, pct)))
      else r.pct:SetText(st.confidence == "state" and "" or "-") end
    end
  end
  empty:SetShown(#list == 0)
  for _, f in ipairs(O.FILTERS) do if f[1] == ns.db.overview.filter then win.filterText:SetText(f[2]) end end
  win:SetHeight(36 + math.max(1, math.min(#list, MAX_ROWS)) * ROW_H)
end

-- shown or not (the setting); building it the first time it's shown
function O.Show(on)
  ns.db.overview.show = on and true or false
  if on then
    if not win then Build() end
    win:Show()
    if not ticker then ticker = C_Timer.NewTicker(0.5, O.Refresh) end
    O.Refresh()
  else
    if win then win:Hide() end
    if ticker then ticker:Cancel(); ticker = nil end
  end
end
function O.IsShown() return win ~= nil and win:IsShown() end

ns.Events.On("STATE_CHANGED", function() if win and win:IsShown() then O.Refresh() end end)
