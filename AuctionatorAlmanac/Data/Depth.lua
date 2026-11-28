local ADDON, A = ...

-- How many of an item were listed at its lowest price. Auctionator saves the lowest price and how many were listed
-- in all, but not how many sat at that lowest price. Every scan it makes (full scan, browse scan, classic search
-- results) hands Auctionator.Database:ProcessScan the unit price and size of each auction, then saves each item with
-- Database:SetPrice(key, lowest, listed). Almanac listens to both: it hears ProcessScan before Auctionator runs it (some
-- versions of Auctionator save every key inside ProcessScan, others over the following frames), and when SetPrice saves a
-- key from that scan, with the lowest price and total its auctions give, it keeps the count at the lowest price beside it.
-- Any other SetPrice (a posting, a one-item search) changed the price behind Almanac's back, so the count for that key
-- is forgotten. A record therefore always describes the save that set Auctionator's current price for the key.
-- Records are kept per realm, like Auctionator's prices. Auctionator's tables are only read.
local Depth = {}
A.Depth = Depth

Depth.ANNOUNCE_DELAY = 1     -- seconds: changes are announced (DEPTH_UPDATED) at most this often

local root                   -- ALMANAC_DB.depth: { realms = { [realm] = { [dbKey] = "price,atLowest,total,day" } } }
local parsed = {}            -- [realm] = { [dbKey] = { price, atLowest, total, day } | false }, read from the strings
local hooked = {}            -- [function] = true for the Auctionator methods that call Almanac back
local scanning               -- the scan Auctionator is saving: { scan, saved = {[key] = true}, left = keys not yet saved, realm, day }
local announcing = false

function Depth.Init(db)
  if type(db.depth) ~= "table" then db.depth = {} end
  if type(db.depth.realms) ~= "table" then db.depth.realms = {} end
  root = db.depth
  parsed, scanning, announcing = {}, nil, false
end

local function currentRealm() return A.Adapter.Realm() or "?" end

-- One key's auctions, as Auctionator hands them over: { {price = unit price, available = count}, ... }.
-- Returns the lowest unit price, how many were listed at it, and how many were listed in all, computed the way
-- Auctionator computes its own lowest price and quantity from the same list; nil when the list has no prices.
function Depth.Summarize(entries)
  if type(entries) ~= "table" then return nil end
  local low, atLow, total
  for _, entry in ipairs(entries) do
    local price = type(entry) == "table" and tonumber(entry.price)
    if price then
      local count = tonumber(entry.available) or 0
      total = (total or 0) + count
      if not low or price < low then
        low, atLow = price, count
      elseif price == low then
        atLow = atLow + count
      end
    end
  end
  return low, atLow, total
end

local function parse(text)
  if type(text) ~= "string" then return nil end
  local price, atLow, total, day = text:match("^([^,]+),([^,]+),([^,]+),([^,]+)$")
  price, atLow, total, day = tonumber(price), tonumber(atLow), tonumber(total), tonumber(day)
  if price and atLow and total and day then return { price, atLow, total, day } end
  return nil
end

-- price, atLowest, total, day for an Auctionator key on this realm (or `realm`), or nil when Almanac has no count.
function Depth.Get(key, realm)
  realm = realm or currentRealm()
  local cache = parsed[realm]
  if not cache then
    cache = {}
    parsed[realm] = cache
  end
  local record = cache[key]
  if record == nil then
    local keys = root and root.realms[realm]
    record = (keys and parse(keys[key])) or false
    cache[key] = record
  end
  if record then return record[1], record[2], record[3], record[4] end
  return nil
end

-- How many keys have a count on this realm.
function Depth.Count()
  local n = 0
  for _ in pairs((root and root.realms[currentRealm()]) or {}) do n = n + 1 end
  return n
end

local function set(realm, key, text)
  if not root then return end
  local keys = root.realms[realm]
  if not keys then
    if text == nil then return end
    keys = {}
    root.realms[realm] = keys
  end
  keys[key] = text
  local cache = parsed[realm]
  if cache then cache[key] = nil end
end

-- One DEPTH_UPDATED for a burst of changes.
local function announce()
  if announcing then return end
  announcing = true
  A.After(Depth.ANNOUNCE_DELAY, function()
    announcing = false
    A.Bus.Fire("DEPTH_UPDATED")
  end)
end

-- Auctionator is about to save `scan`: { [dbKey] = { {price, available}, ... } }. Its saves of these keys come next,
-- over the following frames. A newer scan replaces an older one: Auctionator stops saving the older one when it starts.
function Depth.OnScan(scan)
  if not root or type(scan) ~= "table" then return end
  local left = 0
  for _ in pairs(scan) do left = left + 1 end
  scanning = left > 0 and { scan = scan, saved = {}, left = left, realm = currentRealm(), day = A.Adapter.Today() } or nil
