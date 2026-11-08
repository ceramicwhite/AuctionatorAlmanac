local ADDON, A = ...

-- Glue between the game's events and the ledger / inventory modules. Every
-- client API is feature-detected and every handler tolerates a missing one.
local Tracker = {}
A.Tracker = Tracker

local MAX_INVOICE_ATTEMPTS = 3
local state = { bankOpen = false, mailOpen = false, mailAttempts = 0, pending = nil }
local scheduled = {}

-- Coalesce bursts of events into one call.
local function later(key, seconds, fn)
  if scheduled[key] then return end
  scheduled[key] = true
  A.After(seconds, function()
    scheduled[key] = nil
    fn()
  end)
end

local function now()
  local t = A.env.time
  return t and t() or 0
end

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------
function Tracker.Identity()
  local e = A.env
  local name = e.UnitName and e.UnitName("player")
  local realm = e.GetRealmName and e.GetRealmName()
  if not name or not realm then return nil end
  local class
  if e.UnitClass then
    local _, token = e.UnitClass("player")
    class = token
  end
  local faction = e.UnitFactionGroup and e.UnitFactionGroup("player")
  return { name = name, realm = realm, class = class, faction = faction }
end

local function store(loc, counts)
  if not counts then return false end
  local identity = Tracker.Identity()
  if not identity then return false end
  local rec = A.Inventory.EnsureChar(identity)
  A.Inventory.SetLocation(rec.key, loc, counts, now())
  return true
end

-- ---------------------------------------------------------------------------
-- Inventory snapshots
-- ---------------------------------------------------------------------------
local function scanBank()
  local env = A.env
  local changed = store("bank", A.Inventory.ScanBank(env))
  local hasWarband = env.Enum and env.Enum.BagIndex and env.Enum.BagIndex.AccountBankTab_1 ~= nil
  if hasWarband then
    local counts = A.Inventory.ScanWarband(env)
    if counts then
      A.Inventory.SetWarband(counts, now())
      changed = true
    end
  end
  return changed
end

function Tracker.RefreshBags()
  local env = A.env
  local changed = store("bags", A.Inventory.ScanBags(env))
  changed = store("equipped", A.Inventory.ScanEquipped(env)) or changed
  if state.bankOpen then changed = scanBank() or changed end
  if changed then A.Bus.Fire("INVENTORY_UPDATED") end
end

function Tracker.QueueBags(seconds)
  later("bags", seconds or 0.5, Tracker.RefreshBags)
end

local function scanOwnedAuctions()
  if store("auctions", A.Inventory.ScanOwnedAuctions(A.env)) then A.Bus.Fire("INVENTORY_UPDATED") end
end

local function scanGuildBank()
  local env = A.env
  local guildName = env.GetGuildInfo and env.GetGuildInfo("player")
  if not guildName or not env.GetCurrentGuildBankTab then return end
  local tab = env.GetCurrentGuildBankTab()
  local counts = A.Inventory.ScanGuildBank(tab, env)
  if not counts then return end
  local identity = Tracker.Identity()
  A.Inventory.SetGuildTab(guildName .. "-" .. (identity and identity.realm or "?"), guildName, tab, counts, now())
  A.Bus.Fire("INVENTORY_UPDATED")
end

-- ---------------------------------------------------------------------------
-- Mailbox: sales, purchases, expiries, cancellations, attachments
-- ---------------------------------------------------------------------------
local function mailApi()
  local env = A.env
  local C = env.C_Mail
  return (C and C.GetInboxNumItems) or env.GetInboxNumItems,
         (C and C.GetInboxHeaderInfo) or env.GetInboxHeaderInfo,
         (C and C.GetInboxInvoiceInfo) or env.GetInboxInvoiceInfo,
         (C and C.GetInboxText) or env.GetInboxText
end

-- Returns changed, waitingForInvoice for one inbox mail.
local function processMail(i, getHeader, getInvoice, getText, identity)
  local _, _, _, subject, money, _, daysLeft = getHeader(i)
  local kind = A.Ledger.ClassifySubject(subject)
  if not kind then return false, false end

  local invoice
  if getInvoice and (kind == "sold" or kind == "bought") then
    -- Some clients only load an invoice once the mail's text has been requested
    -- (the same thing that happens when the player opens the mail), so the
    -- retries do that; the first pass leaves the mail's read state alone.
    if state.mailAttempts >= 1 and getText then pcall(getText, i) end
    local ok, t, itemName, party, bid, buyout, deposit, consignment, _, _, _, count = pcall(getInvoice, i)
    if ok and t then
      invoice = { type = t, itemName = itemName, party = party, bid = bid, buyout = buyout,
                  deposit = deposit, consignment = consignment, count = count }
    else
      -- The API exists but has nothing yet: wait for it rather than record a guess
      -- that a later, exact record of the same sale would duplicate.
      return false, true
    end
  end

  local entry = A.Ledger.FromMail({
    subject = subject, invoice = invoice, money = money, daysLeft = daysLeft, now = now(),
    attachments = A.Inventory.MailAttachments(A.env, i),
    char = identity and identity.name, realm = identity and identity.realm,
    resolveName = A.Items.IDByName,
  })
  if not entry then return false, false end
  local _, status = A.Ledger.Add(entry)
  return status == "added" or status == "confirmed", false
end

