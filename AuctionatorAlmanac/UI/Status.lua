local ADDON, A = ...

-- The strip under the title bar: how fresh Auctionator's data is, how much of it
-- there is, which realm it is for, and how far the item-name cache has got.
local Theme = A.UI.Theme
local Fmt = A.Format
local Status = {}
A.UI.Status = Status

local DOT = "   |cff6b5420·|r   "
local REFRESH_SECONDS = 15

local AGE_COLOR = {
  fresh = Theme.hex.good, ok = Theme.hex.bright, stale = Theme.hex.amber, old = Theme.hex.bad,
}

local function nowSeconds()
  return (time and time()) or 0
end

function Status.Text()
  local C = A.Controller
  if not C.ready then
    return Theme.Colorize("Waiting for Auctionator's saved prices...", Theme.hex.amber)
  end
  local parts = {}
  local scan = C.LastScan()
  if scan.time then
    local age = nowSeconds() - scan.time
    local label = Theme.Colorize(Fmt.Ago(age), AGE_COLOR[Fmt.Freshness(age)]) .. " ago"
    if scan.kind and scan.kind ~= "data" then label = label .. " (" .. scan.kind .. ")" end
    if scan.kind == "data" then label = label .. " (newest price data)" end
    parts[#parts + 1] = "Last scan  " .. label
  else
    parts[#parts + 1] = Theme.Colorize("No scan recorded yet", Theme.hex.amber)
  end
  parts[#parts + 1] = Fmt.Count(C.pricedCount) .. " items priced"
  local realm = C.Realm()
  if realm then parts[#parts + 1] = realm end
  parts[#parts + 1] = "History " .. A.Adapter.HistoryDays() .. " days"
  return table.concat(parts, DOT)
end

function Status.RightText()
  local have, total = A.Items.Progress()
  if total > 0 and have < total then
    return Theme.Colorize("Item names " .. Fmt.Count(have) .. " / " .. Fmt.Count(total), Theme.hex.dim)
  end
  return ""
end

local function showTooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
  GameTooltip:AddLine("Auctionator price data", 1, 0.82, 0)
  local scan = A.Controller.LastScan()
  if scan.full then GameTooltip:AddDoubleLine("Last full scan", Fmt.DateTime(scan.full), 0.8, 0.8, 0.8, 1, 1, 1) end
  if scan.browse then GameTooltip:AddDoubleLine("Last browse scan", Fmt.DateTime(scan.browse), 0.8, 0.8, 0.8, 1, 1, 1) end
  if A.Controller.newestDay then
    GameTooltip:AddDoubleLine("Newest price day", Fmt.Date(A.Adapter.DayToTime(A.Controller.newestDay)), 0.8, 0.8, 0.8, 1, 1, 1)
  end
  GameTooltip:AddLine("Prices update when you scan at the Auction House.", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

A.UI.Window.AddBuilder(function(win)
  local bar = win.statusBar
  win.statusText = Theme.Text(bar, "small", "LEFT")
  win.statusText:SetPoint("LEFT", bar, "LEFT", 12, 0)
  win.statusRight = Theme.Text(bar, "small", "RIGHT")
  win.statusRight:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
  win.statusText:SetPoint("RIGHT", win.statusRight, "LEFT", -12, 0)

  local hover = CreateFrame("Button", nil, bar)
  hover:SetAllPoints(bar)
  hover:SetScript("OnEnter", showTooltip)
  hover:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local function update()
    win.statusText:SetText(Status.Text())
    win.statusRight:SetText(Status.RightText())
  end
  Status.Update = update

  local ticker = CreateFrame("Frame", nil, win)
  local elapsedTotal = 0
  ticker:SetScript("OnUpdate", function(_, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal >= REFRESH_SECONDS then
      elapsedTotal = 0
      update()
    end
  end)

  for _, event in ipairs({ "WINDOW_SHOWN", "DATA_UPDATED", "DATA_RELOADED", "ITEM_NAMES_UPDATED" }) do
    A.Bus.On(event, update)
  end
  update()
end)
