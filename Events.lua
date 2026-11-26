-- Threat transition events: what changed on an enemy, for Holdfast's alerts and overview, and for
-- other addons (HoldfastAPI). Payloads never carry a hidden value: a % is included only when it's
-- readable.
--
--   STATE_CHANGED     any change of an enemy's state or of who it's attacking
--   AGGRO_GAINED      it's now attacking you          AGGRO_LOST      it was attacking you, and isn't
--   PET_AGGRO_GAINED  it's now attacking your pet     PET_AGGRO_LOST  it was attacking your pet, and isn't
--   THREAT_UNSTABLE   it turned unstable (orange)     THREAT_SECURE   back to secure from unstable or lost
--   TARGET_CHANGED    you targeted another enemy (or none): its state, if it has a nameplate
--   UNIT_UNTRACKABLE  the game started hiding its state (or gave no usable answer)
--
-- Payload: { unit, kind, oldKind, ownership, ownerUnit, observed, dps, confidence, percentage? }
local _, ns = ...
local E = { counts = {} }
ns.Events = E

E.NAMES = { "STATE_CHANGED", "AGGRO_GAINED", "AGGRO_LOST", "PET_AGGRO_GAINED", "PET_AGGRO_LOST",
  "THREAT_UNSTABLE", "THREAT_SECURE", "TARGET_CHANGED", "UNIT_UNTRACKABLE" }

local listeners, nextHandle = {}, 0

-- E.On(event, fn) -> handle; fn(event, payload). E.Off(handle) stops it.
function E.On(event, fn)
  if type(fn) ~= "function" then return nil end
  nextHandle = nextHandle + 1
  listeners[event] = listeners[event] or {}
  listeners[event][nextHandle] = fn
  return nextHandle
end
function E.Off(handle)
  for _, l in pairs(listeners) do l[handle] = nil end
end

-- one enemy's state as an event payload (a copy, without hidden values)
function E.Payload(unit, st, old)
  local p = { unit = unit, kind = st and st.kind or "none", oldKind = old and old.kind or "none",
    ownership = st and st.ownership, ownerUnit = st and st.ownerUnit, observed = st and st.ownerObserved or false,
    dps = st and st.dps or false, confidence = st and st.confidence or "none" }
  local pct = st and st.percentage
  if type(pct) == "number" and not ns.isSecret(pct) then p.percentage = pct end
  return p
end

function E.Fire(event, payload)
  E.counts[event] = (E.counts[event] or 0) + 1
  for _, fn in pairs(listeners[event] or {}) do
    local ok, err = pcall(fn, event, payload)
    if not ok and ns.debug then ns.Dbg("listener error (" .. event .. "):", tostring(err)) end
  end
end

local UNTRACKED = { hidden = true, unknown = true }

-- From one enemy's old state to its new one (ThreatState calls this on every change).
function E.Transition(unit, old, new)
  local p = E.Payload(unit, new, old)
  E.Fire("STATE_CHANGED", p)
  local was, now = old and old.ownerUnit, new.ownerUnit
  if now == "player" and was ~= "player" then E.Fire("AGGRO_GAINED", p)
  elseif was == "player" and now ~= "player" then E.Fire("AGGRO_LOST", p) end
  if now == "pet" and was ~= "pet" then E.Fire("PET_AGGRO_GAINED", p)
  elseif was == "pet" and now ~= "pet" then E.Fire("PET_AGGRO_LOST", p) end
  local ok, nk = old and old.kind, new.kind
  if nk == "unstable" and ok ~= "unstable" then E.Fire("THREAT_UNSTABLE", p) end
  if nk == "secure" and (ok == "unstable" or ok == "lost") then E.Fire("THREAT_SECURE", p) end
  if UNTRACKED[nk] and not UNTRACKED[ok] then E.Fire("UNIT_UNTRACKABLE", p) end
end

-- For other addons: HoldfastAPI.RegisterCallback(event, fn) -> handle, UnregisterCallback(handle),
-- GetState(unit) -> payload for a nameplate unit ("nameplate3") or nil, Events (the names).
HoldfastAPI = {
  RegisterCallback = E.On,
  UnregisterCallback = E.Off,
  GetState = function(unit)
    local st = ns.State and ns.State.Get(unit)
    return st and E.Payload(unit, st) or nil
  end,
  Events = E.NAMES,
}
