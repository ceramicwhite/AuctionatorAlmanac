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

  win.searchBox = W.EditBox(row, "Search items by name or ID...", function(text, userInput)
    if userInput then showList() end
    if text ~= Ct.state.text then Ct.SetSearchText(text) end
  end, { height = 26 })
  win.searchBox:SetPoint("LEFT", row, "LEFT", 0, 0)
  win.searchBox:SetPoint("RIGHT", win.qualityCycle, "LEFT", -GAP - 2, 0)

  A.Bus.On("WINDOW_SHOWN", SearchBar.Sync)
  SearchBar.Sync()
end)
