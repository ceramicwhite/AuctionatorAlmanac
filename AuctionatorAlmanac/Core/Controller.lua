local ADDON, A = ...

-- The state and data layer behind the window: which items exist, their price
-- summaries, the current search / category / filters / sort, the selection.
-- It owns no widgets; the UI listens to its Bus events:
--   DATA_UPDATED, DATA_RELOADED, RESULTS_UPDATED, SELECTION_CHANGED
local Controller = {}
A.Controller = Controller

local CHUNK = 1500      -- most items summarised in one frame...
local BUDGET_MS = 6      -- ...and no more than this much time per frame
local SEARCH_DEBOUNCE = 0.12

local function defaults()
  return {
    text = "", category = nil, quality = nil, ownedOnly = false, recent = nil,
    minPrice = nil, maxPrice = nil, priceKey = nil, moved = nil,
    sortKey = "name", asc = true, selected = nil,
  }
end

Controller.state = defaults()
Controller.ready = false
Controller.ids, Controller.results, Controller.summaries = {}, {}, {}
Controller.newestDay, Controller.oldestDay = nil, nil
Controller.pricedCount = 0

local index
local tree
local generation = 0
local scanStamp
local refreshQueued = false
local orderCache = {}     -- [sortKey .. direction] = all ids in that order

-- ---------------------------------------------------------------------------
-- Accessors
-- ---------------------------------------------------------------------------
function Controller.Info(id) return A.Items.Get(id) end
function Controller.Summary(id) return Controller.summaries[id] end
function Controller.Owned(id) return A.Inventory.Totals()[id] or 0 end
function Controller.PriceOf(id)
  local s = Controller.summaries[id]
  return s and s.last or nil
end
function Controller.VendorOf(id)
  local info = A.Items.Get(id)
  return info and info.sell or nil
end
function Controller.LastScan() return A.Adapter.LastScan(Controller.newestDay) end
function Controller.Realm() return A.Adapter.Realm() end
function Controller.Today() return A.Adapter.Today() end
function Controller.Variants(id)
  local item = index and index.items[id]
  return item and item.keys or {}
end

-- onAH, atLowest, fromScan: how many were listed, how many of those at the lowest price (nil when unknown), and
-- whether both come from the scan that set the item's price. Almanac's record of that scan (Data/Depth.lua) is used
-- while its price is still the price shown for the item (the summaries are rebuilt after a scan only when the data
-- reloads). Otherwise only the listed count is known: Auctionator's count for its newest day, which is the most it saw
-- listed that day rather than at the last scan, so fromScan is false and the window shows it as approximate.
function Controller.Depth(id)
  local s = Controller.summaries[id]
  if not s then return nil, nil, false end
  local item = index and index.items[id]
  local key = item and (item.base or item.keys[1])
  if key then
    local price, atLow, total = A.Depth.Get(key)
    if price and price == s.last then return total, atLow, true end
  end
  return s.qty, nil, false
end

function Controller.CategoryTree()
  if not tree then tree = A.Categories.Build(A.env) end
  return tree
end

local function context()
  return { info = Controller.Info, summary = Controller.Summary, owned = Controller.Owned, depth = Controller.Depth }
end

local function liveSeries(id)
  local item = index and index.items[id]
  if not item then return nil end
  return A.Adapter.GetSeries(item.base or item.keys[1])
end

-- { live, ext, merged }: Auctionator's current window, Almanac's longer history, and both combined.
function Controller.Series(id)
  local live = liveSeries(id)
  local ext = A.History.Series(id)
  if not live and not ext then return nil end
  return { live = live, ext = ext, merged = A.Stats.Merge(ext, live) }
end

-- ---------------------------------------------------------------------------
-- Searching
-- ---------------------------------------------------------------------------
-- All items in the current sort order, computed once per key/direction and then
-- reused: filtering preserves order, so typing never re-sorts 15,000 items.
local function masterOrder()
  local st = Controller.state
  local key = st.sortKey .. (st.asc and "+" or "-")
  local order = orderCache[key]
  if not order then
    order = {}
    for i, id in ipairs(Controller.ids) do order[i] = id end
    A.Search.Sort(order, st.sortKey, st.asc, context())
    orderCache[key] = order
  end
  return order
end

function Controller.InvalidateOrder() orderCache = {} end

function Controller.Refresh()
  local st = Controller.state
  local params = {
    text = st.text, category = st.category, quality = st.quality, ownedOnly = st.ownedOnly, recent = st.recent,
    minPrice = st.minPrice, maxPrice = st.maxPrice, moved = st.moved,
  }
  Controller.results = A.Search.Run(masterOrder(), params, context())
  A.Bus.Fire("RESULTS_UPDATED")
end

local function queueRefresh()
  if refreshQueued then return end
  refreshQueued = true
  A.After(SEARCH_DEBOUNCE, function()
    refreshQueued = false
    Controller.Refresh()
  end)
end

function Controller.SetSearchText(text)
  Controller.state.text = text or ""
  queueRefresh()
end

