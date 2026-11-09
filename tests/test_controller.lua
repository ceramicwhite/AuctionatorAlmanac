local H = require("harness")
local Fx = require("fixtures")
local test = H.test

local FILES = {
  "Core/Init.lua", "Core/Format.lua", "Data/Adapter.lua", "Data/Stats.lua", "Data/Items.lua", "Data/Categories.lua",
  "Data/Search.lua", "Tracker/Ledger.lua", "Tracker/Inventory.lua", "Tracker/History.lua", "Core/Controller.lua",
}

local ITEMS = {
  [12359] = { name = "Thorium Bar", quality = 2, class = 7, sub = 12, sell = 400 },
  [10620] = { name = "Thorium Ore", quality = 1, class = 7, sub = 7, sell = 150 },
  [12363] = { name = "Arcane Crystal", quality = 3, class = 7, sub = 10, sell = 0 },
  [19019] = { name = "Thunderfury", quality = 5, class = 2, sub = 7, sell = 0, equip = "INVTYPE_WEAPON" },
  [15001] = { name = "Eagle Pants", quality = 2, class = 4, sub = 1, sell = 10, equip = "INVTYPE_LEGS" },
}

local function boot(overrides)
  local env = Fx.env(overrides)
  env.C_Timer = H.fakeTimer()
  env.C_Item = {
    GetItemInfoInstant = function(id)
      local d = ITEMS[id]
      if d then return id, "t", "s", d.equip or "", 100, d.class, d.sub end
    end,
    GetItemInfo = function(id)
      local d = ITEMS[id]
      if d then return d.name, "|link|", d.quality, 10, 0, "t", "s", 20, d.equip or "", 100, d.sell, d.class, d.sub end
    end,
    RequestLoadItemDataByID = function() end,
    GetItemClassInfo = function(c) return ({ [2] = "Weapon", [4] = "Armor", [7] = "Trade Goods" })[c] end,
    GetItemSubClassInfo = function(c, s) return ({ [7] = { [7] = "Metal & Stone", [12] = "Enchanting" } })[c] and ({ [7] = { [7] = "Metal & Stone", [12] = "Enchanting" } })[c][s] end,
  }
  local A = H.newA(FILES, env)
  A.db = A.InitDB(nil)
  A.Items.Init(A.db); A.Ledger.Init(A.db); A.Inventory.Init(A.db); A.History.Init(A.db)
  return A, env
end

local function ready(A, env)
  A.Controller.Reload()
  env.C_Timer.flush()
  return A.Controller
end

