local ADDON, A = ...

-- Persistent item cache. Auctionator's price data has item IDs only, so names
-- come from the client. Category, icon and equip slot are available instantly
-- (GetItemInfoInstant); the name needs a server round trip, so names are loaded
-- in the background, throttled, and saved so they only load once.
local Items = {}
A.Items = Items
Items.BATCH = 50

local BATCH = 50        -- name requests per tick (~500/s: a full 15,000 item cache in under a minute)
local TICK = 0.1        -- seconds between ticks
local CHUNK = 500       -- most ids examined in one frame by EnsureAll
local BUDGET_MS = 6     -- ...and no more than this much time per frame
local NOTIFY_DELAY = 0.3

-- Persisted row layout: db.items[id] = { name, quality, icon, class, sub, invType, sell, minLevel, ilvl }
local views, names, byName = {}, {}, {}
local queue, qhead, qtail, queued = {}, 1, 0, {}
local pending, failed = {}, {}
local pumpScheduled, notifyScheduled = false, false
local tracked = {}
local rows

local INV = {
  INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4, INVTYPE_CHEST = 5,
  INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10,
  INVTYPE_FINGER = 11, INVTYPE_TRINKET = 12, INVTYPE_WEAPON = 13, INVTYPE_SHIELD = 14,
  INVTYPE_RANGED = 15, INVTYPE_CLOAK = 16, INVTYPE_2HWEAPON = 17, INVTYPE_BAG = 18,
  INVTYPE_TABARD = 19, INVTYPE_ROBE = 20, INVTYPE_WEAPONMAINHAND = 21, INVTYPE_WEAPONOFFHAND = 22,
  INVTYPE_HOLDABLE = 23, INVTYPE_AMMO = 24, INVTYPE_THROWN = 25, INVTYPE_RANGEDRIGHT = 26,
  INVTYPE_QUIVER = 27, INVTYPE_RELIC = 28,
}

function Items.EquipToInventoryType(equipLoc)
  if type(equipLoc) ~= "string" then return nil end
  return INV[equipLoc]
end

local function save(v)
  rows[v.id] = { v.name, v.quality, v.icon, v.class, v.sub, v.invType, v.sell, v.minLevel, v.ilvl }
end

local function indexName(lname, id)
  local current = byName[lname]
  if not current or id < current then byName[lname] = id end
end

local function fromRow(id, row)
  local v = {
    id = id, name = row[1], quality = row[2], icon = row[3], class = row[4], sub = row[5],
    invType = row[6], sell = row[7], minLevel = row[8], ilvl = row[9],
  }
  if v.name then
    v.lname = v.name:lower()
    names[id] = v.lname
    indexName(v.lname, id)
  end
  return v
end

function Items.Init(db)
  rows = db.items
  views, names, byName = {}, {}, {}
  queue, qhead, qtail, queued = {}, 1, 0, {}
  pending, failed, tracked = {}, {}, {}
  pumpScheduled, notifyScheduled = false, false
  for id, row in pairs(rows) do
    if type(id) == "number" and type(row) == "table" and row[1] then
      views[id] = fromRow(id, row)
    end
  end
end

function Items.Reset()
  if rows then
    for id in pairs(rows) do rows[id] = nil end
  end
  views, names, byName = {}, {}, {}
  failed, pending = {}, {}
end

function Items.Get(id)
  local v = views[id]
  if v then return v end
  local row = rows and rows[id]
  if type(row) == "table" then
    v = fromRow(id, row)
    views[id] = v
    return v
  end
  return nil
end

function Items.Name(id)
  local v = Items.Get(id)
  return (v and v.name) or ("Item " .. tostring(id))
end

-- {[itemID] = lowercased name}, live: updated as names load.
function Items.NameIndex() return names end

-- Reverse lookup for mail, which only gives item names. On a name clash the
-- lowest item ID wins; unknown names fall back to the client's own cache.
function Items.IDByName(name)
  if type(name) ~= "string" then return nil end
  local id = byName[name:lower()]
  if id then return id end
  local C = A.env.C_Item
  if C and C.GetItemInfoInstant then
    local ok, found = pcall(C.GetItemInfoInstant, name)
    if ok and type(found) == "number" then return found end
  end
  return nil
end

