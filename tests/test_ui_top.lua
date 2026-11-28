local H = require("harness")
local Stub = require("ui_stub")
local Boot = require("boot_ui")
local test = H.test

local function plain(s)
  s = tostring(s):gsub("|c%x%x%x%x%x%x%x%x", "")
  return (s:gsub("|r", ""))
end

local function openTop(w, h)
  local A, env = Boot.boot()
  local win = Boot.open(A, env, w, h)
  win.topButton:Click()
  Stub.settle(env)
  return A, env, win
end

local function panelOf(A) return A.UI.Home.top end

local function shownRow(panel, id)
  for _, row in ipairs(panel.table.list.rows) do
    if row:IsShown() and row.item and row.item.id == id then return row end
  end
end

local function search(panel, text)
  panel.searchBox.edit:SetText(text)
  Stub.fire(panel.searchBox.edit, "OnTextChanged", true)
end

test("the Top 500 button opens a page with the whole list on it", function()
  local A, env, win = openTop()
  H.eq(A.UI.Window.mode, "top")
  H.truthy(win.topButton.active, "Top 500 is lit")
  H.falsy(win.overviewButton.active or win.searchButton.active)
  local panel = panelOf(A)
  H.truthy(panel.frame:IsVisible())
  H.eq(plain(panel.title:GetText()), "Top 500")
  H.eq(panel.backButton, nil, "a page of its own: nothing to go back to")
  H.eq(#panel.table.list.data, 500)
  H.eq(plain(panel.count:GetText()), "500 rows")
  H.falsy(win.homeView:IsVisible(), "the overview is not on this page")
end)

test("every column header sorts the list, and clicking it again reverses it", function()
  local A, env, win = openTop()
  local panel = panelOf(A)
  local t = panel.table
  local def = A.Overview.Section("top500")
  H.eq(#t.columns, #def.columns)
  for i, col in ipairs(def.columns) do
    local header = t.headers[i]
    H.truthy(header:IsShown(), col.title .. " is on the page")
    for click = 1, 2 do
      header:Click()
      Stub.settle(env)
      local key, asc = A.Overview.GetSort("top500")
      H.eq(key, col.key, col.title)
      if click == 1 then H.eq(asc, col.defaultAsc ~= false, col.title .. " starts in its natural direction") end
      H.truthy(header.arrow.visible, col.title .. " shows it is the sort")
      local last, sawNil = nil, false
      for n, row in ipairs(t.list.data) do
        local v = col.value(row)
        if v == nil then
          sawNil = true
        else
          H.falsy(sawNil, col.title .. ": blanks go last, row " .. n)
          if last ~= nil then H.truthy(asc and v >= last or not asc and v <= last, col.title .. " in order at row " .. n) end
          last = v
        end
      end
    end
    local _, firstAsc = A.Overview.GetSort("top500")
    header:Click()
    H.eq(select(2, A.Overview.GetSort("top500")), not firstAsc, col.title .. " flips every click")
  end
end)

test("the list opens dearest first, and the Price header flips it to cheapest first and back", function()
  local A, env, win = openTop()
  local panel = panelOf(A)
  local function priceHeader()
    for i, col in ipairs(panel.table.columns) do
      if col.key == "price" then return panel.table.headers[i] end
    end
  end
  local function firstTwo()
    local data = panel.table.list.data
    H.truthy(data[1].price and data[2].price, "priced items lead")
    return data[1].price, data[2].price
  end
  H.eq({ A.Overview.GetSort("top500") }, { "price", false })
  H.truthy(priceHeader().arrow.visible, "the header says so")
  local a, b = firstTwo()
  H.truthy(a > b, "high to low")
  priceHeader():Click()
  a, b = firstTwo()
  H.truthy(a < b, "low to high")
  priceHeader():Click()
  a, b = firstTwo()
  H.truthy(a > b, "high to low again")
end)

test("the search box narrows the list", function()
  local A, env, win = openTop()
  local panel = panelOf(A)
  local expected = 0
  for _, e in ipairs(A.Top500) do if e.name:lower():find("thorium", 1, true) then expected = expected + 1 end end
  search(panel, "thorium")
  H.eq(#panel.table.list.data, expected)
  H.truthy(plain(panel.count:GetText()):find(expected .. " of 500", 1, true), panel.count:GetText())
  search(panel, "")
  H.eq(#panel.table.list.data, 500)
end)

test("the kind filter shows one kind at a time", function()
  local A, env, win = openTop()
  local panel = panelOf(A)
  panel.filters.kind:Click()
  local kind = A.Overview.GetFilter("top500", "kind")
  H.truthy(kind)
  for _, row in ipairs(panel.table.list.data) do H.eq(row.kind, kind) end
  H.truthy(#panel.table.list.data < 500)
end)

test("clicking a row opens the item beside the list, and the page keeps its own pick", function()
  local A, env, win = openTop()
  local panel = panelOf(A)
  search(panel, "arcane crystal")
  Stub.settle(env)
  local row = shownRow(panel, 12363)
  H.truthy(row, "Arcane Crystal is on the list")
  Stub.fire(row, "OnClick", "LeftButton")
  Stub.settle(env)
  H.eq(A.Controller.state.selected, 12363)
  H.truthy(win.detailPanel:IsShown())
  H.truthy(win.topPanel:IsShown(), "the list stays beside it")
  H.falsy(Stub.overlaps(win.topPanel, win.detailPanel))
  win.overviewButton:Click()
  H.eq(A.Controller.state.selected, nil, "the Overview has its own pick")
  win.topButton:Click()
  H.eq(A.Controller.state.selected, 12363)
end)

test("the star on a row watches the item without opening it", function()
  local A, env, win = openTop()
  local panel = panelOf(A)
  search(panel, "arcane crystal")
  Stub.settle(env)
  local cell = shownRow(panel, 12363).cells[1]
  H.truthy(cell.star:IsShown())
  H.truthy(cell.star:GetRight() <= cell.icon:GetLeft(), "left of the icon")
  cell.star:Click()
  env.C_Timer.flush()
  H.truthy(A.History.IsWatched(12363))
  H.eq(A.Controller.state.selected, nil)
  H.truthy(shownRow(panel, 12363).cells[1].star.on)
end)

test("hovering a row shows the item and why it is on the list", function()
  local A, env, win = openTop()
  local panel = panelOf(A)
  local lines, linked = {}, nil
  env.GameTooltip = {
    SetOwner = function() end, Show = function() end, Hide = function() end,
    SetHyperlink = function(_, link) linked = link end,
    AddLine = function(_, text) lines[#lines + 1] = plain(text) end,
  }
  search(panel, "flask of the titans")
  Stub.settle(env)
  Stub.fire(shownRow(panel, 13510), "OnEnter")
  H.eq(linked, "item:13510")
  H.eq(lines[1], "Consumable · Flasks · req. level 50")
  H.truthy((lines[2] or ""):find("tanks' flask", 1, true), lines[2])
end)

test("new prices that come in while another page shows are there when the Top 500 comes back", function()
  local A, env, win = openTop()
  win.overviewButton:Click()
  Stub.settle(env)
  Boot.put(env.AUCTIONATOR_PRICE_DATABASE.TestRealm, 12363, { 77777 }, 5)
  A.Controller.Reload()
  env.C_Timer.flush()
  win.topButton:Click()
  Stub.settle(env)
  local found
  for _, row in ipairs(panelOf(A).table.list.data) do
    if row.id == 12363 then found = row end
  end
  H.eq(found.price, 77777, "redrawn on coming back, before anything is clicked")
end)

test("the page's parts fit and never overlap at every window size, with or without an item open", function()
  local A, env, win = openTop()
  local panel = panelOf(A)
  for _, size in ipairs({ { 960, 540 }, { 1000, 620 }, { 1400, 900 } }) do
    for _, open in ipairs({ false, true }) do
      A.Controller.Select(open and 12363 or nil)
      Stub.resize(env, win, size[1], size[2])
      local label = size[1] .. "x" .. size[2] .. (open and " with an item open" or "")
      H.falsy(win.searchRow:IsShown() or win.catPanel:IsShown(), "no search row or categories: " .. label)
      if not open then H.near(win.topPanel:GetWidth(), win.body:GetWidth(), 0.5, "the whole body: " .. label) end
      local parts = { panel.bar, panel.searchBox, panel.filterRow, panel.table.frame }
      for _, part in ipairs(parts) do H.truthy(Stub.within(part, win.topPanel), "inside the page: " .. label) end
      for a = 1, #parts do
        for b = a + 1, #parts do H.falsy(Stub.overlaps(parts[a], parts[b]), "overlap: " .. label) end
      end
      H.truthy(Stub.within(panel.title, panel.bar) and Stub.within(panel.count, panel.bar), label)
      H.truthy(panel.table.frame:GetHeight() > 120, "the table has room: " .. label)
      H.truthy(win.topPanel:GetWidth() >= A.UI.Window.RESULTS_MIN, label)
      local shown = {}
      for i, col in ipairs(panel.table.columns) do if panel.table.headers[i]:IsShown() then shown[col.key] = true end end
      H.truthy(shown.item and shown.price, "the item and its price always: " .. label)
      if panel.table.frame:GetWidth() >= A.Overview.QTY_WIDE then
        H.truthy(shown.atmin and shown.onah, "the market columns when there is room: " .. label)
      end
    end
  end
end)

test("the Top 500 keeps its search when you leave a list on the Overview", function()
  local A, env, win = openTop()
  local panel = panelOf(A)
  search(panel, "thorium")
  local narrowed = #panel.table.list.data
  H.truthy(narrowed < 500)
  win.overviewButton:Click()
  A.UI.Home.Expand("movers")
  A.UI.Home.panels.movers.backButton:Click()
  win.topButton:Click()
  Stub.settle(env)
  H.eq(panel.searchBox.edit:GetText(), "thorium")
  panel.table.headers[1]:Click()          -- anything that redraws the list
  H.eq(#panel.table.list.data, narrowed, "the list still matches what the box says")
end)

test("an item the client has not named yet keeps the list's name when it is opened", function()
  local A, env, win = openTop()
  A.Controller.Select(13513)
  Stub.settle(env)
  H.eq(win.itemView.name:GetText(), A.Format.ColorName("Flask of Chromatic Resistance", 1))
end)

test("sorting by Own puts what you own first either way, and the blanks last", function()
  local A, env, win = openTop()
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [12359] = 14, [10620] = 3 }, 1)
  A.Bus.Fire("INVENTORY_UPDATED")
  local panel = panelOf(A)
  local header
  for i, col in ipairs(panel.table.columns) do if col.key == "owned" then header = panel.table.headers[i] end end
  header:Click()
  local data = panel.table.list.data
  H.eq({ data[1].id, data[2].id }, { 12359, 10620 }, "most first")
  header:Click()
  data = panel.table.list.data
  H.eq({ data[1].id, data[2].id }, { 10620, 12359 }, "fewest owned first, not the 498 you have none of")
end)
