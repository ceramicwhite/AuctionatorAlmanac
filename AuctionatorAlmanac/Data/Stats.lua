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

-- summary = { last, low, high, avg, nDays, qty, lastDay, ageDays, change1d, change7d }
-- last      the last price Auctionator saw (m), else the newest day's low
-- avg       mean of daily lows over the available days
-- qty       quantity seen on the newest day (nil for old data without it)
-- change1d  last price vs the previous recorded day's low
-- change7d  last price vs the mean daily low of recorded days in the week before the newest day
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
    if count >= 2 and total > 0 then
      s.change7d = last / (total / count) - 1
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
