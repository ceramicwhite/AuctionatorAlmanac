local ADDON, A = ...

-- Pure statistics over price series (see Adapter.GetSeries for the shape).
local Stats = {}
A.Stats = Stats

-- Thresholds in one place so they are easy to tune.
Stats.MOVER_MIN_QTY = 5
Stats.MOVER_MIN_PRICE = 500          -- 5 silver: skip junk that swings wildly
Stats.BELOW_THRESHOLD = 0.8
Stats.BELOW_MIN_DAYS = 5
Stats.BELOW_MIN_QTY = 3
Stats.WEEK = 7

-- summary = { last, low, high, avg, nDays, qty, firstDay, lastDay, ageDays, change1d, change7d,
--             base, baseDays, vol, qtyMed }
-- last      the last price Auctionator saw (m), else the newest day's low
-- avg       mean of daily lows over the available days
-- qty       quantity seen on the newest day (nil for old data without it)
-- change1d  last price vs the previous recorded day's low
-- change7d  last price vs the mean daily low of recorded days in the week before the newest day
-- base      that mean; baseDays is how many recorded days it is made of
-- vol       the item's usual day-to-day wobble (mean relative change), nil with too little history
-- qtyMed    the typical quantity on the market, so one sold-out day is not mistaken for depth
function Stats.Summarize(series, todayDay)
  if type(series) ~= "table" then return nil end
  local days = series.days or {}
  local n = #days
  local newest = days[n]
  local last = series.last or (newest and newest.low)
  if last == nil then return nil end

  local s = { last = last, nDays = n }
  if n > 0 then
    local sum, low, high = 0, nil, nil
    for i = 1, n do
      local d = days[i]
      sum = sum + d.low
      if not low or d.low < low then low = d.low end
      local top = d.high or d.low
      if not high or top > high then high = top end
    end
    s.low, s.high, s.avg = low, high, sum / n
    s.qty = newest.qty
    s.lastDay = newest.day
    s.firstDay = days[1].day
    if todayDay then s.ageDays = todayDay - newest.day end

    if n >= 2 and days[n - 1].low > 0 then
      s.change1d = last / days[n - 1].low - 1
    end

    local total, count = 0, 0
    for i = 1, n - 1 do
      local gap = newest.day - days[i].day
      if gap >= 1 and gap <= Stats.WEEK then
        total = total + days[i].low
        count = count + 1
      end
    end
    s.baseDays = count
    if count >= 1 and total > 0 then s.base = total / count end
    if count >= 2 and total > 0 then
      s.change7d = last / (total / count) - 1
    end

    -- Typical day-to-day wobble over the days before the newest one (the newest step
    -- is the move being judged, so it is left out). A gap of g days counts as 1/sqrt(g)
    -- of the change, since prices drift further the longer they are left alone.
    local wobble, steps = 0, 0
    for i = 2, n - 1 do
      local gap = days[i].day - days[i - 1].day
      local before = days[i - 1].low
      if gap >= 1 and before > 0 then
        wobble = wobble + math.abs(days[i].low / before - 1) / math.sqrt(gap)
        steps = steps + 1
      end
    end
    if steps >= 2 then s.vol = wobble / steps end

    local quantities = {}
    for i = 1, n do
      if days[i].qty then quantities[#quantities + 1] = days[i].qty end
    end
    if #quantities > 0 then
      table.sort(quantities)
      local mid = (#quantities + 1) / 2
      s.qtyMed = (quantities[math.floor(mid)] + quantities[math.ceil(mid)]) / 2
    end
  end
  return s
end

-- Combine extended history (Almanac's own snapshots) with Auctionator's live
-- window. Live data wins where both have the same day.
function Stats.Merge(ext, live)
  if not ext then return live end
  if not live then return ext end
  local byDay, order = {}, {}
  for _, source in ipairs({ ext, live }) do
    for _, d in ipairs(source.days or {}) do
      if not byDay[d.day] then order[#order + 1] = d.day end
      byDay[d.day] = d
    end
  end
  table.sort(order)
  local days = {}
  for i, day in ipairs(order) do days[i] = byDay[day] end
  return { key = live.key or ext.key, last = live.last or ext.last, days = days }
end

-- list = { {id, s = summary} }. Returns up[], down[] of {id, s, change} by 7 day change.
function Stats.Movers(list, opts)
  opts = opts or {}
  local minQty = opts.minQty or Stats.MOVER_MIN_QTY
  local minPrice = opts.minPrice or Stats.MOVER_MIN_PRICE
  local limit = opts.limit or 10
  local up, down = {}, {}
  for _, e in ipairs(list) do
    local s = e.s
    if s and s.change7d and s.qty and s.qty >= minQty and s.last >= minPrice then
      local row = { id = e.id, s = s, change = s.change7d }
      if s.change7d > 0 then up[#up + 1] = row elseif s.change7d < 0 then down[#down + 1] = row end
    end
  end
  table.sort(up, function(a, b)
    if a.change ~= b.change then return a.change > b.change end
    return a.id < b.id
  end)
  table.sort(down, function(a, b)
    if a.change ~= b.change then return a.change < b.change end
    return a.id < b.id
  end)
  for i = #up, limit + 1, -1 do up[i] = nil end
  for i = #down, limit + 1, -1 do down[i] = nil end
  return up, down
end

-- Items whose last price is well under their recent average: {id, s, ratio} cheapest ratio first.
function Stats.BelowAverage(list, opts)
  opts = opts or {}
  local threshold = opts.threshold or Stats.BELOW_THRESHOLD
  local minDays = opts.minDays or Stats.BELOW_MIN_DAYS
  local minQty = opts.minQty or Stats.BELOW_MIN_QTY
  local limit = opts.limit or 10
  local out = {}
  for _, e in ipairs(list) do
    local s = e.s
    if s and s.avg and s.avg > 0 and s.nDays >= minDays and s.qty and s.qty >= minQty then
      local ratio = s.last / s.avg
      if ratio <= threshold then out[#out + 1] = { id = e.id, s = s, ratio = ratio } end
    end
  end
  table.sort(out, function(a, b)
    if a.ratio ~= b.ratio then return a.ratio < b.ratio end
    return a.id < b.id
  end)
  for i = #out, limit + 1, -1 do out[i] = nil end
  return out
end

-- counts = {[itemID] = n}. Items without an AH price are listed as unpriced and
-- valued at their vendor price separately, never mixed into `value`.
function Stats.InventoryValue(counts, priceOf, vendorOf)
  local result = { value = 0, priced = 0, unpriced = {}, vendorValue = 0, lines = {} }
  for id, count in pairs(counts) do
    if count > 0 then
      local price = priceOf(id)
      if price then
        result.priced = result.priced + 1
        result.value = result.value + price * count
        result.lines[#result.lines + 1] = { id = id, count = count, price = price, value = price * count }
      else
        result.unpriced[#result.unpriced + 1] = id
        local vendor = vendorOf(id)
        if vendor then result.vendorValue = result.vendorValue + vendor * count end
      end
    end
  end
  table.sort(result.unpriced)
  table.sort(result.lines, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.id < b.id
  end)
  return result
end

-- ---------------------------------------------------------------------------
-- Confidence: is this price move believable in a healthy market?
--
-- Most false "big movers" come from a handful of causes, and each gets a factor
-- between 0 and 1 (1 = no concern):
--   depth     few listings mean one seller sets the price. Judged on the smaller of
--             today's quantity and the typical quantity, so a sold-out day is not depth.
--   signal    a 30% move means little for an item that swings 30% every day. The move
--             is measured in units of the item's own day-to-day wobble.
--   history   a week of days to compare against beats two.
--   fresh     the price should have been seen in the newest scan, not days earlier.
--   material  a move worth a few copper is rounding noise on cheap items.
--   sane      a 10x jump is usually one odd listing, not a market.
-- The score is the product of the factors raised to a weight, so any one serious
-- problem pulls the whole score down; a good score needs every factor to hold up.
-- ---------------------------------------------------------------------------
Stats.CONF_HIGH = 70
Stats.CONF_MEDIUM = 40
Stats.MOVE_MIN = 0.05            -- a smaller move is not worth calling a move
Stats.ROW_MIN_PRICE = 100        -- 1 silver: skip copper-level dust

local exp, log = math.exp, math.log
local WEIGHT = { depth = 1.0, signal = 0.8, history = 0.5, fresh = 0.5, material = 0.3, sane = 0.9 }
local FLAG_BELOW = log(0.8)      -- a weighted factor under this is worth telling the player about
local LOG_FLOOR = 1e-6

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

-- Sentences for the factors that dragged a score down. Only built for the few factors that are
-- flagged, and only when a row is actually scored: with 15,000 items this runs on every one.
local function describe(name, s, ctx)
  if name == "depth" then
    if not ctx.qty then return "No quantity data for this item" end
    return "Thin market: only " .. plural(math.floor(ctx.qty), "listing") .. " up"
      .. (s.qtyMed and s.qtyMed > ctx.qty and (" (usually " .. math.floor(s.qtyMed) .. ")") or "")
  elseif name == "history" then
    return "Only " .. plural(ctx.historyDays, "day") .. " of history to compare against"
  elseif name == "fresh" then
    return "Last priced " .. plural(ctx.lag, "day") .. " before the newest scan"
  elseif name == "signal" then
    if s.vol then
      return "Within normal swings: it usually moves about " .. math.floor(s.vol * 100 + 0.5) .. "% a day"
    end
    return "Too little history to know its usual swings"
  elseif name == "material" then
    return "A difference of only " .. math.floor(ctx.absMove + 0.5) .. " copper"
  end
  return "Extreme jump (x" .. string.format("%.0f", ctx.ratio) .. "), often a single odd listing"
end

-- kind: "move" (7 day change) or "deal" (price against the average).
-- opts.newestDay: the newest scan day in the data, to judge staleness against.
-- Returns { score = 0..100, label = "high"|"medium"|"low", reasons = { text... } }.
function Stats.Confidence(s, opts)
  opts = opts or {}
  s = type(s) == "table" and s or {}
  local kind = opts.kind == "deal" and "deal" or "move"
  local last = s.last

  local baseline, change
  if kind == "move" then
    change = s.change7d
    baseline = s.base or ((change and last and change > -1) and last / (1 + change) or nil)
  else
    baseline = s.avg
    change = (last and baseline and baseline > 0) and (last / baseline - 1) or nil
  end
  if not (last and last > 0 and baseline and baseline > 0 and change) then
    return { score = 0, label = "low", reasons = { "Not enough price history to judge" } }
  end

  -- how many listings the price really rests on: the smaller of now and typical
  local qty = s.qty
  local qEff = qty and (s.qtyMed and math.min(qty, s.qtyMed) or qty) or nil
  local historyDays = (kind == "move" and s.baseDays or s.nDays) or 0
  local lag = (opts.newestDay and s.lastDay) and math.max(0, opts.newestDay - s.lastDay) or 0
  local vol = math.max(s.vol or 0.12, 0.02)
  local absMove = math.abs(last - baseline)
  local ratio = last / baseline

  -- each log is weight * ln(factor); the score is exp of their sum
  local lDepth = WEIGHT.depth * log(math.max(qEff and (1 - exp(-qEff / 8)) or 0.4, LOG_FLOOR))
  local lHistory = WEIGHT.history * log(math.max(1 - exp(-historyDays / 3), LOG_FLOOR))
  local lFresh = WEIGHT.fresh * (-lag / 3)
  local lSignal = WEIGHT.signal * log(math.max(1 - exp(-(math.abs(change) / vol) / 2.5), LOG_FLOOR))
  local lMaterial = WEIGHT.material * log(math.max(1 - exp(-absMove / 150), LOG_FLOOR))
  local jump = math.abs(log(ratio))
  local lSane = WEIGHT.sane * -log(1 + math.max(0, jump - log(3)))

  local score = math.floor(exp(lDepth + lHistory + lFresh + lSignal + lMaterial + lSane) * 100 + 0.5)
  local label = score >= Stats.CONF_HIGH and "high" or (score >= Stats.CONF_MEDIUM and "medium" or "low")

  -- Which factors are worth explaining. Most rows have none, so nothing is allocated for them.
  local flagged
  if lDepth < FLAG_BELOW or lHistory < FLAG_BELOW or lFresh < FLAG_BELOW
    or lSignal < FLAG_BELOW or lMaterial < FLAG_BELOW or lSane < FLAG_BELOW then
    flagged = {}
    local candidates = {
      { "depth", lDepth }, { "history", lHistory }, { "fresh", lFresh },
      { "signal", lSignal }, { "material", lMaterial }, { "sane", lSane },
    }
    for _, c in ipairs(candidates) do
      if c[2] < FLAG_BELOW then flagged[#flagged + 1] = { name = c[1], l = c[2] } end
    end
  end

  local reasons = {}
  if flagged then
    table.sort(flagged, function(a, b)
      if a.l ~= b.l then return a.l < b.l end
      return a.name < b.name
    end)
    local ctx = {
      qty = qty, historyDays = historyDays, lag = lag, absMove = absMove,
      ratio = math.max(ratio, 1 / ratio),
    }
    for i = 1, math.min(3, #flagged) do reasons[i] = describe(flagged[i].name, s, ctx) end
  else
    reasons[1] = kind == "move" and "Deep market and a move well outside its usual swings"
      or "Deep market and a dip well outside its usual swings"
  end
  return { score = score, label = label, reasons = reasons }
end

local function byRankThenID(a, b)
  if a.rank ~= b.rank then return a.rank > b.rank end
  return a.id < b.id
end

-- Every item whose price moved, risers and fallers together: { id, s, change, conf, rank }.
-- rank is the size of the move (capped at 100%) times confidence, so a clear +30% in a deep
-- market outranks a +900% on a single listing. Thin items stay in the list, ranked low.
-- list = { {id, s = summary} }
function Stats.MoverRows(list, opts)
  opts = opts or {}
  local minPrice = opts.minPrice or Stats.ROW_MIN_PRICE
  local minChange = opts.minChange or Stats.MOVE_MIN
  local rows = {}
  for _, e in ipairs(list) do
    local s = e.s
    if s and s.change7d and s.last and s.last >= minPrice and math.abs(s.change7d) >= minChange then
      local conf = Stats.Confidence(s, { kind = "move", newestDay = opts.newestDay })
      rows[#rows + 1] = {
        id = e.id, s = s, change = s.change7d, conf = conf,
        rank = math.min(math.abs(s.change7d), 1) * conf.score / 100,
      }
    end
  end
  table.sort(rows, byRankThenID)
  return rows
end

-- Items priced well under their average: { id, s, ratio, conf, rank }. Same idea as MoverRows.
function Stats.DealRows(list, opts)
  opts = opts or {}
  local threshold = opts.threshold or Stats.BELOW_THRESHOLD
  local minDays = opts.minDays or Stats.BELOW_MIN_DAYS
  local minQty = opts.minQty or 1
  local rows = {}
  for _, e in ipairs(list) do
    local s = e.s
    if s and s.avg and s.avg > 0 and s.last and (s.nDays or 0) >= minDays and (s.qty == nil or s.qty >= minQty) then
      local ratio = s.last / s.avg
      if ratio <= threshold then
        local conf = Stats.Confidence(s, { kind = "deal", newestDay = opts.newestDay })
        rows[#rows + 1] = { id = e.id, s = s, ratio = ratio, conf = conf, rank = (1 - ratio) * conf.score / 100 }
      end
    end
  end
  table.sort(rows, byRankThenID)
  return rows
end
