-- Unit Registry: tracks visible nameplates and their unit tokens.
local _, ns = ...
local R = {}
ns.Registry = R

local byUnit = {}   -- "nameplate3" -> plate frame

-- (the second argument, includeForbidden, is false: an addon can't draw on forbidden plates)
local function Lookup(unit)
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit, false)
  if ok and plate and not (plate.IsForbidden and plate:IsForbidden()) then return plate end
end

function R.Add(unit)
  local plate = Lookup(unit)
  byUnit[unit] = plate
  return plate
end

function R.Remove(unit)
  local plate = byUnit[unit]
  byUnit[unit] = nil
  return plate
end

function R.Get(unit) return byUnit[unit] end

-- Rebuild from the client (e.g. after /reload or a zone change).
function R.Scan()
  wipe(byUnit)
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit and not (plate.IsForbidden and plate:IsForbidden()) then byUnit[unit] = plate end
  end
end

function R.Each() return pairs(byUnit) end
