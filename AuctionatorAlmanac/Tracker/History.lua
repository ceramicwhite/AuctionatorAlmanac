local ADDON, A = ...

-- Auctionator keeps `price_history_days` (21 by default) of daily prices. For
-- the items the player cares about (owned, traded, watched, recently viewed)
-- Almanac copies each day into its own saved data so graphs can reach back up
-- to a year. Everything else uses Auctionator's window only, which keeps the
-- saved data small.
local History = {}
A.History = History

local VIEWED_CAP = 200
local store

-- store.items[itemID] = { l = {[day]=low}, h = {[day]=high}, a = {[day]=qty} }  (numeric day keys)
function History.Init(db)
  store = db.history
end

function History.Reset()
  store.items, store.viewed, store.watched = {}, {}, {}
end

-- ---------------------------------------------------------------------------
-- Snapshot and read
-- ---------------------------------------------------------------------------
local function isEmpty(t)
  return next(t) == nil
end

local function prune(entry, cutoff)
  for _, field in ipairs({ "l", "h", "a" }) do
    for day in pairs(entry[field]) do
      if day < cutoff then entry[field][day] = nil end
    end
  end
  return isEmpty(entry.h) and isEmpty(entry.l)
end

-- Copies Auctionator's current days for every tracked item and drops days older
-- than keepDays. Returns the number of items updated.
function History.Snapshot(adapter, tracked, today, keepDays)
  local cutoff = today - keepDays
  local updated = 0
  for id in pairs(tracked) do
    local series = adapter.GetSeries(tostring(id))
    if series and #series.days > 0 then
      local entry = store.items[id]
      if not entry then
        entry = { l = {}, h = {}, a = {} }
        store.items[id] = entry
      end
      for _, d in ipairs(series.days) do
        entry.h[d.day] = d.high or d.low
        entry.l[d.day] = (d.low ~= (d.high or d.low)) and d.low or nil
        entry.a[d.day] = d.qty
      end
      updated = updated + 1
    end
  end
  for id, entry in pairs(store.items) do
    if prune(entry, cutoff) then store.items[id] = nil end
  end
  return updated
end

-- Same shape as Adapter.GetSeries (no `last`, since there is no live price here).
function History.Series(itemID)
  local entry = store.items[itemID]
  if not entry then return nil end
  local days = {}
  for day, high in pairs(entry.h) do days[#days + 1] = day end
  for day in pairs(entry.l) do
    if entry.h[day] == nil then days[#days + 1] = day end
  end
  if #days == 0 then return nil end
  table.sort(days)
  local out = {}
  for i, day in ipairs(days) do
    local high = entry.h[day]
    local low = entry.l[day] or high
    out[i] = { day = day, low = low, high = high or low, qty = entry.a[day] }
  end
  return { key = tostring(itemID), days = out }
end

-- ---------------------------------------------------------------------------
-- Viewed and watched
-- ---------------------------------------------------------------------------
function History.MarkViewed(itemID)
  local viewed = store.viewed
  for i = #viewed, 1, -1 do
    if viewed[i] == itemID then table.remove(viewed, i) end
  end
  table.insert(viewed, 1, itemID)
  for i = #viewed, VIEWED_CAP + 1, -1 do viewed[i] = nil end
end

function History.Viewed() return store.viewed end

function History.Watch(itemID, on)
  store.watched[itemID] = on and true or nil
end

function History.IsWatched(itemID) return store.watched[itemID] == true end

function History.Watched()
  local out = {}
  for id in pairs(store.watched) do out[#out + 1] = id end
  table.sort(out)
  return out
end

-- sets: array of tables whose keys are item IDs (ledger items, inventory totals, ...).
function History.TrackedIDs(sets)
  local tracked = {}
  for id in pairs(store.watched) do tracked[id] = true end
  for _, id in ipairs(store.viewed) do tracked[id] = true end
  for _, set in ipairs(sets or {}) do
    for id in pairs(set) do tracked[id] = true end
  end
  return tracked
end
