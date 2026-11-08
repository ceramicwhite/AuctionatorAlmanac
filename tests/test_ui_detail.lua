local H = require("harness")
local Stub = require("ui_stub")
local Boot = require("boot_ui")
local Fx = require("fixtures")
local test = H.test

local function plain(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  return s
end

local function open(opts)
  local A, env = Boot.boot(opts)
  local win = Boot.open(A, env)
  return A, env, win
end

local function select(A, env, id)
  A.Controller.Select(id)
  env.C_Timer.flush()
  Stub.settle(env)
end

local function cellText(tbl, row, col) return plain(tbl.list.rows[row].cells[col].text:GetText()) end

test("selecting an item shows its header and swaps out the overview", function()
  local A, env, win = open()
  H.truthy(win.homeView:IsShown())
  select(A, env, 12359)
  local iv = win.itemView
  H.truthy(iv:IsShown())
  H.falsy(win.homeView:IsShown())
  H.eq(plain(iv.name:GetText()), "Thorium Bar")
  H.truthy(plain(iv.subtitle:GetText()):find("Trade Goods", 1, true))
  H.truthy(plain(iv.subtitle:GetText()):find("Enchanting", 1, true))
end)

test("the stats row shows price, average, change, range, quantity and vendor value", function()
  local A, env, win = open()
  select(A, env, 12359)
  local s = win.itemView.stat
  H.eq(plain(s.lowest.value:GetText()), "1g 12s 40c")
  H.eq(plain(s.average.value:GetText()), "1g 10s")
  H.eq(plain(s.change.value:GetText()), "+2%")
  H.truthy(plain(s.range.value:GetText()):find("1g 8s", 1, true))
  H.truthy(plain(s.range.value:GetText()):find("1g 18s", 1, true))
  H.eq(plain(s.quantity.value:GetText()), "44")
  H.eq(plain(s.vendor.value:GetText()), "4s")
end)

test("missing data is labelled, not shown as zero", function()
  local A, env, win = open()
  select(A, env, 12363)    -- single day, no change data, vendor price 0
  local s = win.itemView.stat
  H.eq(plain(s.change.value:GetText()), "—")
  H.eq(plain(s.vendor.value:GetText()), "—")
  select(A, env, 10620)    -- old data without quantities
  H.eq(plain(win.itemView.stat.quantity.value:GetText()), "—")
end)

test("the history tab draws the price graph and lists days newest first", function()
  local A, env, win = open()
  select(A, env, 12359)
  local h = win.itemView.history
  H.truthy(h:IsShown())
  H.eq(#h.graph.layout.points, 5)
  local t = h.table
  H.eq(cellText(t, 1, 2), "1g 9s")
  H.eq(cellText(t, 1, 3), "1g 12s 40c")
  H.eq(cellText(t, 1, 4), "44")
  H.truthy(cellText(t, 1, 1):find("Oct 2", 1, true), cellText(t, 1, 1))
  H.truthy(cellText(t, 5, 1):find("Sep 27", 1, true), cellText(t, 5, 1))
end)

test("range buttons change the graph window", function()
  local A, env, win = open()
  select(A, env, 12359)
  local h = win.itemView.history
  h.rangeButtons[0]:Click()
  H.eq(h.graph.layout.firstDay, 1000)
  h.rangeButtons[7]:Click()
  H.eq({ h.graph.layout.firstDay, h.graph.layout.lastDay }, { 999, 1005 })
  h.rangeButtons[90]:Click()
  H.eq(h.graph.layout.firstDay, 1005 - 90 + 1)
  H.truthy(h.rangeButtons[90].active)
end)

test("an item with extended history shows more days than Auctionator keeps", function()
  local A, env, win = open()
  A.History.Snapshot(A.Adapter, { [12359] = true }, 1005, 365)
  A.db.history.items[12359].h[800] = 9000
  select(A, env, 12359)
  local h = win.itemView.history
  h.rangeButtons[0]:Click()
  H.eq(h.graph.layout.firstDay, 800)
  H.eq(#h.table.list.data, 6)
end)

test("your sales and purchases appear as markers on the graph", function()
  local A, env, win = open()
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 20, total = 220000, time = A.Adapter.DayToTime(1003) + 3600, source = "mail", party = "Buyer", char = "Thornwick" })
  A.Ledger.Add({ kind = "bought", itemID = 12359, qty = 5, total = 50000, time = A.Adapter.DayToTime(1001) + 100, source = "ah", char = "Thornwick" })
  select(A, env, 12359)
  local layout = win.itemView.history.graph.layout
  H.eq(#layout.markers, 2)
  local kinds = {}
  for _, m in ipairs(layout.markers) do kinds[m.kind] = m.day end
  H.eq(kinds, { bought = 1001, sold = 1003 })
end)

test("hovering the graph reports the nearest day", function()
  local A, env, win = open()
  select(A, env, 12359)
  local g = win.itemView.history.graph
  g:HoverAt(0)
  H.eq(g.hoverIndex, 1)
  g:HoverAt(99999)
  H.eq(g.hoverIndex, #g.layout.points)
  g:ClearHover()
  H.eq(g.hoverIndex, nil)
end)

test("the activity tab lists your sales and purchases with totals", function()
  local A, env, win = open()
  local t0 = A.Adapter.DayToTime(1003)
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 20, total = 220000, fee = 11000, time = t0, source = "mail", party = "Buyer", char = "Thornwick" })
  A.Ledger.Add({ kind = "bought", itemID = 12359, qty = 20, total = 200000, time = t0 + 5000, source = "ah", char = "Thornwick" })
  A.Ledger.Add({ kind = "posted", itemID = 12359, qty = 20, total = 230000, time = t0 - 5000, source = "auctionator" })
  select(A, env, 12359)
  local iv = win.itemView
  iv.tabs:Select("activity")
  Stub.settle(env)
  H.truthy(iv.activity:IsShown())
  H.falsy(iv.history:IsShown())
  local t = iv.activity.table
  H.eq(cellText(t, 1, 2), "Bought")
  H.eq(cellText(t, 2, 2), "Sold")
  H.eq(cellText(t, 3, 2), "Posted")
  H.eq(cellText(t, 2, 3), "20")
  H.eq(cellText(t, 2, 5), "22g")
  local summary = plain(iv.activity.summary:GetText())
  H.truthy(summary:find("Sold 20", 1, true), summary)
  H.truthy(summary:find("Bought 20", 1, true), summary)
  H.falsy(iv.activity.empty:IsShown())
end)

test("the activity tab explains itself when nothing has been recorded", function()
  local A, env, win = open()
  select(A, env, 12359)
  win.itemView.tabs:Select("activity")
  H.truthy(win.itemView.activity.empty:IsShown())
  H.truthy(plain(win.itemView.activity.empty:GetText()):lower():find("recorded", 1, true))
end)

test("the ownership tab shows where you have the item and what it is worth", function()
  local A, env, win = open()
  A.Inventory.EnsureChar({ name = "Thornwick", realm = "Whitemane", class = "WARRIOR" })
  A.Inventory.EnsureChar({ name = "Mule", realm = "Whitemane", class = "MAGE" })
  local now = Fx.NOW
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [12359] = 6 }, now - 60)
  A.Inventory.SetLocation("Thornwick-Whitemane", "bank", { [12359] = 4 }, now - 86400 * 12)
  A.Inventory.SetLocation("Mule-Whitemane", "mail", { [12359] = 4 }, now - 3600 * 5)
  select(A, env, 12359)
  local iv = win.itemView
  iv.tabs:Select("owned")
  Stub.settle(env)
  H.truthy(iv.owned:IsShown())
  local t = iv.owned.table
  H.eq(#t.list.data, 3)
  H.eq(cellText(t, 1, 1), "Mule")
  H.eq(cellText(t, 1, 2), "Mail")
  H.eq(cellText(t, 1, 3), "4")
  H.truthy(cellText(t, 1, 4):find("5h", 1, true))
  H.eq(cellText(t, 3, 2), "Bank")
  H.truthy(cellText(t, 3, 4):find("12d", 1, true))
  local summary = plain(iv.owned.summary:GetText())
  H.truthy(summary:find("14", 1, true), summary)
  H.truthy(summary:find("15g 73s 60c", 1, true), summary)   -- 14 x 1g 12s 40c
end)