end

-- Auctionator saved `price` (and `listed`, when it knows it) as the lowest price for `key`.
function Depth.OnPrice(key, price, listed)
  if not root or type(key) ~= "string" then return end
  local s = scanning
  local entries = s and not s.saved[key] and s.scan[key]
  if entries then
    s.saved[key] = true             -- a second save of the same key is not the scan's: it falls through to below next time
    s.left = s.left - 1
    if s.left <= 0 then scanning = nil end
    local low, atLow, total = Depth.Summarize(entries)
    if low ~= nil and low == price and total == listed then
      set(s.realm, key, table.concat({ low, atLow, total, s.day }, ","))
    else
      set(s.realm, key, nil)
    end
    if not scanning then announce() end           -- the whole scan is saved
  else
    -- a price Almanac did not see the auctions behind: its count, if any, no longer belongs to the current price
    local realm = currentRealm()
    if Depth.Get(key, realm) then
      set(realm, key, nil)
      announce()
    end
  end
end

-- Forget records from before `cutoffDay` (Auctionator's own history window), on every realm; they describe markets
-- long gone. Returns how many went.
function Depth.Prune(cutoffDay)
  if not root or not cutoffDay then return 0 end
  local removed = 0
  for realm, keys in pairs(root.realms) do
    if type(keys) ~= "table" then
      root.realms[realm] = nil
    else
      for key, text in pairs(keys) do
        local day = type(text) == "string" and tonumber(text:match(",([^,]+)$"))
        if not day or day < cutoffDay then
          keys[key] = nil
          removed = removed + 1
        end
      end
      if next(keys) == nil then root.realms[realm] = nil end
    end
  end
  if removed > 0 then parsed = {} end
  return removed
end

function Depth.Reset()
  if root then root.realms = {} end
  parsed, scanning = {}, nil
end

-- An error here must never break Auctionator, which called us; it is reported instead.
local function report(err)
  local getHandler = A.env.geterrorhandler
  local handler = getHandler and getHandler()
  if handler then handler(err) end
end

local function onScan(_, scan)
  local ok, err = pcall(Depth.OnScan, scan)
  if not ok then report(err) end
end

local function onPrice(_, key, price, listed)
  local ok, err = pcall(Depth.OnPrice, key, price, listed)
  if not ok then report(err) end
end

-- SetPrice: Almanac hears it after Auctionator has saved the price (hooksecurefunc).
local function hookAfter(t, name, fn, hook)
  if type(t) ~= "table" or type(t[name]) ~= "function" or hooked[t[name]] then return end
  if pcall(hook, t, name, fn) and type(t[name]) == "function" then hooked[t[name]] = true end
end

-- ProcessScan: Almanac must hear it before Auctionator runs it, since Auctionator may save every key inside the call.
-- Auctionator's own method runs unchanged right after, with the same arguments, and its results are returned.
local function hookBefore(t, name, fn)
  local original = type(t) == "table" and t[name]
  if type(original) ~= "function" or hooked[original] then return end
  local wrapper = function(self, ...)
    fn(self, ...)
    return original(self, ...)
  end
  hooked[wrapper] = true
  t[name] = wrapper
end

-- Hook ProcessScan and SetPrice on Auctionator's DatabaseMixin, which every Database object Auctionator makes (at login,
-- and again after some of its slash commands) copies its methods from, and on the Database object if one already
-- exists. A Database made from the hooked mixin carries the hooked methods already and is not hooked twice. Safe to
-- call any number of times.
function Depth.Install()
  local auctionator, hook = A.env.Auctionator, A.env.hooksecurefunc
  if type(auctionator) ~= "table" or type(hook) ~= "function" then return false end
  for _, t in ipairs({ auctionator.DatabaseMixin, auctionator.Database }) do
    hookBefore(t, "ProcessScan", onScan)
    hookAfter(t, "SetPrice", onPrice, hook)
  end
  return Depth.Status() ~= "missing"
end

local function listening(t)
  return type(t) == "table" and type(t.ProcessScan) == "function" and type(t.SetPrice) == "function"
    and hooked[t.ProcessScan] and hooked[t.SetPrice] and true or false
end

-- "ok" (the Database Auctionator uses reports its scans here), "waiting" (the mixin is hooked; Auctionator has not
-- made its Database yet) or "missing" (this Auctionator has nothing to listen to, or the client no hooks).
function Depth.Status()
  local auctionator = A.env.Auctionator
  if type(auctionator) ~= "table" then return "missing" end
  if type(auctionator.Database) == "table" then return listening(auctionator.Database) and "ok" or "missing" end
  return listening(auctionator.DatabaseMixin) and "waiting" or "missing"
end
