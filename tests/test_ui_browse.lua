local H = require("harness")
local Stub = require("ui_stub")
local Boot = require("boot_ui")
local test = H.test

local function plain(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  return s
end

local function names(win, n)
  local out = {}
  for i = 1, n do
    local row = win.resultsTable.list.rows[i]
    out[i] = row:IsShown() and plain(row.cells[1].name:GetText()) or nil
  end
  return out
end

local function typeSearch(win, env, text)
  win.searchBox.edit:SetText(text)
  Stub.fire(win.searchBox.edit, "OnTextChanged", true)
  env.C_Timer.flush()
  Stub.settle(env)
end

test("the whole addon loads in TOC order without stray globals", function()
  local _, _, leaks = Boot.boot()
  -- the only globals the addon may define: slash command, key binding, and their labels
  H.eq(leaks, { "AuctionatorAlmanac_Toggle", "BINDING_HEADER_AUCTIONATORALMANAC", "BINDING_NAME_ALMANAC_TOGGLE",
                "SLASH_ALMANAC1", "SLASH_ALMANAC2" })
end)

test("the status strip shows scan age, kind, counts and realm", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  local text = plain(win.statusText:GetText())
  H.truthy(text:find("2h", 1, true), text)
  H.truthy(text:find("browse", 1, true), text)
  H.truthy(text:find("5 items", 1, true), text)
  H.truthy(text:find("TestRealm", 1, true), text)
  H.truthy(text:find("21 days", 1, true), text)
end)

test("the status strip explains when Auctionator has nothing yet", function()
  local A, env = Boot.boot({ fixture = { Auctionator = false } })
  local win = Boot.search(A, env)
  H.truthy(plain(win.statusText:GetText()):lower():find("auctionator", 1, true))
  H.truthy(win.emptyText:IsShown())
  H.truthy(plain(win.emptyText:GetText()):lower():find("scan", 1, true))
end)

test("results list every priced item sorted by name", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  H.eq(names(win, 5), { "Arcane Crystal", "Eagle Pants", "Thorium Bar", "Thorium Ore", "Thunderfury" })
  H.truthy(plain(win.resultsFooter:GetText()):find("5 items", 1, true))
  H.falsy(win.emptyText:IsShown())
  local row = win.resultsTable.list.rows[3]
  H.eq(plain(row.cells[2].text:GetText()), "1g 12s")
  H.truthy(row.cells[3].text:GetText() ~= "")
end)

test("typing in the search box filters live matches", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  typeSearch(win, env, "thor")
  H.eq(names(win, 3), { "Thorium Bar", "Thorium Ore" })
  H.falsy(win.resultsTable.list.rows[3]:IsShown())
  H.truthy(plain(win.resultsFooter:GetText()):find("2 items", 1, true))
  typeSearch(win, env, "zzzz")
  H.truthy(plain(win.resultsFooter:GetText()):lower():find("no items", 1, true))
  H.truthy(win.emptyText:IsShown())
  typeSearch(win, env, "")
  H.eq(#A.Controller.results, 5)
end)

test("the category panel mirrors the Auction House and narrows results", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  local function labels()
    local out = {}
    for _, row in ipairs(win.catList.rows) do
      if row:IsShown() then out[#out + 1] = plain(row.label:GetText()) end
    end
    return out
  end
  H.eq(labels(), { "All Items", "Weapon", "Armor", "Trade Goods" })
  H.eq(plain(win.catList.rows[1].count:GetText()), "5")
  H.eq(plain(win.catList.rows[4].count:GetText()), "3")
  Stub.fire(win.catList.rows[4], "OnClick", "LeftButton")
  Stub.settle(env)
  H.eq(labels(), { "All Items", "Weapon", "Armor", "Trade Goods", "Metal & Stone", "Enchanting" })
  H.eq(#A.Controller.results, 3)
  Stub.fire(win.catList.rows[5], "OnClick", "LeftButton")
  H.eq(A.Controller.results, { 10620 })
  Stub.fire(win.catList.rows[4], "OnClick", "LeftButton")
  H.eq(labels(), { "All Items", "Weapon", "Armor", "Trade Goods" }, "clicking an open category collapses it")
  Stub.fire(win.catList.rows[1], "OnClick", "LeftButton")
  H.eq(#A.Controller.results, 5)
end)

test("clicking a column header sorts, and again reverses", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  win.resultsTable.headers[2]:Click()
  Stub.settle(env)
  H.eq(names(win, 1), { "Thunderfury" }, "highest price first")
  win.resultsTable.headers[2]:Click()
  H.eq(names(win, 1), { "Eagle Pants" })
  win.resultsTable.headers[1]:Click()
  H.eq(names(win, 1), { "Arcane Crystal" })
end)

test("clicking a row selects it", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  Stub.fire(win.resultsTable.list.rows[3], "OnClick", "LeftButton")
  H.eq(A.Controller.state.selected, 12359)
  H.truthy(win.resultsTable.list.rows[3].selected)
end)

test("shift-click and right-click link the item into chat", function()
  local linked = {}
  local A, env = Boot.boot({ env = { ChatEdit_InsertLink = function(link) linked[#linked + 1] = link; return true end } })
  local win = Boot.search(A, env)
  Stub.fire(win.resultsTable.list.rows[3], "OnClick", "RightButton")
  H.eq(#linked, 1)
  H.truthy(linked[1]:find("Hitem:12359", 1, true))
  H.truthy(linked[1]:find("Thorium Bar", 1, true))
  env.IsModifiedClick = function(action) return action == "CHATLINK" end
  Stub.fire(win.resultsTable.list.rows[4], "OnClick", "LeftButton")
  H.eq(#linked, 2)
  H.eq(A.Controller.state.selected, nil, "linking does not change the selection")
end)

test("quality, owned-only and recency filters work from the search row", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  win.qualityCycle:Click()   -- Any -> Common
  win.qualityCycle:Click()   -- -> Uncommon
  Stub.settle(env)
  H.eq(A.Controller.state.quality, 2)
  H.eq(names(win, 3), { "Eagle Pants", "Thorium Bar" })
  win.qualityCycle:SetValue(nil)
  A.Controller.SetQuality(nil)
  A.Inventory.EnsureChar({ name = "Thornwick", realm = "Whitemane" })
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [10620] = 4 }, 1)
  win.ownedCheck:Click()
  Stub.settle(env)
  H.eq(A.Controller.results, { 10620 })
  win.ownedCheck:Click()
  win.recentCycle:Click()    -- Any -> Today
  H.eq(A.Controller.state.recent, 0)
  H.eq(#A.Controller.results, 4)
end)

test("price range and moved filters work from the search row", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  win.priceCycle:Click()        -- Any -> < 1g
  H.eq(A.Controller.state.priceKey, "lt1g")
  H.eq(A.Controller.state.maxPrice, 9999)
  H.eq(names(win, 3), { "Eagle Pants", "Thorium Ore" })
  win.priceCycle:Click(); win.priceCycle:Click(); win.priceCycle:Click(); win.priceCycle:Click()   -- ... back to Any
  H.eq(A.Controller.state.priceKey, nil)
  H.eq(#A.Controller.results, 5)
  A.Controller.summaries[12359].change1d = 0.12      -- the fixture's real moves are all under 5%
  win.movedCycle:Click()        -- Any -> Rose
  H.eq(A.Controller.state.moved, "up")
  H.eq(names(win, 2), { "Thorium Bar" })
  win.movedCycle:Click()        -- Rose -> Fell
  H.eq(#A.Controller.results, 0)
  win.movedCycle:Click()        -- Fell -> Any
  H.eq(#A.Controller.results, 5)
  win.movedCycle:Click()
  H.eq(A.Controller.state.moved, "up")
  A.Controller.ClearFilters()
  A.UI.SearchBar.Sync()
  H.eq(win.movedCycle.value, nil)
  H.eq(win.priceCycle.value, nil)
end)

test("rows show owned counts and data age", function()
  local A, env = Boot.boot()
  A.Inventory.EnsureChar({ name = "Thornwick", realm = "Whitemane" })
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [12359] = 14 }, 1)
  local win = Boot.search(A, env)
  local bar = win.resultsTable.list.rows[3]
  H.eq(plain(Boot.cell(win, bar, "owned").text:GetText()), "14")
  H.eq(plain(Boot.cell(win, bar, "age").text:GetText()), "today")
  local fury = win.resultsTable.list.rows[5]
  H.eq(plain(Boot.cell(win, fury, "age").text:GetText()), "1d")
end)

test("unnamed items show a placeholder", function()
  local nameless = {
    GetItemInfoInstant = function(id) return id, "t", "s", "", 100000 + id, 7, 7 end,
    GetItemInfo = function() return nil end,
    RequestLoadItemDataByID = function() end,
    GetItemClassInfo = function() return nil end,
    GetItemSubClassInfo = function() return nil end,
  }
  local A, env = Boot.boot({ noReload = true, env = { C_Item = nameless } })
  A.Controller.Reload(); env.C_Timer.flush()
  local win = Boot.search(A, env)
  local first = plain(win.resultsTable.list.rows[1].cells[1].name:GetText())
  H.truthy(first:find("Item ", 1, true), first)
  H.eq(#A.Controller.results, 5, "unnamed items still list")
end)

test("browse regions never overlap or leave their panels at any window size", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  for _, size in ipairs({ { 960, 540 }, { 1000, 620 }, { 1400, 900 }, { 1800, 1000 } }) do
    Stub.resize(env, win, size[1], size[2])
    local label = size[1] .. "x" .. size[2]
    H.truthy(Stub.within(win.searchBox, win.searchRow), "search box in its row at " .. label)
    for _, w in ipairs({ win.qualityCycle, win.recentCycle, win.priceCycle, win.movedCycle, win.ownedCheck }) do
      H.truthy(Stub.within(w, win.searchRow), "filter inside the search row at " .. label)
      H.falsy(Stub.overlaps(w, win.searchBox), "filter clear of the search box at " .. label)
    end
    H.falsy(Stub.overlaps(win.qualityCycle, win.recentCycle))
    H.falsy(Stub.overlaps(win.recentCycle, win.priceCycle))
    H.falsy(Stub.overlaps(win.priceCycle, win.movedCycle))
    H.falsy(Stub.overlaps(win.movedCycle, win.ownedCheck))
    H.truthy(win.searchBox:GetWidth() >= 300, "search box stays usable: " .. win.searchBox:GetWidth())
    H.truthy(Stub.within(win.resultsTable.frame, win.resultsPanel), "table in panel at " .. label)
    H.truthy(Stub.within(win.resultsFooter, win.resultsPanel), "footer in panel at " .. label)
    H.falsy(Stub.overlaps(win.resultsFooter, win.resultsTable.frame), "footer clear of the table at " .. label)
    H.truthy(Stub.within(win.catList.frame, win.catPanel), "category list in panel at " .. label)
    local row = win.resultsTable.list.rows[1]
    for i = 1, #row.cells - 1 do
      H.falsy(Stub.overlaps(row.cells[i], row.cells[i + 1]), "cells " .. i .. "/" .. i + 1 .. " at " .. label)
    end
    H.truthy(win.resultsTable.list.rows[1].cells[1]:GetWidth() >= 150, "item column is readable at " .. label .. ": " .. win.resultsTable.list.rows[1].cells[1]:GetWidth())
    local visible = 0
    for _, r in ipairs(win.resultsTable.list.rows) do if r:IsShown() then visible = visible + 1 end end
    H.eq(visible, 5, "all five fixture items fit at " .. label)
  end
end)

test("a taller window shows more result rows", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env, 960, 540)
  local small = #win.resultsTable.list.rows
  Stub.resize(env, win, 960, 1000)
  H.truthy(#win.resultsTable.list.rows > small + 10)
end)

test("the window reflects new scan data after a reload", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  env.Auctionator.Database.db["10620"].m = 90000000
  A.Controller.Reload(); env.C_Timer.flush(); Stub.settle(env)
  win.resultsTable.headers[2]:Click()
  H.eq(names(win, 1), { "Thorium Ore" })
end)

-- ---------------------------------------------------------------------------
-- A hidden item list comes back when you ask it something
-- ---------------------------------------------------------------------------
test("typing a search brings back a hidden item list", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  A.Controller.Select(12359)                  -- the list is hidden beside an open item
  A.UI.Window.SetCollapsed(true)
  H.falsy(win.resultsPanel:IsShown())
  typeSearch(win, env, "thorium")
  H.falsy(A.UI.Window.IsCollapsed())
  H.truthy(win.resultsPanel:IsShown())
end)

test("choosing a category or a filter brings back a hidden item list", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  A.UI.Window.SetCollapsed(true)
  Stub.fire(win.catList.rows[2], "OnClick", "LeftButton")
  H.falsy(A.UI.Window.IsCollapsed(), "category")
  A.UI.Window.SetCollapsed(true)
  win.qualityCycle:Click()
  H.falsy(A.UI.Window.IsCollapsed(), "quality filter")
  A.UI.Window.SetCollapsed(true)
  win.ownedCheck:Click()
  H.falsy(A.UI.Window.IsCollapsed(), "owned only")
end)

test("the list stays hidden when only the program changes the search text", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  A.UI.Window.SetCollapsed(true)
  A.Controller.SetSearchText("")
  win.searchBox:SetText("")
  A.UI.SearchBar.Sync()
  H.truthy(A.UI.Window.IsCollapsed())
end)

test("the slash search opens the list too", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  A.UI.Window.SetCollapsed(true)
  env.SlashCmdList.ALMANAC("search thorium")
  H.falsy(A.UI.Window.IsCollapsed())
  H.eq(A.Controller.state.text, "thorium")
end)

test("the slash search opens the Search page, from a closed window or from the Overview", function()
  local A, env = Boot.boot()
  env.SlashCmdList.ALMANAC("search thorium")
  local win = A.UI.Window.Get()
  H.truthy(win:IsShown())
  H.eq(A.UI.Window.mode, "search")
  A.UI.Window.SetMode("overview")
  env.SlashCmdList.ALMANAC("search arcane")
  H.eq(A.UI.Window.mode, "search")
  H.eq(A.Controller.state.text, "arcane")
  win:Hide()
  env.SlashCmdList.ALMANAC("")
  H.eq(A.UI.Window.mode, "overview", "plain /almanac opens on the Overview")
end)

local function rowFor(win, id)
  for _, row in ipairs(win.resultsTable.list.rows) do
    if row:IsShown() and row.item == id then return row end
  end
end

test("every result has a star left of its icon, filled while the item is watched", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  local cell = rowFor(win, 12359).cells[1]
  H.truthy(cell.star:IsShown(), "an empty star to click")
  H.falsy(cell.star.on)
  H.eq(cell.star.icon:GetTexture(), A.UI.Widgets.STAR_OFF)
  H.truthy(cell.star:GetRight() <= cell.icon:GetLeft(), "the star comes before the icon")
  H.truthy(cell.icon:GetRight() <= cell.name:GetLeft(), "and the icon before the name")
  A.History.Watch(12359, true)
  env.C_Timer.flush()
  cell = rowFor(win, 12359).cells[1]
  H.truthy(cell.star.on, "filled once watched")
  H.eq(cell.star.icon:GetTexture(), A.UI.Widgets.STAR_ON)
  H.falsy(rowFor(win, 10620).cells[1].star.on, "others are not")
  A.History.Watch(12359, false)
  H.falsy(rowFor(win, 12359).cells[1].star.on)
end)

test("clicking a result's star watches the item without opening it, and clicking again stops", function()
  local A, env = Boot.boot()
  local printed = {}
  env.print = function(msg) printed[#printed + 1] = msg end
  local win = Boot.search(A, env)
  rowFor(win, 12359).cells[1].star:Click()
  H.truthy(A.History.IsWatched(12359))
  H.eq(A.History.WatchInfo(12359).price, 11240, "the price it was watched at, for the Watchlist's Since column")
  H.eq(A.Controller.state.selected, nil, "the star does not open the item")
  H.falsy(win.detailPanel:IsShown())
  H.truthy(rowFor(win, 12359).cells[1].star.on)
  H.truthy(printed[#printed]:find("Watching", 1, true), "said in chat: " .. tostring(printed[#printed]))
  rowFor(win, 12359).cells[1].star:Click()
  H.falsy(A.History.IsWatched(12359))
  H.falsy(rowFor(win, 12359).cells[1].star.on)
  H.truthy(printed[#printed]:find("Stopped watching", 1, true))
end)

test("the star says what a click will do", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  local star = rowFor(win, 12359).cells[1].star
  local lines = {}
  env.GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
  Stub.fire(star, "OnEnter")
  H.truthy(lines[1]:find("Watch this item", 1, true), lines[1])
  star:Click()
  Stub.fire(star, "OnEnter")
  H.truthy(lines[2]:find("stop watching", 1, true), lines[2])
end)

test("the item list shows how many were listed at the lowest price and in all, and sorts by both", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  local titles = {}
  for _, col in ipairs(win.resultsTable.columns) do titles[#titles + 1] = col.title end
  H.eq(titles, { "Item", "Lowest", "At lowest", "On AH", "Change", "Own", "Seen" })
  Boot.scan(A, env, { ["12359"] = { { price = 11240, available = 9 }, { price = 11300, available = 30 } } })
  env.C_Timer.flush()
  local bar = rowFor(win, 12359)
  H.eq(plain(Boot.cell(win, bar, "atmin").text:GetText()), "9")
  H.eq(plain(Boot.cell(win, bar, "onah").text:GetText()), "39")
  local crystal = rowFor(win, 12363)
  H.eq(plain(Boot.cell(win, crystal, "atmin").text:GetText()), "—", "not known until a scan is seen")
  H.eq(plain(Boot.cell(win, crystal, "onah").text:GetText()), "2", "Auctionator's own count")
  win.resultsTable.headers[3]:Click()
  H.eq(A.Controller.state.sortKey, "atmin")
  H.eq(A.Controller.results[1], 12359, "most at the lowest price first")
  win.resultsTable.headers[4]:Click()
  H.eq(A.Controller.state.sortKey, "onah")
  H.eq(A.Controller.results[1], 12359, "most listed first")
end)

test("with an item open beside it, a narrow list keeps the market columns and drops the extras", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env, 960, 540)
  local function shown()
    local out = {}
    for i, col in ipairs(win.resultsTable.columns) do
      if win.resultsTable.headers[i]:IsShown() then out[#out + 1] = col.key end
    end
    return out
  end
  H.eq(shown(), { "name", "price", "atmin", "onah", "change", "owned", "age" }, "every column with nothing open")
  A.Controller.Select(12359)
  Stub.settle(env)
  local keys = shown()
  H.eq({ keys[1], keys[2], keys[3], keys[4] }, { "name", "price", "atmin", "onah" })
  local item = win.resultsTable.list.rows[1].cells[1]:GetWidth()
  H.truthy(item >= 150, "the item name keeps room: " .. item)
  A.UI.Window.SetDetailWidth(5000)              -- the divider dragged as far as it goes
  Stub.settle(env)
  item = win.resultsTable.list.rows[1].cells[1]:GetWidth()
  H.truthy(item >= 70, "even at the narrowest: " .. item)
  H.eq({ shown()[3], shown()[4] }, { "atmin", "onah" })
end)

test("On AH in the item list is dimmed until it comes from a scan Almanac saw", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  local cell = Boot.cell(win, rowFor(win, 12359), "onah")
  H.truthy(cell.text:GetText():find("|c", 1, true), "Auctionator's count for the day")
  Boot.scan(A, env, { ["12359"] = { { price = 11240, available = 9 } } })
  H.eq(Boot.cell(win, rowFor(win, 12359), "onah").text:GetText(), "9")
end)

test("an item picked on the Overview does not move or mark the Search list", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  A.Controller.Select(12363)
  Stub.settle(env)
  H.eq(win.resultsTable.list.selected, 12363, "the Search page's own pick is marked")
  win.overviewButton:Click()
  A.Controller.Select(19019)
  Stub.settle(env)
  H.eq(win.resultsTable.list.selected, nil, "the Overview's pick is not")
  win.searchButton:Click()
  Stub.settle(env)
  H.eq(win.resultsTable.list.selected, 12363, "back on Search, its own pick again")
end)

test("the Search list marks its pick again when the Overview had the same item open", function()
  local A, env = Boot.boot()
  local win = Boot.search(A, env)
  A.Controller.Select(12363)
  win.overviewButton:Click()
  H.eq(win.resultsTable.list.selected, nil)
  A.Controller.Select(12363)                      -- the same item, picked on the Overview
  win.searchButton:Click()
  Stub.settle(env)
  H.eq(A.Controller.state.selected, 12363)
  H.eq(win.resultsTable.list.selected, 12363, "its row is marked again")
end)
