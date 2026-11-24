local ADDON, A = ...

-- A copy of Auctionator's prices for the Almanac website. When the game saves (logging out or /reload) the
-- whole market is written into this addon's own saved file as a compact block, so one file is all a player
-- uploads. The block is made at PLAYER_LOGOUT and replaced each time; if Auctionator's data is not loaded at
-- that moment the previous block is kept, never wiped.
--
-- ALMANAC_DB.export = {
--   format = 1, generatedAt = <unix>, addon = "1.3.0", realm = "...", faction = "Horde"|"Alliance"|nil,
--   character = "Name-Realm", house = nil (reserved: "faction" | "neutral"), today = <Auctionator day>,
--   market = { ["19019"] = "last|day,low,high,qty;day,low,high,qty", ["g:123:200"] = "..." },
-- }
-- A price list is one string, not nested tables: far smaller in the file and quick for the game to load.
local Export = {}
A.Export = Export

Export.FORMAT = 1
Export.last = nil   -- what the most recent build found: { items, skipped, at } or { error }

local function whole(v)
  return string.format("%.0f", v)
end

-- series = { last, days = { {day, low, high, qty} ... } } (see Adapter.GetSeries) -> "last|day,low,high,qty;..."
function Export.Pack(series)
  local parts = {}
  for i, d in ipairs(series.days or {}) do
    parts[i] = whole(d.day) .. "," .. whole(d.low) .. "," .. whole(d.high or d.low) .. "," .. (d.qty and whole(d.qty) or "")
  end
  return (series.last and whole(series.last) or "") .. "|" .. table.concat(parts, ";")
end

local function addonVersion()
  local env = A.env
  local get = (env.C_AddOns and env.C_AddOns.GetAddOnMetadata) or env.GetAddOnMetadata
  if not get then return nil end
  local ok, version = pcall(get, ADDON, "Version")
  return ok and version or nil
end

local function now()
  local f = A.env.time
  return f and f() or 0
end

-- Returns the block, or nil and a reason. Never changes saved data.
function Export.Build()
  if not A.Adapter.IsReady() then
    return nil, "Auctionator's saved prices are not loaded"
  end
  local data = A.Adapter.RealmData()
  if not data then return nil, "Auctionator's saved prices are not loaded" end

  local market, items, skipped = {}, 0, 0
  for key, value in pairs(data) do
    if type(value) == "table" and A.Adapter.ParseKey(key) then
      local ok, series = pcall(A.Adapter.GetSeries, key)
      if ok then
        if series then
          local packedOk, packed = pcall(Export.Pack, series)
          if packedOk then
            market[key] = packed
            items = items + 1
          else
            skipped = skipped + 1
          end
        end
      else
        skipped = skipped + 1
      end
    end
  end

  local identity = A.Tracker and A.Tracker.Identity and A.Tracker.Identity() or nil
  local at = now()
  Export.last = { items = items, skipped = skipped, at = at }
  return {
    format = Export.FORMAT,
    generatedAt = at,
    addon = addonVersion(),
    realm = A.Adapter.Realm(),
    faction = identity and identity.faction or nil,
    character = identity and (identity.name .. "-" .. identity.realm) or nil,
    house = nil,
    today = A.Adapter.Today(),
    market = market,
  }
end

-- "written" | "kept" (nothing new could be built, the old block stays) | "off"
function Export.Write()
  if not A.db then return "kept" end
  if A.Get("siteExport") == false then
    A.db.export = nil
    return "off"
  end
  local ok, block, reason = pcall(Export.Build)
  if not ok then
    Export.last = { error = tostring(block) }
    return "kept"
  end
  if not block then
    Export.lastReason = reason
    return "kept"
  end
  A.db.export = block
  return "written"
end

local function when(t)
  return t and A.Format.DateTime(t) or "an unknown time"
end

-- One line for /almanac debug.
function Export.DebugLine()
  if A.Get("siteExport") == false then return "Website export: off" end
  local saved = A.db and A.db.export
  local last = Export.last
  if last and last.items then
    return string.format("Website export: on (%d items built this session%s)", last.items,
      last.skipped > 0 and (", " .. last.skipped .. " skipped") or "")
  end
  if last and last.error then return "Website export: on, but the last build failed: " .. last.error end
  if saved then return "Website export: on (the saved file has one from " .. when(saved.generatedAt) .. ")" end
  return "Website export: on (nothing built yet; it is written when you log out or /reload)"
end

-- Lines for /almanac export: what the next save will contain.
function Export.Describe()
  if A.Get("siteExport") == false then
    return { "Website export is off. Turn it on in Options to include prices in the saved file." }
  end
  local lines = {}
  local ok, block, reason = pcall(Export.Build)
  if ok and block then
    lines[1] = string.format("The next save (log out or /reload) will include %d items from %s%s.", Export.last.items,
      tostring(block.realm), block.faction and (" (" .. block.faction .. ")") or "")
    lines[2] = "Then upload WTF\\Account\\<your account>\\SavedVariables\\AuctionatorAlmanac.lua on the Almanac website."
  else
    local why = ok and reason or tostring(block)
    local saved = A.db and A.db.export
    lines[1] = tostring(why) .. ", so the saved file keeps "
      .. (saved and ("the export from " .. when(saved.generatedAt)) or "no export yet") .. "."
  end
  return lines
end

A.RegisterEvent("PLAYER_LOGOUT", function() Export.Write() end)