local function notifySoon()
  if notifyScheduled then return end
  notifyScheduled = true
  A.After(NOTIFY_DELAY, function()
    notifyScheduled = false
    A.Bus.Fire("ITEM_NAMES_UPDATED")
  end)
end

-- Fill name and details if the client has the item cached. GetItemInfo asks the
-- server about an uncached item, so unless `force` is set (the data has just
-- loaded) it is only called when the client reports the item as cached; the
-- throttled loader is the one place that requests uncached items.
local function tryName(v, force)
  local C = A.env.C_Item
  if not (C and C.GetItemInfo) then return false end
  if not force and C.IsItemDataCachedByID and C.IsItemDataCachedByID(v.id) == false then return false end
  local name, _, quality, ilvl, minLevel, _, _, _, equipLoc, _, sell = C.GetItemInfo(v.id)
  if not name then return false end
  v.name, v.lname = name, name:lower()
  v.quality, v.ilvl, v.minLevel, v.sell = quality, ilvl, minLevel, sell
  if v.invType == nil then v.invType = Items.EquipToInventoryType(equipLoc) end
  names[v.id] = v.lname
  indexName(v.lname, v.id)
  save(v)
  notifySoon()
  return true
end

local function fillInstant(v)
  local C = A.env.C_Item
  if not (C and C.GetItemInfoInstant) then
    v.missing = true
    return
  end
  local _, _, _, equipLoc, icon, class, sub = C.GetItemInfoInstant(v.id)
  if class == nil and icon == nil then
    v.missing = true
    return
  end
  v.icon, v.class, v.sub = icon, class, sub
  v.invType = Items.EquipToInventoryType(equipLoc)
  save(v)
end

local function pump()
  pumpScheduled = false
  local C = A.env.C_Item
  local requests = 0
  while qhead <= qtail and requests < BATCH do
    local id = queue[qhead]
    queue[qhead] = nil
    qhead = qhead + 1
    queued[id] = nil
    local v = views[id]
    if v and not v.name and not v.missing and not failed[id] and not pending[id] then
      if not tryName(v) and C and C.RequestLoadItemDataByID then
        C.RequestLoadItemDataByID(id)
        pending[id] = true
        requests = requests + 1
      end
    end
  end
  if qhead <= qtail then
    pumpScheduled = true
    A.After(TICK, pump)
  else
    queue, qhead, qtail = {}, 1, 0
  end
end

local function enqueue(id)
  if queued[id] then return end
  qtail = qtail + 1
  queue[qtail] = id
  queued[id] = true
  if not pumpScheduled then
    pumpScheduled = true
    A.After(TICK, pump)
  end
end

-- Returns the cached view for `id`, creating it from instant info and queueing
-- the name load if needed. Never blocks and never errors without an item API.
function Items.Ensure(id)
  local v = Items.Get(id)
  if not v then
    v = { id = id }
    views[id] = v
  end
  if v.class == nil and not v.missing then fillInstant(v) end
  if not v.name and not v.missing and not failed[id] and not pending[id] then
    if not tryName(v) then enqueue(id) end
  end
  return v
end

-- Ensure many ids without hitching: CHUNK per frame. onProgress(done, total).
function Items.EnsureAll(ids, onProgress)
  tracked = ids
  local total, i = #ids, 1
  if total == 0 then
    if onProgress then onProgress(0, 0) end
    return
  end
  local function step()
    i = A.RunBudgeted(i, total, CHUNK, BUDGET_MS, function(k) Items.Ensure(ids[k]) end)
    if onProgress then onProgress(i - 1, total) end
    if i <= total then A.After(0, step) end
  end
  step()
end

function Items.OnLoaded(id, success)
  local v = views[id]
  if not v then return end            -- not an item we asked about
  pending[id] = nil
  if v.name then return end
  if success == false or not tryName(v, true) then failed[id] = true end
end

function Items.Progress()
  local have = 0
  for i = 1, #tracked do
    local v = views[tracked[i]]
    if v and v.name then have = have + 1 end
  end
  return have, #tracked
end

function Items.Start()
  local handler = function(_, id, success) Items.OnLoaded(id, success) end
  A.RegisterEvent("ITEM_DATA_LOAD_RESULT", handler)
  A.RegisterEvent("GET_ITEM_INFO_RECEIVED", handler)
end
