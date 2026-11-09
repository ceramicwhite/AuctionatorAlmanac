local ADDON, A = ...

-- "New finds": items Auctionator saw for the very first time on the latest scan.
--
-- Auctionator only keeps ~21 days, so an item it forgot and later sees again would
-- look brand new. Almanac therefore remembers the first day it ever saw each item
-- (store.first). Nothing on or before the first day of data (store.floor) can be
-- called new, because we cannot know when those items first appeared.
--
-- A big caution is built in: if the previous scans only covered part of the
-- Auction House (say one category), the first full scan makes thousands of old
-- items look new. Each find is therefore given a confidence from how much of its
-- own category is new at once: a rare drop in a category that is 2% new is
-- believable; "everything in Armor is new" means Armor was not scanned before.
local Discovery = {}
A.Discovery = Discovery

Discovery.PARTIAL_RATIO = 0.35     -- more than this share of a scan being new is suspicious
Discovery.PARTIAL_MIN_SEEN = 20    -- ...but only worth saying for a scan of some size
local SMOOTHING = 5                -- pseudo-items of the overall ratio mixed into small categories

local store

function Discovery.Init(db)
  store = db.discovery
end

function Discovery.Reset()
  store.first, store.floor = {}, nil
end

function Discovery.FirstSeen(id) return store.first[id] end
function Discovery.Floor() return store.floor end

function Discovery.Count()
  local n = 0
  for _ in pairs(store.first) do n = n + 1 end
  return n
end

-- summaries = { [itemID] = { firstDay, ... } } as Controller builds them; oldestDay is the
-- earliest day present anywhere in Auctionator's data.
function Discovery.Observe(summaries, oldestDay)
  if not oldestDay then return end
  if store.floor == nil then store.floor = oldestDay end
  local first = store.first
  for id, s in pairs(summaries) do
    local day = s.firstDay
    if day then
      local have = first[id]
      if have == nil or day < have then first[id] = day end
    end
  end
end

local function labelFor(score)
  if score >= A.Stats.CONF_HIGH then return "high" end
  if score >= A.Stats.CONF_MEDIUM then return "medium" end
  return "low"
end

-- opts.window    days before the newest scan day that still count as new (0 = the last scan only)
-- opts.classOf   function(itemID) -> item class, to judge each find against its own category
-- opts.className function(class) -> readable category name
-- Returns { rows = { {id, s, first, conf} }, seen, newCount, partial, needsHistory }.
function Discovery.NewFinds(summaries, newestDay, opts)
  opts = opts or {}
  local result = { rows = {}, seen = 0, newCount = 0, partial = false, needsHistory = false }
  if not newestDay then return result end
  local floor = store.floor
  if floor == nil or floor >= newestDay then
    result.needsHistory = true
    return result
  end

  local window = opts.window or 0
  local since = newestDay - window
  local classOf = opts.classOf or function() return nil end

  local total, fresh = {}, {}
  local candidates = {}
  for id, s in pairs(summaries) do
    if s.lastDay and s.lastDay >= since then
      local class = classOf(id) or "?"
      total[class] = (total[class] or 0) + 1
      result.seen = result.seen + 1
      local first = store.first[id] or s.firstDay
      if first and first > floor and first >= since and first <= newestDay then
        fresh[class] = (fresh[class] or 0) + 1
        candidates[#candidates + 1] = { id = id, s = s, first = first, class = class }
      end
    end
  end
  table.sort(candidates, function(a, b) return a.id < b.id end)
  result.newCount = #candidates

  local overall = result.seen > 0 and result.newCount / result.seen or 0
  result.partial = result.seen >= Discovery.PARTIAL_MIN_SEEN and overall >= Discovery.PARTIAL_RATIO

  for _, c in ipairs(candidates) do
    local n, newInClass = total[c.class], fresh[c.class] or 0
    local ratio = (newInClass + SMOOTHING * overall) / (n + SMOOTHING)
    local score = math.max(0, math.min(100, math.floor((1 - ratio) * 100 + 0.5)))
    local name = (c.class ~= "?" and opts.className and opts.className(c.class)) or "its category"
    local reason
    if score < A.Stats.CONF_MEDIUM then
      reason = string.format("%d of %d items in %s are new today, so it has probably not been scanned before",
        newInClass, n, name)
    else
      reason = string.format("Only %d of %d items in %s are new, so this one really is", newInClass, n, name)
    end
    result.rows[#result.rows + 1] = {
      id = c.id, s = c.s, first = c.first, class = c.class,
      conf = { score = score, label = labelFor(score), reasons = { reason } },
    }
  end
  return result
end
