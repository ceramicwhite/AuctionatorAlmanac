local H = require("harness")
local test = H.test

local NOW = 1800000000
local DAY = 86400

local function load(env)
  env = env or {}
  env.date = env.date or function(fmt, t) return os.date("!" .. fmt, t) end   -- UTC: timezone-independent tests
  local A = H.newA({ "Core/Init.lua", "Tracker/Ledger.lua" }, env)
  A.db = A.InitDB(nil)
  A.Ledger.Init(A.db)
  return A.Ledger, A
end

local names = { ["Thorium Bar"] = 12359, ["Arcane Crystal"] = 12363 }
local function resolve(name) return names[name] end

-- A seller invoice mail as the client would report it.
local function soldMail(o)
  o = o or {}
  return {
    subject = "Auction successful: Thorium Bar",
    invoice = { type = "seller", itemName = "Thorium Bar", party = o.party or "Buyer", bid = o.bid or 11000, buyout = o.buyout or 12000,
                deposit = 200, consignment = 550, count = o.count or 20 },
    attachments = {},
    daysLeft = o.daysLeft or 29.5,
    now = o.now or NOW,
    char = "Thornwick", realm = "Whitemane",
    resolveName = resolve,
  }
end

test("ClassifySubject recognizes auction mails", function()
  local L = load()
  local kind, name = L.ClassifySubject("Auction successful: Thorium Bar")
  H.eq(kind, "sold"); H.eq(name, "Thorium Bar")
  kind, name = L.ClassifySubject("Auction won: Arcane Crystal")
  H.eq(kind, "bought"); H.eq(name, "Arcane Crystal")
  H.eq({ L.ClassifySubject("Auction expired: Thorium Bar") }, { "expired", "Thorium Bar" })
  H.eq({ L.ClassifySubject("Auction cancelled: Thorium Bar") }, { "cancelled", "Thorium Bar" })
  H.eq(L.ClassifySubject("Outbid on Thorium Bar"), nil)
  H.eq(L.ClassifySubject("Hello friend"), nil)
  H.eq(L.ClassifySubject(nil), nil)
end)

test("ClassifySubject uses the client's localized subject formats when present", function()
  local L = load({ AUCTION_SOLD_MAIL_SUBJECT = "Subasta con éxito: %s" })
  H.eq({ L.ClassifySubject("Subasta con éxito: Barra de torio") }, { "sold", "Barra de torio" })
  H.eq(L.ClassifySubject("Auction successful: Thorium Bar"), nil, "only the localized form is used")
end)

test("a seller invoice becomes a sold entry priced from the bid", function()
  local L = load()
  local e = L.FromMail(soldMail())
  H.eq(e.kind, "sold")
  H.eq(e.itemID, 12359)
  H.eq(e.qty, 20)
  H.eq(e.total, 11000)
  H.eq(e.unit, 550)
  H.eq(e.fee, 550)
  H.eq(e.deposit, 200)
  H.eq(e.party, "Buyer")
  H.eq(e.time, NOW - 43200, "30 day mail lifetime minus days left")
  H.eq(e.source, "mail")
  H.eq(e.char, "Thornwick")
  H.eq(e.realm, "Whitemane")
  H.eq(L.FromMail(soldMail({ bid = 0 })).total, 12000, "falls back to the buyout when there is no bid")
end)

