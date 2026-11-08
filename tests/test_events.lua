local H = require("harness")
local test = H.test

local NOW = 1800000000

-- Builds a fake client and boots the tracker against it.
local function boot(o)
  o = o or {}
  local timer = H.fakeTimer()
  local state = {
    now = NOW, mails = o.mails or {}, bags = o.bags or {}, worn = o.worn or {},
    owned = o.owned or {}, guildSlots = o.guildSlots or {},
  }
  local env = {
    time = function() return state.now end,
    C_Timer = timer,
    UnitName = function() return "Thornwick" end,
    GetRealmName = function() return "Whitemane" end,
    UnitClass = function() return "Warrior", "WARRIOR" end,
    UnitFactionGroup = function() return "Alliance" end,
    Enum = { BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5, Bank = -1, CharacterBankTab_1 = 6 },
             AuctionStatus = { Active = 0, Sold = 1 } },
    NUM_BAG_SLOTS = 4,
    C_Container = {
      GetContainerNumSlots = function(bag)
        local b = state.bags[bag]
        if not b then return 0 end
        local max = 0
        for slot in pairs(b) do if slot > max then max = slot end end
        return max
      end,
      GetContainerItemInfo = function(bag, slot)
        local e = state.bags[bag] and state.bags[bag][slot]
        if e then return { itemID = e[1], stackCount = e[2] } end
      end,
    },
    GetInventoryItemID = function(_, slot) return state.worn[slot] end,
    GetInboxNumItems = function() return #state.mails end,
    GetInboxHeaderInfo = function(i)
      local m = state.mails[i]
      return 1, 1, "Auction House", m.subject, m.money or 0, 0, m.daysLeft or 30, #(m.items or {}) > 0, false, false, false, false, false
    end,
    GetInboxItem = function(i, j)
      local it = (state.mails[i].items or {})[j]
      if it then return it.name, it.itemID, 1, it.count end
    end,
    C_AuctionHouse = {
      StartCommoditiesPurchase = function() end,
      PlaceBid = function() end,
      GetAuctionInfoByID = function(id) return state.auctionInfo and state.auctionInfo[id] end,
      GetNumOwnedAuctions = function() return #state.owned end,
      GetOwnedAuctionInfo = function(i) return state.owned[i] end,
    },
    hooksecurefunc = function(tbl, name, fn)
      local orig = tbl[name]
      tbl[name] = function(...) local r = orig(...); fn(...); return r end
    end,
    GetGuildInfo = function() return "Boss" end,
    GetCurrentGuildBankTab = function() return 2 end,
    GetGuildBankItemLink = function(tab, slot) return state.guildSlots[slot] and state.guildSlots[slot][1] end,
    GetGuildBankItemInfo = function(tab, slot) if state.guildSlots[slot] then return 1, state.guildSlots[slot][2] end end,
  }
  state.textRead = {}
  if o.invoiceNeedsText then
    env.GetInboxText = function(i) state.textRead[i] = true end
  end
  if not o.noInvoiceAPI then
    env.GetInboxInvoiceInfo = function(i)
      local inv = state.mails[i].invoice
      if o.invoiceNil or not inv then return nil end
      if o.invoiceNeedsText and not state.textRead[i] then return nil end
      return inv.type, inv.itemName, inv.party, inv.bid, inv.buyout, inv.deposit, inv.consignment, 0, 0, 0, inv.count
    end
  end
  if o.noContainerAPI then env.C_Container = nil end
  if o.noAuctionHouse then env.C_AuctionHouse = nil end

  local A = H.newA({ "Core/Init.lua", "Data/Items.lua", "Tracker/Ledger.lua", "Tracker/Inventory.lua", "Tracker/Events.lua" }, env)
  A.db = A.InitDB(nil)
  A.db.items[12359] = { "Thorium Bar", 2, 1, 7, 12 }
  A.db.items[19019] = { "Thunderfury", 5, 1, 2, 7 }
  A.Items.Init(A.db)
  A.Ledger.Init(A.db)
  A.Inventory.Init(A.db)
  local fired = { LEDGER_UPDATED = 0, INVENTORY_UPDATED = 0, AH_CLOSED = 0 }
  for name in pairs(fired) do A.Bus.On(name, function() fired[name] = fired[name] + 1 end) end
  A.Tracker.Start()
  return A, { state = state, timer = timer, fired = fired, env = env }
end

local function soldMail()
  return { subject = "Auction successful: Thorium Bar", money = 10650, daysLeft = 29.5,
           invoice = { type = "seller", itemName = "Thorium Bar", party = "Buyer", bid = 11000, buyout = 12000, deposit = 200, consignment = 550, count = 20 } }
end

local function wonMail(daysLeft)
  return { subject = "Auction won: Thorium Bar", daysLeft = daysLeft or 30,
           items = { { name = "Thorium Bar", itemID = 12359, count = 20 } },
           invoice = { type = "buyer", itemName = "Thorium Bar", party = "Seller", bid = 219000, buyout = 219000, count = 20 } }
end

test("Identity reads the current character", function()
  local A = boot()
  H.eq(A.Tracker.Identity(), { name = "Thornwick", realm = "Whitemane", class = "WARRIOR", faction = "Alliance" })
end)

