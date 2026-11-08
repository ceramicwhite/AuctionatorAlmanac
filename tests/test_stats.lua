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
