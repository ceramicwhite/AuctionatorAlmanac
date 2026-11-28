local ADDON, A = ...

-- The right-hand panel, open while an item is selected on either page: a header, key numbers and
-- three tabs. Also home to watching: the Watch button here, and the star beside items in every list.
local Theme = A.UI.Theme
local W = A.UI.Widgets
local Fmt = A.Format
local C = Theme.color
local Detail = {}
A.UI.Detail = Detail

local HEADER_H, STATS_H, STAT_ROW_H = 58, 78, 38
local QUESTION_MARK = 134400
local dirty = true

local STATS = {
  { "lowest", "Lowest now", 1, 0 },
  { "average", "Average", 2, 0 },
  { "change", "7-day change", 3, 0 },
  { "range", "Range", 1, 1 },
  { "quantity", "On AH / at lowest", 2, 1 },
  { "vendor", "Vendor price", 3, 1 },
}

local TABS = {
  { key = "history", label = "Price History" },
  { key = "activity", label = "My Activity" },
  { key = "owned", label = "Where I Own It" },
}

local DASH = "—"

function Detail.Subtitle(info)
  if not info or info.class == nil then return "" end
  local item = C_Item
  local parts = {}
  local className = item and item.GetItemClassInfo and item.GetItemClassInfo(info.class)
  local subName = item and item.GetItemSubClassInfo and item.GetItemSubClassInfo(info.class, info.sub)
  if className and className ~= "" then parts[#parts + 1] = className end
  if subName and subName ~= "" and subName ~= className then parts[#parts + 1] = subName end
  return table.concat(parts, "  ·  ")
end

local function setStat(iv, key, text)
  iv.stat[key].value:SetText(text)
end

local function buildHeader(iv)
  local header = CreateFrame("Frame", nil, iv)
  header:SetHeight(HEADER_H)
  header:SetPoint("TOPLEFT", iv, "TOPLEFT", 6, -6)
  header:SetPoint("TOPRIGHT", iv, "TOPRIGHT", -6, -6)

  iv.icon = header:CreateTexture(nil, "ARTWORK")
  iv.icon:SetSize(40, 40)
  iv.icon:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -2)

  -- Closing the panel hands its room back to the list beside it, which never went away.
  iv.backButton = W.Button(header, "Close", function() A.Controller.Select(nil) end, { width = 56, height = 20 })
  iv.backButton:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)

  iv.name = Theme.Text(header, "title", "LEFT")
  iv.name:SetPoint("TOPLEFT", iv.icon, "TOPRIGHT", 8, -1)
  iv.name:SetPoint("RIGHT", iv.backButton, "LEFT", -6, 0)

  iv.subtitle = Theme.Text(header, "dim", "LEFT")
  iv.subtitle:SetPoint("TOPLEFT", iv.name, "BOTTOMLEFT", 0, -3)
  iv.subtitle:SetPoint("RIGHT", header, "RIGHT", 0, 0)

  iv.linkButton = W.Button(header, "Link", function()
    if A.Controller.state.selected then A.UI.Results.InsertLink(A.Controller.state.selected) end
  end, { width = 44, height = 20 })
  iv.linkButton:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)

  iv.watchButton = W.Button(header, "Watch", function() Detail.ToggleWatch() end, { width = 70, height = 20 })
  iv.watchButton:SetPoint("RIGHT", iv.linkButton, "LEFT", -4, 0)
  iv.watchButton:HookScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(self.tip, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  iv.watchButton:HookScript("OnLeave", function() GameTooltip:Hide() end)
  return header
end

local function buildStats(iv)
  local row = CreateFrame("Frame", nil, iv)
  row:SetHeight(STATS_H)
  row:SetPoint("TOPLEFT", iv.header, "BOTTOMLEFT", 0, -4)
  row:SetPoint("TOPRIGHT", iv.header, "BOTTOMRIGHT", 0, -4)
  Theme.Fill(row, C.panelAlt)
  Theme.Border(row, C.borderDim, 1)

  iv.stat = {}
  for _, def in ipairs(STATS) do
    local cell = CreateFrame("Frame", nil, row)
    cell:SetSize(100, STAT_ROW_H)
    local label = Theme.Text(cell, "dim", "LEFT")
    label:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, -5)
    label:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
    label:SetText(def[2])
    local value = Theme.Text(cell, "normal", "LEFT")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    value:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
    iv.stat[def[1]] = { cell = cell, label = label, value = value, column = def[3], line = def[4] }
  end

  row:SetScript("OnSizeChanged", function(_, width)
    local cellWidth = math.floor((width - 2) / 3)
    for _, stat in pairs(iv.stat) do
      stat.cell:ClearAllPoints()
      stat.cell:SetPoint("TOPLEFT", row, "TOPLEFT", 1 + (stat.column - 1) * cellWidth, -1 - stat.line * STAT_ROW_H)
      stat.cell:SetSize(cellWidth, STAT_ROW_H)
    end
  end)
  return row
