local ADDON, A = ...

-- /almanac debug: which client APIs this build of the game provides, what
-- Auctionator exposed, and how much Almanac has stored. The Forever client is
-- young and its API set is still moving, so this is the first thing to look at
-- when something does not show up.
local Debug = {}
A.Debug = Debug

-- Each entry is a label and the alternatives that satisfy it ("A or B").
local APIS = {
  { "C_Item.GetItemInfo", { "C_Item.GetItemInfo" } },
  { "C_Item.GetItemInfoInstant", { "C_Item.GetItemInfoInstant" } },
  { "C_Item.RequestLoadItemDataByID", { "C_Item.RequestLoadItemDataByID" } },
  { "C_Item.GetItemClassInfo", { "C_Item.GetItemClassInfo", "GetItemClassInfo" } },
  { "C_Item.GetItemSubClassInfo", { "C_Item.GetItemSubClassInfo", "GetItemSubClassInfo" } },
  { "C_Container.GetContainerNumSlots", { "C_Container.GetContainerNumSlots" } },
  { "C_Container.GetContainerItemInfo", { "C_Container.GetContainerItemInfo" } },
  { "GetInventoryItemID", { "GetInventoryItemID" } },
  { "Mail: inbox count", { "C_Mail.GetInboxNumItems", "GetInboxNumItems" } },
  { "Mail: header info", { "C_Mail.GetInboxHeaderInfo", "GetInboxHeaderInfo" } },
  { "Mail: invoice info", { "C_Mail.GetInboxInvoiceInfo", "GetInboxInvoiceInfo" } },
  { "Mail: attachments", { "C_Mail.GetInboxItem", "GetInboxItem" } },
  { "C_AuctionHouse.GetNumOwnedAuctions", { "C_AuctionHouse.GetNumOwnedAuctions" } },
  { "C_AuctionHouse.GetOwnedAuctionInfo", { "C_AuctionHouse.GetOwnedAuctionInfo" } },
  { "C_AuctionHouse.GetAuctionInfoByID", { "C_AuctionHouse.GetAuctionInfoByID" } },
  { "C_AuctionHouse.StartCommoditiesPurchase", { "C_AuctionHouse.StartCommoditiesPurchase" } },
  { "C_AuctionHouse.PlaceBid", { "C_AuctionHouse.PlaceBid" } },
  { "hooksecurefunc", { "hooksecurefunc" } },
  { "TooltipDataProcessor.AddTooltipPostCall", { "TooltipDataProcessor.AddTooltipPostCall" } },
  { "Enum.BagIndex", { "Enum.BagIndex" } },
  { "Enum.BagIndex.AccountBankTab_1 (warband bank)", { "Enum.BagIndex.AccountBankTab_1" } },
  { "Guild bank", { "GetGuildBankItemLink" } },
  { "Settings.RegisterCanvasLayoutCategory", { "Settings.RegisterCanvasLayoutCategory" } },
  { "C_Timer.After", { "C_Timer.After" } },
}

local function resolve(path)
  local value = A.env
  for part in path:gmatch("[^.]+") do
    if type(value) ~= "table" then return nil end
    value = value[part]
  end
  return value
end

function Debug.Lines()
  local lines = {}
  local function add(text) lines[#lines + 1] = text end

  local getMeta = (A.env.C_AddOns and A.env.C_AddOns.GetAddOnMetadata) or A.env.GetAddOnMetadata
  local version = getMeta and getMeta(ADDON, "Version") or "?"
  add("Auctionator Almanac " .. tostring(version))
  if A.env.GetBuildInfo then
    local gameVersion, build, _, toc = A.env.GetBuildInfo()
    add("Game " .. tostring(gameVersion) .. " build " .. tostring(build) .. " interface " .. tostring(toc))
  end

  add("— Client APIs —")
  for _, def in ipairs(APIS) do
    local ok = false
    for _, path in ipairs(def[2]) do
      if resolve(path) ~= nil then ok = true; break end
    end
    add(def[1] .. ": " .. (ok and "ok" or "MISSING"))
  end

  add("— Auctionator —")
  add("Auctionator: " .. (A.Adapter.IsReady() and "ready" or "NOT ready"))
  add("Realm: " .. tostring(A.Adapter.Realm()))
  add("Items priced: " .. A.Controller.pricedCount)
  add("History window: " .. A.Adapter.HistoryDays() .. " days")
  local scan = A.Adapter.LastScan(A.Controller.newestDay)
  add("Last scan: " .. (scan.time and (A.Format.DateTime(scan.time) .. " (" .. tostring(scan.kind) .. ")") or "none"))

  add("— Almanac data —")
  local have, total = A.Items.Progress()
  add("Item names cached: " .. have .. " / " .. total)
  add("Ledger entries: " .. #A.db.ledger.entries)
  local chars = 0
  for _ in pairs(A.db.chars) do chars = chars + 1 end
  add("Characters tracked: " .. chars)
  local ext = 0
  for _ in pairs(A.db.history.items) do ext = ext + 1 end
  add("Items with long-term history: " .. ext)
  add("Items remembered for New finds: " .. A.Discovery.Count())
  return lines
end

function Debug.Print()
  for _, line in ipairs(Debug.Lines()) do A.Print(line) end
end
