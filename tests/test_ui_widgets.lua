local H = require("harness")
local Stub = require("ui_stub")
local test = H.test

local FILES = { "Core/Init.lua", "Core/Format.lua", "UI/Theme.lua", "UI/Widgets.lua", "UI/VirtualList.lua", "UI/Table.lua" }

local function boot()
  local env = Stub.new()
  env.C_Timer = H.fakeTimer()
  local A, leaks = H.newUI(FILES, env)
  return A, env, leaks
end

local function host(env, w, h)
  local f = env.CreateFrame("Frame", nil, env.UIParent)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 0, 0)
  return f
end

local function items(n)
  local t = {}
  for i = 1, n do t[i] = { id = i, name = "Item " .. i } end
  return t
end

test("UI files define no stray globals", function()
  local _, _, leaks = boot()
  H.eq(leaks, {})
end)

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------
test("Button runs its handler when enabled and ignores clicks when disabled", function()
  local A, env = boot()
  local n = 0
  local b = A.UI.Widgets.Button(host(env, 200, 100), "Go", function() n = n + 1 end)
  b:Click()
  H.eq(n, 1)
  b:SetEnabled(false)
  b:Click()
  H.eq(n, 1)
  b:SetLabel("Stop")
  H.eq(b.label:GetText(), "Stop")
end)

test("Checkbox reads state, writes the opposite on click and refreshes", function()
  local A, env = boot()
  local value = false
  local c = A.UI.Widgets.Checkbox(host(env, 200, 100), "Show", function() return value end, function(v) value = v end)
  c:Click()
  H.eq(value, true)
  c:Click()
  H.eq(value, false)
  value = true
  c:Refresh()
  H.truthy(c.check:IsShown())
end)