end

local tabUpdaters = {
  history = function(iv, id) A.UI.TabHistory.Update(iv.history, id) end,
  activity = function(iv, id) A.UI.TabActivity.Update(iv.activity, id) end,
  owned = function(iv, id) A.UI.TabOwned.Update(iv.owned, id) end,
}

local function showTab(iv, key)
  for k, view in pairs({ history = iv.history, activity = iv.activity, owned = iv.owned }) do
    view:SetShown(k == key)
  end
  local id = A.Controller.state.selected
  if id and tabUpdaters[key] then tabUpdaters[key](iv, id) end
end

local WATCH_TIP = "Add this item to your Watchlist on the Overview, where you can see how its price "
  .. "moves from today. Almanac also keeps its price history past Auctionator's 21 days."
local UNWATCH_TIP = "Stop watching this item and take it off your Watchlist."

function Detail.UpdateWatch()
  local win = Detail.win
  local id = A.Controller.state.selected
  if not (win and id) then return end
  local watching = A.History.IsWatched(id)
  local button = win.itemView.watchButton
  button:SetLabel(watching and "Watching" or "Watch")
  button:SetActive(watching)
  button.tip = watching and UNWATCH_TIP or WATCH_TIP
end

-- Watch or stop watching an item (the selected one when id is nil). It says so in chat as well as
-- on the button and the stars, since the Watchlist itself may be on the other page.
function Detail.ToggleWatch(id)
  local Ct = A.Controller
  id = id or Ct.state.selected
  if not id then return end
  local link = A.UI.Results.ItemLink(id)
  if A.History.IsWatched(id) then
    A.History.Watch(id, false)
    A.Print("Stopped watching " .. link .. ".")
  else
    A.History.Watch(id, true, { price = Ct.PriceOf(id), day = Ct.Today(), time = (time and time()) or nil })
    A.Print("Watching " .. link .. ". It is on the Watchlist on your Overview now, and Almanac keeps its "
      .. "price history past Auctionator's 21 days.")
  end
  Detail.UpdateWatch()
end

local STAR_TIPS = {
  off = "Watch this item: add it to the Watchlist on your Overview.",
  on = "Watching. Click to stop watching and take it off your Watchlist.",
}

-- The star beside an item in a list: filled while the item is watched, and a click watches or stops
-- watching it. star:SetItem(id) points it at a row's item (nil hides it).
function Detail.WatchStar(parent, size)
  local star = W.Star(parent, size or 14, function(self)
    if not self.itemID then return end
    Detail.ToggleWatch(self.itemID)
    self:SetOn(A.History.IsWatched(self.itemID))
  end)
  star.tips = STAR_TIPS
  function star:SetItem(id)
    self.itemID = id
    self:SetOn(id ~= nil and A.History.IsWatched(id))
    self:SetShown(id ~= nil)
  end
  return star
end

-- "44 / 5": listed in the latest scan, and how many of those at the lowest price; a dash for what is not known. A
-- listed count that is only Auctionator's count for the day (the most it saw) is dimmed.
function Detail.DepthText(id)
  local onAH, atLow, fromScan = A.Controller.Depth(id)
  if not onAH and not atLow then return DASH end
  local listed = onAH and Fmt.Count(onAH) or DASH
  if onAH and not fromScan then listed = Theme.Colorize(listed, Theme.hex.dim) end
  return listed .. " / " .. (atLow and Fmt.Count(atLow) or DASH)
end