function Controller.SetCategory(node)
  Controller.state.category = node
  Controller.Refresh()
end

function Controller.SetQuality(quality)
  Controller.state.quality = quality
  Controller.Refresh()
end

function Controller.SetOwnedOnly(on)
  Controller.state.ownedOnly = on and true or false
  Controller.Refresh()
end

function Controller.SetRecent(days)
  Controller.state.recent = days
  Controller.Refresh()
end

A.Bus.On("INVENTORY_UPDATED", function()
  if Controller.state.sortKey == "owned" or Controller.state.ownedOnly then
    Controller.InvalidateOrder()
    queueRefresh()
  end
end)

-- A scan Almanac recorded can change the market counts, which matter when the list is sorted by them.
A.Bus.On("DEPTH_UPDATED", function()
  local key = Controller.state.sortKey
  if key == "onah" or key == "atmin" then
    Controller.InvalidateOrder()
    queueRefresh()
  end
end)

-- Names arrive in batches while the item cache fills. Re-sorting by name is the
-- expensive part, so it happens at most every few seconds, and only when the
-- names can change what is on screen.
local namesQueued = false
A.Bus.On("ITEM_NAMES_UPDATED", function()
  if namesQueued then return end
  namesQueued = true
  A.After(2, function()
    namesQueued = false
    local st = Controller.state
    if st.text ~= "" or st.sortKey == "name" then
      Controller.InvalidateOrder()
      Controller.Refresh()
    end
  end)
end)

-- key names the choice in the UI so the widget can be put back in step with the state.
function Controller.SetPriceRange(minCopper, maxCopper, key)
  local st = Controller.state
  st.minPrice, st.maxPrice, st.priceKey = minCopper, maxCopper, key
  Controller.Refresh()
end

function Controller.SetMoved(direction)
  Controller.state.moved = direction
  Controller.Refresh()
end

function Controller.SetSort(key, ascending)
  Controller.state.sortKey, Controller.state.asc = key, ascending and true or false
  Controller.Refresh()
end

function Controller.ClearFilters()
  local st = Controller.state
  st.text, st.category, st.quality, st.ownedOnly, st.recent = "", nil, nil, false, nil
  st.minPrice, st.maxPrice, st.priceKey, st.moved = nil, nil, nil, nil
  Controller.Refresh()
end

function Controller.Select(id)
  Controller.state.selected = id
  if id then A.History.MarkViewed(id) end
  A.Bus.Fire("SELECTION_CHANGED", id)
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------
local function sortedIDs(items)
  local ids = {}
  for id in pairs(items) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

function Controller.Reload()
  generation = generation + 1
  local gen = generation
  Controller.summaries, Controller.newestDay, Controller.oldestDay, Controller.pricedCount = {}, nil, nil, 0
  Controller.InvalidateOrder()

  if not A.Adapter.IsReady() then
    Controller.ready = false
    Controller.ids, Controller.results, index = {}, {}, nil
    A.Bus.Fire("DATA_UPDATED")
    A.Bus.Fire("RESULTS_UPDATED")
    return
  end

  index = A.Adapter.BuildIndex()
  Controller.ids = sortedIDs(index.items)
  Controller.ready = true
  scanStamp = A.Adapter.LastScan().time

  local ids = Controller.ids
  A.Items.EnsureAll(ids, function(done, total)
    if gen ~= generation or done ~= total then return end
    A.Categories.Count(Controller.CategoryTree(), ids, Controller.Info)
    A.Bus.Fire("DATA_UPDATED")
  end)

  local today = A.Adapter.Today()
  local i = 1
  local function step()
    if gen ~= generation then return end
    local first = (i == 1)
    i = A.RunBudgeted(i, #ids, CHUNK, BUDGET_MS, function(k)
      local id = ids[k]
      local s = A.Stats.Summarize(liveSeries(id), today)
      if s then
        Controller.pricedCount = Controller.pricedCount + 1
        Controller.summaries[id] = s
        if s.lastDay and (not Controller.newestDay or s.lastDay > Controller.newestDay) then
          Controller.newestDay = s.lastDay
        end
        if s.firstDay and (not Controller.oldestDay or s.firstDay < Controller.oldestDay) then
          Controller.oldestDay = s.firstDay
        end
      end
    end)
    if i <= #ids then
      if first then Controller.Refresh() end    -- show the list as soon as the first chunk is in
      A.After(0, step)
    else
      Controller.InvalidateOrder()
      Controller.Refresh()
      A.Bus.Fire("DATA_UPDATED")
      A.Bus.Fire("DATA_RELOADED")
    end
  end
  if #ids == 0 then
    Controller.Refresh()
    A.Bus.Fire("DATA_UPDATED")
    A.Bus.Fire("DATA_RELOADED")
  else
    step()
  end
end

-- Reload when Auctionator has scanned since we last looked (or we never loaded).
function Controller.CheckForNewData(force)
  if force or not Controller.ready or A.Adapter.LastScan().time ~= scanStamp then
    Controller.Reload()
  end
end
