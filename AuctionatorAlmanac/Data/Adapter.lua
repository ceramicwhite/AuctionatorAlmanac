local ADDON, A = ...

-- The only file that knows how Auctionator stores its data. Everything here is
-- read-only: Almanac never writes into Auctionator's tables. Only
-- Auctionator.API.v1 is a promised-stable interface and it exposes just the
-- last price, so the saved tables are read directly and this module is the one
-- place to fix if Auctionator changes its format.
local Adapter = {}
A.Adapter = Adapter

local floor = math.floor

local function E() return A.env end

local function auctionator()
  local a = E().Auctionator
  if type(a) == "table" then return a end
end

-- ---------------------------------------------------------------------------
-- Readiness and access
-- ---------------------------------------------------------------------------
function Adapter.RealmData()
  local a = auctionator()
  if a and type(a.Database) == "table" and type(a.Database.db) == "table" then
    return a.Database.db
  end
  local all = E().AUCTIONATOR_PRICE_DATABASE
  local realm = a and a.State and a.State.CurrentRealm
  if type(all) == "table" and realm and type(all[realm]) == "table" then
    return all[realm]
  end
  return nil
end

function Adapter.IsReady()
  local a = auctionator()
  if not (a and type(a.State) == "table" and a.State.Loaded) then return false end
  return Adapter.RealmData() ~= nil
end

function Adapter.Realm()
  local a = auctionator()
  local realm = a and a.State and a.State.CurrentRealm
  if realm then return realm end
  local get = E().GetRealmName
  return get and get() or nil
end

function Adapter.HistoryDays()
  local a = auctionator()
  local config = a and a.Config
  if config and config.Get and config.Options and config.Options.PRICE_HISTORY_DAYS then
    local ok, value = pcall(config.Get, config.Options.PRICE_HISTORY_DAYS)
    if ok and tonumber(value) then return tonumber(value) end
  end
  return 21
end

-- ---------------------------------------------------------------------------
-- Keys
-- ---------------------------------------------------------------------------
-- "123" plain, "g:123:200" gear at item level 200, "gr:123:of Bear" legacy
-- suffix gear. Pet keys ("p:...") and anything else are not items we index.
function Adapter.ParseKey(key)
  if type(key) ~= "string" then return nil end
  local plain = key:match("^(%d+)$")
  if plain then return tonumber(plain), nil end
  local gid, ilvl = key:match("^g:(%d+):(%d+)$")
  if gid then return tonumber(gid), "g:" .. ilvl end
  local rid, suffix = key:match("^gr:(%d+):(.+)$")
  if rid then return tonumber(rid), "gr:" .. suffix end
  return nil
end