test("Reload indexes the price database and computes summaries", function()
  local A, env = boot()
  local Ct = ready(A, env)
  H.truthy(Ct.ready)
  H.eq(#Ct.ids, 5)
  local s = Ct.Summary(12359)
  H.eq(s.last, 11240)
  H.eq(s.nDays, 5)
  H.eq(s.ageDays, 0)
  H.eq(Ct.newestDay, 1005)
  H.eq(#Ct.results, 5)
  H.truthy(Ct.Info(12359).name == "Thorium Bar")
end)

test("when Auctionator is not ready the controller is empty, not broken", function()
  local A, env = boot({ Auctionator = false })
  local fired = 0
  A.Bus.On("DATA_UPDATED", function() fired = fired + 1 end)
  local Ct = ready(A, env)
  H.falsy(Ct.ready)
  H.eq(#Ct.ids, 0)
  H.eq(Ct.results, {})
  H.truthy(fired >= 1)
  H.nothrows(function() Ct.Refresh(); Ct.Select(1) end)
end)

test("search text filters and sort orders the results", function()
  local A, env = boot()
  local Ct = ready(A, env)
  Ct.SetSearchText("thorium")
  env.C_Timer.flush()
  H.eq(#Ct.results, 2)
  Ct.SetSort("price", false)
  H.eq(Ct.results, { 12359, 10620 }, "price descending")
  Ct.SetSort("price", true)
  H.eq(Ct.results, { 10620, 12359 })
  Ct.SetSort("name", true)
  H.eq(Ct.results, { 12359, 10620 }, "Thorium Bar before Thorium Ore")
end)

test("typing is debounced into one refresh", function()
  local A, env = boot()
  local Ct = ready(A, env)
  local refreshes = 0
  A.Bus.On("RESULTS_UPDATED", function() refreshes = refreshes + 1 end)
  Ct.SetSearchText("t"); Ct.SetSearchText("th"); Ct.SetSearchText("thor")
  H.eq(refreshes, 0)
  env.C_Timer.flush()
  H.eq(refreshes, 1)
  H.eq(Ct.state.text, "thor")
end)

test("categories narrow the results and count their items", function()
  local A, env = boot()
  local Ct = ready(A, env)
  local tree = Ct.CategoryTree()
  local weapon
  for _, node in ipairs(tree) do if node.name == "Weapon" then weapon = node end end
  H.eq(weapon.count, 1)
  Ct.SetCategory(weapon)
  H.eq(Ct.results, { 19019 })
  Ct.SetCategory(nil)
  H.eq(#Ct.results, 5)
end)

test("filters: quality, owned only, recent", function()
  local A, env = boot()
  local Ct = ready(A, env)
  Ct.SetQuality(3)
  H.eq(Ct.results, { 12363 })
  Ct.SetQuality(nil)
  A.Inventory.EnsureChar({ name = "Thornwick", realm = "Whitemane" })
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [10620] = 9 }, 1)
  Ct.SetOwnedOnly(true)
  H.eq(Ct.results, { 10620 })
  H.eq(Ct.Owned(10620), 9)
  H.eq(Ct.Owned(12359), 0)
  Ct.SetOwnedOnly(false)
  Ct.SetRecent(0)
  H.eq(#Ct.results, 4, "only items last priced today: 19019's data is from the day before")
  Ct.SetRecent(1)
  H.eq(#Ct.results, 5)
  Ct.SetRecent(nil)
  H.eq(#Ct.results, 5)
end)

test("Select records the view, remembers it and announces the change", function()
  local A, env = boot()
  local Ct = ready(A, env)
  local seen
  A.Bus.On("SELECTION_CHANGED", function(id) seen = id end)
  Ct.Select(12359)
  H.eq(Ct.state.selected, 12359)
  H.eq(seen, 12359)
  H.eq(A.History.Viewed()[1], 12359)
  Ct.Select(nil)
  H.eq(Ct.state.selected, nil)
end)

test("Series merges Auctionator's days with extended history and lists variants", function()
  local A, env = boot()
  local Ct = ready(A, env)
  A.History.Snapshot(A.Adapter, { [12359] = true }, 1005, 365)
  A.db.history.items[12359].h[900] = 9000
  local s = Ct.Series(12359)
  H.eq(s.merged.days[1].day, 900)
  H.eq(#s.live.days, 5)
  H.eq(#s.merged.days, 6)
  H.eq(Ct.Variants(19019), { "19019", "g:19019:60" })
  H.eq(Ct.Series(99999), nil)
end)

test("CheckForNewData reloads only when a newer scan appears", function()
  local A, env = boot()
  local Ct = ready(A, env)
  local reloads = 0
  A.Bus.On("DATA_RELOADED", function() reloads = reloads + 1 end)
  Ct.CheckForNewData()
  env.C_Timer.flush()
  H.eq(reloads, 0)
  env.AUCTIONATOR_SAVEDVARS.TimeOfLastBrowseScan = env.AUCTIONATOR_SAVEDVARS.TimeOfLastBrowseScan + 600
  Ct.CheckForNewData()
  env.C_Timer.flush()
  H.eq(reloads, 1)
  Ct.CheckForNewData(true)
  env.C_Timer.flush()
  H.eq(reloads, 2, "force reloads regardless")
end)

test("LastScan and Realm come from Auctionator", function()
  local A, env = boot()
  local Ct = ready(A, env)
  H.eq(Ct.LastScan().kind, "browse")
  H.eq(Ct.Realm(), "TestRealm")
end)

test("a numeric search finds an item by id", function()
  local A, env = boot()
  local Ct = ready(A, env)
  Ct.SetSearchText("19019")
  env.C_Timer.flush()
  H.eq(Ct.results, { 19019 })
end)

test("a reload keeps the current search and selection", function()
  local A, env = boot()
  local Ct = ready(A, env)
  Ct.SetSearchText("thorium"); env.C_Timer.flush()
  Ct.Select(12359)
  Ct.Reload(); env.C_Timer.flush()
  H.eq(Ct.state.text, "thorium")
  H.eq(Ct.state.selected, 12359)
  H.eq(#Ct.results, 2)
end)

test("sort order is computed once per key, then reused while filtering", function()
  local A, env = boot()
  local Ct = ready(A, env)
  local sorts = 0
  local realSort = A.Search.Sort
  A.Search.Sort = function(...) sorts = sorts + 1; return realSort(...) end
  Ct.SetSort("price", false)
  local afterFirst = sorts
  H.truthy(afterFirst >= 1)
  Ct.SetSearchText("t"); env.C_Timer.flush()
  Ct.SetSearchText("thor"); env.C_Timer.flush()
  Ct.SetQuality(2); Ct.SetQuality(nil)
  H.eq(sorts, afterFirst, "filtering reuses the cached order")
  H.eq(Ct.results[1], 12359)
  Ct.SetSort("price", true)
  H.truthy(sorts > afterFirst, "a new sort key or direction sorts once")
end)

test("the cached order follows the data after a reload", function()
  local A, env = boot()
  local Ct = ready(A, env)
  Ct.SetSort("price", false)
  H.eq(Ct.results[1], 19019)
  env.Auctionator.Database.db["10620"].m = 90000000
  Ct.Reload(); env.C_Timer.flush()
  H.eq(Ct.results[1], 10620)
end)

test("price range and moved filters narrow the results and clear with the rest", function()
  local A, env = boot()
  local Ct = ready(A, env)
  Ct.SetPriceRange(100000, nil, "gt10g")
  H.eq(Ct.state.priceKey, "gt10g")
  local ids = {}
  for _, id in ipairs(Ct.results) do ids[id] = true end
  H.eq(ids, { [12363] = true, [19019] = true }, "only items over 10g: Arcane Crystal and Thunderfury")
  Ct.SetPriceRange(nil, 9999, "lt1g")
  H.eq(#Ct.results, 2, "under 1g: Thorium Ore (48s) and Eagle Pants (9s)")
  Ct.SetPriceRange(nil, nil, nil)
  H.eq(#Ct.results, 5)
  Ct.SetMoved("up")
  H.eq(Ct.state.moved, "up")
  Ct.SetPriceRange(100000, nil, "gt10g")
  Ct.ClearFilters()
  H.eq({ Ct.state.moved, Ct.state.priceKey, Ct.state.minPrice, Ct.state.maxPrice }, { nil, nil, nil, nil })
  H.eq(#Ct.results, 5)
end)

test("Reload records the oldest day of data as well as the newest", function()
  local A, env = boot()
  local Ct = ready(A, env)
  H.eq(Ct.oldestDay, 1000, "Thorium Bar has been priced since day 1000")
  H.eq(Ct.newestDay, 1005)
  local empty, env2 = boot({ Auctionator = false })
  empty.Controller.Reload()
  env2.C_Timer.flush()
  H.eq(empty.Controller.oldestDay, nil)
end)
