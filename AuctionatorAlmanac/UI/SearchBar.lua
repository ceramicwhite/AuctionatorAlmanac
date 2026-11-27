local ADDON, A = ...

-- The search row: a search box that fills the row, and the filters to its right.
-- Quality, how recently the price was seen, price range, and whether it moved.
local Theme = A.UI.Theme
local W = A.UI.Widgets
local SearchBar = {}
A.UI.SearchBar = SearchBar

local GAP = 8

local QUALITY = {
  { label = "Any" },
  { value = 1, label = "Common" },
  { value = 2, label = "Uncommon" },
  { value = 3, label = "Rare" },
  { value = 4, label = "Epic" },
  { value = 5, label = "Legendary" },
}

local RECENT = {
  { label = "Any" },
  { value = 0, label = "Today" },
  { value = 3, label = "3 days" },
  { value = 7, label = "7 days" },
}

-- Price ranges in copper; the key lets the widget and the controller stay in step.
local PRICE = {
  { label = "Any" },
  { value = "lt1g", label = "< 1g" },
  { value = "1g-10g", label = "1g - 10g" },
  { value = "10g-100g", label = "10g - 100g" },
  { value = "gt100g", label = "> 100g" },
}
local PRICE_BOUNDS = {
  lt1g = { nil, 9999 }, ["1g-10g"] = { 10000, 99999 }, ["10g-100g"] = { 100000, 999999 }, gt100g = { 1000000, nil },
}

local MOVED = {
  { label = "Any" },
  { value = "up", label = "Rose" },
  { value = "down", label = "Fell" },
}

-- Push the controller's state into the widgets (after a reload or when shown).
function SearchBar.Sync()
  local win = SearchBar.win
  if not win then return end
  local st = A.Controller.state
  if win.searchBox:GetText() ~= st.text then win.searchBox:SetText(st.text) end
  win.qualityCycle:SetValue(st.quality)
  win.recentCycle:SetValue(st.recent)
  win.priceCycle:SetValue(st.priceKey)
  win.movedCycle:SetValue(st.moved)
  win.ownedCheck:Refresh()
end

-- Anything the player changes here is about the item list, so a hidden list comes back.
local function showList() A.UI.Window.ExpandResults() end

local SEARCH_ROWS = 12      -- how many searches the menu in the search box shows

-- Search for `text` as if it had been typed, and remember it.
function SearchBar.Apply(text)
  local win = SearchBar.win
  if not win then return end
  showList()
  win.searchBox:SetText(text)
  A.Recents.Add(text)
end

-- The searches menu: the newest searches, from here and from Auctionator, to pick one.
function SearchBar.OpenSearches()
  local win = SearchBar.win
  if not win then return end
  A.Recents.Sync()
  local items = {}
  for i, text in ipairs(A.Recents.List()) do
    if i > SEARCH_ROWS then break end
    items[i] = text
  end
  win.searchesList:Open(items, SearchBar.Apply)
end

A.UI.Window.AddBuilder(function(win)
  SearchBar.win = win
  local row = win.searchRow
  local Ct = A.Controller

  win.ownedCheck = W.Checkbox(row, "Owned only", function() return Ct.state.ownedOnly end, function(v) showList(); Ct.SetOwnedOnly(v) end, { width = 98 })
  win.ownedCheck:SetPoint("RIGHT", row, "RIGHT", 0, 0)

  win.movedCycle = W.Cycle(row, "Moved", MOVED, function(v) showList(); Ct.SetMoved(v) end, { width = 104, height = 24 })
  win.movedCycle:SetPoint("RIGHT", win.ownedCheck, "LEFT", -GAP, 0)

  win.priceCycle = W.Cycle(row, "Price", PRICE, function(v)
    showList()
    local bounds = v and PRICE_BOUNDS[v]
    Ct.SetPriceRange(bounds and bounds[1], bounds and bounds[2], v)
  end, { width = 126, height = 24 })
  win.priceCycle:SetPoint("RIGHT", win.movedCycle, "LEFT", -GAP, 0)

  win.recentCycle = W.Cycle(row, "Seen", RECENT, function(v) showList(); Ct.SetRecent(v) end, { width = 108, height = 24 })
  win.recentCycle:SetPoint("RIGHT", win.priceCycle, "LEFT", -GAP, 0)

  win.qualityCycle = W.Cycle(row, "Quality", QUALITY, function(v) showList(); Ct.SetQuality(v) end, { width = 138, height = 24 })
  win.qualityCycle:SetPoint("RIGHT", win.recentCycle, "LEFT", -GAP, 0)

  -- Searches are remembered when the player is done with the box, and the box completes what is typed from them, as
  -- Auctionator's does. The typed text, not the completion, is what filters the list until the completion is accepted.
  win.searchBox = W.EditBox(row, "Search items by name or ID...", function(text, userInput)
    if userInput then showList() end
    if text ~= Ct.state.text then Ct.SetSearchText(text) end
  end, {
    height = 26,
    reserveRight = 20,
    suggest = A.Recents.Suggest,
    onCommit = A.Recents.Add,
    onFocus = A.Recents.Sync,
  })
  win.searchBox:SetPoint("LEFT", row, "LEFT", 0, 0)
  win.searchBox:SetPoint("RIGHT", win.qualityCycle, "LEFT", -GAP - 2, 0)

  -- A small button in the box, beside its clear button, opens the list of recent searches.
  win.searchesButton = W.Button(win.searchBox, "v", function() SearchBar.OpenSearches() end, { width = 18, height = 18, plainText = true })
  win.searchesButton:SetPoint("RIGHT", win.searchBox, "RIGHT", -24, 0)
  win.searchesList = W.PopupList(win.searchBox, { maxRows = SEARCH_ROWS, empty = "No searches yet." })

  A.Bus.On("WINDOW_HIDDEN", function() win.searchesList:Close() end)

  A.Bus.On("WINDOW_SHOWN", SearchBar.Sync)
  SearchBar.Sync()
end)