test("the same mail scanned again is a duplicate", function()
  local L = load()
  local first = soldMail()
  local again = soldMail({ now = NOW + 40, daysLeft = 29.5 - 40 / DAY })
  local e, status = L.Add(L.FromMail(first))
  H.eq(status, "added")
  H.truthy(e.id)
  local dup, dupStatus = L.Add(L.FromMail(again))
  H.eq(dup, nil)
  H.eq(dupStatus, "duplicate")
  H.eq(#L.ForItem(12359), 1)
end)

test("two identical sales two hours apart are both kept", function()
  local L = load()
  L.Add(L.FromMail(soldMail()))
  -- an hour-later mail that would have the same price: its estimated sale time differs by 2h
  local _, status = L.Add(L.FromMail(soldMail({ daysLeft = 29.5 + 7200 / DAY })))
  H.eq(status, "added")
  H.eq(#L.ForItem(12359), 2)
end)

test("a buyer invoice takes item and count from the attachment", function()
  local L = load()
  local e = L.FromMail({
    subject = "Auction won: Thorium Bar",
    invoice = { type = "buyer", itemName = "Thorium Bar", party = "Seller", bid = 220000, buyout = 220000, count = 20 },
    attachments = { { itemID = 12359, count = 20 } },
    daysLeft = 29.9, now = NOW, char = "Thornwick", realm = "Whitemane", resolveName = resolve,
  })
  H.eq(e.kind, "bought")
  H.eq(e.itemID, 12359)
  H.eq(e.qty, 20)
  H.eq(e.total, 220000)
  H.eq(e.unit, 11000)
  H.eq(e.party, "Seller")
end)

test("a pending-sale temp invoice is ignored", function()
  local L = load()
  local m = soldMail()
  m.invoice.type = "seller_temp_invoice"
  H.eq(L.FromMail(m), nil)
end)

test("expired and cancelled mails use the returned attachment", function()
  local L = load()
  local m = { subject = "Auction expired: Thorium Bar", attachments = { { itemID = 12359, count = 20 } },
              daysLeft = 29, now = NOW, char = "Thornwick", realm = "Whitemane", resolveName = resolve }
  local e = L.FromMail(m)
  H.eq(e.kind, "expired"); H.eq(e.itemID, 12359); H.eq(e.qty, 20); H.eq(e.total, nil)
  m.subject = "Auction cancelled: Thorium Bar"
  H.eq(L.FromMail(m).kind, "cancelled")
  m.attachments = {}
  H.eq(L.FromMail(m), nil, "nothing was returned, nothing to record")
end)

test("outbid and unrelated mails produce nothing", function()
  local L = load()
  H.eq(L.FromMail({ subject = "Outbid on Thorium Bar", attachments = {}, daysLeft = 30, now = NOW, resolveName = resolve }), nil)
  H.eq(L.FromMail({ subject = "Hi", attachments = {}, daysLeft = 30, now = NOW, resolveName = resolve }), nil)
end)

test("a sale with no invoice API is recorded approximately from the mail money", function()
  local L = load()
  local e = L.FromMail({ subject = "Auction successful: Thorium Bar", money = 10650, attachments = {}, daysLeft = 29.5, now = NOW,
                         char = "Thornwick", realm = "Whitemane", resolveName = resolve })
  H.eq(e.kind, "sold")
  H.eq(e.total, 10650)
  H.eq(e.approx, true)
end)

test("unresolved item names are kept and resolved later", function()
  local L = load()
  local m = soldMail()
  m.resolveName = function() return nil end
  local e = L.Add(L.FromMail(m))
  H.eq(e.itemID, nil)
  H.eq(e.itemName, "Thorium Bar")
  H.eq(#L.ForItem(12359), 0)
  H.eq(L.ResolvePending(resolve), 1)
  H.eq(#L.ForItem(12359), 1)
  H.eq(L.ResolvePending(resolve), 0)
end)

test("an AH-observed purchase is confirmed, not duplicated, by its invoice", function()
  local L = load()
  L.Add({ kind = "bought", itemID = 12359, qty = 20, total = 220000, time = NOW - 3000, source = "ah", char = "Thornwick", realm = "Whitemane" })
  local mail = {
    subject = "Auction won: Thorium Bar",
    invoice = { type = "buyer", itemName = "Thorium Bar", party = "Seller", bid = 219000, buyout = 219000, count = 20 },
    attachments = { { itemID = 12359, count = 20 } },
    daysLeft = 30 - 600 / DAY, now = NOW, char = "Thornwick", realm = "Whitemane", resolveName = resolve,
  }
  local e, status = L.Add(L.FromMail(mail))
  H.eq(e, nil)
  H.eq(status, "confirmed")
  local rows = L.ForItem(12359)
  H.eq(#rows, 1)
  H.eq(rows[1].confirmed, true)
  H.eq(rows[1].total, 219000, "the invoice amount is authoritative")
  H.eq(rows[1].party, "Seller")
  local _, again = L.Add(L.FromMail(mail))
  H.eq(again, "duplicate", "re-scanning the confirmed mail adds nothing")
  H.eq(#L.ForItem(12359), 1)
end)

test("a purchase invoice with no matching AH record is added", function()
  local L = load()
  local mail = {
    subject = "Auction won: Thorium Bar",
    invoice = { type = "buyer", itemName = "Thorium Bar", party = "Seller", bid = 219000, buyout = 219000, count = 20 },
    attachments = { { itemID = 12359, count = 20 } }, daysLeft = 29, now = NOW, char = "Thornwick", realm = "Whitemane", resolveName = resolve,
  }
  local _, status = L.Add(L.FromMail(mail))
  H.eq(status, "added")
end)

test("Add rejects entries without a kind, item or time", function()
  local L = load()
  H.eq({ L.Add({ itemID = 1, time = NOW }) }, { nil, "invalid" })
  H.eq({ L.Add({ kind = "sold", time = NOW }) }, { nil, "invalid" })
  H.eq({ L.Add({ kind = "sold", itemID = 1 }) }, { nil, "invalid" })
  H.eq({ L.Add({ kind = "weird", itemID = 1, time = NOW }) }, { nil, "invalid" })
  H.eq({ L.Add(nil) }, { nil, "invalid" })
end)

test("ForItem is newest first and Recent filters by kind", function()
  local L = load()
  L.Add({ kind = "sold", itemID = 1, qty = 1, total = 100, time = NOW - 300, source = "mail", party = "a" })
  L.Add({ kind = "bought", itemID = 1, qty = 1, total = 50, time = NOW - 100, source = "ah" })
  L.Add({ kind = "posted", itemID = 2, qty = 5, total = 500, time = NOW - 200, source = "auctionator" })
  local rows = L.ForItem(1)
  H.eq({ rows[1].kind, rows[2].kind }, { "bought", "sold" })
  local recent = L.Recent(10, { sold = true, bought = true })
  H.eq(#recent, 2)
  H.eq(recent[1].kind, "bought")
  H.eq(#L.Recent(1), 1)
  H.eq(L.Recent(10)[2].kind, "posted")
end)

local function poster(rows)
  return { AllPostings = function() return rows end }
end

test("ImportPosting adds posted entries once and merges same-day same-price updates", function()
  local L = load()
  local rows = { { itemID = 12359, time = NOW - 10 * DAY, price = 11900, quantity = 20 } }
  H.eq(L.ImportPosting(poster(rows)), 1)
  H.eq(L.ImportPosting(poster(rows)), 0, "idempotent")
  H.eq(#L.ForItem(12359), 1)
  -- Auctionator merged a second same-day same-price post into the existing row
  rows[1] = { itemID = 12359, time = NOW - 10 * DAY + 3600, price = 11900, quantity = 25 }
  H.eq(L.ImportPosting(poster(rows)), 0)
  local posted = L.ForItem(12359)
  H.eq(#posted, 1)
  H.eq(posted[1].qty, 25)
  H.eq(posted[1].total, 11900 * 25)
  H.eq(posted[1].unit, 11900)
  H.eq(posted[1].kind, "posted")
  H.eq(posted[1].source, "auctionator")
  -- a different price the same day is a different posting
  rows[2] = { itemID = 12359, time = NOW - 10 * DAY + 7200, price = 12500, quantity = 5 }
  H.eq(L.ImportPosting(poster(rows)), 1)
  H.eq(#L.ForItem(12359), 2)
end)

test("Prune removes only entries older than the keep window", function()
  local L = load()
  L.Add({ kind = "sold", itemID = 1, qty = 1, total = 1, time = NOW - 800 * DAY, source = "mail", party = "x" })
  L.Add({ kind = "sold", itemID = 1, qty = 1, total = 2, time = NOW - 10 * DAY, source = "mail", party = "y" })
  H.eq(L.Prune(730, NOW), 1)
  local rows = L.ForItem(1)
  H.eq(#rows, 1)
  H.eq(rows[1].total, 2)
  H.eq(L.Prune(730, NOW), 0)
end)

test("Summary totals sales, purchases, fees and net", function()
  local L = load()
  local entries = {
    { kind = "sold", qty = 20, total = 11000, fee = 550 },
    { kind = "sold", qty = 10, total = 6000, fee = 300 },
    { kind = "bought", qty = 20, total = 9000 },
    { kind = "posted", qty = 30, total = 0 },
    { kind = "expired", qty = 5 },
  }
  local s = L.Summary(entries)
  H.eq(s.sold.n, 2); H.eq(s.sold.qty, 30); H.eq(s.sold.gross, 17000); H.eq(s.sold.fees, 850)
  H.near(s.sold.avg, 17000 / 30)
  H.eq(s.bought.n, 1); H.eq(s.bought.qty, 20); H.eq(s.bought.spent, 9000); H.near(s.bought.avg, 450)
  H.eq(s.posted.n, 1); H.eq(s.posted.qty, 30)
  H.eq(s.expired.qty, 5)
  H.eq(s.net, 17000 - 850 - 9000)
  local empty = L.Summary({})
  H.eq(empty.sold.n, 0); H.eq(empty.sold.avg, nil); H.eq(empty.net, 0)
end)

test("the ledger survives a reload of the saved variables", function()
  local L, A = load()
  L.Add(L.FromMail(soldMail()))
  local saved = A.db
  local L2 = H.newA({ "Core/Init.lua", "Tracker/Ledger.lua" }).Ledger
  L2.Init(saved)
  H.eq(#L2.ForItem(12359), 1)
  local _, status = L2.Add(L2.FromMail(soldMail({ now = NOW + 90, daysLeft = 29.5 - 90 / DAY })))
  H.eq(status, "duplicate", "dedupe index is rebuilt from saved entries")
end)

test("ItemSet lists every item that has ledger entries", function()
  local L = load()
  L.Add({ kind = "sold", itemID = 5, qty = 1, total = 1, time = NOW, source = "mail", party = "x" })
  L.Add({ kind = "posted", itemID = 9, qty = 1, total = 1, time = NOW, source = "auctionator" })
  L.Add({ kind = "sold", itemName = "Mystery", qty = 1, total = 1, time = NOW + 500, source = "mail", party = "x" })
  H.eq(L.ItemSet(), { [5] = true, [9] = true })
end)
