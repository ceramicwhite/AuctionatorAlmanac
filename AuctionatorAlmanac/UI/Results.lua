local ADDON, A = ...

-- The middle panel: matching items as a sortable table (item, lowest price,
-- change, how many you own, how old the price is).
local Theme = A.UI.Theme
local Table = A.UI.Table
local Fmt = A.Format
local C = Theme.color
local Results = {}
A.UI.Results = Results

local ROW_HEIGHT = 22
local FOOTER_HEIGHT = 20
local QUESTION_MARK = 134400     -- INV_Misc_QuestionMark

function Results.ItemLink(id)
  local info = A.Controller.Info(id)
  local name = info and info.name or ("Item " .. id)
  local _, _, _, hex = Fmt.QualityColor(info and info.quality)
  return "|cff" .. hex .. "|Hitem:" .. id .. ":::::::::::::::|h[" .. name .. "]|h|r"
end

local function insertLink(link)
  if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
  if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
end

function Results.InsertLink(id)
  insertLink(Results.ItemLink(id))
end

local function ageText(id)
  local s = A.Controller.Summary(id)
  if not s or not s.ageDays then return "—" end
  if s.ageDays <= 0 then return "today" end
  return s.ageDays .. "d"
end

local function itemColumn()
  return {
    key = "name", title = "Item", flex = 1, align = "LEFT", sortable = true, defaultAsc = true,
    build = function(cell)
      cell.icon = cell:CreateTexture(nil, "ARTWORK")
      cell.icon:SetSize(18, 18)
      cell.icon:SetPoint("LEFT", cell, "LEFT", 3, 0)
      cell.name = Theme.Text(cell, "normal", "LEFT")
      cell.name:SetPoint("LEFT", cell.icon, "RIGHT", 6, 0)
      cell.name:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
    end,
    update = function(cell, id)
      local info = A.Controller.Info(id)
      cell.icon:SetTexture((info and info.icon) or QUESTION_MARK)
      if info and info.name then
        cell.name:SetText(Fmt.ColorName(info.name, info.quality))
      else
        cell.name:SetText(Theme.Colorize("Item " .. id, Theme.hex.dim))
      end
    end,
  }
end

local function columns()
  local Ct = A.Controller
  return {
    itemColumn(),
    Table.TextColumn("price", "Lowest", { width = 88, align = "RIGHT", defaultAsc = false }, function(id)
      local s = Ct.Summary(id)
      return s and Fmt.Money(s.last, { short = true }) or "—"
    end),
    Table.TextColumn("change", "Change", { width = 58, align = "RIGHT", defaultAsc = false }, function(id)
      local s = Ct.Summary(id)
      return Fmt.Change(s and s.change1d)
    end),
    Table.TextColumn("owned", "Own", { width = 42, align = "RIGHT", defaultAsc = false }, function(id)
      local n = Ct.Owned(id)
      return n > 0 and Fmt.Count(n) or ""
    end),
    Table.TextColumn("age", "Seen", { width = 48, align = "RIGHT" }, ageText),
  }
end

local function emptyMessage()
  local Ct = A.Controller
  if not Ct.ready then
    return "Auctionator's saved prices are not available yet. Make sure Auctionator is enabled, then scan the Auction House once."
  end
  if #Ct.ids == 0 then
    return "Auctionator has not saved any prices yet. Open the Auction House and scan, and they will appear here."
  end
  return "No items match your search."
end

function Results.Update()
  local win = Results.win
  if not win then return end
  local Ct = A.Controller
  win.resultsTable:SetData(Ct.results)
  local n = #Ct.results
  if n == 0 then
    win.resultsFooter:SetText("No items")
    win.emptyText:SetText(emptyMessage())
    win.emptyText:Show()
  else
    win.resultsFooter:SetText(Fmt.Count(n) .. (n == 1 and " item" or " items"))
    win.emptyText:Hide()
  end
  Results.SyncSelection()
end

function Results.SyncSelection()
  local win = Results.win
  if not win then return end
  local id = A.Controller.state.selected
  win.resultsTable:SetSelectedItem(id)
  if id then
    for index, candidate in ipairs(A.Controller.results) do
      if candidate == id then win.resultsTable.list:ScrollTo(index); break end
    end
  end
end

local function onClick(id, _, button)
  if button == "RightButton" or IsModifiedClick("CHATLINK") then
    insertLink(Results.ItemLink(id))
    return
  end
  A.Controller.Select(id)
end

local function onEnter(row, id)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetHyperlink("item:" .. id)
  GameTooltip:Show()
end

A.UI.Window.AddBuilder(function(win)
  Results.win = win
  local panel = win.resultsPanel

  win.resultsTable = Table.New(panel, {
    columns = columns(),
    rowHeight = ROW_HEIGHT,
    sortKey = A.Controller.state.sortKey,
    sortAsc = A.Controller.state.asc,
    onSort = function(key, asc) A.Controller.SetSort(key, asc) end,
    onClick = onClick,
    onEnter = onEnter,
    onLeave = function() GameTooltip:Hide() end,
  })
  win.resultsTable.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
  win.resultsTable.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, FOOTER_HEIGHT + 2)

  win.resultsFooter = Theme.Text(panel, "dim", "LEFT")
  win.resultsFooter:SetHeight(14)
  win.resultsFooter:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 5)
  win.resultsFooter:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 5)

  win.emptyText = Theme.Text(panel, "normal", "CENTER")
  win.emptyText:SetWordWrap(true)
  win.emptyText:SetPoint("LEFT", panel, "LEFT", 36, 0)
  win.emptyText:SetPoint("RIGHT", panel, "RIGHT", -36, 0)
  win.emptyText:Hide()

  A.Bus.On("RESULTS_UPDATED", Results.Update)
  A.Bus.On("WINDOW_SHOWN", Results.Update)
  A.Bus.On("SELECTION_CHANGED", Results.SyncSelection)
  for _, event in ipairs({ "DATA_UPDATED", "ITEM_NAMES_UPDATED", "INVENTORY_UPDATED" }) do
    A.Bus.On(event, function() win.resultsTable:Refresh() end)
  end
  Results.Update()
end)
