local H = require("harness")
local test = H.test

local function load() return H.newA({ "Core/Init.lua", "Data/Stats.lua" }).Stats end

local function series(lows, opts)
  opts = opts or {}
  local days = {}
  local start = opts.start or 1000
  for i, low in ipairs(lows) do
    days[i] = { day = start + (i - 1) * (opts.step or 1), low = low, high = low + (opts.spread or 0), qty = opts.qty }
  end
  return { key = "1", last = opts.last or lows[#lows], days = days }
end

test("Summarize computes avg, range, last day and age", function()
  local S = load()
  local s = S.Summarize(series({ 100, 110, 90 }, { qty = 7, spread = 5 }), 1004)
  H.eq(s.last, 90)
  H.eq(s.low, 90)
  H.eq(s.high, 115)
  H.eq(s.avg, 100)
  H.eq(s.nDays, 3)
  H.eq(s.qty, 7)
  H.eq(s.lastDay, 1002)
  H.eq(s.ageDays, 2)
end)

test("Summarize change1d compares the last price with the previous recorded day", function()
  local S = load()
  local s = S.Summarize(series({ 100, 110, 90 }), 1002)
  H.near(s.change1d, 90 / 110 - 1)
end)

test("Summarize change7d compares with the mean of the prior week's recorded days", function()
  local S = load()
  local s = S.Summarize(series({ 100, 110, 90 }), 1002)
  H.near(s.change7d, 90 / 105 - 1)
  -- days further back than 7 days before the latest do not count
  local old = S.Summarize(series({ 500, 100, 110, 90 }, { start = 980, step = 10 }), 1010)
  H.eq(old.change7d, nil, "no recorded days within 7 days before the latest")
  H.near(old.change1d, 90 / 110 - 1)
end)

test("Summarize with one day has no changes", function()
  local S = load()
  local s = S.Summarize(series({ 1500000 }, { qty = 2 }), 1000)
  H.eq(s.nDays, 1)
  H.eq(s.change1d, nil)
  H.eq(s.change7d, nil)
  H.eq(s.avg, 1500000)
  H.eq(s.ageDays, 0)
end)

test("Summarize handles a last price with no days and nothing at all", function()
  local S = load()
  local s = S.Summarize({ key = "x", last = 500, days = {} }, 1000)
  H.eq(s.last, 500)
  H.eq(s.nDays, 0)
  H.eq(s.avg, nil)
  H.eq(s.lastDay, nil)
  H.eq(S.Summarize(nil, 1000), nil)
  H.eq(S.Summarize({ key = "x", days = {} }, 1000), nil, "no price anywhere")
end)

test("Summarize leaves qty nil for old data without quantities", function()
  local S = load()
  H.eq(S.Summarize(series({ 5000, 4810 }), 1005).qty, nil)
end)

test("Merge unions days and lets live data win", function()
  local S = load()
  local ext = { key = "1", last = 50, days = { { day = 1, low = 10, high = 12 }, { day = 2, low = 11, high = 13 } } }
  local live = { key = "1", last = 99, days = { { day = 2, low = 20, high = 22 }, { day = 3, low = 30, high = 31 } } }
  local merged = S.Merge(ext, live)
  H.eq(#merged.days, 3)
  H.eq(merged.days[1].low, 10)
  H.eq(merged.days[2].low, 20, "live wins on the overlapping day")
  H.eq(merged.days[3].low, 30)
  H.eq(merged.last, 99)
  H.eq(S.Merge(nil, live), live)
  H.eq(S.Merge(ext, nil), ext)
  H.eq(S.Merge(nil, nil), nil)
end)

local function entry(id, change7d, last, qty)
  return { id = id, s = { change7d = change7d, last = last, qty = qty, nDays = 6, avg = last } }
end

test("Movers splits rises and drops and ignores thin or cheap items", function()
  local S = load()
  local list = {
    entry(1, 0.30, 10000, 20), entry(2, 0.10, 10000, 20), entry(3, -0.25, 10000, 20),
    entry(4, 0.90, 10000, 1),      -- too little quantity
    entry(5, -0.80, 100, 50),      -- too cheap
    entry(6, nil, 10000, 50),      -- no 7 day data
    entry(7, 0.30, 10000, nil),    -- unknown quantity
  }
  local up, down = S.Movers(list, {})
  H.eq({ up[1].id, up[2].id }, { 1, 2 })
  H.eq(#up, 2)
  H.eq(down[1].id, 3)
  H.eq(#down, 1)
  H.near(up[1].change, 0.30)
  local limited = S.Movers(list, { limit = 1 })
  H.eq(#limited, 1)
end)

test("BelowAverage finds items well under their recent average", function()
  local S = load()
  local function e(id, last, avg, nDays, qty)
    return { id = id, s = { last = last, avg = avg, nDays = nDays, qty = qty } }
  end
  local list = { e(1, 70, 100, 6, 5), e(2, 85, 100, 6, 5), e(3, 50, 100, 2, 5), e(4, 60, 100, 6, 1), e(5, 40, 100, 9, 9) }
  local out = S.BelowAverage(list, {})
  H.eq({ out[1].id, out[2].id }, { 5, 1 })
  H.eq(#out, 2)
  H.near(out[1].ratio, 0.4)
end)

test("InventoryValue prices items and reports the unpriced separately", function()
  local S = load()
  local prices = { [1] = 1000, [2] = 50 }
  local vendor = { [3] = 25, [2] = 5 }
  local v = S.InventoryValue({ [1] = 3, [2] = 10, [3] = 4, [4] = 1 },
    function(id) return prices[id] end, function(id) return vendor[id] end)
  H.eq(v.value, 3 * 1000 + 10 * 50)
  H.eq(v.priced, 2)
  H.eq(v.unpriced, { 3, 4 })
  H.eq(v.vendorValue, 4 * 25, "vendor value only for unpriced items")
  H.eq(v.lines[1].id, 1)
  H.eq(v.lines[1].value, 3000)
  H.eq(v.lines[2].id, 2)
end)

test("InventoryValue of nothing is zero", function()
  local S = load()
  local v = S.InventoryValue({}, function() end, function() end)
  H.eq(v.value, 0)
  H.eq(v.priced, 0)
  H.eq(v.unpriced, {})
end)

-- ---------------------------------------------------------------------------
-- Extra facts Summarize keeps for judging a move
-- ---------------------------------------------------------------------------
local function lowsWithQty(lows, qtys, opts)
  opts = opts or {}
  local days = {}
  for i, low in ipairs(lows) do
    days[i] = { day = (opts.start or 1000) + i - 1, low = low, high = low, qty = type(qtys) == "table" and qtys[i] or qtys }
  end
  return { key = "1", last = opts.last or lows[#lows], days = days }
end

test("Summarize keeps the first day, the week baseline, the daily wobble and the typical quantity", function()
  local S = load()
  local s = S.Summarize(lowsWithQty({ 100, 110, 100, 110, 130 }, { 5, 9, 7, 3, 8 }), 1004)
  H.eq(s.firstDay, 1000)
  H.eq(s.baseDays, 4, "four recorded days in the week before the newest")
  H.near(s.base, 105)
  H.near(s.change7d, 130 / 105 - 1)
  H.near(s.vol, (0.1 + 10 / 110 + 0.1) / 3, 1e-9, "mean day-to-day change before the newest day")
  H.eq(s.qtyMed, 7, "median of 5,9,7,3,8")
end)

test("Summarize leaves the wobble unknown when there is too little history", function()
  local S = load()
  local s = S.Summarize(lowsWithQty({ 100, 120, 90 }, 10), 1002)
  H.eq(s.vol, nil, "one step is not enough to call a pattern")
  H.eq(S.Summarize(lowsWithQty({ 100 }, nil), 1000).qtyMed, nil, "no quantity data")
  H.eq(S.Summarize(lowsWithQty({ 100 }, nil), 1000).firstDay, 1000)
end)

test("Summarize treats a gap between days as less wobble per day", function()
  local S = load()
  local flat = S.Summarize(lowsWithQty({ 100, 100, 100, 100 }, 5), 1003)
  H.eq(flat.vol, 0)
  local days = {
    { day = 1000, low = 100, high = 100 }, { day = 1004, low = 120, high = 120 },
    { day = 1008, low = 140, high = 140 }, { day = 1009, low = 140, high = 140 },
  }
  local s = S.Summarize({ key = "1", last = 140, days = days }, 1009)
  H.near(s.vol, (0.2 / 2 + (140 / 120 - 1) / 2) / 2, 1e-9, "a 20% change over 4 days is 10% a day")
end)

-- ---------------------------------------------------------------------------
-- Confidence: is this move real in a healthy market?
-- ---------------------------------------------------------------------------
local function summary(lows, qty, opts)
  local S = load()
  local s = S.Summarize(lowsWithQty(lows, qty, opts), (opts and opts.today) or (1000 + #lows - 1))
  return s, S
end

local STEADY = { 1000, 1010, 990, 1005, 995, 1010, 1000 }
local function withLast(base, last)
  local out = {}
  for i, v in ipairs(base) do out[i] = v end
  out[#out + 1] = last
  return out
end

test("Confidence is a whole number from 0 to 100 with a label and reasons", function()
  local s, S = summary(withLast(STEADY, 1300), 40)
  local c = S.Confidence(s, { kind = "move", newestDay = s.lastDay })
  H.truthy(c.score >= 0 and c.score <= 100)
  H.eq(c.score, math.floor(c.score), "whole number")
  H.truthy(c.label == "high" or c.label == "medium" or c.label == "low")
  H.eq(type(c.reasons), "table")
  H.truthy(#c.reasons >= 1, "always says something")
end)

test("a deep, steady market with a clear move scores high", function()
  local s, S = summary(withLast(STEADY, 1300), 40)
  local c = S.Confidence(s, { kind = "move", newestDay = s.lastDay })
  H.truthy(c.score >= 75, "got " .. c.score)
  H.eq(c.label, "high")
end)

test("a thin market scores low however big the move", function()
  local s, S = summary(withLast(STEADY, 2000), 1)
  local c = S.Confidence(s, { kind = "move", newestDay = s.lastDay })
  H.truthy(c.score <= 30, "got " .. c.score)
  H.eq(c.label, "low")
  local text = table.concat(c.reasons, " "):lower()
  H.truthy(text:find("thin", 1, true) or text:find("listed", 1, true), text)
end)

test("a move that is within the item's usual swings scores low", function()
  local noisy = { 1000, 1400, 700, 1300, 800, 1250, 900 }
  local s, S = summary(withLast(noisy, 1300), 40)
  local c = S.Confidence(s, { kind = "move", newestDay = s.lastDay })
  local steady, S2 = summary(withLast(STEADY, 1300), 40)
  local ref = S2.Confidence(steady, { kind = "move", newestDay = steady.lastDay })
  H.truthy(c.score <= 45, "got " .. c.score)
  H.truthy(c.score < ref.score - 30)
  H.truthy(table.concat(c.reasons, " "):lower():find("swing", 1, true), table.concat(c.reasons, " "))
end)

test("a price not seen in the newest scan loses confidence", function()
  local s, S = summary(withLast(STEADY, 1300), 40)
  local fresh = S.Confidence(s, { kind = "move", newestDay = s.lastDay })
  local stale = S.Confidence(s, { kind = "move", newestDay = s.lastDay + 4 })
  H.truthy(stale.score < fresh.score - 20, fresh.score .. " vs " .. stale.score)
  H.truthy(table.concat(stale.reasons, " "):lower():find("scan", 1, true))
end)

test("more history means more confidence", function()
  local long, S = summary(withLast(STEADY, 1300), 40)
  local short = S.Summarize(lowsWithQty({ 1000, 1005, 1300 }, 40), 1002)
  local a = S.Confidence(long, { kind = "move", newestDay = long.lastDay })
  local b = S.Confidence(short, { kind = "move", newestDay = short.lastDay })
  H.truthy(b.score < a.score)
  H.truthy(table.concat(b.reasons, " "):lower():find("day", 1, true))
end)

test("an extreme jump is distrusted more than a plausible one", function()
  local s1, S = summary(withLast(STEADY, 1300), 40)
  local s2 = S.Summarize(lowsWithQty(withLast(STEADY, 10000), 40), 1007)
  local a = S.Confidence(s1, { kind = "move", newestDay = s1.lastDay })
  local b = S.Confidence(s2, { kind = "move", newestDay = s2.lastDay })
  H.truthy(b.score < a.score, a.score .. " vs " .. b.score)
end)

test("a change worth a few copper is not material", function()
  local cheap, S = summary({ 40, 40, 41, 40, 40, 40, 41, 60 }, 60)
  local c = S.Confidence(cheap, { kind = "move", newestDay = cheap.lastDay })
  local real, S2 = summary(withLast(STEADY, 1300), 60)
  local d = S2.Confidence(real, { kind = "move", newestDay = real.lastDay })
  H.truthy(c.score < d.score - 10, c.score .. " vs " .. d.score)
end)

test("Confidence copes with missing facts instead of erroring", function()
  local S = load()
  local c = S.Confidence({ last = 5000 }, { kind = "move" })
  H.truthy(c.score >= 0 and c.score <= 20, "nothing to go on: " .. c.score)
  H.nothrows(function() S.Confidence({ last = 5000, change7d = 0.4, qty = 30 }, { kind = "move" }) end)
  H.nothrows(function() S.Confidence({}, {}) end)
  H.nothrows(function() S.Confidence(nil, nil) end)
end)

test("a deal is trusted when the market is deep and the dip is clear", function()
  local lows = { 1000, 990, 1010, 1000, 995, 1005, 1000 }
  local s, S = summary(withLast(lows, 600), 40)
  local c = S.Confidence(s, { kind = "deal", newestDay = s.lastDay })
  H.truthy(c.score >= 70, "got " .. c.score)
  local thin = S.Summarize(lowsWithQty(withLast(lows, 600), 2), 1007)
  local t = S.Confidence(thin, { kind = "deal", newestDay = thin.lastDay })
  H.truthy(t.score <= 30, "got " .. t.score)
end)

-- ---------------------------------------------------------------------------
-- MoverRows / DealRows: everything that moved, with confidence, best first
-- ---------------------------------------------------------------------------
local function entryFrom(S, id, lows, qty)
  return { id = id, s = S.Summarize(lowsWithQty(lows, qty), 1000 + #lows - 1) }
end

test("MoverRows lists risers and fallers together with a confidence on each", function()
  local S = load()
  local list = {
    entryFrom(S, 1, withLast(STEADY, 1300), 40),     -- real rise
    entryFrom(S, 2, withLast(STEADY, 700), 40),      -- real fall
    entryFrom(S, 3, withLast(STEADY, 2000), 1),      -- thin-market spike
    entryFrom(S, 4, STEADY, 40),                     -- barely moved
  }
  local rows = S.MoverRows(list, { newestDay = 1007 })
  local byId = {}
  for _, r in ipairs(rows) do byId[r.id] = r end
  H.truthy(byId[1] and byId[2] and byId[3], "all three movers are listed")
  H.truthy(byId[1].change > 0 and byId[2].change < 0)
  H.truthy(byId[1].conf.score > byId[3].conf.score)
  H.eq(rows[1].id == 1 or rows[1].id == 2, true, "the trustworthy movers rank above the thin spike")
  H.eq(rows[#rows].id, 3)
  for i = 2, #rows do H.truthy(rows[i - 1].rank >= rows[i].rank, "sorted by rank") end
end)

test("MoverRows ranks by size of move times confidence", function()
  local S = load()
  local list = {
    entryFrom(S, 1, withLast(STEADY, 1100), 40),
    entryFrom(S, 2, withLast(STEADY, 1400), 40),
  }
  local rows = S.MoverRows(list, { newestDay = 1007 })
  H.eq(rows[1].id, 2, "a bigger clear move outranks a smaller one")
end)

test("MoverRows keeps thin items (they just rank low) but drops dust and unknowns", function()
  local S = load()
  local list = {
    entryFrom(S, 1, withLast(STEADY, 1300), 1),
    { id = 2, s = { change7d = 0.5, last = 50, qty = 60, nDays = 6, avg = 40 } },     -- under the price floor
    { id = 3, s = { change7d = nil, last = 5000, qty = 60, nDays = 6, avg = 5000 } }, -- no week of history
    { id = 4, s = nil },
  }
  local rows = S.MoverRows(list, { newestDay = 1007 })
  H.eq(#rows, 1)
  H.eq(rows[1].id, 1)
end)

test("DealRows finds items under their average with a confidence on each", function()
  local S = load()
  local lows = { 1000, 990, 1010, 1000, 995, 1005, 1000 }
  local list = {
    entryFrom(S, 1, withLast(lows, 600), 40),
    entryFrom(S, 2, withLast(lows, 600), 2),
    entryFrom(S, 3, withLast(lows, 950), 40),
  }
  local rows = S.DealRows(list, { newestDay = 1007 })
  H.eq(#rows, 2, "a 5% dip is not a deal")
  H.eq(rows[1].id, 1)
  H.near(rows[1].ratio, 600 / ((1000 + 990 + 1010 + 1000 + 995 + 1005 + 1000 + 600) / 8))
  H.truthy(rows[1].conf.score > rows[2].conf.score)
  H.truthy(rows[1].rank > rows[2].rank)
end)

test("Movers and BelowAverage keep working for callers that only want the raw top", function()
  local S = load()
  local list = { entry(1, 0.30, 10000, 20), entry(2, -0.25, 10000, 20) }
  local up, down = S.Movers(list, {})
  H.eq(up[1].id, 1)
  H.eq(down[1].id, 2)
end)
