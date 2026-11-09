local ADDON, A = ...

local F = {}
A.Format = F

local DASH = "—"
local floor = math.floor

local COLOR = {
  gold = "ffd700", silver = "c7c7cf", copper = "eda55f",
  up = "5fd35f", down = "ff6a5a", flat = "8a8a8a",
}
F.COLOR = COLOR

-- ---------------------------------------------------------------------------
-- Money
-- ---------------------------------------------------------------------------
-- opts.plain: no color codes. opts.short: at most the two most significant
-- units (123g 45s), for narrow columns.
function F.Money(copper, opts)
  if copper == nil then return DASH end
  opts = opts or {}
  local negative = copper < 0
  local c = floor(math.abs(copper))
  local units = {
    { floor(c / 10000), "g", COLOR.gold },
    { floor((c % 10000) / 100), "s", COLOR.silver },
    { c % 100, "c", COLOR.copper },
  }

  local first, last = 3, 3
  for i = 1, 3 do
    if units[i][1] ~= 0 then first = i; break end
  end
  for i = 3, 1, -1 do
    if units[i][1] ~= 0 then last = i; break end
  end
  if last < first then last = first end
  if opts.short and last > first + 1 then last = first + 1 end
  while last > first and units[last][1] == 0 do last = last - 1 end

  local parts = {}
  for i = first, last do
    local text = string.format("%d%s", units[i][1], units[i][2])
    if not opts.plain then text = "|cff" .. units[i][3] .. text .. "|r" end
    parts[#parts + 1] = text
  end
  return (negative and "-" or "") .. table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------
-- Time
-- ---------------------------------------------------------------------------
function F.Ago(seconds)
  if seconds == nil then return "never" end
  local s = floor(math.max(seconds, 0))
  if s < 60 then return s .. "s" end
  if s < 3600 then return floor(s / 60) .. "m" end
  if s < 86400 then
    local h, m = floor(s / 3600), floor((s % 3600) / 60)
    return m > 0 and (h .. "h " .. m .. "m") or (h .. "h")
  end
  local d, h = floor(s / 86400), floor((s % 86400) / 3600)
  return h > 0 and (d .. "d " .. h .. "h") or (d .. "d")
end

-- A short age for narrow columns: "now", minutes under an hour, then only the biggest unit
-- (1h, 15h, 2d, 1w, 3mo, 1y), never "15h 20m".
function F.AgoShort(seconds)
  if seconds == nil then return "never" end
  local s = floor(math.max(seconds, 0))
  if s < 60 then return "now" end
  if s < 3600 then return floor(s / 60) .. "m" end
  if s < 86400 then return floor(s / 3600) .. "h" end
  if s < 7 * 86400 then return floor(s / 86400) .. "d" end
  if s < 30 * 86400 then return floor(s / (7 * 86400)) .. "w" end
  if s < 365 * 86400 then return math.max(1, floor(s / 2629800)) .. "mo" end    -- 2629800s = a month
  return floor(s / (365 * 86400)) .. "y"
end

-- fresh < 6h, ok < 24h, stale < 72h, old otherwise (or unknown)
function F.Freshness(seconds)
  if seconds == nil then return "old" end
  if seconds < 6 * 3600 then return "fresh" end
  if seconds < 24 * 3600 then return "ok" end
  if seconds < 72 * 3600 then return "stale" end
  return "old"
end

local function dateFn()
  return A.env.date or (os and os.date)
end

function F.Date(t)
  local d = dateFn()
  if not d or not t then return DASH end
  return (d("%b %d", t):gsub("^(%a+) 0", "%1 "))
end

function F.DateTime(t)
  local d = dateFn()
  if not d or not t then return DASH end
  return (d("%b %d %H:%M", t):gsub("^(%a+) 0", "%1 "))
end

-- ---------------------------------------------------------------------------
-- Numbers
-- ---------------------------------------------------------------------------
local function whole(ratio)
  local pct = ratio * 100
  local n = floor(math.abs(pct) + 0.5)
  return (pct < 0) and -n or n
end

function F.Percent(ratio)
  if ratio == nil then return DASH end
  local n = whole(ratio)
  if n == 0 then return "0%" end
  return (n > 0 and "+" or "-") .. math.abs(n) .. "%"
end

-- Percent colored by direction: green up, red down, grey flat or unknown.
function F.Change(ratio)
  if ratio == nil then return "|cff" .. COLOR.flat .. DASH .. "|r" end
  local n = whole(ratio)
  local color = n > 0 and COLOR.up or (n < 0 and COLOR.down or COLOR.flat)
  return "|cff" .. color .. F.Percent(ratio) .. "|r"
end

function F.Count(n)
  if n == nil then return DASH end
  local s = string.format("%d", floor(math.abs(n)))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  out = out:gsub("^,", "")
  return (n < 0 and "-" or "") .. out
end

-- ---------------------------------------------------------------------------
-- Item quality colors (Blizzard's standard values, independent of any API)
-- ---------------------------------------------------------------------------
local QUALITY_HEX = {
  [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee",
  [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff", [8] = "00ccff",
}

function F.QualityColor(quality)
  local hex = QUALITY_HEX[quality] or QUALITY_HEX[1]
  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  return r, g, b, hex
end

function F.ColorName(name, quality)
  local _, _, _, hex = F.QualityColor(quality)
  return "|cff" .. hex .. tostring(name) .. "|r"
end
