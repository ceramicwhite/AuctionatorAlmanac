-- Builds realistic AuctionatorAlmanac.lua saved files for the Almanac website's tests.
--
--   lua scripts/make-fixture.lua <output dir>        (run from the repository root)
--
-- It boots the real addon in the test harness with a generated Auctionator market, records sales,
-- purchases, inventory and a watch list through the addon's own modules, lets Almanac 1.3 write its
-- export block, then writes ALMANAC_DB the way WoW writes SavedVariables (tabs, ["key"] = value,
-- positional values with "-- [n]" comments). Everything is seeded, so the output is reproducible.
package.path = "tests/?.lua;" .. package.path
local Boot = require("boot_ui")
local Fx = require("fixtures")

local outDir = arg and arg[1]
if not outDir then
  io.stderr:write("usage: lua scripts/make-fixture.lua <output dir>\n")
  os.exit(2)
end

local REALM = "Fixtureland"
local TODAY = Fx.TODAY

-- ---------------------------------------------------------------------------
-- A tiny seeded generator, so the fixtures never change between runs
-- ---------------------------------------------------------------------------
local function rng(seed)
  local state = seed
  return function()
    state = (state * 1103515245 + 12345) % 2147483648
    return state / 2147483648
  end
end

local ADJ = { "Ancient", "Bloodied", "Crimson", "Dusty", "Elder", "Frostbound", "Gilded", "Hallowed", "Iron", "Jagged" }
local NOUN = {
  { "Bar", 7, 12 }, { "Cloth", 7, 5 }, { "Herb", 7, 9 }, { "Gem", 3, 0 }, { "Potion", 0, 1 },
  { "Blade", 2, 7, "INVTYPE_WEAPON" }, { "Helm", 4, 1, "INVTYPE_HEAD" }, { "Ring", 4, 0, "INVTYPE_FINGER" },
  { "Scroll", 9, 0 }, { "Pelt", 7, 6 },
}

-- ---------------------------------------------------------------------------
-- Serialising a table the way WoW writes SavedVariables
-- ---------------------------------------------------------------------------
local function quote(s)
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
  s = s:gsub("[%z\1-\8\11\12\14-\31]", function(c) return string.format("\\%03d", c:byte()) end)
  return '"' .. s .. '"'
end

local function number(n)
  if n ~= n or n == math.huge or n == -math.huge then error("cannot save a non-finite number") end
  if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%.0f", n) end
  return string.format("%.14g", n)
end

local function keyText(k)
  if type(k) == "number" then return "[" .. number(k) .. "]" end
  return "[" .. quote(k) .. "]"
end

