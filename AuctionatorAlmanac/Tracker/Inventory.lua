local ADDON, A = ...

-- Where the player's items are: per-character snapshots of bags, bank, mail,
-- equipped gear and active auctions, plus guild bank tabs and the warband bank
-- when the client has them. Each snapshot carries the time it was taken so the
-- UI can say how stale a character's data is.
local Inventory = {}
A.Inventory = Inventory

local db
local dirty, totals = true, nil

local LOC_ORDER = { bags = 1, equipped = 2, reagents = 3, bank = 4, mail = 5, auctions = 6 }
local MAX_MAIL_ATTACHMENTS = 16
local GUILD_SLOTS = 98

local function copyCounts(counts)
  local out = {}
  for id, n in pairs(counts or {}) do
    if n and n > 0 then out[id] = n end
  end
  return out
end

function Inventory.Init(saved)
  db = saved
  dirty, totals = true, nil
end

function Inventory.Reset()
  db.chars, db.guilds, db.warband = {}, {}, nil
  dirty = true
end

function Inventory.CharKey(name, realm) return name .. "-" .. realm end

-- ---------------------------------------------------------------------------
-- Characters
-- ---------------------------------------------------------------------------
-- info = { name, realm, class, faction }
function Inventory.EnsureChar(info)
  local key = Inventory.CharKey(info.name, info.realm)
  local rec = db.chars[key]
  if not rec then
    rec = { key = key, name = info.name, realm = info.realm, lastSeen = 0, loc = {}, stamps = {} }
    db.chars[key] = rec
  end
  rec.class = info.class or rec.class
  rec.faction = info.faction or rec.faction
  return rec
end

local function charFor(key)
  local rec = db.chars[key]
  if rec then return rec end
  local name, realm = key:match("^([^-]+)-(.+)$")
  return Inventory.EnsureChar({ name = name or key, realm = realm or "?" })
end

