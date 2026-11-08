local H = require("harness")
local test = H.test

local function load()
  local A = H.newA({ "Core/Init.lua", "Core/Format.lua" }, { date = function(fmt, t) return os.date("!" .. fmt, t) end })
  -- Graph.lua needs the UI namespace; its pure Layout does not touch widgets.
  A.UI = { Theme = { color = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }), hex = {} } }
  local f = assert(loadfile(H.addonDir .. "/UI/Graph.lua"))
  H.graphLoader = f
  local ok, err = pcall(f, "AuctionatorAlmanac", A)
  if not ok then error(err) end
  return A.UI.Graph, A
end

local function day(d, low, high, qty) return { day = d, low = low, high = high or low, qty = qty } end
local THREE = { day(1000, 100, 120, 10), day(1001, 90, 90, 40), day(1002, 110, 130, 20) }

test("Layout places points across the width and scales prices to the height", function()
  local G = load()
  local L = G.Layout(THREE, { range = 0 }, 300, 100)
  H.eq(#L.points, 3)
  H.near(L.points[1].x, G.PAD)
  H.near(L.points[2].x, 150)
  H.near(L.points[3].x, 300 - G.PAD)
  H.truthy(L.yMin <= 90 and L.yMax >= 130)
  H.truthy(L.points[2].yLow < L.points[1].yLow and L.points[1].yLow < L.points[3].yLow, "lower price, lower point")
  for _, p in ipairs(L.points) do
    H.truthy(p.yLow >= 0 and p.yHigh <= 100 and p.yLow <= p.yHigh, "inside the plot")
  end
  H.eq({ L.points[1].low, L.points[1].high, L.points[1].qty, L.points[1].day }, { 100, 120, 10, 1000 })
end)

test("Layout scales quantity bars to the busiest day and gives missing quantities no bar", function()
  local G = load()
  local L = G.Layout({ day(1, 10, 10, 50), day(2, 10, 10, 25), day(3, 10, 10, nil) }, { range = 0 }, 300, 100)
  H.near(L.points[1].yQty, G.BAR_FRACTION * 100)
  H.near(L.points[2].yQty, G.BAR_FRACTION * 100 / 2)
  H.eq(L.points[3].yQty, 0)
  H.truthy(L.barWidth > 0)
end)

test("a single day is centered and flat prices do not divide by zero", function()
  local G = load()
  local L = G.Layout({ day(1005, 1500000, 1500000, 2) }, { range = 0 }, 300, 100)
  H.near(L.points[1].x, 150)
  H.truthy(L.yMax > L.yMin)
  H.truthy(L.points[1].yLow > 0 and L.points[1].yLow < 100)
  local flat = G.Layout({ day(1, 5, 5), day(2, 5, 5) }, { range = 0 }, 300, 100)
  H.truthy(flat.yMax > flat.yMin)
  for _, t in ipairs(flat.yTicks) do H.truthy(t.y >= 0 and t.y <= 100) end
end)

test("a fixed range spans its whole window even when data covers part of it", function()
  local G = load()
  local days = { day(990, 1, 1), day(1000, 100, 100), day(1004, 110, 110) }
  local L = G.Layout(days, { range = 7, today = 1005 }, 300, 100)
  H.eq(#L.points, 2, "days 1000 and 1004 are inside (999..1005); 990 is not")
  H.eq({ L.points[1].day, L.points[2].day }, { 1000, 1004 })
  H.eq({ L.firstDay, L.lastDay }, { 999, 1005 })
  H.near(L.points[2].x, G.PAD + (1004 - 999) / (1005 - 999) * (300 - 2 * G.PAD))
end)

test("range 0 spans the data and nothing in range gives nil", function()
  local G = load()
  local L = G.Layout({ day(10, 1, 1), day(20, 2, 2) }, { range = 0, today = 100 }, 300, 100)
  H.eq({ L.firstDay, L.lastDay }, { 10, 20 })
  H.eq(G.Layout({ day(10, 1, 1) }, { range = 7, today = 100 }, 300, 100), nil)
  H.eq(G.Layout({}, { range = 0 }, 300, 100), nil)
  H.eq(G.Layout(nil, { range = 0 }, 300, 100), nil)
end)

test("ticks are ascending, labelled, and bounded", function()
  local G = load()
  local L = G.Layout(THREE, { range = 0 }, 300, 100)
  H.eq(#L.yTicks, 4)
  for i = 2, #L.yTicks do
    H.truthy(L.yTicks[i].y > L.yTicks[i - 1].y)
    H.truthy(L.yTicks[i].value > L.yTicks[i - 1].value)
  end
  H.truthy(L.yTicks[1].label:find("c") or L.yTicks[1].label:find("s") or L.yTicks[1].label:find("g"))
  H.truthy(#L.xTicks >= 2 and #L.xTicks <= 5)
  H.near(L.xTicks[1].x, G.PAD)
  H.near(L.xTicks[#L.xTicks].x, 300 - G.PAD)
end)

test("markers are placed at their day, grouped, and clipped to the window", function()
  local G = load()
  local markers = {
    { day = 1001, kind = "sold", text = "Sold 20" },
    { day = 1001, kind = "sold", text = "Sold 5" },
    { day = 1001, kind = "bought", text = "Bought 1" },
    { day = 900, kind = "sold", text = "too old" },
  }
  local L = G.Layout(THREE, { range = 0, markers = markers }, 300, 100)
  H.eq(#L.markers, 2)
  local sold
  for _, m in ipairs(L.markers) do if m.kind == "sold" then sold = m end end
  H.eq(sold.count, 2)
  H.near(sold.x, 150)
  H.eq(#sold.events, 2)
end)

test("NearestPoint finds the closest day to the cursor", function()
  local G = load()
  local L = G.Layout(THREE, { range = 0 }, 300, 100)
  H.eq(G.NearestPoint(L, 0), 1)
  H.eq(G.NearestPoint(L, 140), 2)
  H.eq(G.NearestPoint(L, 290), 3)
  H.eq(G.NearestPoint(L, 9999), 3)
  H.eq(G.NearestPoint(nil, 10), nil)
end)

test("Layout copes with very small plots", function()
  local G = load()
  H.nothrows(function() G.Layout(THREE, { range = 0 }, 20, 10) end)
  H.nothrows(function() G.Layout(THREE, { range = 0 }, 0, 0) end)
end)
