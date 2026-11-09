local H = require("harness")
local test = H.test

local function load()
  local A = H.newA({ "Core/Init.lua", "Data/Stats.lua", "Tracker/History.lua" })
  A.db = A.InitDB(nil)
  A.History.Init(A.db)
  return A.History, A
end

-- Adapter stub: GetSeries(key) from a table of series by key.
local function adapter(seriesByKey)
  return { GetSeries = function(key) return seriesByKey[key] end }
end

local function s(days) return { key = "x", last = 1, days = days } end

test("Snapshot stores tracked items' days and is idempotent", function()
  local History = load()
  local ad = adapter({ ["12359"] = s({ { day = 1000, low = 100, high = 120, qty = 5 }, { day = 1001, low = 90, high = 90, qty = 7 } }) })
  H.eq(History.Snapshot(ad, { [12359] = true }, 1005, 365), 1)
  local series = History.Series(12359)
  H.eq(#series.days, 2)
  H.eq(series.days[1], { day = 1000, low = 100, high = 120, qty = 5 })
  H.eq(series.days[2], { day = 1001, low = 90, high = 90, qty = 7 })
  History.Snapshot(ad, { [12359] = true }, 1005, 365)
  H.eq(#History.Series(12359).days, 2, "no duplicates")
end)

test("Snapshot overwrites a day Auctionator later revised", function()
  local History = load()
  local live = { ["1"] = s({ { day = 1000, low = 100, high = 100, qty = 5 } }) }
  History.Snapshot(adapter(live), { [1] = true }, 1000, 365)
  live["1"] = s({ { day = 1000, low = 80, high = 100, qty = 9 } })
  History.Snapshot(adapter(live), { [1] = true }, 1000, 365)
  H.eq(History.Series(1).days[1], { day = 1000, low = 80, high = 100, qty = 9 })
end)

test("untracked items are not stored", function()
  local History = load()
  local ad = adapter({ ["1"] = s({ { day = 1000, low = 1, high = 1 } }), ["2"] = s({ { day = 1000, low = 2, high = 2 } }) })
  History.Snapshot(ad, { [1] = true }, 1000, 365)
  H.eq(History.Series(2), nil)
  H.truthy(History.Series(1))
end)

test("items missing from Auctionator are skipped without error", function()
  local History = load()
  H.eq(History.Snapshot(adapter({}), { [99] = true }, 1000, 365), 0)
  H.eq(History.Series(99), nil)
end)

test("days older than the keep window are pruned, newer kept", function()
  local History = load()
  local ad = adapter({ ["1"] = s({ { day = 970, low = 1, high = 1 }, { day = 980, low = 2, high = 2 }, { day = 1005, low = 3, high = 3 } }) })
  History.Snapshot(ad, { [1] = true }, 1005, 30)
  local days = History.Series(1).days
  H.eq({ days[1].day, days[2].day }, { 980, 1005 })
end)

test("a fully pruned item is dropped from storage", function()
  local History, A = load()
  History.Snapshot(adapter({ ["1"] = s({ { day = 100, low = 1, high = 1 } }) }), { [1] = true }, 100, 365)
  History.Snapshot(adapter({}), {}, 2000, 365)
  H.eq(History.Series(1), nil)
  H.eq(A.db.history.items[1], nil)
end)

test("quantity stays nil when Auctionator had none", function()
  local History = load()
  History.Snapshot(adapter({ ["1"] = s({ { day = 1000, low = 5, high = 6 } }) }), { [1] = true }, 1000, 365)
  H.eq(History.Series(1).days[1].qty, nil)
end)

test("Series merges with live data through Stats.Merge", function()
  local History, A = load()
  History.Snapshot(adapter({ ["1"] = s({ { day = 1, low = 10, high = 10 }, { day = 2, low = 11, high = 11 } }) }), { [1] = true }, 5, 365)
  local live = { key = "1", last = 99, days = { { day = 2, low = 20, high = 20 }, { day = 3, low = 30, high = 30 } } }
  local merged = A.Stats.Merge(History.Series(1), live)
  H.eq({ merged.days[1].low, merged.days[2].low, merged.days[3].low }, { 10, 20, 30 })
end)

test("viewed items are capped at 200 with most recent first and no duplicates", function()
  local History = load()
  for id = 1, 250 do History.MarkViewed(id) end
  local viewed = History.Viewed()
  H.eq(#viewed, 200)
  H.eq(viewed[1], 250)
  H.eq(viewed[200], 51)
  History.MarkViewed(100)
  viewed = History.Viewed()
  H.eq(viewed[1], 100)
  H.eq(#viewed, 200)
  local count = 0
  for _, id in ipairs(viewed) do if id == 100 then count = count + 1 end end
  H.eq(count, 1)
end)

test("watching and tracked set", function()
  local History = load()
  History.Watch(7, true)
  History.Watch(8, true)
  History.Watch(8, false)
  H.truthy(History.IsWatched(7))
  H.falsy(History.IsWatched(8))
  H.eq(History.Watched(), { 7 })
  History.MarkViewed(9)
  local tracked = History.TrackedIDs({ { [1] = 5, [2] = 3 }, { [4] = true } })
  H.eq(tracked, { [7] = true, [9] = true, [1] = true, [2] = true, [4] = true })
end)

test("a watched item remembers the price and day it was added", function()
  local History = load()
  History.Watch(7, true, { price = 12000, day = 1005, time = 555 })
  local w = History.WatchInfo(7)
  H.eq(w.price, 12000)
  H.eq(w.day, 1005)
  H.eq(w.time, 555)
  History.Watch(7, true, { price = 99999, day = 1010 })
  H.eq(History.WatchInfo(7).price, 12000, "watching again does not rewrite when it was added")
  H.eq(History.WatchInfo(8), nil)
  History.Watch(7, false)
  H.eq(History.WatchInfo(7), nil)
end)

test("watching without details still works, and so do older saved watch lists", function()
  local History, A = load()
  History.Watch(3, true)
  H.truthy(History.IsWatched(3))
  H.eq(History.WatchInfo(3), {}, "watched, with nothing known about when")
  A.db.history.watched[4] = true                      -- how the first version saved it
  H.truthy(History.IsWatched(4))
  H.eq(History.Watched(), { 3, 4 })
  H.eq(History.WatchInfo(4), {})
end)

test("changing the watch list announces it", function()
  local History, A = load()
  local seen = {}
  A.Bus.On("WATCH_CHANGED", function(id, on) seen[#seen + 1] = id .. ":" .. tostring(on) end)
  History.Watch(7, true)
  History.Watch(7, true)
  History.Watch(7, false)
  History.Watch(7, false)
  H.eq(seen, { "7:true", "7:false" }, "only real changes are announced")
end)

test("watched items are always tracked for long-term history", function()
  local History = load()
  History.Watch(7, true, { price = 1 })
  H.truthy(History.TrackedIDs({})[7])
end)