function Inventory.Characters()
  local list = {}
  for _, rec in pairs(db.chars) do list[#list + 1] = rec end
  table.sort(list, function(a, b)
    if a.lastSeen ~= b.lastSeen then return a.lastSeen > b.lastSeen end
    return a.key < b.key
  end)
  return list
end

-- loc: bags | bank | mail | equipped | auctions
function Inventory.SetLocation(charKey, loc, counts, now)
  local rec = charFor(charKey)
  rec.loc[loc] = copyCounts(counts)
  rec.stamps[loc] = now
  if now > (rec.lastSeen or 0) then rec.lastSeen = now end
  dirty = true
end

function Inventory.SetGuildTab(guildKey, guildName, tab, counts, now)
  local rec = db.guilds[guildKey]
  if not rec then
    rec = { name = guildName, tabs = {}, stamps = {} }
    db.guilds[guildKey] = rec
  end
  rec.tabs[tab] = copyCounts(counts)
  rec.stamps[tab] = now
  dirty = true
end

function Inventory.SetWarband(counts, now)
  db.warband = { items = copyCounts(counts), stamp = now }
  dirty = true
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------
-- Counts what the player owns: characters plus the warband bank. Guild bank
-- contents belong to the guild, so they are listed but never counted.
function Inventory.Totals()
  if not dirty and totals then return totals end
  local out = {}
  for _, rec in pairs(db.chars) do
    for _, counts in pairs(rec.loc) do
      for id, n in pairs(counts) do out[id] = (out[id] or 0) + n end
    end
  end
  if db.warband then
    for id, n in pairs(db.warband.items or {}) do out[id] = (out[id] or 0) + n end
  end
  totals, dirty = out, false
  return out
end

-- { total, rows = { {charKey, name, realm, loc, count, stamp} | {loc="warband"...} | {guild, loc="guildbank", shared=true} } }
function Inventory.Owned(itemID)
  local rows, total = {}, 0
  for key, rec in pairs(db.chars) do
    for loc, counts in pairs(rec.loc) do
      local n = counts[itemID]
      if n and n > 0 then
        rows[#rows + 1] = { group = 1, charKey = key, name = rec.name, realm = rec.realm, loc = loc, count = n, stamp = rec.stamps[loc] }
        total = total + n
      end
    end
  end
  if db.warband then
    local n = db.warband.items and db.warband.items[itemID]
    if n and n > 0 then
      rows[#rows + 1] = { group = 2, loc = "warband", count = n, stamp = db.warband.stamp }
      total = total + n
    end
  end
  for _, guild in pairs(db.guilds) do
    local sum, stamp = 0, 0
    for tab, counts in pairs(guild.tabs) do
      local n = counts[itemID]
      if n and n > 0 then
        sum = sum + n
        stamp = math.max(stamp, guild.stamps[tab] or 0)
      end
    end
    if sum > 0 then
      rows[#rows + 1] = { group = 3, guild = guild.name, loc = "guildbank", count = sum, stamp = stamp, shared = true }
    end
  end
  table.sort(rows, function(a, b)
    if a.group ~= b.group then return a.group < b.group end
    if a.group == 1 then
      if a.name ~= b.name then return a.name < b.name end
      if a.realm ~= b.realm then return a.realm < b.realm end
      return (LOC_ORDER[a.loc] or 99) < (LOC_ORDER[b.loc] or 99)
    end
    return (a.guild or "") < (b.guild or "")
  end)
  for _, row in ipairs(rows) do row.group = nil end
  return { total = total, rows = rows }
end

-- ---------------------------------------------------------------------------
-- Bag classification
-- ---------------------------------------------------------------------------
-- ctx = { Enum = <game Enum table or nil>, numBagSlots = 4 }
local function bagMap(ctx)
  local map = {}
  local BI = ctx.Enum and ctx.Enum.BagIndex
  if BI then
    local function put(name, class)
      local id = BI[name]
      if id ~= nil then map[id] = class end
    end
    -- bank and warband first so carried bags win any index collision
    put("Bank", "bank"); put("Reagentbank", "bank")
    for n = 1, 8 do
      put("BankBag_" .. n, "bank")
      put("CharacterBankTab_" .. n, "bank")
      put("AccountBankTab_" .. n, "warband")
    end
    put("Backpack", "bags"); put("Keyring", "bags"); put("ReagentBag", "bags")
    for n = 1, 4 do put("Bag_" .. n, "bags") end
  else
    local carried = ctx.numBagSlots or 4
    for id = 0, carried do map[id] = "bags" end
    map[-1], map[-3] = "bank", "bank"
    for id = carried + 1, carried + 7 do map[id] = "bank" end
  end
  return map
end

function Inventory.ClassifyBag(bagID, ctx)
  return bagMap(ctx)[bagID]
end

-- ---------------------------------------------------------------------------
-- Collectors (read the live game; nil means the API is unavailable)
-- ---------------------------------------------------------------------------
local function bagIDs(class, env)
  local ctx = { Enum = env.Enum, numBagSlots = env.NUM_BAG_SLOTS or 4 }
  local map = bagMap(ctx)
  local ids = {}
  for id = -3, 30 do
    if map[id] == class then ids[#ids + 1] = id end
  end
  return ids
end

local function scanContainers(class, env)
  local C = env.C_Container
  if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return nil end
  local counts = {}
  for _, bag in ipairs(bagIDs(class, env)) do
    for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
      local info = C.GetContainerItemInfo(bag, slot)
      if type(info) == "table" and info.itemID then
        counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  return counts
end

function Inventory.ScanBags(env) return scanContainers("bags", env) end
function Inventory.ScanBank(env) return scanContainers("bank", env) end
function Inventory.ScanWarband(env) return scanContainers("warband", env) end

function Inventory.ScanEquipped(env)
  if not env.GetInventoryItemID then return nil end
  local counts = {}
  for slot = 1, 23 do
    local id = env.GetInventoryItemID("player", slot)
    if id then counts[id] = (counts[id] or 0) + 1 end
  end
  return counts
end

local function itemIDFromLink(link)
  local id = type(link) == "string" and link:match("item:(%d+)")
  return id and tonumber(id) or nil
end

-- Attachments of one inbox mail: { {itemID, count} }. Handles the classic return
-- shape (name, itemID, texture, count), table-returning variants, and item links.
function Inventory.MailAttachments(env, index)
  local C = env.C_Mail
  local getItem = (C and C.GetInboxItem) or env.GetInboxItem
  local out = {}
  if not getItem then return out end
  local getLink = (C and C.GetInboxItemLink) or env.GetInboxItemLink
  for j = 1, MAX_MAIL_ATTACHMENTS do
    local a, b, _, d = getItem(index, j)
    local id, count
    if type(a) == "table" then
      id, count = a.itemID, a.count or a.stackCount
    elseif a ~= nil then
      id, count = b, d
      if not id and getLink then id = itemIDFromLink(getLink(index, j)) end
    end
    if id then out[#out + 1] = { itemID = id, count = count or 1 } end
  end
  return out
end

function Inventory.ScanMail(env)
  local C = env.C_Mail
  local getNum = (C and C.GetInboxNumItems) or env.GetInboxNumItems
  local getItem = (C and C.GetInboxItem) or env.GetInboxItem
  if not (getNum and getItem) then return nil end
  local counts = {}
  for i = 1, (getNum() or 0) do
    for _, att in ipairs(Inventory.MailAttachments(env, i)) do
      counts[att.itemID] = (counts[att.itemID] or 0) + att.count
    end
  end
  return counts
end

function Inventory.ScanOwnedAuctions(env)
  local C = env.C_AuctionHouse
  if not (C and C.GetNumOwnedAuctions and C.GetOwnedAuctionInfo) then return nil end
  local active = env.Enum and env.Enum.AuctionStatus and env.Enum.AuctionStatus.Active or 0
  local counts = {}
  for i = 1, (C.GetNumOwnedAuctions() or 0) do
    local info = C.GetOwnedAuctionInfo(i)
    local id = type(info) == "table" and info.itemKey and info.itemKey.itemID
    if id and (info.status == nil or info.status == active) then
      counts[id] = (counts[id] or 0) + (info.quantity or 1)
    end
  end
  return counts
end

function Inventory.ScanGuildBank(tab, env)
  if not (env.GetGuildBankItemLink and env.GetGuildBankItemInfo) then return nil end
  local counts = {}
  for slot = 1, GUILD_SLOTS do
    local id = itemIDFromLink(env.GetGuildBankItemLink(tab, slot))
    if id then
      local _, count = env.GetGuildBankItemInfo(tab, slot)
      counts[id] = (counts[id] or 0) + (count or 1)
    end
  end
  return counts
end
