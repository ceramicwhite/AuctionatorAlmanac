local H = require("harness")
local Fx = require("fixtures")
local test = H.test

local function load(overrides)
  local A = H.newA({ "Core/Init.lua", "Data/Adapter.lua" }, Fx.env(overrides))
  return A.Adapter, A
end

test("ParseKey handles plain, gear, legacy gear, pets and garbage", function()
  local Ad = load()
  local id, variant = Ad.ParseKey("12359")
  H.eq(id, 12359); H.eq(variant, nil)
  id, variant = Ad.ParseKey("g:19019:60")
  H.eq(id, 19019); H.eq(variant, "g:60")
  id, variant = Ad.ParseKey("gr:15001:of the Eagle")
  H.eq(id, 15001); H.eq(variant, "gr:of the Eagle")
  H.eq(Ad.ParseKey("p:1234"), nil)
  H.eq(Ad.ParseKey("garbage"), nil)
  H.eq(Ad.ParseKey("abc:5"), nil)
  H.eq(Ad.ParseKey(nil), nil)
  H.eq(Ad.ParseKey(42), nil)
end)

test("IsReady and RealmData follow Auctionator state", function()
  local Ad = load()
  H.truthy(Ad.IsReady())
  H.truthy(Ad.RealmData()["12359"])

  local notLoaded = load({ Auctionator = { State = { Loaded = false } } })
  H.falsy(notLoaded.IsReady())

  local none = load({ Auctionator = false })
  H.falsy(none.IsReady())
  H.eq(none.RealmData(), nil)
  H.eq(none.BuildIndex().count, 0, "index of nothing is empty, not an error")
end)

test("RealmData falls back to the saved variable and ignores serialized strings", function()
  local env = Fx.env()
  env.Auctionator.Database = nil
  local A = H.newA({ "Core/Init.lua", "Data/Adapter.lua" }, env)
  H.truthy(A.Adapter.RealmData()["12359"], "falls back to AUCTIONATOR_PRICE_DATABASE[realm]")
  env.AUCTIONATOR_PRICE_DATABASE.TestRealm = "CBORBLOB"
  H.eq(A.Adapter.RealmData(), nil)
end)

test("empty price database (no_price_database option) is ready but empty", function()
  local Ad = load({ Auctionator = { State = { Loaded = true, CurrentRealm = "R" }, Database = { db = {} } } })
  H.truthy(Ad.IsReady())
  H.eq(Ad.BuildIndex().count, 0)
end)

test("BuildIndex groups variants under the base item and skips junk", function()
  local Ad = load()
  local index = Ad.BuildIndex()
  H.eq(index.count, 5, "12359, 10620, 12363, 19019, 15001")
  H.eq(index.items[19019].base, "19019")
  H.eq(index.items[19019].keys, { "19019", "g:19019:60" })
  H.eq(index.items[15001].base, nil, "only a legacy suffix key exists")
  H.eq(index.items[15001].keys, { "gr:15001:of the Eagle" })
  H.eq(index.items[1234], nil, "pets skipped")
end)

