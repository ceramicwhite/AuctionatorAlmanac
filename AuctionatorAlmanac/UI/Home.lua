local ADDON, A = ...

-- The overview shown in the detail panel when no item is selected: a stack of short tables
-- (movers, deals, new finds, watchlist, activity, inventory, shopping lists), each with
-- sortable column headers. Clicking a table's heading opens that table on its own, with a
-- search box, filters and every row (the "full list"). What each table contains lives in
-- Overview; this file only draws it.
local Theme = A.UI.Theme
local W = A.UI.Widgets
local VL = A.UI.VirtualList
local Table = A.UI.Table
local Fmt = A.Format
local C = Theme.color
local Home = {}
A.UI.Home = Home

local ROW_HEIGHT = 22
local QUESTION_MARK = 134400
local WATCH_STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local MAX_VALUE_CELLS = 4           -- columns besides the item in a compact table
local EXTRA_MIN_WIDTH = 480         -- extra columns on a full list need a pane this wide
local BAR_H, SEARCH_H, FILTER_H, NOTE_H = 28, 26, 24, 40

Home.view = "overview"              -- "overview", or the key of the section shown on its own
Home.panels = {}                    -- [key] = the full-list widgets for that section
Home.query = {}                     -- [key] = the search text typed into that section's list

-- ---------------------------------------------------------------------------
-- Content of the compact overview
-- ---------------------------------------------------------------------------
function Home.Lines()
  local O = A.Overview
  local lines = {}
  local function add(line) lines[#lines + 1] = line end

  add({ kind = "text", text = "Pick an item for its price history. Click any heading below to open its full list." })
  for _, def in ipairs(O.Sections()) do
    local rows, total = O.Compact(def.key)
    add({ kind = "title", key = def.key, text = def.title, total = total })
    if def.note then add({ kind = "note", text = def.note }) end
    local lead = O.Lead(def.key)
    for _, text in ipairs(lead) do add({ kind = "text", text = text }) end
    if #rows == 0 then
      if #lead == 0 then add({ kind = "text", text = def.empty }) end
    else
      add({ kind = "cols", key = def.key })
      local lastGroup
      for _, row in ipairs(rows) do
        if def.group then
          local group = def.group(row)
          if group ~= lastGroup then
            add({ kind = "group", text = group })
            lastGroup = group
          end
        end
        add({ kind = "row", key = def.key, row = row })
      end
      if total > #rows then add({ kind = "more", key = def.key, text = "View all " .. Fmt.Count(total), total = total }) end
    end
  end
  return lines
end

-- ---------------------------------------------------------------------------
-- Showing the overview or one full list
-- ---------------------------------------------------------------------------
function Home.Update()
  if not Home.list then return end
  local O = A.Overview
  if Home.view ~= "overview" and not O.Section(Home.view) then Home.view = "overview" end
  local expanded = Home.view ~= "overview"
  Home.list.frame:SetShown(not expanded)
  Home.expandedFrame:SetShown(expanded)
  for key, panel in pairs(Home.panels) do panel.frame:SetShown(expanded and key == Home.view) end
  if expanded then
    if not Home.panels[Home.view] then Home.BuildPanel(Home.view) end
    Home.panels[Home.view].frame:Show()
    Home.RefreshPanel(Home.view)
  else
    Home.list:SetData(Home.Lines())
  end
end

-- Show one section on its own.
function Home.Expand(key)
  if not A.Overview.Section(key) then return end
  Home.view = key
  Home.Update()
end

function Home.ShowOverview()
  Home.view = "overview"
  Home.query = {}
  for _, panel in pairs(Home.panels) do panel.searchBox:SetText("") end
  Home.Update()
end

-- ---------------------------------------------------------------------------
-- A full list
-- ---------------------------------------------------------------------------
local function itemColumn(def)
  local source = def.columns[1]
  return {
    key = "item", title = "Item", flex = 1, align = "LEFT", sortable = true, defaultAsc = true,
    build = function(cell)
      cell.icon = cell:CreateTexture(nil, "ARTWORK")
      cell.icon:SetSize(18, 18)
      cell.icon:SetPoint("LEFT", cell, "LEFT", 3, 0)
      cell.star = cell:CreateTexture(nil, "OVERLAY")
      cell.star:SetSize(12, 12)
      cell.star:SetPoint("RIGHT", cell, "RIGHT", -3, 0)
      cell.star:SetTexture(WATCH_STAR)
      cell.star:Hide()
      cell.name = Theme.Text(cell, "normal", "LEFT")
    end,
    update = function(cell, row)
      local watched = row.id and A.History.IsWatched(row.id)
      cell.star:SetShown(watched and true or false)
      cell.name:ClearAllPoints()
      cell.name:SetPoint("LEFT", cell.icon, "RIGHT", 6, 0)
      cell.name:SetPoint("RIGHT", watched and cell.star or cell, watched and "LEFT" or "RIGHT", watched and -2 or -4, 0)
      local info = row.id and A.Items.Ensure(row.id)
      cell.icon:SetTexture((info and info.icon) or QUESTION_MARK)
      cell.name:SetText(source.text(row))
    end,
  }
end

local function tableColumns(key, def)
  local out = { itemColumn(def) }
  for i = 2, #def.columns do
    local col = def.columns[i]
    out[#out + 1] = Table.TextColumn(col.key, col.title, {
      width = col.width, align = col.align, defaultAsc = col.defaultAsc,
      minWidth = (col.compact == false) and EXTRA_MIN_WIDTH or nil,
    }, function(row) return col.text(row) end)
  end
  return out