local function fillHeaderAndStats(iv, id)
  local info = A.Items.Ensure(id)
  iv.icon:SetTexture(info.icon or QUESTION_MARK)
  local listed = not info.name and A.Overview.TopEntry(id)     -- not named by the client yet, but on the Top 500
  if info.name then
    iv.name:SetText(Fmt.ColorName(info.name, info.quality))
  elseif listed then
    iv.name:SetText(Fmt.ColorName(listed.name, listed.q))
  else
    iv.name:SetText(Theme.Colorize("Item " .. id, Theme.hex.dim))
  end
  iv.subtitle:SetText(Detail.Subtitle(info))

  local s = A.Controller.Summary(id)
  if not s then
    for _, def in ipairs(STATS) do setStat(iv, def[1], DASH) end
    iv.stat.average.label:SetText("Average")
  else
    setStat(iv, "lowest", Fmt.Money(s.last))
    setStat(iv, "average", s.avg and Fmt.Money(math.floor(s.avg)) or DASH)
    iv.stat.average.label:SetText(s.nDays > 0 and ("Average (" .. s.nDays .. "d)") or "Average")
    setStat(iv, "change", Fmt.Change(s.change7d))
    if s.low and s.high then
      setStat(iv, "range", Fmt.Money(s.low, { short = true }) .. "–" .. Fmt.Money(s.high, { short = true }))
    else
      setStat(iv, "range", DASH)
    end
    setStat(iv, "quantity", Detail.DepthText(id))
    local sell = info.sell
    setStat(iv, "vendor", (sell and sell > 0) and Fmt.Money(sell) or DASH)
  end
  if not s then setStat(iv, "vendor", (info.sell and info.sell > 0) and Fmt.Money(info.sell) or DASH) end
  Detail.UpdateWatch()
end

-- reason == "inventory" means only ownership changed, so the price views are left alone; "depth" means only the
-- market counts changed, which live in the stats row.
function Detail.Update(reason)
  local win = Detail.win
  if not win then return end
  if not win:IsVisible() then
    dirty = true
    return
  end
  dirty = false
  local id = A.Controller.state.selected
  if not id then
    win.itemView:Hide()
    return
  end
  win.itemView:Show()
  if reason == "inventory" and win.itemView.tabs.selected ~= "owned" then return end
  if reason == "depth" then
    setStat(win.itemView, "quantity", Detail.DepthText(id))
    return
  end
  fillHeaderAndStats(win.itemView, id)
  showTab(win.itemView, win.itemView.tabs.selected or "history")
end

A.UI.Window.AddBuilder(function(win)
  Detail.win = win
  local panel = win.detailPanel

  local iv = CreateFrame("Frame", nil, panel)
  iv:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
  iv:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)
  iv:Hide()
  win.itemView = iv

  iv.header = buildHeader(iv)
  iv.statsRow = buildStats(iv)

  iv.tabs = W.Tabs(iv, TABS, function(key) showTab(iv, key) end)
  iv.tabs:SetPoint("TOPLEFT", iv.statsRow, "BOTTOMLEFT", 0, -6)
  iv.tabs:SetPoint("TOPRIGHT", iv.statsRow, "BOTTOMRIGHT", 0, -6)

  iv.content = CreateFrame("Frame", nil, iv)
  iv.content:SetPoint("TOPLEFT", iv.tabs, "BOTTOMLEFT", 0, -4)
  iv.content:SetPoint("BOTTOMRIGHT", iv, "BOTTOMRIGHT", -6, 6)

  iv.history = A.UI.TabHistory.Build(iv.content)
  iv.activity = A.UI.TabActivity.Build(iv.content)
  iv.owned = A.UI.TabOwned.Build(iv.content)
  iv.tabs:Select("history")

  for _, event in ipairs({ "SELECTION_CHANGED", "DATA_RELOADED", "LEDGER_UPDATED", "WATCH_CHANGED" }) do
    A.Bus.On(event, function() Detail.Update() end)
  end
  A.Bus.On("DEPTH_UPDATED", function() Detail.Update("depth") end)
  A.Bus.On("INVENTORY_UPDATED", function() Detail.Update("inventory") end)
  -- Names arrive in many small batches while the item cache fills; refresh at most every 1.5s.
  local namesQueued = false
  A.Bus.On("ITEM_NAMES_UPDATED", function()
    if namesQueued then return end
    namesQueued = true
    A.After(1.5, function()
      namesQueued = false
      Detail.Update()
    end)
  end)
  A.Bus.On("WINDOW_SHOWN", function()
    if dirty then Detail.Update() end
  end)
  Detail.Update()
end)
