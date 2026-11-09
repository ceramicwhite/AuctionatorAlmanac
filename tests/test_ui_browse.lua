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
  local win = Boot.open(A, env)
  local text = plain(win.statusText:GetText())
  H.truthy(text:find("2h", 1, true), text)
  H.truthy(text:find("browse", 1, true), text)
  H.truthy(text:find("5 items", 1, true), text)
  H.truthy(text:find("TestRealm", 1, true), text)
  H.truthy(text:find("21 days", 1, true), text)
end)

test("the status strip explains when Auctionator has nothing yet", function()
  local A, env = Boot.boot({ fixture = { Auctionator = false } })
  local win = Boot.open(A, env)
  H.truthy(plain(win.statusText:GetText()):lower():find("auctionator", 1, true))
  H.truthy(win.emptyText:IsShown())
  H.truthy(plain(win.emptyText:GetText()):lower():find("scan", 1, true))
end)

test("results list every priced item sorted by name", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  H.eq(names(win, 5), { "Arcane Crystal", "Eagle Pants", "Thorium Bar", "Thorium Ore", "Thunderfury" })
  H.truthy(plain(win.resultsFooter:GetText()):find("5 items", 1, true))
  H.falsy(win.emptyText:IsShown())
  local row = win.resultsTable.list.rows[3]
  H.eq(plain(row.cells[2].text:GetText()), "1g 12s")
  H.truthy(row.cells[3].text:GetText() ~= "")
end)

test("typing in the search box filters live matches", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
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
  local win = Boot.open(A, env)
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
  local win = Boot.open(A, env)
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
  local win = Boot.open(A, env)
  Stub.fire(win.resultsTable.list.rows[3], "OnClick", "LeftButton")
  H.eq(A.Controller.state.selected, 12359)
  H.truthy(win.resultsTable.list.rows[3].selected)
end)

test("shift-click and right-click link the item into chat", function()
  local linked = {}
  local A, env = Boot.boot({ env = { ChatEdit_InsertLink = function(link) linked[#linked + 1] = link; return true end } })
  local win = Boot.open(A, env)
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
  local win = Boot.open(A, env)
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
  local win = Boot.open(A, env)
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
  local win = Boot.open(A, env)
  local bar = win.resultsTable.list.rows[3]
  H.eq(plain(bar.cells[4].text:GetText()), "14")
  H.eq(plain(bar.cells[5].text:GetText()), "today")
  local fury = win.resultsTable.list.rows[5]
  H.eq(plain(fury.cells[5].text:GetText()), "1d")
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
  local win = Boot.open(A, env)
  local first = plain(win.resultsTable.list.rows[1].cells[1].name:GetText())
  H.truthy(first:find("Item ", 1, true), first)
  H.eq(#A.Controller.results, 5, "unnamed items still list")
end)

test("browse regions never overlap or leave their panels at any window size", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
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
  local win = Boot.open(A, env, 960, 540)
  local small = #win.resultsTable.list.rows
  Stub.resize(env, win, 960, 1000)
  H.truthy(#win.resultsTable.list.rows > small + 10)
end)

test("the window reflects new scan data after a reload", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
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
  local win = Boot.open(A, env)
  A.UI.Window.SetCollapsed(true)
  H.falsy(win.resultsPanel:IsShown())
  typeSearch(win, env, "thorium")
  H.falsy(A.UI.Window.IsCollapsed())
  H.truthy(win.resultsPanel:IsShown())
end)

test("choosing a category or a filter brings back a hidden item list", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
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
  local win = Boot.open(A, env)
  A.UI.Window.SetCollapsed(true)
  A.Controller.SetSearchText("")
  win.searchBox:SetText("")
  A.UI.SearchBar.Sync()
  H.truthy(A.UI.Window.IsCollapsed())
end)

test("the slash search opens the list too", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  A.UI.Window.SetCollapsed(true)
  env.SlashCmdList.ALMANAC("search thorium")
  H.falsy(A.UI.Window.IsCollapsed())
  H.eq(A.Controller.state.text, "thorium")
end)

test("watched items wear a star in the results list", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  local function rowFor(id)
    for _, row in ipairs(win.resultsTable.list.rows) do
      if row:IsShown() and row.item == id then return row end
    end
  end
  H.falsy(rowFor(12359).cells[1].star:IsShown())
  A.History.Watch(12359, true)
  env.C_Timer.flush()
  H.truthy(rowFor(12359).cells[1].star:IsShown(), "starred once watched")
  H.falsy(rowFor(10620).cells[1].star:IsShown(), "others are not")
  A.History.Watch(12359, false)
  H.falsy(rowFor(12359).cells[1].star:IsShown())
end)