test("GetSeries returns ascending numeric days with low/high/qty", function()
  local Ad = load()
  local s = Ad.GetSeries("12359")
  H.eq(s.key, "12359")
  H.eq(s.last, 11240)
  H.eq(#s.days, 5)
  H.eq(s.days[1], { day = 1000, low = 11000, high = 11500, qty = 40 })
  H.eq(s.days[2], { day = 1001, low = 11300, high = 11300, qty = 35 }, "low falls back to high")
  H.eq(s.days[5].day, 1005)
  for i = 2, #s.days do H.truthy(s.days[i].day > s.days[i - 1].day, "ascending") end
end)

test("GetSeries copes with missing quantity, single day, and unknown keys", function()
  local Ad = load()
  local old = Ad.GetSeries("10620")
  H.eq(old.days[1].qty, nil)
  H.eq(#old.days, 2)
  H.eq(#Ad.GetSeries("12363").days, 1)
  H.eq(Ad.GetSeries("999999"), nil)
  H.eq(#Ad.GetSeries("garbage").days, 0, "a last price with no days is still a series")
  local empty = load({ Auctionator = {
    State = { Loaded = true, CurrentRealm = "R" },
    Database = { db = { ["7"] = { h = {}, l = {}, a = {} } } },
  } })
  H.eq(empty.GetSeries("7"), nil, "no days and no price is nothing")
end)

test("GetSeries accepts numeric day keys as well as strings", function()
  local Ad = load({ Auctionator = {
    State = { Loaded = true, CurrentRealm = "R" },
    Database = { db = { ["5"] = { m = 9, h = { [1000] = 9 }, l = {}, a = { [1000] = 2 } } } },
  } })
  local s = Ad.GetSeries("5")
  H.eq(s.days[1], { day = 1000, low = 9, high = 9, qty = 2 })
end)

test("day/time conversion round-trips and uses Auctionator's day zero", function()
  local Ad = load()
  H.eq(Ad.DayToTime(0), Fx.DAY0)
  H.eq(Ad.DayToTime(1005), Fx.DAY0 + 1005 * 86400)
  H.eq(Ad.TimeToDay(Fx.NOW), 1005)
  H.eq(Ad.Today(), 1005)
end)

test("LastScan takes the newest scan timestamp and names its kind", function()
  local Ad = load()
  local scan = Ad.LastScan()
  H.eq(scan.time, Fx.NOW - 7200)
  H.eq(scan.kind, "browse")
  H.eq(scan.browse, Fx.NOW - 7200)
  H.eq(scan.full, Fx.NOW - 3 * 86400)

  local fullNewest = load({ AUCTIONATOR_SAVEDVARS = { TimeOfLastReplicateScan = Fx.NOW - 60, TimeOfLastBrowseScan = Fx.NOW - 999 } })
  H.eq(fullNewest.LastScan().kind, "full")
end)

test("LastScan falls back to the newest data day, then to nothing", function()
  local Ad = load({ AUCTIONATOR_SAVEDVARS = {} })
  local scan = Ad.LastScan(1005)
  H.eq(scan.kind, "data")
  H.eq(scan.time, Fx.DAY0 + 1005 * 86400)
  local none = Ad.LastScan(nil)
  H.eq(none.time, nil)
  H.eq(none.kind, nil)
end)

test("PostingHistory merges an item's keys and sorts by time", function()
  local Ad = load()
  local rows = Ad.PostingHistory(12359)
  H.eq(#rows, 2)
  H.truthy(rows[1].time <= rows[2].time)
  H.eq(rows[2].price, 11900)
  H.eq(rows[2].quantity, 20)
  local gear = Ad.PostingHistory(19019)
  H.eq(#gear, 1, "g: variant keys count for the base item")
  H.eq(Ad.PostingHistory(1), {})
end)

test("PostingHistory tolerates a missing table", function()
  local Ad = load({ AUCTIONATOR_POSTING_HISTORY = false })
  H.eq(Ad.PostingHistory(12359), {})
end)

test("ShoppingLists returns valid lists only", function()
  local Ad = load()
  local lists = Ad.ShoppingLists()
  H.eq(#lists, 2)
  H.eq(lists[1].name, "Smithing")
  H.eq(lists[1].items, { '"Thorium Bar";;;;;;;;;;;;;;', "Arcane Crystal" }, "non-string entries dropped")
  H.eq(load({ AUCTIONATOR_SHOPPING_LISTS = false }).ShoppingLists(), {})
end)

test("ParseSearchTerm splits Auctionator's advanced search strings", function()
  local Ad = load()
  H.eq(Ad.ParseSearchTerm('"Thorium Bar";;;;;;;;;;;;;;'), { query = "Thorium Bar", exact = true })
  H.eq(Ad.ParseSearchTerm("Arcane Crystal"), { query = "Arcane Crystal", exact = false })
  H.eq(Ad.ParseSearchTerm(""), { query = "", exact = false })
end)

test("HistoryDays reads Auctionator config with a default of 21", function()
  H.eq(load().HistoryDays(), 21)
  H.eq(load({ Auctionator = { State = { Loaded = true } } }).HistoryDays(), 21)
  local custom = load({ Auctionator = {
    State = { Loaded = true },
    Config = { Options = { PRICE_HISTORY_DAYS = "price_history_days" }, Get = function() return 45 end },
  } })
  H.eq(custom.HistoryDays(), 45)
end)

test("Realm name comes from Auctionator state", function()
  H.eq(load().Realm(), "TestRealm")
  H.eq(load({ Auctionator = false, GetRealmName = function() return "Fallback" end }).Realm(), "Fallback")
end)

test("AllPostings lists every posting with its item id, skipping junk keys", function()
  local Ad = load({ AUCTIONATOR_POSTING_HISTORY = {
    ["__dbversion"] = 1,
    ["12359"] = { { price = 11900, quantity = 20, time = 100 }, { price = 12100, quantity = 5, time = 50 } },
    ["g:19019:60"] = { { price = 5300000, quantity = 1, time = 70 } },
    ["p:7"] = { { price = 1, quantity = 1, time = 1 } },
    ["999"] = "not a table",
  } })
  local rows = Ad.AllPostings()
  H.eq(#rows, 3)
  H.eq({ rows[1].itemID, rows[1].time }, { 12359, 50 }, "sorted by time")
  H.eq({ rows[2].itemID, rows[2].price, rows[2].quantity }, { 19019, 5300000, 1 })
  H.eq(rows[3].price, 11900)
  H.eq(load({ AUCTIONATOR_POSTING_HISTORY = false }).AllPostings(), {})
end)