end

local function showRowTooltip(owner, key, row)
  if not row.id then return end
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:SetHyperlink("item:" .. row.id)
  local def = A.Overview.Section(key)
  local lines = def.tip and def.tip(row)
  if lines then
    for i, text in ipairs(lines) do
      if i == 1 then
        local c = row.conf
        local color = c and (c.label == "high" and C.good or (c.label == "medium" and C.amber or C.bad)) or C.text
        GameTooltip:AddLine(text, color[1], color[2], color[3])
      else
        GameTooltip:AddLine(text, 0.75, 0.75, 0.75, true)
      end
    end
  end
  GameTooltip:Show()
end

function Home.BuildPanel(key)
  local def = A.Overview.Section(key)
  local panel = {}
  Home.panels[key] = panel

  local frame = CreateFrame("Frame", nil, Home.expandedFrame)
  frame:SetAllPoints(Home.expandedFrame)
  frame:Hide()
  panel.frame = frame

  panel.bar = CreateFrame("Frame", nil, frame)
  panel.bar:SetHeight(BAR_H)
  panel.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  panel.bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  Theme.Fill(panel.bar, C.header)

  panel.backButton = W.Button(panel.bar, "< Overview", function() Home.ShowOverview() end, { width = 86, height = 20 })
  panel.backButton:SetPoint("LEFT", panel.bar, "LEFT", 6, 0)

  panel.count = Theme.Text(panel.bar, "dim", "RIGHT")
  panel.count:SetPoint("RIGHT", panel.bar, "RIGHT", -8, 0)
  panel.count:SetWidth(70)

  panel.title = Theme.Text(panel.bar, "gold", "LEFT")
  panel.title:SetPoint("LEFT", panel.backButton, "RIGHT", 10, 0)
  panel.title:SetPoint("RIGHT", panel.count, "LEFT", -6, 0)
  panel.title:SetText(def.title)

  panel.searchBox = W.EditBox(frame, "Search this list...", function(text)
    if Home.query[key] == text then return end
    Home.query[key] = text
    if Home.view == key then Home.RefreshPanel(key) end
  end, { height = SEARCH_H })
  panel.searchBox:SetPoint("TOPLEFT", panel.bar, "BOTTOMLEFT", 6, -4)
  panel.searchBox:SetPoint("TOPRIGHT", panel.bar, "BOTTOMRIGHT", -6, -4)

  -- filters share one row, each taking an equal part of it
  panel.filterRow = CreateFrame("Frame", nil, frame)
  panel.filterRow:SetPoint("TOPLEFT", panel.searchBox, "BOTTOMLEFT", 0, -4)
  panel.filterRow:SetPoint("TOPRIGHT", panel.searchBox, "BOTTOMRIGHT", 0, -4)
  panel.filters = {}
  local count = #(def.filters or {})
  panel.filterRow:SetHeight(count > 0 and FILTER_H or 1)
  for i, f in ipairs(def.filters or {}) do
    local cycle = W.Cycle(panel.filterRow, f.title, f.options, function(value)
      A.Overview.SetFilter(key, f.key, value)
      Home.RefreshPanel(key)
    end, { height = FILTER_H })
    cycle:ClearAllPoints()
    if count == 1 then
      cycle:SetAllPoints(panel.filterRow)
    elseif i == 1 then
      cycle:SetPoint("TOPLEFT", panel.filterRow, "TOPLEFT", 0, 0)
      cycle:SetPoint("BOTTOMRIGHT", panel.filterRow, "BOTTOM", -2, 0)
    else
      cycle:SetPoint("TOPLEFT", panel.filterRow, "TOP", 2, 0)
      cycle:SetPoint("BOTTOMRIGHT", panel.filterRow, "BOTTOMRIGHT", 0, 0)
    end
    panel.filters[f.key] = cycle
  end

  panel.note = Theme.Text(frame, "dim", "LEFT")
  panel.note:SetWordWrap(true)
  panel.note:SetJustifyV("TOP")
  panel.note:SetHeight(NOTE_H)
  panel.note:SetPoint("TOPLEFT", panel.filterRow, "BOTTOMLEFT", 2, -4)
  panel.note:SetPoint("TOPRIGHT", panel.filterRow, "BOTTOMRIGHT", -2, -4)

  panel.table = Table.New(frame, {
    columns = tableColumns(key, def),
    rowHeight = ROW_HEIGHT,
    sortKey = (A.Overview.GetSort(key)),
    sortAsc = select(2, A.Overview.GetSort(key)),
    onSort = function(colKey, asc)
      A.Overview.SetSort(key, colKey, asc)
      Home.RefreshPanel(key)
    end,
    onClick = function(row)
      if row.id then A.Controller.Select(row.id) end
    end,
    onEnter = function(owner, row) showRowTooltip(owner, key, row) end,
    onLeave = function() GameTooltip:Hide() end,
  })
  panel.table.frame:SetPoint("TOPLEFT", panel.note, "BOTTOMLEFT", -2, -4)
  panel.table.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

  panel.empty = Theme.Text(frame, "dim", "CENTER")
  panel.empty:SetWordWrap(true)
  panel.empty:SetPoint("LEFT", panel.table.frame, "LEFT", 24, 0)
  panel.empty:SetPoint("RIGHT", panel.table.frame, "RIGHT", -34, 0)
  panel.empty:SetPoint("TOP", panel.table.frame, "TOP", 0, -60)
  panel.empty:Hide()
  return panel