function Tracker.ScanMailbox()
  if not state.mailOpen then return end
  local getNum, getHeader, getInvoice, getText = mailApi()
  if not (getNum and getHeader) then return end

  local identity = Tracker.Identity()
  local changed, waiting = false, false
  for i = 1, (getNum() or 0) do
    local ok, didChange, isWaiting = pcall(processMail, i, getHeader, getInvoice, getText, identity)
    if ok then
      changed = changed or didChange
      waiting = waiting or isWaiting
    end
  end

  if store("mail", A.Inventory.ScanMail(A.env)) then A.Bus.Fire("INVENTORY_UPDATED") end
  if changed then A.Bus.Fire("LEDGER_UPDATED") end

  if waiting and state.mailAttempts < MAX_INVOICE_ATTEMPTS then
    state.mailAttempts = state.mailAttempts + 1
    later("mail", 1, Tracker.ScanMailbox)
  end
end

-- ---------------------------------------------------------------------------
-- Auction House purchases
-- ---------------------------------------------------------------------------
local function recordPurchase(itemID, qty, total)
  local identity = Tracker.Identity()
  local _, status = A.Ledger.Add({
    kind = "bought", itemID = itemID, qty = qty, total = total, time = now(), source = "ah",
    approx = (total == nil) or nil,
    char = identity and identity.name, realm = identity and identity.realm,
  })
  if status == "added" then A.Bus.Fire("LEDGER_UPDATED") end
end

function Tracker.OnCommodityStart(itemID, quantity)
  state.pending = { itemID = itemID, qty = quantity }
end

function Tracker.OnCommodityPrice(unitPrice, totalPrice)
  if state.pending then
    state.pending.unit, state.pending.total = unitPrice, totalPrice
  end
end

function Tracker.OnCommoditySucceeded()
  local p = state.pending
  state.pending = nil
  if p and p.itemID and p.qty then recordPurchase(p.itemID, p.qty, p.total) end
end

function Tracker.OnCommodityFailed()
  state.pending = nil
end

-- A buyout of a single (non-commodity) item. Plain bids are not purchases yet.
function Tracker.OnPlaceBid(auctionID, bidAmount)
  local AH = A.env.C_AuctionHouse
  if not (AH and AH.GetAuctionInfoByID) then return end
  local ok, info = pcall(AH.GetAuctionInfoByID, auctionID)
  if not ok or type(info) ~= "table" then return end
  local buyout = info.buyoutAmount
  local itemID = info.itemKey and info.itemKey.itemID
  if itemID and buyout and buyout > 0 and bidAmount and bidAmount >= buyout then
    recordPurchase(itemID, info.quantity or 1, buyout)
  end
end

local function installHooks()
  local AH, hook = A.env.C_AuctionHouse, A.env.hooksecurefunc
  if not (AH and hook) then return end
  if type(AH.StartCommoditiesPurchase) == "function" then
    pcall(hook, AH, "StartCommoditiesPurchase", function(itemID, quantity)
      pcall(Tracker.OnCommodityStart, itemID, quantity)
    end)
  end
  if type(AH.PlaceBid) == "function" then
    pcall(hook, AH, "PlaceBid", function(auctionID, bidAmount)
      pcall(Tracker.OnPlaceBid, auctionID, bidAmount)
    end)
  end
end

-- ---------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------
function Tracker.Start()
  local on = A.RegisterEvent

  on("PLAYER_ENTERING_WORLD", function() Tracker.QueueBags(3) end)
  on("BAG_UPDATE_DELAYED", function() Tracker.QueueBags() end)
  on("PLAYER_EQUIPMENT_CHANGED", function() Tracker.QueueBags() end)
  on("PLAYERBANKSLOTS_CHANGED", function() Tracker.QueueBags() end)
  on("PLAYER_LOGOUT", function() Tracker.RefreshBags() end)

  on("BANKFRAME_OPENED", function()
    state.bankOpen = true
    Tracker.QueueBags(0.3)
  end)
  on("BANKFRAME_CLOSED", function() state.bankOpen = false end)

  on("MAIL_SHOW", function()
    state.mailOpen, state.mailAttempts = true, 0
    later("mail", 0.3, Tracker.ScanMailbox)
  end)
  on("MAIL_INBOX_UPDATE", function() later("mail", 0.3, Tracker.ScanMailbox) end)
  on("MAIL_CLOSED", function() state.mailOpen = false end)

  on("AUCTION_HOUSE_CLOSED", function() A.Bus.Fire("AH_CLOSED") end)
  on("OWNED_AUCTIONS_UPDATED", function() later("owned", 0.3, scanOwnedAuctions) end)
  on("COMMODITY_PRICE_UPDATED", function(_, unit, total) Tracker.OnCommodityPrice(unit, total) end)
  on("COMMODITY_PURCHASE_SUCCEEDED", function() Tracker.OnCommoditySucceeded() end)
  on("COMMODITY_PURCHASE_FAILED", function() Tracker.OnCommodityFailed() end)

  on("GUILDBANKBAGSLOTS_CHANGED", function() later("guild", 0.5, scanGuildBank) end)

  installHooks()

  A.Bus.On("ITEM_NAMES_UPDATED", function()
    if A.Ledger.ResolvePending(A.Items.IDByName) > 0 then A.Bus.Fire("LEDGER_UPDATED") end
  end)
end