test("opening the mailbox records a sale once, however often the inbox updates", function()
  local A, ctx = boot({ mails = { soldMail() } })
  A.FireEvent("MAIL_SHOW")
  ctx.timer.flush()
  local rows = A.Ledger.ForItem(12359)
  H.eq(#rows, 1)
  H.eq(rows[1].kind, "sold")
  H.eq(rows[1].total, 11000)
  H.eq(rows[1].char, "Thornwick")
  H.eq(rows[1].realm, "Whitemane")
  H.eq(ctx.fired.LEDGER_UPDATED, 1)
  A.FireEvent("MAIL_INBOX_UPDATE")
  ctx.timer.flush()
  H.eq(#A.Ledger.ForItem(12359), 1)
  H.eq(ctx.fired.LEDGER_UPDATED, 1, "no change, no event")
end)

test("the mailbox snapshot of attachments is saved as the mail location", function()
  local A, ctx = boot({ mails = { wonMail() } })
  A.FireEvent("MAIL_SHOW")
  ctx.timer.flush()
  local owned = A.Inventory.Owned(12359)
  H.eq(owned.total, 20)
  H.eq(owned.rows[1].loc, "mail")
end)

test("an invoice that never loads records nothing, rather than a guess that would double count later", function()
  local A, ctx = boot({ mails = { soldMail() }, invoiceNil = true })
  A.FireEvent("MAIL_SHOW")
  ctx.timer.flush()
  H.eq(#A.Ledger.Recent(10), 0)
end)

test("when the invoice only loads after the mail text is requested, the retry requests it", function()
  local A, ctx = boot({ mails = { soldMail() }, invoiceNeedsText = true })
  A.FireEvent("MAIL_SHOW")
  ctx.timer.flush()
  local rows = A.Ledger.ForItem(12359)
  H.eq(#rows, 1)
  H.eq(rows[1].total, 11000)
  H.eq(rows[1].approx, nil)
end)

test("without any invoice API a sale is recorded approximately from the mail money", function()
  local A, ctx = boot({ mails = { soldMail() }, noInvoiceAPI = true })
  A.FireEvent("MAIL_SHOW")
  ctx.timer.flush()
  local rows = A.Ledger.ForItem(12359)
  H.eq(#rows, 1)
  H.eq(rows[1].approx, true)
  H.eq(rows[1].total, 10650)
end)

test("expired auction mails are recorded from the returned items", function()
  local A, ctx = boot({ mails = { { subject = "Auction expired: Thorium Bar", daysLeft = 29, items = { { name = "Thorium Bar", itemID = 12359, count = 20 } } } } })
  A.FireEvent("MAIL_SHOW")
  ctx.timer.flush()
  H.eq(A.Ledger.ForItem(12359)[1].kind, "expired")
end)

test("unrelated mail is ignored", function()
  local A, ctx = boot({ mails = { { subject = "Hello from a friend", money = 100 } } })
  A.FireEvent("MAIL_SHOW")
  ctx.timer.flush()
  H.eq(#A.Ledger.Recent(10), 0)
end)

test("a sale whose item name is not known yet is resolved when names load", function()
  local mail = soldMail()
  mail.subject, mail.invoice.itemName = "Auction successful: Mystery Ore", "Mystery Ore"
  local A, ctx = boot({ mails = { mail } })
  A.FireEvent("MAIL_SHOW")
  ctx.timer.flush()
  H.eq(#A.Ledger.Recent(10), 1)
  H.eq(A.Ledger.Recent(1)[1].itemID, nil)
  A.db.items[55555] = { "Mystery Ore", 1, 1, 7, 7 }
  A.Items.Init(A.db)
  local before = ctx.fired.LEDGER_UPDATED
  A.Bus.Fire("ITEM_NAMES_UPDATED")
  H.eq(#A.Ledger.ForItem(55555), 1)
  H.eq(ctx.fired.LEDGER_UPDATED, before + 1)
end)

test("bag changes coalesce into one scan of bags and equipped gear", function()
  local A, ctx = boot({ bags = { [0] = { [1] = { 12359, 20 } } }, worn = { [1] = 16000 } })
  A.FireEvent("BAG_UPDATE_DELAYED"); A.FireEvent("BAG_UPDATE_DELAYED"); A.FireEvent("PLAYER_EQUIPMENT_CHANGED")
  ctx.timer.flush()
  H.eq(A.Inventory.Owned(12359).rows[1].loc, "bags")
  H.eq(A.Inventory.Owned(16000).rows[1].loc, "equipped")
  H.eq(ctx.fired.INVENTORY_UPDATED, 1)
end)

test("logout scans immediately", function()
  local A = boot({ bags = { [0] = { [1] = { 12359, 3 } } } })
  A.FireEvent("PLAYER_LOGOUT")
  H.eq(A.Inventory.Owned(12359).total, 3)
end)

test("the bank is only read while the bank window is open", function()
  local A, ctx = boot({ bags = { [-1] = { [1] = { 12363, 1 } } } })
  A.FireEvent("BAG_UPDATE_DELAYED"); ctx.timer.flush()
  H.eq(A.Inventory.Owned(12363).total, 0, "bank closed: not read")
  A.FireEvent("BANKFRAME_OPENED"); ctx.timer.flush()
  H.eq(A.Inventory.Owned(12363).rows[1].loc, "bank")
  ctx.state.bags[-1] = { [1] = { 12363, 5 } }
  A.FireEvent("BAG_UPDATE_DELAYED"); ctx.timer.flush()
  H.eq(A.Inventory.Owned(12363).total, 5, "rescanned while open")
  A.FireEvent("BANKFRAME_CLOSED")
  ctx.state.bags[-1] = {}
  A.FireEvent("BAG_UPDATE_DELAYED"); ctx.timer.flush()
  H.eq(A.Inventory.Owned(12363).total, 5, "closed bank keeps its last snapshot")
end)

test("a commodity purchase is recorded when it succeeds", function()
  local A, ctx = boot()
  ctx.env.C_AuctionHouse.StartCommoditiesPurchase(12359, 20)
  A.FireEvent("COMMODITY_PRICE_UPDATED", 11000, 220000)
  A.FireEvent("COMMODITY_PURCHASE_SUCCEEDED")
  local rows = A.Ledger.ForItem(12359)
  H.eq(#rows, 1)
  H.eq({ rows[1].kind, rows[1].qty, rows[1].total, rows[1].unit, rows[1].source }, { "bought", 20, 220000, 11000, "ah" })
  H.eq(ctx.fired.LEDGER_UPDATED, 1)
end)

test("a failed commodity purchase records nothing and clears the pending buy", function()
  local A, ctx = boot()
  ctx.env.C_AuctionHouse.StartCommoditiesPurchase(12359, 20)
  A.FireEvent("COMMODITY_PRICE_UPDATED", 11000, 220000)
  A.FireEvent("COMMODITY_PURCHASE_FAILED")
  A.FireEvent("COMMODITY_PURCHASE_SUCCEEDED")
  H.eq(#A.Ledger.Recent(10), 0)
end)

test("an AH purchase is confirmed, not duplicated, when its invoice mail is read", function()
  local A, ctx = boot({ mails = { wonMail(30 - 600 / 86400) } })
  ctx.env.C_AuctionHouse.StartCommoditiesPurchase(12359, 20)
  A.FireEvent("COMMODITY_PRICE_UPDATED", 11000, 220000)
  A.FireEvent("COMMODITY_PURCHASE_SUCCEEDED")
  A.FireEvent("MAIL_SHOW"); ctx.timer.flush()
  local rows = A.Ledger.ForItem(12359)
  H.eq(#rows, 1)
  H.eq(rows[1].confirmed, true)
  H.eq(rows[1].total, 219000)
end)

test("buying out a single item is recorded unconfirmed; a plain bid is not", function()
  local A, ctx = boot()
  ctx.state.auctionInfo = {
    [1] = { itemKey = { itemID = 19019 }, quantity = 1, buyoutAmount = 5000000 },
  }
  ctx.env.C_AuctionHouse.PlaceBid(1, 4000000)
  H.eq(#A.Ledger.Recent(10), 0, "a bid below buyout is not a purchase")
  ctx.env.C_AuctionHouse.PlaceBid(1, 5000000)
  local rows = A.Ledger.ForItem(19019)
  H.eq(#rows, 1)
  H.eq({ rows[1].kind, rows[1].total, rows[1].source, rows[1].confirmed }, { "bought", 5000000, "ah", nil })
end)

test("owned auctions are snapshotted when the client reports them", function()
  local A, ctx = boot({ owned = { { itemKey = { itemID = 12359 }, quantity = 20, status = 0 } } })
  A.FireEvent("OWNED_AUCTIONS_UPDATED"); ctx.timer.flush()
  H.eq(A.Inventory.Owned(12359).rows[1].loc, "auctions")
end)

test("leaving the Auction House announces it", function()
  local A, ctx = boot()
  A.FireEvent("AUCTION_HOUSE_CLOSED")
  H.eq(ctx.fired.AH_CLOSED, 1)
end)

test("guild bank tabs are recorded under the guild", function()
  local A, ctx = boot({ guildSlots = { [1] = { "|Hitem:12359:0|h[Bar]|h", 40 } } })
  A.FireEvent("GUILDBANKBAGSLOTS_CHANGED"); ctx.timer.flush()
  local row = A.Inventory.Owned(12359).rows[1]
  H.eq({ row.guild, row.loc, row.count }, { "Boss", "guildbank", 40 })
end)

test("missing client APIs never raise", function()
  local A, ctx = boot({ noContainerAPI = true, noAuctionHouse = true, mails = { soldMail() } })
  H.nothrows(function()
    A.FireEvent("BAG_UPDATE_DELAYED"); A.FireEvent("BANKFRAME_OPENED"); A.FireEvent("MAIL_SHOW")
    A.FireEvent("OWNED_AUCTIONS_UPDATED"); A.FireEvent("COMMODITY_PURCHASE_SUCCEEDED")
    ctx.timer.flush()
  end)
end)