-- index.items[itemID] = { keys = {base first, then variants sorted}, base = "123"|nil }
function Adapter.BuildIndex()
  local index = { items = {}, count = 0 }
  local realm = Adapter.RealmData()
  if not realm then return index end
  for key, value in pairs(realm) do
    if type(value) == "table" then
      local id, variant = Adapter.ParseKey(key)
      if id then
        local item = index.items[id]
        if not item then
          item = { keys = {}, base = nil }
          index.items[id] = item
          index.count = index.count + 1
        end
        item.keys[#item.keys + 1] = key
        if not variant then item.base = key end
      end
    end
  end
  for _, item in pairs(index.items) do
    if #item.keys > 1 then
      local base = item.base
      table.sort(item.keys, function(a, b)
        if a == base then return b ~= base end
        if b == base then return false end
        return a < b
      end)
    end
  end
  return index
end

-- ---------------------------------------------------------------------------
-- Price series
-- ---------------------------------------------------------------------------
local function dayValue(t, day)
  if type(t) ~= "table" then return nil end
  local v = t[tostring(day)]
  if v == nil then v = t[day] end
  return v
end

-- { key, last, days = { {day, low, high, qty}... ascending } }
-- Auctionator only stores "l" on days where the low differs from "h", so the
-- daily low is l[day] or h[day]. "a" is missing in databases from before
-- December 2020.
function Adapter.GetSeries(key)
  local realm = Adapter.RealmData()
  local entry = realm and realm[key]
  if type(entry) ~= "table" then return nil end

  local seen, days = {}, {}
  for _, source in ipairs({ entry.h, entry.l }) do
    if type(source) == "table" then
      for dayKey in pairs(source) do
        local day = tonumber(dayKey)
        if day and not seen[day] then
          seen[day] = true
          days[#days + 1] = day
        end
      end
    end
  end
  table.sort(days)

  if #days == 0 and entry.m == nil then return nil end

  local out = {}
  for i, day in ipairs(days) do
    local high = dayValue(entry.h, day)
    local low = dayValue(entry.l, day) or high
    out[i] = { day = day, low = low, high = high or low, qty = dayValue(entry.a, day) }
  end
  return { key = key, last = entry.m, days = out }
end

-- ---------------------------------------------------------------------------
-- Time
-- ---------------------------------------------------------------------------
local function day0()
  local a = auctionator()
  local constants = a and a.Constants
  if constants and constants.SCAN_DAY_0 then return constants.SCAN_DAY_0 end
  local timeFn = E().time or os.time
  return timeFn({ year = 2020, month = 1, day = 1, hour = 0 })
end

function Adapter.DayToTime(day) return day0() + day * 86400 end
function Adapter.TimeToDay(t) return floor((t - day0()) / 86400) end

function Adapter.Today()
  local timeFn = E().time or os.time
  return Adapter.TimeToDay(timeFn())
end

-- Newest scan Auctionator recorded. `newestDay` (optional) is the newest day
-- present in the price data, used when no scan timestamp survives.
function Adapter.LastScan(newestDay)
  local a = auctionator()
  local state = E().AUCTIONATOR_SAVEDVARS or (a and a.SavedState)
  local browse, full
  if type(state) == "table" then
    browse = tonumber(state.TimeOfLastBrowseScan)
    local replicate = tonumber(state.TimeOfLastReplicateScan)
    local getAll = tonumber(state.TimeOfLastGetAllScan)
    full = math.max(replicate or 0, getAll or 0)
    if full == 0 then full = nil end
  end
  local result = { browse = browse, full = full }
  if browse or full then
    if (full or 0) >= (browse or 0) then
      result.time, result.kind = full, "full"
    else
      result.time, result.kind = browse, "browse"
    end
  elseif newestDay then
    result.time, result.kind = Adapter.DayToTime(newestDay), "data"
  end
  return result
end

-- ---------------------------------------------------------------------------
-- Other Auctionator data
-- ---------------------------------------------------------------------------
-- Auctions the player posted (not sales): { {time, price, quantity, bidPrice} } oldest first.
function Adapter.PostingHistory(itemID)
  local history = E().AUCTIONATOR_POSTING_HISTORY
  local out = {}
  if type(history) ~= "table" then return out end
  for key, rows in pairs(history) do
    if type(rows) == "table" and Adapter.ParseKey(key) == itemID then
      for _, row in ipairs(rows) do
        if type(row) == "table" and row.time then
          out[#out + 1] = { time = row.time, price = row.price, quantity = row.quantity, bidPrice = row.bidPrice }
        end
      end
    end
  end
  table.sort(out, function(x, y) return x.time < y.time end)
  return out
end

-- Every posting for every item: { {itemID, time, price, quantity, bidPrice} } oldest first.
function Adapter.AllPostings()
  local history = E().AUCTIONATOR_POSTING_HISTORY
  local out = {}
  if type(history) ~= "table" then return out end
  for key, rows in pairs(history) do
    local itemID = type(rows) == "table" and Adapter.ParseKey(key)
    if itemID then
      for _, row in ipairs(rows) do
        if type(row) == "table" and row.time and row.price then
          out[#out + 1] = {
            itemID = itemID, time = row.time, price = row.price,
            quantity = row.quantity or 1, bidPrice = row.bidPrice,
          }
        end
      end
    end
  end
  table.sort(out, function(x, y)
    if x.time ~= y.time then return x.time < y.time end
    return x.itemID < y.itemID
  end)
  return out
end

function Adapter.ShoppingLists()
  local lists = E().AUCTIONATOR_SHOPPING_LISTS
  local out = {}
  if type(lists) ~= "table" then return out end
  for _, list in ipairs(lists) do
    if type(list) == "table" and type(list.name) == "string" then
      local items = {}
      for _, term in ipairs(type(list.items) == "table" and list.items or {}) do
        if type(term) == "string" then items[#items + 1] = term end
      end
      out[#out + 1] = { name = list.name, items = items }
    end
  end
  return out
end

-- Shopping list entries are Auctionator advanced-search strings:
-- `"Exact Name";category;minilvl;...` (fields separated by ';').
function Adapter.ParseSearchTerm(term)
  local query = (tostring(term or ""):match("^([^;]*)")) or ""
  local quoted = query:match('^"(.*)"$')
  if quoted then return { query = quoted, exact = true } end
  return { query = query, exact = false }
end
