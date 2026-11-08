local ADDON, A = ...

-- The player's own sales, purchases, postings, expiries and cancellations.
-- Auctionator records none of the first four, so Almanac keeps them.
-- Entry: { id, kind, itemID, itemName, qty, total, unit, fee, deposit, time,
--          char, realm, party, source, confirmed, approx, mailTime, mailSig, postKey }
local Ledger = {}
A.Ledger = Ledger

local floor = math.floor
local MAIL_LIFETIME_DAYS = 30     -- auction mails stay in the inbox this long
local MAIL_TOLERANCE = 120        -- seconds: two sightings of one mail estimate the same sale time
local CONFIRM_WINDOW = 7200       -- an AH-observed purchase and its invoice are within 2h

local KINDS = { sold = true, bought = true, posted = true, expired = true, cancelled = true }

local store
local byItem, sigIndex, unresolved, postIndex = {}, {}, {}, {}

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
local function sigOf(e)
  return table.concat({
    e.kind, tostring(e.itemID or e.itemName or "?"), tostring(e.qty or 1), tostring(e.total or 0), e.party or "",
  }, "|")
end

local function addSig(sig, e)
  local list = sigIndex[sig]
  if not list then
    list = {}
    sigIndex[sig] = list
  end
  list[#list + 1] = e
end

local function index(e)
  if e.itemID then
    local list = byItem[e.itemID]
    if not list then
      list = {}
      byItem[e.itemID] = list
    end
    list[#list + 1] = e
  else
    unresolved[#unresolved + 1] = e
  end
  addSig(sigOf(e), e)
  if e.mailSig then addSig(e.mailSig, e) end
  if e.postKey then postIndex[e.postKey] = e end
end

local function rebuild()
  byItem, sigIndex, unresolved, postIndex = {}, {}, {}, {}
  for _, e in ipairs(store.entries) do index(e) end
end

function Ledger.Init(db)
  store = db.ledger
  rebuild()
end

function Ledger.Reset()
  store.entries = {}
  store.seq = 0
  rebuild()
end

-- ---------------------------------------------------------------------------
-- Mail subjects
-- ---------------------------------------------------------------------------
local SUBJECTS = {
  { "sold", "AUCTION_SOLD_MAIL_SUBJECT", "Auction successful: %s" },
  { "bought", "AUCTION_WON_MAIL_SUBJECT", "Auction won: %s" },
  { "expired", "AUCTION_EXPIRED_MAIL_SUBJECT", "Auction expired: %s" },
  { "cancelled", "AUCTION_REMOVED_MAIL_SUBJECT", "Auction cancelled: %s" },
  { "outbid", "AUCTION_OUTBID_MAIL_SUBJECT", "Outbid on %s" },
}

local function toPattern(fmt)
  local escaped = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  escaped = escaped:gsub("%%%%s", "(.+)")
  return "^" .. escaped .. "$"
end

-- Returns kind ("sold"|"bought"|"expired"|"cancelled") and the item name from the
-- subject, or nil for anything else (outbid notices, player mail, ...).
function Ledger.ClassifySubject(subject)
  if type(subject) ~= "string" then return nil end
  for _, def in ipairs(SUBJECTS) do
    local fmt = A.env[def[2]]
    if type(fmt) ~= "string" then fmt = def[3] end
    local name = subject:match(toPattern(fmt))
    if name then
      if def[1] == "outbid" then return nil end
      return def[1], name
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Building entries from mail
-- ---------------------------------------------------------------------------
local function amountOf(invoice)
  local bid = tonumber(invoice.bid) or 0
  if bid > 0 then return bid end
  local buyout = tonumber(invoice.buyout) or 0
  if buyout > 0 then return buyout end
  return nil
end

-- m = { subject, invoice = {type, itemName, party, bid, buyout, deposit, consignment, count}|nil,
--       money, attachments = {{itemID, count}}, daysLeft, now, char, realm, resolveName(name) }
-- Pure: returns a candidate entry, or nil if the mail is not one we record.
function Ledger.FromMail(m)
  local invoice = m.invoice
  local kind, subjectName = Ledger.ClassifySubject(m.subject)
  if invoice then
    if invoice.type == "seller_temp_invoice" then return nil end
    if invoice.type == "seller" then kind = "sold" elseif invoice.type == "buyer" then kind = "bought" end
  end
  if kind == nil then return nil end

  local time = floor((m.now or 0) - (MAIL_LIFETIME_DAYS - (m.daysLeft or MAIL_LIFETIME_DAYS)) * 86400 + 0.5)
  local attachment = m.attachments and m.attachments[1]
  local itemName = (invoice and invoice.itemName) or subjectName
  local e = { kind = kind, time = time, char = m.char, realm = m.realm, source = "mail", itemName = itemName }

  local function resolve()
    if attachment and attachment.itemID then return attachment.itemID end
    return m.resolveName and itemName and m.resolveName(itemName) or nil
  end

  if kind == "sold" then
    e.itemID = resolve()
    if invoice then
      e.qty = tonumber(invoice.count) or 1
      e.total = amountOf(invoice)
      e.fee, e.deposit, e.party = invoice.consignment, invoice.deposit, invoice.party
    else
      e.qty, e.total, e.approx = 1, m.money, true      -- invoice API unavailable: net proceeds only
    end
  elseif kind == "bought" then
    e.itemID = resolve()
    e.qty = (attachment and attachment.count) or (invoice and tonumber(invoice.count)) or 1
    if invoice then
      e.total = amountOf(invoice)
      e.party = invoice.party
    else
      e.approx = true
    end
  else    -- expired or cancelled: the returned item is the record
    if not attachment then return nil end
    e.itemID = resolve()
    e.qty = attachment.count or 1
  end

  if e.total and e.qty > 0 then e.unit = floor(e.total / e.qty) end
  return e
end

-- ---------------------------------------------------------------------------
-- Adding
-- ---------------------------------------------------------------------------
-- Returns entry, "added" | nil, "duplicate" | nil, "confirmed" | nil, "invalid".
function Ledger.Add(entry)
  if type(entry) ~= "table" or not KINDS[entry.kind] or type(entry.time) ~= "number"
      or not (entry.itemID or entry.itemName) then
    return nil, "invalid"
  end
  entry.qty = entry.qty or 1
  if entry.total and not entry.unit and entry.qty > 0 then entry.unit = floor(entry.total / entry.qty) end

  if entry.source == "mail" then
    local sig = sigOf(entry)
    for _, x in ipairs(sigIndex[sig] or {}) do
      if math.abs((x.mailTime or x.time) - entry.time) <= MAIL_TOLERANCE then return nil, "duplicate" end
    end
    if entry.kind == "bought" and entry.itemID then
      for _, x in ipairs(byItem[entry.itemID] or {}) do
        if x.kind == "bought" and x.source == "ah" and not x.confirmed and x.qty == entry.qty
            and math.abs(x.time - entry.time) <= CONFIRM_WINDOW then
          x.confirmed, x.mailTime, x.mailSig = true, entry.time, sig
          if entry.total then x.total, x.unit = entry.total, entry.unit end
          if entry.party then x.party = entry.party end
          addSig(sig, x)
          return nil, "confirmed"
        end
      end
    end
  end

  store.seq = store.seq + 1
  entry.id = store.seq
  store.entries[#store.entries + 1] = entry
  index(entry)
  return entry, "added"
end

-- Entries recorded before their item name could be resolved get their itemID now.
function Ledger.ResolvePending(resolveName)
  local remaining, fixed = {}, 0
  for _, e in ipairs(unresolved) do
    local id = e.itemName and resolveName(e.itemName)
    if id then
      e.itemID = id
      local list = byItem[id]
      if not list then
        list = {}
        byItem[id] = list
      end
      list[#list + 1] = e
      fixed = fixed + 1
    else
      remaining[#remaining + 1] = e
    end
  end
  unresolved = remaining
  return fixed
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------
local function newestFirst(a, b)
  if a.time ~= b.time then return a.time > b.time end
  return (a.id or 0) > (b.id or 0)
end

function Ledger.ForItem(itemID)
  local out = {}
  for i, e in ipairs(byItem[itemID] or {}) do out[i] = e end
  table.sort(out, newestFirst)
  return out
end

-- Set of item IDs that have at least one entry: { [itemID] = true }
function Ledger.ItemSet()
  local set = {}
  for id, list in pairs(byItem) do
    if #list > 0 then set[id] = true end
  end
  return set
end

-- kinds: optional set such as { sold = true, bought = true }
function Ledger.Recent(n, kinds)
  local out = {}
  for _, e in ipairs(store.entries) do
    if not kinds or kinds[e.kind] then out[#out + 1] = e end
  end
  table.sort(out, newestFirst)
  for i = #out, n + 1, -1 do out[i] = nil end
  return out
end

function Ledger.Summary(entries)
  local s = {
    sold = { n = 0, qty = 0, gross = 0, fees = 0 },
    bought = { n = 0, qty = 0, spent = 0 },
    posted = { n = 0, qty = 0 },
    expired = { n = 0, qty = 0 },
    cancelled = { n = 0, qty = 0 },
  }
  for _, e in ipairs(entries) do
    local bucket = s[e.kind]
    if bucket then
      bucket.n = bucket.n + 1
      bucket.qty = bucket.qty + (e.qty or 0)
      if e.kind == "sold" then
        bucket.gross = bucket.gross + (e.total or 0)
        bucket.fees = bucket.fees + (e.fee or 0)
      elseif e.kind == "bought" then
        bucket.spent = bucket.spent + (e.total or 0)
      end
    end
  end
  if s.sold.qty > 0 then s.sold.avg = s.sold.gross / s.sold.qty end
  if s.bought.qty > 0 then s.bought.avg = s.bought.spent / s.bought.qty end
  s.net = s.sold.gross - s.sold.fees - s.bought.spent
  return s
end

-- ---------------------------------------------------------------------------
-- Auctionator posting history
-- ---------------------------------------------------------------------------
local function dayKey(t)
  local d = A.env.date or (os and os.date)
  if d then return d("%Y%m%d", t) end
  return tostring(floor(t / 86400))
end

-- adapter.AllPostings() -> { {itemID, time, price, quantity} }. Auctionator merges
-- same-day same-price posts into one row (quantity grows, time moves), so rows are
-- keyed by item, unit price and calendar day and updated in place.
function Ledger.ImportPosting(adapter)
  local added = 0
  for _, row in ipairs(adapter.AllPostings()) do
    local key = row.itemID .. "|" .. tostring(row.price) .. "|" .. dayKey(row.time)
    local existing = postIndex[key]
    if existing then
      if existing.qty ~= row.quantity or existing.time ~= row.time then
        existing.qty, existing.time = row.quantity, row.time
        existing.total = row.price * row.quantity
      end
    else
      local _, status = Ledger.Add({
        kind = "posted", itemID = row.itemID, qty = row.quantity, unit = row.price,
        total = row.price * row.quantity, time = row.time, source = "auctionator", postKey = key,
      })
      if status == "added" then added = added + 1 end
    end
  end
  return added
end

function Ledger.Prune(keepDays, now)
  local cutoff = now - keepDays * 86400
  local kept, removed = {}, 0
  for _, e in ipairs(store.entries) do
    if e.time >= cutoff then kept[#kept + 1] = e else removed = removed + 1 end
  end
  if removed > 0 then
    store.entries = kept
    rebuild()
  end
  return removed
end
