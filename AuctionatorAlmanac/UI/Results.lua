local ADDON, A = ...

-- The Search page's item list: matching items as a sortable table (a star to watch the item, the item,
-- lowest price, how many were listed at it and in all, change, how many you own, how old the price is).
-- Narrow lists (the detail panel open beside them) drop the least important columns first.
local Theme = A.UI.Theme
local Table = A.UI.Table
local Fmt = A.Format
local C = Theme.color
local Results = {}
A.UI.Results = Results

local ROW_HEIGHT = 22
local FOOTER_HEIGHT = 20
local QUESTION_MARK = 134400     -- INV_Misc_QuestionMark
local STAR = 14

-- The game's own hyperlink when it knows the item (so the name and colour are exactly right),
-- otherwise one built from what Almanac has cached.
local function gameLink(id)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not getInfo then return nil end
  local ok, _, link = pcall(getInfo, id)
  if ok and type(link) == "string" and link:find("|Hitem:", 1, true) then return link end
  return nil
end

function Results.ItemLink(id)
  local link = gameLink(id)
  if link then return link end
  local info = A.Controller.Info(id)
  local name = info and info.name or ("Item " .. id)
  local _, _, _, hex = Fmt.QualityColor(info and info.quality)
  return "|cff" .. hex .. "|Hitem:" .. id .. ":::::::::::::::|h[" .. name .. "]|h|r"
end

local function worked(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, result = pcall(fn, ...)
  return ok and result and true or false
end

-- Put the link into the chat box that is open. The game's insert call returns false when no
-- box is open, which is the normal case when you are looking at a window, so then open the box
-- with the link already in it. If the client offers neither, print the link: chat links are
-- clickable and can be shift-clicked from there.
local function insertLink(link)
  local util = ChatFrameUtil
  -- newer clients moved the call into ChatFrameUtil; older ones only have the global
  local insert = (util and util.InsertLink) or ChatEdit_InsertLink
  if worked(insert, link) then return true end
  if util and type(util.OpenChat) == "function" and pcall(util.OpenChat, link) then return true end
  if type(ChatFrame_OpenChat) == "function" and pcall(ChatFrame_OpenChat, link, DEFAULT_CHAT_FRAME) then return true end
  A.Print(link)
  return false
end

function Results.InsertLink(id)
  return insertLink(Results.ItemLink(id))
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
      cell.star = A.UI.Detail.WatchStar(cell, STAR)        -- filled while watched; a click watches or stops
      cell.star:SetPoint("LEFT", cell, "LEFT", 3, 0)
      cell.icon = cell:CreateTexture(nil, "ARTWORK")
      cell.icon:SetSize(18, 18)
      cell.icon:SetPoint("LEFT", cell.star, "RIGHT", 4, 0)
      cell.name = Theme.Text(cell, "normal", "LEFT")
      cell.name:SetPoint("LEFT", cell.icon, "RIGHT", 6, 0)
      cell.name:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
    end,
    update = function(cell, id)
      cell.star:SetItem(id)
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

local function count(n) return n and Fmt.Count(n) or "—" end

-- minWidth: the list width below which a column is dropped, so the item name keeps its room.
local function columns()
  local Ct = A.Controller
  return {
    itemColumn(),
    Table.TextColumn("price", "Lowest", { width = 84, align = "RIGHT", defaultAsc = false }, function(id)
      local s = Ct.Summary(id)
      return s and Fmt.Money(s.last, { short = true }) or "—"
    end),
    Table.TextColumn("atmin", "At lowest", { width = 64, align = "RIGHT", defaultAsc = false }, function(id)
      return count(select(2, Ct.Depth(id)))
    end),
    Table.TextColumn("onah", "On AH", { width = 56, align = "RIGHT", defaultAsc = false }, function(id)
      local onAH, _, fromScan = Ct.Depth(id)
      -- dimmed when it is Auctionator's count for the day rather than the count from the latest scan
      if onAH and not fromScan then return Theme.Colorize(Fmt.Count(onAH), Theme.hex.dim) end
      return count(onAH)
    end),
    Table.TextColumn("change", "Change", { width = 58, align = "RIGHT", defaultAsc = false, minWidth = 440 }, function(id)
      local s = Ct.Summary(id)
      return Fmt.Change(s and s.change1d)
    end),
    Table.TextColumn("owned", "Own", { width = 42, align = "RIGHT", defaultAsc = false, minWidth = 520 }, function(id)
      local n = Ct.Owned(id)
      return n > 0 and Fmt.Count(n) or ""
    end),
    Table.TextColumn("age", "Seen", { width = 48, align = "RIGHT", minWidth = 600 }, ageText),
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

-- Only the Search page's own selection shows here: an item picked on the Overview must not move this list.
function Results.SyncSelection()
  local win = Results.win
  if not win then return end
  local id = A.UI.Window.mode == "search" and A.Controller.state.selected or nil
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
  -- Opening a result is what makes a search worth remembering. The search box may still be offering a completion (clicking here
  -- does not take the keyboard from it), so that is taken first: what is remembered is what the box shows.
  if Results.win and Results.win.searchBox then Results.win.searchBox:Accept() end
  A.Recents.Add(A.Controller.state.text)
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
  A.Bus.On("MODE_CHANGED", Results.SyncSelection)        -- the page's own pick may be the same item as the other page's
  for _, event in ipairs({ "DATA_UPDATED", "ITEM_NAMES_UPDATED", "INVENTORY_UPDATED", "WATCH_CHANGED", "DEPTH_UPDATED" }) do
    A.Bus.On(event, function() win.resultsTable:Refresh() end)
  end
  Results.Update()
end)