test("the ownership tab says so when you own none", function()
  local A, env, win = open()
  select(A, env, 12359)
  win.itemView.tabs:Select("owned")
  H.truthy(win.itemView.owned.empty:IsShown())
  H.truthy(plain(win.itemView.owned.summary:GetText()):find("0", 1, true))
end)

test("watch, link and back buttons work", function()
  local linked = {}
  local A, env, win = open({ env = { ChatEdit_InsertLink = function(l) linked[#linked + 1] = l; return true end } })
  select(A, env, 12359)
  local iv = win.itemView
  H.falsy(A.History.IsWatched(12359))
  iv.watchButton:Click()
  H.truthy(A.History.IsWatched(12359))
  iv.watchButton:Click()
  H.falsy(A.History.IsWatched(12359))
  iv.linkButton:Click()
  H.truthy(linked[1] and linked[1]:find("Hitem:12359", 1, true))
  iv.backButton:Click()
  Stub.settle(env)
  H.eq(A.Controller.state.selected, nil)
  H.truthy(win.homeView:IsShown())
  H.falsy(iv:IsShown())
end)

test("switching items refreshes every tab", function()
  local A, env, win = open()
  select(A, env, 12359)
  select(A, env, 10620)
  H.eq(plain(win.itemView.name:GetText()), "Thorium Ore")
  H.eq(plain(win.itemView.stat.lowest.value:GetText()), "48s 10c")
  H.eq(#win.itemView.history.table.list.data, 2)
end)

test("an item with only a legacy suffix key still shows its prices", function()
  local A, env, win = open()
  select(A, env, 15001)
  H.eq(plain(win.itemView.stat.lowest.value:GetText()), "9s")
end)

test("detail panels stay inside the window and keep a usable graph and table at every size", function()
  local A, env, win = open()
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 20, total = 220000, time = A.Adapter.DayToTime(1003), source = "mail", party = "B", char = "T" })
  select(A, env, 12359)
  local iv = win.itemView
  for _, size in ipairs({ { 960, 540 }, { 1000, 620 }, { 1400, 900 }, { 1800, 1000 } }) do
    Stub.resize(env, win, size[1], size[2])
    local label = size[1] .. "x" .. size[2]
    for _, part in ipairs({ iv.header, iv.statsRow, iv.tabs, iv.content }) do
      H.truthy(Stub.within(part, win.detailPanel), "part inside the detail panel at " .. label)
      H.truthy(part:GetWidth() > 0 and part:GetHeight() > 0, "part has size at " .. label)
    end
    H.falsy(Stub.overlaps(iv.header, iv.statsRow), "header/stats at " .. label)
    H.falsy(Stub.overlaps(iv.statsRow, iv.tabs), "stats/tabs at " .. label)
    H.falsy(Stub.overlaps(iv.tabs, iv.content), "tabs/content at " .. label)
    local h = iv.history
    H.truthy(h.graph.frame:GetHeight() >= 100, "graph tall enough at " .. label .. ": " .. h.graph.frame:GetHeight())
    H.truthy(h.graph.plot:GetWidth() > 150, "plot wide enough at " .. label)
    H.truthy(h.table.frame:GetHeight() >= 60, "table tall enough at " .. label .. ": " .. h.table.frame:GetHeight())
    H.falsy(Stub.overlaps(h.graph.frame, h.rangeRow), "graph/range at " .. label)
    H.falsy(Stub.overlaps(h.rangeRow, h.table.frame), "range/table at " .. label)
    H.truthy(Stub.within(h.graph.frame, iv.content) and Stub.within(h.table.frame, iv.content), "history inside content at " .. label)
    for _, key in ipairs({ "lowest", "average", "change", "range", "quantity", "vendor" }) do
      H.truthy(Stub.within(iv.stat[key].cell, iv.statsRow), "stat " .. key .. " inside the row at " .. label)
    end
    for _, a in ipairs({ "lowest", "average", "change" }) do
      for _, b in ipairs({ "range", "quantity", "vendor" }) do
        H.falsy(Stub.overlaps(iv.stat[a].cell, iv.stat[b].cell), a .. "/" .. b .. " at " .. label)
      end
    end
    -- the other tabs fit too
    iv.tabs:Select("activity"); Stub.settle(env)
    H.truthy(iv.activity.table.frame:GetHeight() >= 60, "activity table at " .. label)
    H.truthy(Stub.within(iv.activity.table.frame, iv.content))
    iv.tabs:Select("owned"); Stub.settle(env)
    H.truthy(Stub.within(iv.owned.table.frame, iv.content))
    iv.tabs:Select("history"); Stub.settle(env)
  end
end)

test("a tall graph redraws when the window is resized", function()
  local A, env, win = open()
  select(A, env, 12359)
  local g = win.itemView.history.graph
  local before = g.layout.H
  Stub.resize(env, win, 1000, 900)
  H.truthy(g.layout.H > before)
end)

test("the graph sizes itself from the resize event, not from child frames mid-layout", function()
  local A, env, win = open()
  select(A, env, 12359)
  local g = win.itemView.history.graph
  Stub.fire(g.frame, "OnSizeChanged", 500, 300)
  H.eq({ g.layout.W, g.layout.H }, { 500 - 58 - 10, 300 - 10 - 24 })
end)

test("gear with several versions gets one version selector, reused across refreshes", function()
  local A, env, win = open()
  local function cycles()
    local n = 0
    for _, child in ipairs(win.itemView.history.rangeRow.__children) do
      if child.label and child.label:GetText():find("Version", 1, true) then n = n + 1 end
    end
    return n
  end
  select(A, env, 19019)
  select(A, env, 12359)
  select(A, env, 19019)
  select(A, env, 19019)
  H.eq(cycles(), 1, "a single selector exists for this item's versions")
  local v = win.itemView.history
  H.truthy(v.variantCycle:IsShown())
  v.variantCycle:Click()                 -- Base -> iLvl 60
  H.eq(v.variantKey, "g:19019:60")
  H.eq(v.graph.layout.points[1].low, 5200000, "the chosen version's own prices are drawn")
  select(A, env, 12359)
  H.falsy(v.variantCycle:IsShown(), "single-version items have no selector")
end)

test("inventory changes only redraw what they can change", function()
  local A, env, win = open()
  select(A, env, 12359)
  local g = win.itemView.history.graph
  local redraws = 0
  local real = g.Redraw
  g.Redraw = function(self, ...) redraws = redraws + 1; return real(self, ...) end
  A.Bus.Fire("INVENTORY_UPDATED")
  H.eq(redraws, 0, "the price graph does not depend on inventory")
  win.itemView.tabs:Select("owned")
  A.Inventory.EnsureChar({ name = "T", realm = "R" })
  A.Inventory.SetLocation("T-R", "bags", { [12359] = 3 }, Fx.NOW)
  A.Bus.Fire("INVENTORY_UPDATED")
  H.eq(win.itemView.owned.table.list.data[1].count, 3, "the ownership tab does")
end)