local function sortedKeys(t, skip)
  local nums, strs = {}, {}
  for k in pairs(t) do
    if not (skip and type(k) == "number" and k >= 1 and k <= skip and k == math.floor(k)) then
      if type(k) == "number" then nums[#nums + 1] = k else strs[#strs + 1] = tostring(k) end
    end
  end
  table.sort(nums)
  table.sort(strs)
  return nums, strs
end

local function write(out, v, indent)
  local t = type(v)
  if t == "table" then
    out[#out + 1] = "{\n"
    local inner = indent .. "\t"
    local n = 0
    while v[n + 1] ~= nil do n = n + 1 end
    for i = 1, n do
      out[#out + 1] = inner
      write(out, v[i], inner)
      out[#out + 1] = ", -- [" .. i .. "]\n"
    end
    local nums, strs = sortedKeys(v, n)
    for _, k in ipairs(nums) do
      out[#out + 1] = inner .. keyText(k) .. " = "
      write(out, v[k], inner)
      out[#out + 1] = ",\n"
    end
    for _, k in ipairs(strs) do
      out[#out + 1] = inner .. keyText(k) .. " = "
      write(out, v[k], inner)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = indent .. "}"
  elseif t == "string" then
    out[#out + 1] = quote(v)
  elseif t == "number" then
    out[#out + 1] = number(v)
  elseif t == "boolean" then
    out[#out + 1] = tostring(v)
  else
    error("cannot save a " .. t)
  end
end

local function serialize(name, value)
  local out = { name, " = " }
  write(out, value, "")
  out[#out + 1] = "\n"
  return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- The market
-- ---------------------------------------------------------------------------
local function fillMarket(realm, count, days, rand)
  local ids = {}
  local first = TODAY - days + 1
  local function put(key, series)
    local h, l, a = {}, {}, {}
    local last
    for _, p in ipairs(series) do
      local d = tostring(p.day)
      h[d] = p.high
      if p.low < p.high then l[d] = p.low end
      if p.qty then a[d] = p.qty end
      last = p.low
    end
    realm[key] = { m = last, h = h, l = l, a = a }
  end

  -- the fixture's well known items keep their hand-made data
  for key, v in pairs(Fx.realm()) do realm[key] = v end

  for i = 1, count do
    local id = 20000 + i * 7
    local noun = NOUN[(i % #NOUN) + 1]
    local name = ADJ[(i * 3 % #ADJ) + 1] .. " " .. ADJ[(i % #ADJ) + 1]:lower() .. " " .. noun[1]
    Boot.ITEMS[id] = {
      name = name, quality = 1 + (i % 4), class = noun[2], sub = noun[3], sell = (i % 5) * 25, equip = noun[4],
    }
    ids[#ids + 1] = id
    local base = math.floor(math.exp(math.log(50) + rand() * (math.log(2000000) - math.log(50))))
    local fresh = (i % 25 == 0)                      -- seen for the first time on the newest day
    local thin = (i % 17 == 0)
    local series, price = {}, base
    local start = fresh and TODAY or first
    for day = start, TODAY do
      if day == TODAY or rand() > 0.1 then          -- a few missing days
        price = math.max(1, math.floor(price * (0.92 + rand() * 0.16)))
        if i % 11 == 0 and day == TODAY then price = math.floor(price * (1.4 + rand())) end   -- movers
        if i % 13 == 0 and day == TODAY then price = math.max(1, math.floor(price * 0.6)) end -- bargains
        local qty = thin and 1 or (5 + math.floor(rand() * 75))
        series[#series + 1] = { day = day, high = price, low = math.floor(price * (1 - rand() * 0.05)), qty = qty }
      end
    end
    for _, p in ipairs(series) do if p.low > p.high then p.low = p.high end end
    put(tostring(id), series)
    if i % 30 == 0 then                              -- gear at item levels
      put("g:" .. id .. ":" .. (40 + i % 20), { { day = TODAY, high = price * 2, low = price * 2, qty = 2 } })
    end
  end
  realm["g:12345:60"] = { m = 9000, h = { [tostring(TODAY)] = 9500 }, l = { [tostring(TODAY)] = 9000 }, a = { [tostring(TODAY)] = 3 } }
  realm["99999"] = { m = 4200, h = { [tostring(TODAY)] = 4200 }, l = {}, a = { [tostring(TODAY)] = 6 } }   -- no cached name
  ids[#ids + 1] = 99999
  return ids
end

-- ---------------------------------------------------------------------------
-- One fixture
-- ---------------------------------------------------------------------------
local function build(name, count, days, withPersonal)
  local rand = rng(20261125 + count)
  local A, env = Boot.boot({
    noReload = true,
    env = {
      UnitName = function() return "Thrall" end,
      GetRealmName = function() return REALM end,
      UnitFactionGroup = function() return "Horde" end,
      UnitClass = function() return "Shaman", "SHAMAN" end,
      GetAddOnMetadata = function(_, field) if field == "Version" then return "1.3.0" end end,
    },
  })
  env.Auctionator.State.CurrentRealm = REALM
  local realm = env.Auctionator.Database.db
  for k in pairs(realm) do realm[k] = nil end
  local ids = fillMarket(realm, count, days, rand)
  env.AUCTIONATOR_PRICE_DATABASE = { [REALM] = realm }

  A.Controller.Reload()
  env.C_Timer.flush()
  A.Items.EnsureAll(ids)
  for _ = 1, 40 do env.C_Timer.flush() end

  local meta = { realm = REALM, faction = "Horde", character = "Thrall-" .. REALM, today = TODAY, days = days }

  if withPersonal then
    local pick = function(n) return ids[(n * 37) % (#ids - 1) + 1] end
    local now = Fx.NOW

    -- sales, purchases, postings, expiries
    local ledger = 0
    local function add(e)
      e.char, e.realm = e.char or "Thrall", REALM
      if A.Ledger.Add(e) then ledger = ledger + 1 end
    end
    for n = 1, 12 do
      local id = pick(n)
      local qty = 1 + n % 4
      local total = (500 + n * 997) * qty
      add({ kind = "sold", source = "mail", itemID = id, itemName = Boot.ITEMS[id] and Boot.ITEMS[id].name or ("Item " .. id),
        qty = qty, total = total, fee = math.floor(total * 0.05), deposit = 30 * n, party = "Buyer" .. n,
        time = now - n * 7200, mailTime = now - n * 7200 })
    end
    for n = 1, 8 do
      local id = pick(n + 40)
      local qty = 1 + n % 3
      add({ kind = "bought", source = "ah", itemID = id, qty = qty, total = (300 + n * 411) * qty, time = now - n * 5400 - 60 })
    end
    local confirm = pick(41)
    add({ kind = "bought", source = "mail", itemID = confirm, itemName = Boot.ITEMS[confirm].name, qty = 2, total = (300 + 411) * 2,
      party = "Seller1", time = now - 5400 - 90 })        -- confirms the first unconfirmed purchase
    for n = 1, 6 do
      local id = pick(n + 80)
      add({ kind = "posted", source = "auctionator", itemID = id, qty = 5, total = 5 * (800 + n * 100), postKey = "post" .. n, time = now - n * 3000 })
    end
    for n = 1, 3 do
      local id = pick(n + 120)
      add({ kind = n == 1 and "cancelled" or "expired", source = "mail", itemID = id, itemName = Boot.ITEMS[id].name, qty = 3, time = now - n * 9000 - 17 })
    end
    meta.ledger = #A.db.ledger.entries

    -- who owns what
    local function counts(from, n) local c = {} for k = 0, n - 1 do c[pick(from + k)] = 1 + (from + k) % 6 end return c end
    for _, c in ipairs({
      { "Thrall", "SHAMAN", "Horde" }, { "Cairne", "WARRIOR", "Horde" }, { "Jaina", "MAGE", "Alliance" },
    }) do
      local key = A.Inventory.EnsureChar({ name = c[1], realm = REALM, class = c[2], faction = c[3] }).key
      A.Inventory.SetLocation(key, "bags", counts(200 + #c[1], 5), now - 600)
      A.Inventory.SetLocation(key, "bank", counts(300 + #c[1], 6), now - 86400)
      if c[1] == "Thrall" then
        A.Inventory.SetLocation(key, "mail", counts(400, 3), now - 3600)
        A.Inventory.SetLocation(key, "auctions", counts(500, 4), now - 1800)
        A.Inventory.SetLocation(key, "equipped", { [19019] = 1 }, now - 600)
      end
    end
    A.Inventory.SetGuildTab("The Fixtures-" .. REALM, "The Fixtures", 1, counts(600, 5), now - 7200)
    A.Inventory.SetWarband(counts(700, 4), now - 900)

    -- the watch list: four with details, one saved the old way
    for n = 1, 4 do
      local id = pick(n + 300)
      A.History.Watch(id, true, { price = 1000 * n, day = TODAY - n, time = now - n * 86400 })
    end
    A.db.history.watched[pick(305)] = true
    A.Main.OnDataReloaded()                           -- snapshots long-term history for tracked items

    -- price history older than Auctionator's 21 days, for a few tracked items
    local older = 0
    for id, entry in pairs(A.db.history.items) do
      if older < 3 then
        older = older + 1
        local price = 1000 * older
        for day = TODAY - 80, TODAY - days do
          price = math.max(1, math.floor(price * (0.95 + rand() * 0.1)))
          entry.h[day], entry.l[day], entry.a[day] = price, math.floor(price * 0.97), 10 + older
        end
      end
    end
  end

  assert(A.Export.Write() == "written", "the export block was not written")
  meta.exportItems = A.Export.last.items
  meta.pricedItems = A.Controller.pricedCount
  if withPersonal then
    meta.holders = 0
    for _ in pairs(A.db.chars) do meta.holders = meta.holders + 1 end
    meta.watched = #A.History.Watched()
    meta.historyItems = 0
    for _ in pairs(A.db.history.items) do meta.historyItems = meta.historyItems + 1 end
    meta.itemNames = 0
    for id in pairs(A.db.items) do if A.db.items[id][1] then meta.itemNames = meta.itemNames + 1 end end
  end

  local file = io.open(outDir .. "/" .. name .. ".lua", "w")
  assert(file, "cannot write to " .. outDir)
  file:write(serialize("ALMANAC_DB", A.db))
  file:close()

  local keys, parts = {}, {}
  for k in pairs(meta) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = meta[k]
    parts[#parts + 1] = string.format("  %q: %s", k, type(v) == "string" and string.format("%q", v) or tostring(v))
  end
  local m = io.open(outDir .. "/" .. name .. ".meta.json", "w")
  m:write("{\n" .. table.concat(parts, ",\n") .. "\n}\n")
  m:close()
  print(string.format("%s: %d priced items, export of %d, %d ledger entries", name, meta.pricedItems, meta.exportItems, meta.ledger or 0))
end

build("AuctionatorAlmanac", 600, 21, true)
build("AuctionatorAlmanac.small", 25, 3, true)