end

function Home.RefreshPanel(key)
  local O = A.Overview
  local def = O.Section(key)
  local panel = Home.panels[key]
  if not (def and panel) then return end
  local query = Home.query[key] or ""
  local rows, total = O.View(key, { expanded = true, query = query })
  panel.table:SetData(rows)
  panel.table:SetSort(O.GetSort(key))
  for _, f in ipairs(def.filters or {}) do
    panel.filters[f.key]:SetValue(O.GetFilter(key, f.key))
  end

  if query:match("%S") then
    panel.count:SetText(Fmt.Count(#rows) .. " of " .. Fmt.Count(total))
  else
    panel.count:SetText(Fmt.Count(#rows) .. (#rows == 1 and " row" or " rows"))
  end

  local note = { def.hint }
  for _, text in ipairs(O.Lead(key)) do note[#note + 1] = text end
  panel.note:SetText(table.concat(note, " "))

  if #rows == 0 then
    panel.empty:SetText((total > 0 and query:match("%S")) and "Nothing in this list matches your search." or def.empty)
    panel.empty:Show()
  else
    panel.empty:Hide()
  end
end

-- ---------------------------------------------------------------------------
-- The compact overview
-- ---------------------------------------------------------------------------
local function chevron(row)
  local a = row:CreateLine(nil, "OVERLAY")
  local b = row:CreateLine(nil, "OVERLAY")
  for _, line in ipairs({ a, b }) do
    line:SetThickness(2)
    line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    line:Hide()
  end
  a:SetStartPoint("RIGHT", row, -14, 4)
  a:SetEndPoint("RIGHT", row, -10, 0)
  b:SetStartPoint("RIGHT", row, -10, 0)
  b:SetEndPoint("RIGHT", row, -14, -4)
  local arrow = {}
  function arrow:Show() self.visible = true; a:Show(); b:Show() end
  function arrow:Hide() self.visible = false; a:Hide(); b:Hide() end
  return arrow
end

local function onHeaderClick(button)
  local key, col = button.sectionKey, button.column
  if not (key and col) then return end
  local O = A.Overview
  local current, ascending = O.GetSort(key)
  local asc
  if current == col.key then asc = not ascending else asc = col.defaultAsc ~= false end
  O.SetSort(key, col.key, asc)
  Home.Update()
end

local function createRow(row)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)

  row.cells = {}
  for i = 1, MAX_VALUE_CELLS do row.cells[i] = Theme.Text(row, "normal", "RIGHT") end

  row.hbtns = {}
  for i = 1, MAX_VALUE_CELLS + 1 do
    local b = CreateFrame("Button", nil, row)
    b:SetHeight(ROW_HEIGHT)
    b:RegisterForClicks("LeftButtonUp")
    b.label = Theme.Text(b, "goldSmall", "RIGHT")
    b.arrow = W.SortArrow(b)
    b:SetScript("OnClick", onHeaderClick)
    b:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1, 1) end)
    b:SetScript("OnLeave", function(self)
      local c = self.active and C.gold or C.text
      self.label:SetTextColor(c[1], c[2], c[3], 1)
    end)
    b:Hide()
    row.hbtns[i] = b
  end

  row.name = Theme.Text(row, "normal", "LEFT")
  row.viewAll = Theme.Text(row, "goldSmall", "RIGHT")
  row.chevron = chevron(row)
  row.rule = row:CreateTexture(nil, "BORDER")
  row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 1)
  row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 1)
  row.rule:SetHeight(1)
  Theme.SetColor(row.rule, C.border)
