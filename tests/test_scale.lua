local H = require("harness")
local Stub = require("ui_stub")
local Boot = require("boot_ui")
local Fx = require("fixtures")
local test = H.test

-- A realistic-size price database: 15,000 items with 21 days of history each.
local N = 15000
local function bigDatabase()
  local db = {}
  for id = 1, N do
    local h, a = {}, {}
    for d = 985, 1005 do
      h[tostring(d)] = 1000 + (id * 7 + d * 13) % 5000
      a[tostring(d)] = (id + d) % 90 + 1
    end
    db[tostring(id + 100000)] = { m = h["1005"], h = h, l = {}, a = a }
    Boot.ITEMS[id + 100000] = { name = "Scale Item " .. id, quality = id % 5, class = (id % 3) * 2 + 1, sub = id % 4, sell = id % 50 }
  end
  return db
end

test("15,000 items load, search, sort and render with a bounded number of widgets", function()
  local db = bigDatabase()
  local A, env = Boot.boot({ noReload = true, fixture = { Auctionator = {
    State = { Loaded = true, CurrentRealm = "R" }, Database = { db = db }, Constants = { SCAN_DAY_0 = Fx.DAY0 },
    Config = { Options = { PRICE_HISTORY_DAYS = "price_history_days" }, Get = function() return 21 end },
  } } })
  A.Controller.Reload()
  env.C_Timer.flush(100000)
  H.eq(#A.Controller.ids, N)
  H.eq(A.Controller.pricedCount, N)
  H.eq(#A.Controller.results, N)

  local win = Boot.open(A, env)
  local rows = #win.resultsTable.list.rows
  H.truthy(rows >= 10 and rows <= 40, "result rows are a small pool, got " .. rows)
  local widgets = #env.__all
  H.truthy(widgets < 2500, "no widget per item, got " .. widgets)

  A.Controller.SetSearchText('"scale item 77"')
  env.C_Timer.flush()
  H.eq(#A.Controller.results, 111, "Scale Item 77, 770-779, 7700-7799 (= 1 + 10 + 100)")
  A.Controller.SetSearchText("scale item 77")
  env.C_Timer.flush()
  H.eq(#A.Controller.results, 375, "without quotes every word may match anywhere in the name")
  A.Controller.SetSort("price", false)
  local first = A.Controller.Summary(A.Controller.results[1]).last
  local last = A.Controller.Summary(A.Controller.results[#A.Controller.results]).last
  H.truthy(first >= last, "highest price first")
  A.Controller.ClearFilters()
  H.eq(#A.Controller.results, N)

  A.Controller.Select(100500)
  Stub.settle(env)
  H.eq(win.itemView.history.graph.layout and #win.itemView.history.graph.layout.points, 21)
end)