test("EditBox reports typing, shows its placeholder only when empty, and clears", function()
  local A, env = boot()
  local got = {}
  local box = A.UI.Widgets.EditBox(host(env, 300, 100), "Search...", function(text, user) got[#got + 1] = { text, user } end)
  H.truthy(box.hint:IsShown())
  box.edit:SetText("thor")
  Stub.fire(box.edit, "OnTextChanged", true)
  H.eq(got[#got], { "thor", true })
  H.falsy(box.hint:IsShown())
  box:Clear()
  H.eq(box:GetText(), "")
  H.truthy(box.hint:IsShown())
  H.eq(got[#got], { "", false }, "programmatic changes are flagged as not typed")
end)

test("Tabs select one at a time and report the key", function()
  local A, env = boot()
  local chosen
  local tabs = A.UI.Widgets.Tabs(host(env, 400, 100), { { key = "a", label = "Alpha" }, { key = "b", label = "Beta" } }, function(k) chosen = k end)
  tabs:Select("b")
  H.eq(chosen, "b")
  H.eq(tabs.selected, "b")
  tabs.buttons.a:Click()
  H.eq(chosen, "a")
  H.eq(tabs.selected, "a")
end)

test("Cycle button steps through its options and wraps", function()
  local A, env = boot()
  local seen = {}
  local c = A.UI.Widgets.Cycle(host(env, 200, 100), "Quality", { { label = "Any" }, { value = 2, label = "Uncommon" }, { value = 3, label = "Rare" } },
    function(v) seen[#seen + 1] = v == nil and "nil" or v end)
  c:Click(); c:Click(); c:Click()
  H.eq(seen, { 2, 3, "nil" })
  c:SetValue(3)
  H.eq(c.value, 3)
  H.truthy(c.label:GetText():find("Rare", 1, true))
end)

-- ---------------------------------------------------------------------------
-- VirtualList
-- ---------------------------------------------------------------------------
local function makeList(A, env, opts)
  opts = opts or {}
  local parent = host(env, opts.w or 400, opts.h or 200)
  local updates = 0
  local list = A.UI.VirtualList.New(parent, {
    rowHeight = 20,
    createRow = function(row) row.text = row:CreateFontString(nil, "OVERLAY"); row.text:SetPoint("LEFT", row, "LEFT", 4, 0) end,
    update = function(row, item, index, selected)
      updates = updates + 1
      row.text:SetText(item.name)
      row.selectedFlag = selected
    end,
    onClick = opts.onClick,
  })
  list.frame:SetAllPoints(parent)
  Stub.settle(env)
  return list, parent, function() return updates end
end

test("VirtualList builds just enough rows for its height and grows when resized", function()
  local A, env = boot()
  local list, parent = makeList(A, env, { h = 200 })
  H.eq(#list.rows, 11, "200px / 20px = 10 visible, plus one for partial scroll")
  Stub.resize(env, parent, 400, 400)
  H.eq(#list.rows, 21)
  Stub.resize(env, parent, 400, 100)
  H.eq(#list.rows, 21, "the pool never shrinks")
  local shown = 0
  for _, row in ipairs(list.rows) do if row:IsShown() then shown = shown + 1 end end
  H.eq(shown, 0, "no data, no visible rows")
end)

test("VirtualList renders only the visible slice of a huge data set", function()
  local A, env = boot()
  local list, _, updates = makeList(A, env, { h = 200 })
  list:SetData(items(15000))
  H.truthy(updates() <= #list.rows, "updates are bounded by the pool, got " .. updates())
  H.eq(list.rows[1].text:GetText(), "Item 1")
  list:SetOffset(1000)
  H.eq(list.rows[1].text:GetText(), "Item 1001")
  H.eq(list:GetOffset(), 1000)
  list:SetOffset(999999)
  H.eq(list:GetOffset(), 15000 - 10, "offset clamps so the last page is full")
  list:SetOffset(-5)
  H.eq(list:GetOffset(), 0)
end)

test("VirtualList mouse wheel scrolls three rows per notch and keeps within range", function()
  local A, env = boot()
  local list = makeList(A, env, { h = 200 })
  list:SetData(items(100))
  Stub.fire(list.frame, "OnMouseWheel", -1)
  H.eq(list:GetOffset(), 3)
  Stub.fire(list.frame, "OnMouseWheel", 1)
  Stub.fire(list.frame, "OnMouseWheel", 1)
  H.eq(list:GetOffset(), 0)
end)

test("VirtualList handles empty, single and shrinking data", function()
  local A, env = boot()
  local list = makeList(A, env, { h = 200 })
  list:SetData({})
  H.falsy(list.rows[1]:IsShown())
  H.falsy(list.scrollbar.frame:IsShown(), "no scrollbar when everything fits")
  list:SetData(items(1))
  H.truthy(list.rows[1]:IsShown())
  H.falsy(list.rows[2]:IsShown())
  list:SetData(items(100))
  list:SetOffset(80)
  list:SetData(items(20))
  H.eq(list:GetOffset(), 10, "offset re-clamps when the data shrinks")
  H.eq(list.rows[1].text:GetText(), "Item 11")
  H.truthy(list.scrollbar.frame:IsShown())
end)

test("VirtualList selection and clicks", function()
  local A, env = boot()
  local clicked
  local list = makeList(A, env, { h = 200, onClick = function(item, index, button) clicked = { item.id, index, button } end })
  local data = items(50)
  list:SetData(data)
  list:SetSelectedItem(data[3])
  H.truthy(list.rows[3].selectedFlag)
  H.falsy(list.rows[2].selectedFlag)
  Stub.fire(list.rows[2], "OnClick", "LeftButton")
  H.eq(clicked, { 2, 2, "LeftButton" })
  list:SetOffset(5)
  Stub.fire(list.rows[1], "OnClick", "RightButton")
  H.eq(clicked, { 6, 6, "RightButton" }, "index is the data index, not the row")
end)

test("VirtualList ScrollTo brings an index into view", function()
  local A, env = boot()
  local list = makeList(A, env, { h = 200 })
  list:SetData(items(100))
  list:ScrollTo(50)
  local offset = list:GetOffset()
  H.truthy(offset + 1 <= 50 and 50 <= offset + 10)
  list:ScrollTo(1)
  H.eq(list:GetOffset(), 0)
end)

test("VirtualList rows stay inside the list and do not overlap", function()
  local A, env = boot()
  local list, parent = makeList(A, env, { h = 200, w = 320 })
  list:SetData(items(100))
  for _, row in ipairs(list.rows) do
    if row:IsShown() then H.truthy(Stub.within(row, parent, 25), "row inside list") end
  end
  H.falsy(Stub.overlaps(list.rows[1], list.rows[2]))
  H.falsy(Stub.overlaps(list.rows[1], list.scrollbar.frame), "rows leave room for the scrollbar")
end)

test("scrollbar drag moves the list", function()
  local A, env = boot()
  local list = makeList(A, env, { h = 200 })
  list:SetData(items(100))
  list.scrollbar.slider:SetValue(40)
  H.eq(list:GetOffset(), 40)
end)

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------
local function makeTable(A, env, w, onSort)
  local parent = host(env, w, 240)
  local columns = {
    A.UI.Table.TextColumn("name", "Name", { flex = 1 }, function(item) return item.name end),
    A.UI.Table.TextColumn("price", "Price", { width = 80, align = "RIGHT" }, function(item) return tostring(item.id * 10) end),
    A.UI.Table.TextColumn("plain", "Static", { width = 50, sortable = false }, function() return "-" end),
  }
  local tbl = A.UI.Table.New(parent, { columns = columns, rowHeight = 20, onSort = onSort })
  tbl.frame:SetAllPoints(parent)
  Stub.settle(env)
  return tbl, parent
end

test("Table splits width between fixed and flexible columns and follows resizes", function()
  local A, env = boot()
  local tbl, parent = makeTable(A, env, 500)
  tbl:SetData(items(5))
  local row = tbl.list.rows[1]
  local nameW = row.cells[1]:GetWidth()
  H.eq(row.cells[2]:GetWidth(), 80)
  H.eq(row.cells[3]:GetWidth(), 50)
  H.truthy(nameW > 250, "the flexible column takes the rest, got " .. nameW)
  Stub.resize(env, parent, 900, 240)
  H.near(row.cells[1]:GetWidth() - nameW, 400, 0.5)
  H.eq(row.cells[2]:GetWidth(), 80, "fixed columns do not change")
  local total = 0
  for _, cell in ipairs(row.cells) do total = total + cell:GetWidth() end
  H.truthy(total <= row:GetWidth() + 0.5, "cells fit the row")
  H.falsy(Stub.overlaps(row.cells[1], row.cells[2]))
  H.falsy(Stub.overlaps(row.cells[2], row.cells[3]))
end)

test("Table headers line up with their cells", function()
  local A, env = boot()
  local tbl = makeTable(A, env, 600)
  tbl:SetData(items(3))
  local row = tbl.list.rows[1]
  for i = 1, 3 do
    H.near(tbl.headers[i]:GetLeft(), row.cells[i]:GetLeft(), 0.5, "column " .. i)
    H.near(tbl.headers[i]:GetWidth(), row.cells[i]:GetWidth(), 0.5, "column " .. i)
  end
end)

test("Table rows show the column text", function()
  local A, env = boot()
  local tbl = makeTable(A, env, 600)
  tbl:SetData(items(3))
  local row = tbl.list.rows[2]
  H.eq(row.cells[1].text:GetText(), "Item 2")
  H.eq(row.cells[2].text:GetText(), "20")
end)

test("Table header clicks sort, flip direction, and ignore non-sortable columns", function()
  local A, env = boot()
  local calls = {}
  local tbl = makeTable(A, env, 600, function(key, asc) calls[#calls + 1] = key .. ":" .. tostring(asc) end)
  tbl:SetSort("name", true)
  tbl.headers[2]:Click()
  tbl.headers[2]:Click()
  tbl.headers[1]:Click()
  tbl.headers[3]:Click()
  H.eq(calls, { "price:true", "price:false", "name:true" })
  H.eq(tbl.sortKey, "name")
  H.eq(tbl.sortAsc, true)
end)

test("Table SetSort does not fire the sort callback", function()
  local A, env = boot()
  local n = 0
  local tbl = makeTable(A, env, 600, function() n = n + 1 end)
  tbl:SetSort("price", false)
  H.eq(n, 0)
  H.eq(tbl.sortKey, "price")
  H.eq(tbl.sortAsc, false)
end)

test("Table keeps working at a tiny width", function()
  local A, env = boot()
  local tbl, parent = makeTable(A, env, 500)
  tbl:SetData(items(5))
  H.nothrows(function() Stub.resize(env, parent, 120, 240) end)
  local row = tbl.list.rows[1]
  H.truthy(row.cells[1]:GetWidth() >= 0)
end)