end

local function resetRow(row)
  row.icon:Hide()
  row.rule:Hide()
  row.viewAll:Hide()
  row.chevron:Hide()
  for _, cell in ipairs(row.cells) do cell:Hide() end
  for _, b in ipairs(row.hbtns) do b:Hide() end
  row.name:ClearAllPoints()
end

-- Column geometry shared by data rows and header rows: value columns stack leftwards from the
-- right edge; whatever remains is the item column.
local function placeColumns(row, cols, targets)
  local previous
  for i = #cols, 2, -1 do
    local target = targets[i - 1]
    target:ClearAllPoints()
    target:SetWidth(cols[i].width)
    if previous then
      target:SetPoint("RIGHT", previous, "LEFT", 0, 0)
    else
      target:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    end
    target:Show()
    previous = target
  end
  return previous
end

local function updateRow(row, line)
  resetRow(row)
  local kind = line.kind
  if kind == "text" or kind == "note" or kind == "group" then
    row.name:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    local color = kind == "note" and Theme.hex.dim or (kind == "group" and Theme.hex.gold or nil)
    row.name:SetText(color and Theme.Colorize(line.text, color) or line.text)
  elseif kind == "title" then
    row.viewAll:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    row.viewAll:SetText(line.total > 0 and ("View all " .. Fmt.Count(line.total)) or "Open")
    row.viewAll:Show()
    row.chevron:Show()
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name:SetPoint("RIGHT", row.viewAll, "LEFT", -8, 0)
    row.name:SetText(Theme.Colorize(line.text, Theme.hex.gold))
  elseif kind == "more" then
    row.chevron:Show()
    row.name:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    row.name:SetText(Theme.Colorize(line.text, Theme.hex.gold))
  elseif kind == "cols" then
    local cols = A.Overview.CompactColumns(line.key)
    local sortKey, ascending = A.Overview.GetSort(line.key)
    local leftmost = placeColumns(row, cols, row.hbtns)
    for i, col in ipairs(cols) do
      local b = i == 1 and row.hbtns[MAX_VALUE_CELLS + 1] or row.hbtns[i - 1]
      b.sectionKey, b.column = line.key, col
      b.active = col.key == sortKey
      local c = b.active and C.gold or C.text
      b.label:ClearAllPoints()
      b.label:SetJustifyH(col.align)
      b.label:SetPoint("LEFT", b, "LEFT", i == 1 and 26 or 4, 0)
      b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
      b.label:SetText(col.title)
      b.label:SetTextColor(c[1], c[2], c[3], 1)
      if b.active then b.arrow:Show(col.align, ascending) else b.arrow:Hide() end
      if i == 1 then
        b:ClearAllPoints()
        b:SetPoint("LEFT", row, "LEFT", 6, 0)
        b:SetPoint("RIGHT", leftmost or row, leftmost and "LEFT" or "RIGHT", leftmost and 0 or -6, 0)
        b:Show()
      end
    end
  elseif kind == "row" then
    local cols = A.Overview.CompactColumns(line.key)
    local leftmost = placeColumns(row, cols, row.cells)
    for i = 2, #cols do row.cells[i - 1]:SetText(cols[i].text(line.row)) end
    local data = line.row
    local info = data.id and A.Items.Ensure(data.id)
    row.icon:SetTexture((info and info.icon) or QUESTION_MARK)
    row.icon:SetShown(data.id ~= nil)
    row.name:SetPoint("LEFT", row, "LEFT", data.id and 28 or 10, 0)
    row.name:SetPoint("RIGHT", leftmost or row, leftmost and "LEFT" or "RIGHT", leftmost and -4 or -8, 0)
    row.name:SetText(cols[1].text(data))
  end
