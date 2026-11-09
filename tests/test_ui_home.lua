local H = require("harness")
local Stub = require("ui_stub")
local Boot = require("boot_ui")
local Fx = require("fixtures")
local test = H.test

local function plain(s)
  s = tostring(s):gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  return s
end

local function openRich(opts)
  local A, env = Boot.rich(opts)
  local win = Boot.open(A, env)
  return A, env, win
end

local function lineIndex(win, predicate)
  for i, line in ipairs(win.homeList.data) do
    if predicate(line) then return i end
  end
end

-- Scroll the overview so the first line matching `predicate` is on screen and return its row widget.
local function showLine(win, env, predicate)
  local i = lineIndex(win, predicate)
  H.truthy(i, "the overview has that line")
  win.homeList:SetOffset(math.max(0, i - 2))
  Stub.settle(env)
  local row = win.homeList.rows[i - win.homeList:GetOffset()]
  H.eq(row.item, win.homeList.data[i], "row widget shows that line")
  return row, i
end

local function title(key) return function(l) return l.kind == "title" and l.key == key end end
local function cols(key) return function(l) return l.kind == "cols" and l.key == key end end

local function rowsOf(lines, key)
  local out = {}
  for _, l in ipairs(lines) do
    if l.kind == "row" and l.key == key then out[#out + 1] = l.row end
  end
  return out
end

local function headerButton(row, label)
  for _, b in ipairs(row.hbtns) do
    if b:IsShown() and plain(b.label:GetText()) == label then return b end
  end
end

-- ---------------------------------------------------------------------------
-- The overview
-- ---------------------------------------------------------------------------
test("the overview has a clickable heading for each section, in order", function()
  local A, env, win = openRich()
  local keys = {}
  for _, line in ipairs(A.UI.Home.Lines()) do
    if line.kind == "title" then keys[#keys + 1] = line.key end
  end
  H.eq(keys, { "movers", "deals", "newfinds", "watchlist", "activity", "inventory", "shopping" })
  H.eq(A.UI.Home.Lines()[1].kind, "text", "starts with a hint")
  H.truthy(plain(A.UI.Home.Lines()[1].text):lower():find("click", 1, true))
end)

test("headings look like buttons: a View all label and an arrow", function()
  local A, env, win = openRich()
  local row = showLine(win, env, title("movers"))
  H.truthy(row.viewAll:IsShown())
  H.truthy(plain(row.viewAll:GetText()):find("View all", 1, true), row.viewAll:GetText())
  H.truthy(row.chevron.visible, "an arrow")
  H.eq(plain(row.name:GetText()), "Biggest movers (7 days)")
  -- the next heading is the same
  local deals = showLine(win, env, title("deals"))
  H.truthy(deals.viewAll:IsShown() and deals.chevron.visible)
  H.eq(plain(deals.name:GetText()), "Below their average")
  -- a plain row has neither
  local item = showLine(win, env, function(l) return l.kind == "row" and l.key == "movers" end)
  H.falsy(item.viewAll:IsShown())
  H.falsy(item.chevron.visible)
end)

test("a heading with a lot behind it says how much", function()
  local A, env, win = openRich()
  local row = showLine(win, env, title("movers"))
  H.truthy(plain(row.viewAll:GetText()):find("4", 1, true), "four movers: " .. row.viewAll:GetText())
end)

test("hovering a heading explains it and never errors", function()
  local A, env, win = openRich()
  local lines = {}
  env.GameTooltip = {
    SetOwner = function() end, Show = function() end, Hide = function() end, SetHyperlink = function() end,
    AddLine = function(_, text) lines[#lines + 1] = plain(text) end,
  }
  local row = showLine(win, env, title("movers"))
  Stub.fire(row, "OnEnter")
  H.truthy(table.concat(lines, " "):lower():find("full list", 1, true), table.concat(lines, " "))
  H.nothrows(function() Stub.fire(row, "OnLeave") end)
end)

test("clicking a heading makes that table the only one on the pane", function()
  local A, env, win = openRich()
  local Home = A.UI.Home
  H.eq(Home.view, "overview")
  H.truthy(win.homeList.frame:IsShown())
  local row = showLine(win, env, title("movers"))
  Stub.fire(row, "OnClick", "LeftButton")
  Stub.settle(env)
  H.eq(Home.view, "movers")
  H.falsy(win.homeList.frame:IsShown(), "the overview is gone")
  H.truthy(win.homeExpanded:IsShown())
  H.truthy(Home.panels.movers.frame:IsShown())
  for key, panel in pairs(Home.panels) do
    if key ~= "movers" then H.falsy(panel.frame:IsShown(), key .. " is hidden") end
  end
  H.eq(plain(Home.panels.movers.title:GetText()), "Biggest movers (7 days)")
  H.eq(#Home.panels.movers.table.list.data, 4, "every mover, not just the top few")
end)

test("every heading opens its own full list", function()
  local A, env, win = openRich()
  local Home = A.UI.Home
  for _, def in ipairs(A.Overview.Sections()) do
    Home.ShowOverview()
    Stub.settle(env)
    local row = showLine(win, env, title(def.key))
    Stub.fire(row, "OnClick", "LeftButton")
    Stub.settle(env)
    H.eq(Home.view, def.key)
    H.eq(plain(Home.panels[def.key].title:GetText()), def.title)
    H.truthy(Home.panels[def.key].frame:IsShown(), def.key)
  end
end)

test("the View all line under a long table opens the list too", function()
  local A, env, win = openRich()
  A.Overview.Section("movers").limit = 2
  A.Overview.Invalidate()
  A.UI.Home.Update()
  local row = showLine(win, env, function(l) return l.kind == "more" and l.key == "movers" end)
  H.truthy(plain(row.name:GetText()):find("View all 4", 1, true), row.name:GetText())
  Stub.fire(row, "OnClick", "LeftButton")
  H.eq(A.UI.Home.view, "movers")
  A.Overview.Section("movers").limit = 6
end)

test("the Back button above a full list returns to the overview", function()
  local A, env, win = openRich()
  local Home = A.UI.Home
  Home.Expand("deals")
  Stub.settle(env)
  H.truthy(win.homeExpanded:IsShown())
  Home.panels.deals.backButton:Click()
  Stub.settle(env)
  H.eq(Home.view, "overview")
  H.truthy(win.homeList.frame:IsShown())
  H.falsy(win.homeExpanded:IsShown())
end)

-- ---------------------------------------------------------------------------
-- Compact tables: columns, Confidence, sorting
-- ---------------------------------------------------------------------------
test("movers and deals show a Confidence column", function()
  local A, env, win = openRich()
  for _, key in ipairs({ "movers", "deals", "newfinds" }) do
    local row = showLine(win, env, cols(key))
    H.truthy(headerButton(row, "Confidence"), key .. " has a Confidence header")
  end
  local line = rowsOf(A.UI.Home.Lines(), "movers")[1]
  local rowWidget = showLine(win, env, function(l) return l.kind == "row" and l.key == "movers" end)
  local cells = {}
  for _, cell in ipairs(rowWidget.cells) do if cell:IsShown() then cells[#cells + 1] = plain(cell:GetText()) end end
  H.eq(cells[#cells], tostring(rowWidget.item.row.conf.score), "the last cell is the confidence score")
  H.truthy(rowWidget.cells[3]:GetText():find("|c", 1, true), "and it is coloured")
end)

test("the column headers are buttons that sort the table", function()
  local A, env, win = openRich()
  local Ov = A.Overview
  local function topMover()
    for _, l in ipairs(A.UI.Home.Lines()) do
      if l.kind == "row" and l.key == "movers" then return l.row.id end
    end
  end
  local header = showLine(win, env, cols("movers"))
  local conf = headerButton(header, "Confidence")
  conf:Click()
  Stub.settle(env)
  H.eq({ Ov.GetSort("movers") }, { "conf", false }, "first click: highest first")
  local best = topMover()
  H.truthy(Ov.Rows("movers")[1].conf.score >= 0)
  H.truthy(best ~= 20002, "the thin spike is not the most confident")
  header = showLine(win, env, cols("movers"))
  conf = headerButton(header, "Confidence")
  H.truthy(conf.arrow.visible, "the active column shows an arrow")
  H.falsy(headerButton(header, "Price").arrow.visible)
  conf:Click()
  Stub.settle(env)
  H.eq({ Ov.GetSort("movers") }, { "conf", true }, "second click: lowest first")
  H.eq(topMover(), 20002, "the thin spike has the lowest confidence")
  header = showLine(win, env, cols("movers"))
  headerButton(header, "Price"):Click()
  Stub.settle(env)
  H.eq(Ov.GetSort("movers"), "price")
  headerButton(showLine(win, env, cols("movers")), "Item"):Click()
  Stub.settle(env)
  H.eq({ Ov.GetSort("movers") }, { "item", true })
  H.eq(topMover(), 20004, "Bargain Herb comes first alphabetically")
end)

test("sorting a compact table re-ranks the whole list before the top rows are taken", function()
  local A, env, win = openRich()
  A.Overview.Section("movers").limit = 1
  A.Overview.Invalidate()
  A.UI.Home.Update()
  local header = showLine(win, env, cols("movers"))
  headerButton(header, "Confidence"):Click()
  headerButton(showLine(win, env, cols("movers")), "Confidence"):Click()
  Stub.settle(env)
  H.eq(rowsOf(A.UI.Home.Lines(), "movers")[1].id, 20002, "the single row is the least confident of all four")
  A.Overview.Section("movers").limit = 6
end)

test("one table's sort does not disturb another's", function()
  local A, env, win = openRich()
  headerButton(showLine(win, env, cols("movers")), "Price"):Click()
  H.eq(A.Overview.GetSort("deals"), "rank")
  H.eq(A.Overview.GetSort("movers"), "price")
end)

test("rows show the price, change and confidence, and clicking one selects the item", function()
  local A, env, win = openRich()
  local row = showLine(win, env, function(l) return l.kind == "row" and l.key == "movers" and l.row.id == 20001 end)
  H.truthy(plain(row.name:GetText()):find("Rising Bar", 1, true))
  H.truthy(plain(row.cells[1]:GetText()):find("g", 1, true) or plain(row.cells[1]:GetText()):find("s", 1, true))
  H.truthy(plain(row.cells[2]:GetText()):find("+30%", 1, true), plain(row.cells[2]:GetText()))
  Stub.fire(row, "OnClick", "LeftButton")
  H.eq(A.Controller.state.selected, 20001)
  H.falsy(win.homeView:IsShown())
  H.truthy(win.itemView:IsShown())
end)

test("hovering a mover shows why it is, or is not, trusted", function()
  local A, env, win = openRich()
  local lines, linked = {}, nil
  env.GameTooltip = {
    SetOwner = function() end, Show = function() end, Hide = function() end,
    SetHyperlink = function(_, link) linked = link end,
    AddLine = function(_, text) lines[#lines + 1] = plain(text) end,
  }
  local row = showLine(win, env, function(l) return l.kind == "row" and l.key == "movers" and l.row.id == 20002 end)
  Stub.fire(row, "OnEnter")
  H.eq(linked, "item:20002")
  local text = table.concat(lines, " "):lower()
  H.truthy(text:find("confidence", 1, true), text)
  H.truthy(text:find("thin", 1, true), "the reason it is low: " .. text)
end)

test("an empty section says why", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  local texts = {}
  for _, l in ipairs(A.UI.Home.Lines()) do
    if l.kind == "text" then texts[#texts + 1] = plain(l.text):lower() end
  end
  local joined = table.concat(texts, "\n")
  H.truthy(joined:find("no big movers", 1, true), joined)
  H.truthy(joined:find("nothing is priced well below", 1, true))
  H.truthy(joined:find("nothing watched", 1, true))
  H.truthy(joined:find("no sales or purchases", 1, true))
end)

test("shopping lists keep their list names as sub-headings", function()
  local A, env, win = openRich()
  local lines = A.UI.Home.Lines()
  local found
  for i, l in ipairs(lines) do
    if l.kind == "group" and plain(l.text) == "Smithing" then
      found = i
      break
    end
  end
  H.truthy(found, "a Smithing sub-heading")
  H.eq(lines[found + 1].kind, "row")
  H.eq(lines[found + 1].row.id, 12359)
end)

test("the inventory section shows its summary above its rows", function()
  local A, env, win = openRich()
  A.Inventory.EnsureChar({ name = "Thornwick", realm = "Whitemane" })
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [12359] = 14, [12363] = 1, [19019] = 1, [55555] = 9 }, 1)
  A.Bus.Fire("INVENTORY_UPDATED")
  env.C_Timer.flush()
  local lines = A.UI.Home.Lines()
  local inside, summary, rows = false, nil, {}
  for _, l in ipairs(lines) do
    if l.kind == "title" then inside = l.key == "inventory"
    elseif inside and l.kind == "text" then summary = summary or plain(l.text)
    elseif inside and l.kind == "row" then rows[#rows + 1] = l.row.id end
  end
  H.truthy(summary and summary:find("worth", 1, true), tostring(summary))
  H.eq(rows, { 19019, 12363, 12359 })
end)

test("new finds warns when there is not yet enough history", function()
  local A, env = Boot.boot({ noReload = true })
  local realm = env.AUCTIONATOR_PRICE_DATABASE.TestRealm
  for _, entry in pairs(realm) do
    if type(entry) == "table" then entry.h, entry.l, entry.a = { ["1005"] = entry.m or 100 }, {}, { ["1005"] = 5 } end
  end
  A.Controller.Reload()
  env.C_Timer.flush()
  local win = Boot.open(A, env)
  local joined = {}
  for _, l in ipairs(A.UI.Home.Lines()) do
    if l.kind == "text" then joined[#joined + 1] = plain(l.text):lower() end
  end
  H.truthy(table.concat(joined, "\n"):find("another scan", 1, true), table.concat(joined, "\n"))
end)

test("the overview works with no Auctionator data at all", function()
  local A, env = Boot.boot({ fixture = { Auctionator = false } })
  local win = Boot.open(A, env)
  H.nothrows(function() A.UI.Home.Lines() end)
  H.truthy(#A.UI.Home.Lines() >= 7)
  for _, def in ipairs(A.Overview.Sections()) do
    H.nothrows(function()
      A.UI.Home.Expand(def.key)
      Stub.settle(env)
    end)
    H.truthy(A.UI.Home.panels[def.key].frame:IsShown())
  end
end)

-- ---------------------------------------------------------------------------
-- Full lists
-- ---------------------------------------------------------------------------
test("a full list has a search box that narrows it as you type", function()
  local A, env, win = openRich()
  local Home = A.UI.Home
  Home.Expand("movers")
  Stub.settle(env)
  local panel = Home.panels.movers
  H.eq(#panel.table.list.data, 4)
  panel.searchBox.edit:SetText("rising")
  Stub.fire(panel.searchBox.edit, "OnTextChanged", true)
  Stub.settle(env)
  H.eq(#panel.table.list.data, 1)
  H.eq(panel.table.list.data[1].id, 20001)
  H.truthy(plain(panel.count:GetText()):find("1 of 4", 1, true), panel.count:GetText())
  panel.searchBox.edit:SetText("zzz")
  Stub.fire(panel.searchBox.edit, "OnTextChanged", true)
  H.eq(#panel.table.list.data, 0)
  H.truthy(panel.empty:IsShown())
  H.truthy(plain(panel.empty:GetText()):lower():find("search", 1, true), panel.empty:GetText())
  panel.searchBox:Clear()
  Stub.fire(panel.searchBox.edit, "OnTextChanged", true)
  H.eq(#panel.table.list.data, 4)
  H.falsy(panel.empty:IsShown())
end)

test("a full list can be sorted by any column, and says which", function()
  local A, env, win = openRich()
  local Home = A.UI.Home
  Home.Expand("movers")
  Stub.settle(env)
  local t = Home.panels.movers.table
  local function headerFor(label)
    for i, col in ipairs(t.columns) do
      if col.title == label then return t.headers[i], i end
    end
  end
  local h = headerFor("Confidence")
  h:Click()
  Stub.settle(env)
  H.eq({ A.Overview.GetSort("movers") }, { "conf", false })
  local first = t.list.data[1]
  H.truthy(first.conf.score >= t.list.data[#t.list.data].conf.score)
  H.truthy(h.arrow.visible)
  h:Click()
  H.eq(t.list.data[1].id, 20002, "ascending: the thin spike first")
  headerFor("Item"):Click()
  H.eq(t.list.data[1].id, 20004)
end)

test("a full list's filters change what it shows and are remembered", function()
  local A, env, win = openRich()
  local Home = A.UI.Home
  Home.Expand("movers")
  Stub.settle(env)
  local panel = Home.panels.movers
  H.truthy(panel.filters.dir and panel.filters.minConf)
  panel.filters.dir:Click()
  H.eq(A.Overview.GetFilter("movers", "dir"), "up")
  local ids = {}
  for _, row in ipairs(panel.table.list.data) do ids[#ids + 1] = row.id end
  table.sort(ids)
  H.eq(ids, { 20001, 20002 }, "only the risers")
  panel.filters.dir:Click()
  panel.filters.dir:Click()
  H.eq(A.Overview.GetFilter("movers", "dir"), nil, "back to rises and falls")
  panel.filters.minConf:Click()
  panel.filters.minConf:Click()
  H.eq(A.Overview.GetFilter("movers", "minConf"), 60)
  H.eq(#panel.table.list.data, 3, "60 and up leaves out the thin spike")
  -- and the choice is there the next time the list is opened
  Home.ShowOverview()
  Home.Expand("movers")
  Stub.settle(env)
  H.eq(#Home.panels.movers.table.list.data, 3)
end)

test("recent activity opens as the full list of everything, with a search", function()
  local A, env, win = openRich()
  local now = Fx.NOW
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 20, total = 220000, time = now - 3600, source = "mail", party = "Buyer", char = "T" })
  A.Ledger.Add({ kind = "bought", itemID = 12363, qty = 1, total = 1400000, time = now - 86400 * 2, source = "ah", char = "T" })
  A.Ledger.Add({ kind = "posted", itemID = 12359, qty = 20, total = 230000, time = now - 100, source = "auctionator" })
  A.Ledger.Add({ kind = "expired", itemID = 10620, qty = 5, time = now - 86400 * 3, source = "mail", char = "T" })
  A.Ledger.Add({ kind = "cancelled", itemName = "Mystery Goods", qty = 2, time = now - 86400 * 4, source = "mail", char = "T" })
  A.Bus.Fire("LEDGER_UPDATED")
  env.C_Timer.flush()
  local compact = rowsOf(A.UI.Home.Lines(), "activity")
  H.eq(#compact, 2, "the overview shows sales and purchases")
  A.UI.Home.Expand("activity")
  Stub.settle(env)
  local panel = A.UI.Home.panels.activity
  H.eq(#panel.table.list.data, 5, "the full list has every kind of activity")
  panel.searchBox.edit:SetText("mystery")
  Stub.fire(panel.searchBox.edit, "OnTextChanged", true)
  H.eq(#panel.table.list.data, 1)
  H.eq(panel.table.list.data[1].kind, "cancelled")
  -- an entry whose item Almanac could not identify does not break clicking
  local row = panel.table.list.rows[1]
  H.nothrows(function() Stub.fire(row, "OnClick", "LeftButton") end)
  H.eq(A.Controller.state.selected, nil)
end)

test("the full list keeps your place when you look at an item and come Back", function()
  local A, env, win = openRich()
  local Home = A.UI.Home
  Home.Expand("movers")
  Stub.settle(env)
  local panel = Home.panels.movers
  panel.searchBox.edit:SetText("rising")
  Stub.fire(panel.searchBox.edit, "OnTextChanged", true)
  Stub.settle(env)
  local row = panel.table.list.rows[1]
  Stub.fire(row, "OnClick", "LeftButton")
  Stub.settle(env)
  H.eq(A.Controller.state.selected, 20001)
  H.falsy(win.homeView:IsShown())
  win.itemView.backButton:Click()
  Stub.settle(env)
  H.truthy(win.homeView:IsShown())
  H.eq(Home.view, "movers")
  H.truthy(panel.frame:IsShown())
  H.eq(panel.searchBox:GetText(), "rising", "the search is still there")
  H.eq(#panel.table.list.data, 1)
end)

test("going back to the overview clears the search so the next visit starts fresh", function()
  local A, env, win = openRich()
  local Home = A.UI.Home
  Home.Expand("movers")
  local panel = Home.panels.movers
  panel.searchBox.edit:SetText("bar")
  Stub.fire(panel.searchBox.edit, "OnTextChanged", true)
  Home.ShowOverview()
  Home.Expand("movers")
  Stub.settle(env)
  H.eq(panel.searchBox:GetText(), "")
  H.eq(#panel.table.list.data, 4)
end)

test("a full list keeps working when the data reloads underneath it", function()
  local A, env, win = openRich()
  local Home = A.UI.Home
  Home.Expand("movers")
  Stub.settle(env)
  A.Controller.Reload()
  env.C_Timer.flush()
  Stub.settle(env)
  H.eq(Home.view, "movers")
  H.eq(#Home.panels.movers.table.list.data, 4)
end)

test("the watchlist fills in as items are watched", function()
  local A, env, win = openRich()
  local function watchRows() return #rowsOf(A.UI.Home.Lines(), "watchlist") end
  H.eq(watchRows(), 0)
  A.History.Watch(20001, true, { price = 1000, day = 1000 })
  env.C_Timer.flush()
  Stub.settle(env)
  H.eq(watchRows(), 1)
  local row = showLine(win, env, function(l) return l.kind == "row" and l.key == "watchlist" end)
  H.truthy(plain(row.name:GetText()):find("Rising Bar", 1, true))
  H.truthy(plain(row.cells[2]:GetText()):find("+30%", 1, true), "up 30% since it was added: " .. plain(row.cells[2]:GetText()))
  A.History.Watch(20001, false)
  env.C_Timer.flush()
  H.eq(watchRows(), 0)
end)

test("extra columns appear on a full list only when the pane is wide enough", function()
  local A, env, win = openRich()
  local Home = A.UI.Home
  Home.Expand("movers")
  Stub.settle(env)
  local t = Home.panels.movers.table
  local function shownColumns()
    local n = 0
    for _, h in ipairs(t.headers) do if h:IsShown() then n = n + 1 end end
    return n
  end
  Stub.resize(env, win, 960, 540)
  local narrow = shownColumns()
  A.UI.Window.SetCollapsed(true)
  Stub.settle(env)
  H.truthy(shownColumns() > narrow, "hiding the item list gives room for the extra columns")
  A.UI.Window.SetCollapsed(false)
  Stub.settle(env)
  H.eq(shownColumns(), narrow)
end)

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
test("the compact tables fit at every window size", function()
  local A, env, win = openRich()
  -- give every section something to show, so every kind of row gets checked
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 20, total = 20 * 12382, time = Fx.NOW - 3600, source = "mail", party = "Buyer", char = "T" })
  A.Ledger.Add({ kind = "bought", itemID = 12363, qty = 1, total = 1200000, time = Fx.NOW - 86400, source = "ah", char = "T" })
  A.Bus.Fire("LEDGER_UPDATED")
  A.Inventory.EnsureChar({ name = "Thornwick", realm = "Whitemane" })
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [12359] = 14, [12363] = 1 }, 1)
  A.Bus.Fire("INVENTORY_UPDATED")
  A.History.Watch(20001, true, { price = 1000, day = 1000 })
  env.C_Timer.flush()

  local MIN_NAME = 60
  for _, size in ipairs({ { 960, 540 }, { 1000, 620 }, { 1400, 900 } }) do
    Stub.resize(env, win, size[1], size[2])
    local label = size[1] .. "x" .. size[2]
    H.truthy(Stub.within(win.homeList.frame, win.detailPanel), "list inside the panel at " .. label)
    H.truthy(win.homeList.frame:GetHeight() > 200)

    -- one heading, one header row and one data row from every section
    local checked, sections = {}, {}
    for _, line in ipairs(win.homeList.data) do
      local id = line.kind .. ":" .. (line.key or "")
      if (line.kind == "title" or line.kind == "cols" or line.kind == "row") and not checked[id] then
        checked[id] = true
        sections[line.key] = true
        local row = showLine(win, env, function(l) return l == line end)
        local where = label .. " " .. id
        if line.kind == "row" then
          H.truthy(row.name:GetWidth() >= MIN_NAME, "the item name has room (" .. row.name:GetWidth() .. ") at " .. where)
          H.truthy(Stub.within(row.name, row), "name inside row at " .. where)
          local shown = {}
          for _, cell in ipairs(row.cells) do if cell:IsShown() then shown[#shown + 1] = cell end end
          H.truthy(#shown >= 2, "value cells at " .. where)
          for a = 1, #shown do
            H.truthy(Stub.within(shown[a], row), "cell inside row at " .. where)
            H.falsy(Stub.overlaps(shown[a], row.name), "cell and name overlap at " .. where)
            for b = a + 1, #shown do H.falsy(Stub.overlaps(shown[a], shown[b]), "cells overlap at " .. where) end
          end
        elseif line.kind == "cols" then
          local shown = {}
          for _, b in ipairs(row.hbtns) do if b:IsShown() then shown[#shown + 1] = b end end
          H.truthy(#shown >= 3, "headers at " .. where)
          for a = 1, #shown do
            H.truthy(Stub.within(shown[a], row), "header inside row at " .. where)
            for b = a + 1, #shown do H.falsy(Stub.overlaps(shown[a], shown[b]), "headers overlap at " .. where) end
          end
        else
          H.truthy(Stub.within(row.viewAll, row), "View all inside the heading at " .. where)
          H.falsy(Stub.overlaps(row.viewAll, row.name), "View all and the title overlap at " .. where)
        end
      end
    end
    for _, def in ipairs(A.Overview.Sections()) do
      H.truthy(checked["row:" .. def.key], def.key .. " had a data row to check at " .. label)
    end
  end
end)

test("a full list's parts fit and never overlap at every window size", function()
  local A, env, win = openRich()
  local Home = A.UI.Home
  for _, key in ipairs({ "movers", "newfinds", "activity" }) do
    Home.Expand(key)
    for _, size in ipairs({ { 960, 540 }, { 1400, 900 } }) do
      Stub.resize(env, win, size[1], size[2])
      local panel = Home.panels[key]
      local label = key .. " at " .. size[1] .. "x" .. size[2]
      local parts = { panel.bar, panel.searchBox, panel.table.frame }
      for _, part in ipairs(parts) do H.truthy(Stub.within(part, win.homeExpanded), "inside the pane: " .. label) end
      for a = 1, #parts do
        for b = a + 1, #parts do H.falsy(Stub.overlaps(parts[a], parts[b]), "overlap: " .. label) end
      end
      H.truthy(panel.table.frame:GetHeight() > 120, "the table has room: " .. label)
      H.truthy(Stub.within(panel.backButton, panel.bar))
      H.truthy(Stub.within(panel.count, panel.bar))
      H.falsy(Stub.overlaps(panel.backButton, panel.title), "back button and title: " .. label)
      for _, cycle in pairs(panel.filters) do
        H.truthy(Stub.within(cycle, win.homeExpanded), "filter inside: " .. label)
        H.falsy(Stub.overlaps(cycle, panel.table.frame), "filter above the table: " .. label)
        H.falsy(Stub.overlaps(cycle, panel.searchBox), label)
      end
    end
  end
end)
