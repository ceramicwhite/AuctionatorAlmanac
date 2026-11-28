local H = require("harness")
local Fx = require("fixtures")
local test = H.test

-- How many were listed at the lowest price: Almanac listens to Auctionator saving each scan (Data/Depth.lua), and the
-- controller and the search use what it heard.
local FILES = {
  "Core/Init.lua", "Core/Format.lua", "Data/Adapter.lua", "Data/Stats.lua", "Data/Items.lua", "Data/Categories.lua",
  "Data/Search.lua", "Data/Depth.lua", "Tracker/Ledger.lua", "Tracker/Inventory.lua", "Tracker/History.lua",
  "Core/Controller.lua",
}

-- Auctionator's Database, as far as Almanac sees it (Auctionator/Source/Database/Mixin.lua): ProcessScan takes every
-- auction of a scan and starts saving it a few keys a frame (here: when the test calls Save); a newer scan cancels the
-- saving of an older one; SetPrice saves a key's lowest price and, when it knows it, the count listed.
local function newMixin()
  local mixin = {}
  function mixin:SetPrice(key, price, listed)
    local entry = self.db[key]
    if not entry then
      entry = { h = {}, l = {}, a = {} }
      self.db[key] = entry
    end
    entry.m = price
    local day = tostring(Fx.TODAY)
    entry.h[day] = math.max(entry.h[day] or 0, price)
    if listed then entry.a[day] = math.max(entry.a[day] or 0, listed) end
  end
  function mixin:ProcessScan(scan)
    local keys = {}
    for key in pairs(scan) do keys[#keys + 1] = key end
    table.sort(keys)
    self.saving = { scan = scan, keys = keys, next = 1 }
    return "ticker"
  end
  return mixin
end

-- A Database made the way CreateAndInitFromMixin makes the real one: the mixin's methods copied in.
local function newDatabase(mixin, db)
  local o = { db = db or {} }
  for k, v in pairs(mixin) do o[k] = v end
  -- the ticker: save up to n keys of the scan being saved (all of them when n is nil)
  function o:Save(n)
    local s = self.saving
    if not s then return end
    local stop = n and math.min(#s.keys, s.next + n - 1) or #s.keys
    for i = s.next, stop do
      local entries = s.scan[s.keys[i]]
      local low, listed = entries[1].price, 0
      for _, e in ipairs(entries) do
        listed = listed + e.available
        if e.price < low then low = e.price end
      end
      self:SetPrice(s.keys[i], low, listed)
    end
    s.next = stop + 1
    if s.next > #s.keys then self.saving = nil end
  end
  return o
end

local function hookFn(tbl, name, fn)
  local orig = tbl[name]
  tbl[name] = function(...)
    local r = orig(...)
    fn(...)
    return r
  end
end

-- opts.timer: a fake C_Timer (announcements wait to be flushed); opts.noHooks: a client without hooksecurefunc.
-- The fixture realm is Auctionator's live price table, so a scan saved here is what the controller reads after a reload.
local function boot(opts)
  opts = opts or {}
  local env = Fx.env()
  if opts.timer then env.C_Timer = H.fakeTimer() end
  env.C_Item = { GetItemInfoInstant = function() end, GetItemInfo = function() end, RequestLoadItemDataByID = function() end }
  local realm = env.Auctionator.Database.db
  env.Auctionator.DatabaseMixin = newMixin()
  env.Auctionator.Database = nil
  if not opts.noHooks then env.hooksecurefunc = hookFn end
  local errors = {}
  env.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
  local A = H.newA(FILES, env)
  A.db = A.InitDB(nil)
  A.Items.Init(A.db); A.Ledger.Init(A.db); A.Inventory.Init(A.db); A.History.Init(A.db); A.Depth.Init(A.db)
  return A, env, realm, errors
end

-- Almanac installed, and Auctionator's Database made at login from the (hooked) mixin.
local function listening(opts)
  local A, env, realm, errors = boot(opts)
  A.Depth.Install()
  env.Auctionator.Database = newDatabase(env.Auctionator.DatabaseMixin, realm)
  return A, env, env.Auctionator.Database, errors
end

local function scanAndSave(db, scan)
  local result = db:ProcessScan(scan)
  db:Save()
  return result
end

test("a new database keeps no counts yet", function()
  local A = boot()
  H.eq(A.NewDB().depth, { realms = {} })
  H.eq(A.Depth.Count(), 0)
  H.eq(A.Depth.Get("12359"), nil)
end)

test("Summarize finds the lowest unit price, how many were listed at it, and how many in all", function()
  local D = boot().Depth
  local low, atLow, total = D.Summarize({
    { price = 120, available = 5 }, { price = 100, available = 3 }, { price = 100, available = 20 }, { price = 150, available = 1 },
  })
  H.eq({ low, atLow, total }, { 100, 23, 29 })
  H.eq({ D.Summarize({ { price = 7, available = 1 } }) }, { 7, 1, 1 }, "a single auction")
  H.eq({ D.Summarize({ { price = 50, available = 2 }, { price = 40, available = 4 }, { price = 40, available = 1 } }) },
    { 40, 5, 7 }, "a cheaper auction resets the count at the lowest price")
  H.eq(D.Summarize({}), nil, "no auctions")
  H.eq(D.Summarize(nil), nil)
  H.eq({ D.Summarize({ { price = "x" }, { price = 30 }, 5 }) }, { 30, 0, 0 }, "a missing count counts as none, junk is skipped")
end)

-- ---------------------------------------------------------------------------
-- Hearing a scan being saved
-- ---------------------------------------------------------------------------
test("each key Auctionator saves from a scan gets its count at the lowest price, kept per realm", function()
  local A, env, db = listening()
  local result = scanAndSave(db, {
    ["12359"] = { { price = 11240, available = 4 }, { price = 11240, available = 6 }, { price = 11500, available = 34 } },
    ["g:19019:60"] = { { price = 5200000, available = 1 } },
  })
  H.eq(result, "ticker", "Auctionator's own call still returns what it returned")
  H.eq(db.db["12359"].m, 11240, "and Auctionator saved its price as always")
  H.eq({ A.Depth.Get("12359") }, { 11240, 10, 44, Fx.TODAY })
  H.eq({ A.Depth.Get("g:19019:60") }, { 5200000, 1, 1, Fx.TODAY })
  H.eq(A.Depth.Count(), 2)
  H.eq(A.db.depth.realms.TestRealm["12359"], "11240,10,44," .. Fx.TODAY, "kept compactly in the saved file")
end)

test("nothing is recorded before Auctionator saves the key, and the scan is announced once, when all of it is saved", function()
  local A, env, db = listening({ timer = true })
  local announced = 0
  A.Bus.On("DEPTH_UPDATED", function() announced = announced + 1 end)
  local scan = {}
  for i = 1, 30 do scan[tostring(i)] = { { price = 100 + i, available = 1 } } end
  db:ProcessScan(scan)
  H.eq(A.Depth.Count(), 0, "Auctionator has not saved anything yet")
  db:Save(10)
  H.eq(A.Depth.Count(), 10, "keys are recorded as Auctionator saves them")
  env.C_Timer.flush()
  H.eq(announced, 0, "not announced half way")
  db:Save()
  env.C_Timer.flush()
  H.eq(A.Depth.Count(), 30)
  H.eq(announced, 1)
end)

test("a later price for the same key without its auctions forgets the count, even at the same price", function()
  local A, env, db = listening()
  scanAndSave(db, { ["12359"] = { { price = 11240, available = 7 }, { price = 12000, available = 30 } } })
  A.Controller.Reload()
  H.eq({ A.Controller.Depth(12359) }, { 37, 7, true })
  -- a one-item search at the Auction House saves the same lowest price with a different count listed
  db:SetPrice("12359", 11240, 99)
  H.eq(A.Depth.Get("12359"), nil, "the count belonged to the earlier save")
  A.Controller.Reload()
  H.eq({ A.Controller.Depth(12359) }, { 99, nil, false }, "only Auctionator's own count is known now")
  -- posting saves a price with no count at all
  scanAndSave(db, { ["12363"] = { { price = 1500000, available = 2 } } })
  db:SetPrice("12363", 1400000)
  H.eq(A.Depth.Get("12363"), nil)
end)

test("an Auctionator that saves every key inside ProcessScan is heard too", function()
  local A, env, realm = boot({ timer = true })
  local mixin = env.Auctionator.DatabaseMixin
  local deferred = mixin.ProcessScan
  function mixin:ProcessScan(scan)                -- older and other builds save before returning
    local result = deferred(self, scan)
    self:Save()
    return result
  end
  local announced = 0
  A.Bus.On("DEPTH_UPDATED", function() announced = announced + 1 end)
  A.Depth.Install()
  env.Auctionator.Database = newDatabase(mixin, realm)
  local result = env.Auctionator.Database:ProcessScan({
    ["12359"] = { { price = 11240, available = 3 }, { price = 11300, available = 9 } },
    ["12363"] = { { price = 1500000, available = 2 } },
  })
  env.C_Timer.flush()
  H.eq(result, "ticker")
  H.eq({ A.Depth.Get("12359") }, { 11240, 3, 12, Fx.TODAY })
  H.eq({ A.Depth.Get("12363") }, { 1500000, 2, 2, Fx.TODAY })
  H.eq(announced, 1, "and the finished scan is announced")
end)

test("a key saved twice while a scan is being saved counts once, and does not cut the scan short", function()
  local A, env, db = listening()
  db:ProcessScan({
    a = { { price = 10, available = 1 } }, b = { { price = 20, available = 2 } }, c = { { price = 30, available = 3 } },
  })
  db:Save(1)                                      -- "a" from the scan
  db:SetPrice("a", 10, 1)                         -- "a" again, from something else (a posting, a search)
  H.eq(A.Depth.Get("a"), nil, "the second save is not the scan's")
  db:Save()                                       -- the rest of the scan
  H.eq({ A.Depth.Get("b") }, { 20, 2, 2, Fx.TODAY })
  H.eq({ A.Depth.Get("c") }, { 30, 3, 3, Fx.TODAY }, "the scan's last key is still recorded")
  db:SetPrice("c", 31, 3)
  H.eq(A.Depth.Get("c"), nil, "and once the scan is saved, nothing else is taken for it")
end)

test("a save that does not match the scan's own auctions records nothing", function()
  local A, env, db = listening()
  db:ProcessScan({ ["12359"] = { { price = 100, available = 3 } } })
  db:SetPrice("12359", 90, 3)                    -- not what those auctions say
  H.eq(A.Depth.Get("12359"), nil)
end)

test("a newer scan replaces one Auctionator stopped saving, and a stray save after it is not mistaken for it", function()
  local A, env, db = listening()
  db:ProcessScan({ a = { { price = 10, available = 1 } }, b = { { price = 20, available = 2 } } })
  db:Save(1)                                      -- "a" saved, then Auctionator starts the next scan and drops this one
  scanAndSave(db, { b = { { price = 21, available = 5 } }, c = { { price = 30, available = 3 } } })
  H.eq({ A.Depth.Get("a") }, { 10, 1, 1, Fx.TODAY })
  H.eq({ A.Depth.Get("b") }, { 21, 5, 5, Fx.TODAY }, "the newer scan's auctions")
  H.eq({ A.Depth.Get("c") }, { 30, 3, 3, Fx.TODAY })
  db:SetPrice("a", 10, 1)                         -- not part of any scan in progress
  H.eq(A.Depth.Get("a"), nil)
end)

test("counts from one realm never show on another", function()
  local A, env, db = listening()
  scanAndSave(db, { ["12359"] = { { price = 11240, available = 7 }, { price = 12000, available = 30 } } })
  A.Controller.Reload()
  H.eq({ A.Controller.Depth(12359) }, { 37, 7, true })
  env.Auctionator.State.CurrentRealm = "OtherRealm"      -- the same account, logged in on another realm
  env.AUCTIONATOR_PRICE_DATABASE.OtherRealm = env.AUCTIONATOR_PRICE_DATABASE.TestRealm   -- same item, same price
  A.Controller.Reload()
  H.eq(A.Depth.Get("12359"), nil)
  H.eq(A.Depth.Count(), 0)
  H.eq({ A.Controller.Depth(12359) }, { 44, nil, false }, "that realm's own count, nothing at the lowest price")
  scanAndSave(db, { ["12359"] = { { price = 11240, available = 2 } } })
  H.eq({ A.Depth.Get("12359") }, { 11240, 2, 2, Fx.TODAY })
  env.Auctionator.State.CurrentRealm = "TestRealm"
  H.eq({ A.Depth.Get("12359") }, { 11240, 7, 37, Fx.TODAY }, "each realm keeps its own")
end)

test("a hand-edited record is ignored, not misread", function()
  local A = boot()
  A.db.depth.realms.TestRealm = { ["12359"] = "lots", ["10620"] = "1,2,3" }
  A.Depth.Init(A.db)
  H.eq(A.Depth.Get("12359"), nil)
  H.eq(A.Depth.Get("10620"), nil)
end)

test("records older than Auctionator's history window are pruned on every realm; current ones stay", function()
  local A = boot()
  A.db.depth.realms = {
    TestRealm = { ["1"] = "10,1,1,980", ["2"] = "10,1,1,1004", ["3"] = "garbage" },
    Gone = { ["1"] = "10,1,1,900" },
    Broken = "not a table",
  }
  A.Depth.Init(A.db)
  H.eq(A.Depth.Get("1"), 10, "read before pruning")
  H.eq(A.Depth.Prune(1005 - 21), 3)
  H.eq(A.db.depth.realms.TestRealm, { ["2"] = "10,1,1,1004" })
  H.eq(A.db.depth.realms.Gone, nil, "a realm with nothing left goes")
  H.eq(A.db.depth.realms.Broken, nil)
  H.eq(A.Depth.Get("1"), nil, "nothing stale is left in memory either")
end)

test("Reset forgets every count", function()
  local A, env, db = listening()
  scanAndSave(db, { ["12359"] = { { price = 1, available = 1 } } })
  A.Depth.Reset()
  H.eq(A.Depth.Count(), 0)
  H.eq(A.Depth.Get("12359"), nil)
end)

-- ---------------------------------------------------------------------------
-- Hooking Auctionator
-- ---------------------------------------------------------------------------
test("Install hooks the mixin, so the Database Auctionator makes at login reports to Almanac, once", function()
  local A, env, realm = boot()
  H.truthy(A.Depth.Install())
  H.eq(A.Depth.Status(), "waiting", "the mixin is hooked; no Database yet")
  local heard = 0
  local onPrice = A.Depth.OnPrice
  A.Depth.OnPrice = function(...) heard = heard + 1; return onPrice(...) end
  env.Auctionator.Database = newDatabase(env.Auctionator.DatabaseMixin, realm)
  H.eq(A.Depth.Status(), "ok")
  A.Depth.Install()          -- again, as every data reload does
  scanAndSave(env.Auctionator.Database, { ["12359"] = { { price = 9, available = 2 } } })
  H.eq(heard, 1, "one save heard once")
  H.eq({ A.Depth.Get("12359") }, { 9, 2, 2, Fx.TODAY })
end)

test("a Database that already exists is hooked as well, and never twice", function()
  local A, env, realm = boot()
  env.Auctionator.Database = newDatabase(env.Auctionator.DatabaseMixin, realm)
  local heard = 0
  local onPrice = A.Depth.OnPrice
  A.Depth.OnPrice = function(...) heard = heard + 1; return onPrice(...) end
  A.Depth.Install()
  A.Depth.Install()
  H.eq(A.Depth.Status(), "ok")
  scanAndSave(env.Auctionator.Database, { ["1"] = { { price = 1, available = 1 } } })
  H.eq(heard, 1)
  -- Auctionator remakes its Database (some of its slash commands do): made from the hooked mixin, it reports too
  env.Auctionator.Database = newDatabase(env.Auctionator.DatabaseMixin, realm)
  A.Depth.Install()
  scanAndSave(env.Auctionator.Database, { ["2"] = { { price = 1, available = 1 } } })
  H.eq(heard, 2)
  H.truthy(A.Depth.Get("2"))
end)

test("a failure while listening never breaks Auctionator's scan, and is reported", function()
  local A, env, db, errors = listening()
  A.Adapter.Today = function() error("boom") end
  local result
  H.nothrows(function() result = scanAndSave(db, { ["1"] = { { price = 1, available = 1 } } }) end)
  H.eq(result, "ticker")
  H.eq(db.db["1"].m, 1, "Auctionator saved its price")
  H.truthy(#errors >= 1)
  H.truthy(tostring(errors[1]):find("boom", 1, true))
end)

test("without hooks, or an Auctionator without those methods, Install says so and nothing breaks", function()
  local A = boot({ noHooks = true })
  H.falsy(A.Depth.Install())
  H.eq(A.Depth.Status(), "missing")
  local B, env = boot()
  env.Auctionator.DatabaseMixin = nil
  env.Auctionator.Database = { db = {}, ProcessScan = function() end }
  H.falsy(B.Depth.Install())
  H.eq(B.Depth.Status(), "missing", "SetPrice is needed too")
end)

-- ---------------------------------------------------------------------------
-- What the window shows: Controller.Depth and sorting
-- ---------------------------------------------------------------------------
test("the count at the lowest price shows while the save it came from set the item's shown price", function()
  local A, env, db = listening()
  A.Controller.Reload()
  H.eq({ A.Controller.Depth(12359) }, { 44, nil, false }, "no record: Auctionator's count for the day, nothing at the lowest")
  scanAndSave(db, { ["12359"] = { { price = 11000, available = 7 }, { price = 12000, available = 30 } } })
  H.eq({ A.Controller.Depth(12359) }, { 44, nil, false }, "a new price the loaded data does not show yet: not mixed in")
  A.Controller.Reload()
  H.eq({ A.Controller.Depth(12359) }, { 37, 7, true }, "after the reload, both counts from that scan")
  H.eq({ A.Controller.Depth(10620) }, { nil, nil, false }, "old data with no counts at all")
  H.eq({ A.Controller.Depth(424242) }, { nil, nil, false }, "an item Auctionator does not know")
end)

test("gear is read from the key Almanac shows its price from", function()
  local A, env, db = listening()
  scanAndSave(db, { ["19019"] = { { price = 5000000, available = 1 } }, ["g:19019:60"] = { { price = 5200000, available = 2 } } })
  scanAndSave(db, { ["gr:15001:of the Eagle"] = { { price = 900, available = 3 } } })
  A.Controller.Reload()
  H.eq({ A.Controller.Depth(19019) }, { 1, 1, true })
  H.eq({ A.Controller.Depth(15001) }, { 3, 3, true }, "an item with only a legacy suffix key")
end)

test("the item list sorts by the count at the lowest price and by the count listed, unknowns last", function()
  local A, env, db = listening()
  scanAndSave(db, {
    ["12359"] = { { price = 11240, available = 7 } },
    ["12363"] = { { price = 1500000, available = 2 } },
  })
  A.Controller.Reload()
  A.Controller.SetSort("atmin", false)
  H.eq({ A.Controller.results[1], A.Controller.results[2] }, { 12359, 12363 })
  local last = A.Controller.results[#A.Controller.results]
  H.eq(select(2, A.Controller.Depth(last)), nil, "items without a count go last")
  A.Controller.SetSort("onah", true)
  local previous, seenUnknown = -1, false
  for _, id in ipairs(A.Controller.results) do
    local onAH = A.Controller.Depth(id)
    if onAH == nil then
      seenUnknown = true
    else
      H.falsy(seenUnknown, "a known count after an unknown one")
      H.truthy(onAH >= previous, "the fewest listed first")
      previous = onAH
    end
  end
  H.eq(A.Controller.results[1], 19019, "one Thunderfury listed")
end)

test("new counts re-sort a list sorted by them", function()
  local A, env, db = listening({ timer = true })
  A.Controller.Reload()
  env.C_Timer.flush()
  A.Controller.SetSort("atmin", false)
  H.truthy(A.Controller.results[1] ~= 12363)
  scanAndSave(db, { ["12363"] = { { price = 1500000, available = 500 } } })
  env.C_Timer.flush()
  H.eq(A.Controller.results[1], 12363)
end)