end

local function rowColor(line, hover)
  if line.kind == "title" then return hover and C.buttonHover or C.header end
  if line.kind == "more" then return hover and C.hover or C.panel end
  if line.kind == "cols" then return C.panelAlt end
  if line.kind == "text" or line.kind == "note" or line.kind == "group" then return C.panel end
  return nil
end

local function onClick(line)
  if line.kind == "title" or line.kind == "more" then
    Home.Expand(line.key)
  elseif line.kind == "row" and line.row.id then
    A.Controller.Select(line.row.id)
  end
end

local function onEnter(row, line)
  if line.kind == "title" then
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:AddLine(line.text, 1, 0.82, 0)
    GameTooltip:AddLine("Click to open the full list: search it, filter it and sort any column.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  elseif line.kind == "row" then
    showRowTooltip(row, line.key, line.row)
  end
end

A.UI.Window.AddBuilder(function(win)
  Home.list = VL.New(win.homeView, {
    rowHeight = ROW_HEIGHT,
    createRow = createRow,
    update = updateRow,
    rowColor = rowColor,
    onClick = onClick,
    onEnter = onEnter,
    onLeave = function() GameTooltip:Hide() end,
  })
  Home.list.frame:SetAllPoints(win.homeView)
  win.homeList = Home.list

  Home.expandedFrame = CreateFrame("Frame", nil, win.homeView)
  Home.expandedFrame:SetAllPoints(win.homeView)
  Home.expandedFrame:Hide()
  win.homeExpanded = Home.expandedFrame

  Home.Update()
end)
