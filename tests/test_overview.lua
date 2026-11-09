local H = require("harness")
local Boot = require("boot_ui")
local Fx = require("fixtures")
local test = H.test

local function plain(s)
  s = tostring(s):gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  return s
end

local rich = Boot.rich

local function ids(rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r.id end
  return out
end

local function has(rows, id)
  for _, r in ipairs(rows) do if r.id == id then return r end end
end

-- ---------------------------------------------------------------------------
-- The sections
-- ---------------------------------------------------------------------------
test("the overview has its sections in a fixed order", function()
  local A = rich()
  local keys = {}
  for _, def in ipairs(A.Overview.Sections()) do keys[#keys + 1] = def.key end
  H.eq(keys, { "movers", "deals", "newfinds", "watchlist", "activity", "inventory", "shopping" })
  for _, def in ipairs(A.Overview.Sections()) do
    H.truthy(def.title and def.title ~= "", def.key .. " has a title")
    H.truthy(#def.columns >= 2, def.key .. " has columns")
    H.eq(def.columns[1].key, "item", def.key .. " starts with the item")
    H.truthy(def.empty and def.empty ~= "", def.key .. " says why it can be empty")
  end
end)

test("movers and deals carry a Confidence column, and every column can be sorted", function()
  local A = rich()
  for _, key in ipairs({ "movers", "deals", "newfinds" }) do
    local def = A.Overview.Section(key)
    local found
    for _, col in ipairs(def.columns) do if col.key == "conf" then found = col end end
    H.truthy(found, key .. " has a Confidence column")
    H.eq(found.title, "Confidence")
  end
  for _, def in ipairs(A.Overview.Sections()) do
    for _, col in ipairs(def.columns) do
      H.eq(type(col.value), "function", def.key .. "." .. col.key .. " can be sorted")
      H.eq(type(col.text), "function", def.key .. "." .. col.key .. " can be shown")
    end
  end
end)

-- ---------------------------------------------------------------------------
-- Biggest movers
-- ---------------------------------------------------------------------------
test("movers lists risers and fallers with a confidence, trustworthy ones first", function()
  local A = rich()
  local rows = A.Overview.View("movers")
  local up, down, thin = has(rows, 20001), has(rows, 20003), has(rows, 20002)
  H.truthy(up and down and thin, "all three moved")
  H.truthy(has(rows, 20004), "and so did the bargain herb, which fell 40%")
  H.truthy(up.change > 0.25 and down.change < -0.25)
  H.truthy(up.conf.score >= 75 and down.conf.score >= 75)
  H.truthy(thin.conf.score <= 30)
  H.eq(rows[#rows].id, 20002, "the thin-market spike ranks last")
  H.eq(has(rows, 12359), nil, "a 2% wobble is not a move")
end)

test("a click on a column header sorts by it and the sort is remembered", function()
  local A = rich()
  local Ov = A.Overview
  H.eq({ Ov.GetSort("movers") }, { "rank", false }, "default: best first")
  Ov.SetSort("movers", "conf", true)
  local rows = Ov.View("movers")
  H.eq(ids(rows)[1], 20002, "lowest confidence first")
  Ov.SetSort("movers", "change", false)
  local byChange = Ov.View("movers")
  H.eq(byChange[1].id, 20002, "+100% is the biggest rise")
  H.eq(byChange[#byChange].id, 20004, "the 40% fall is last")
  Ov.SetSort("movers", "change", true)
  H.eq(Ov.View("movers")[1].id, 20004)
  Ov.SetSort("movers", "item", true)
  H.eq(ids(Ov.View("movers")), { 20004, 20003, 20001, 20002 }, "Bargain Herb, Falling Cloth, Rising Bar, Thin Spike")
  Ov.SetSort("movers", "price", false)
  H.eq(Ov.View("movers")[1].id, 20002)
  H.eq({ Ov.GetSort("movers") }, { "price", false })
end)

test("sort choices are kept in the saved data", function()
  local A = rich()
  A.Overview.SetSort("deals", "price", true)
  H.eq(A.db.ui.overview.sort.deals, { "price", true })
end)

test("a sort key the section does not have falls back to the default", function()
  local A = rich()
  A.Overview.SetSort("movers", "nonsense", true)
  H.eq({ A.Overview.GetSort("movers") }, { "rank", false })
  A.db.ui.overview.sort.deals = "garbage"
  H.nothrows(function() A.Overview.View("deals") end)
end)

test("the compact table shows only the top few rows under the current sort; the full view shows all", function()
  local A = rich()
  local Ov = A.Overview
  local def = Ov.Section("movers")
  local compact, total = Ov.Compact("movers")
  H.truthy(#compact <= def.limit)
  H.eq(total, 4)
  Ov.Section("movers").limit = 2
  local limited, all = Ov.Compact("movers")
  H.eq(#limited, 2)
  H.eq(all, 4)
  H.eq(#Ov.View("movers", { expanded = true }), 4)
  Ov.Section("movers").limit = def.limit
end)

test("a sort click re-ranks the whole list before the top rows are taken", function()
  local A = rich()
  local Ov = A.Overview
  Ov.Section("movers").limit = 1
  Ov.SetSort("movers", "conf", true)
  H.eq(Ov.Compact("movers")[1].id, 20002, "the top row is the lowest confidence of all, not of a pre-picked few")
  Ov.Section("movers").limit = 6
end)

test("search narrows a full list by item name", function()
  local A = rich()
  local Ov = A.Overview
  H.eq(ids(Ov.View("movers", { expanded = true, query = "rising" })), { 20001 })
  H.eq(#Ov.View("movers", { expanded = true, query = "RISING BAR" }), 1, "case and word order do not matter")
  H.eq(#Ov.View("movers", { expanded = true, query = "bar rising" }), 1)
  H.eq(#Ov.View("movers", { expanded = true, query = "zzz" }), 0)
  H.eq(#Ov.View("movers", { expanded = true, query = "  " }), 4, "blank means everything")
  local _, total = Ov.View("movers", { expanded = true, query = "zzz" })
  H.eq(total, 4, "the total is what the section holds, whatever the search")
end)

test("movers can be limited to risers or fallers, and to a minimum confidence", function()
  local A = rich()
  local Ov = A.Overview
  H.eq(ids(Ov.View("movers", { expanded = true, filters = { dir = "up" } }))[1], 20001)
  H.eq(#Ov.View("movers", { expanded = true, filters = { dir = "up" } }), 2, "Rising Bar and Thin Spike rose")
  local falls = ids(Ov.View("movers", { expanded = true, filters = { dir = "down" } }))
  table.sort(falls)
  H.eq(falls, { 20003, 20004 })
  local solid = Ov.View("movers", { expanded = true, filters = { minConf = 60 } })
  H.eq(#solid, 3)
  H.eq(has(solid, 20002), nil, "the thin spike is filtered out")
end)

test("filter choices live in the section and are saved", function()
  local A = rich()
  local Ov = A.Overview
  Ov.SetFilter("movers", "minConf", 60)
  H.eq(Ov.GetFilter("movers", "minConf"), 60)
  H.eq(#Ov.View("movers", { expanded = true }), 3, "the saved filter applies to the full list")
  H.eq(#Ov.View("movers"), 4, "the compact table is never hidden behind a filter")
  H.eq(A.db.ui.overview.filters.movers.minConf, 60)
end)

test("rows are built once and rebuilt only when the data changes", function()
  local A, env = rich()
  local first = A.Overview.Rows("movers")
  H.eq(A.Overview.Rows("movers"), first, "cached")
  A.Bus.Fire("DATA_RELOADED")
  H.truthy(A.Overview.Rows("movers") ~= first, "rebuilt after a reload")
end)

-- ---------------------------------------------------------------------------
-- Below their average
-- ---------------------------------------------------------------------------
test("deals lists items under their average with a confidence", function()
  local A = rich()
  local rows = A.Overview.View("deals")
  H.eq(ids(rows), { 20004, 20003 }, "the herb at 40% off, then the cloth at 27% off")
  H.truthy(rows[1].ratio < 0.7)
  H.truthy(rows[1].conf.score >= 70)
  H.eq(A.Overview.Section("deals").title, "Below their average")
end)

test("deals sort by how deep the discount is", function()
  local A = rich()
  A.Overview.SetSort("deals", "vsavg", true)
  H.eq(A.Overview.View("deals")[1].id, 20004)
  H.eq(A.Overview.Section("deals").columns[3].key, "vsavg")
end)

-- ---------------------------------------------------------------------------
-- New finds
-- ---------------------------------------------------------------------------
test("new finds are the items first seen on the last scan, rare ones first", function()
  local A = rich()
  local rows = A.Overview.View("newfinds")
  local got = ids(rows)
  table.sort(got)
  H.eq(got, { 12363, 15001, 20005, 20006 }, "Arcane Crystal, Eagle Pants, the crown and the pebble")
  H.eq(rows[1].id, 20005, "the epic comes first")
  H.eq(rows[2].id, 12363, "then the rare")
  H.eq(rows[1].first, 1005)
end)

test("new finds have a confidence like the other lists", function()
  local A = rich()
  local row = has(A.Overview.View("newfinds"), 20005)
  H.eq(type(row.conf.score), "number")
  H.truthy(#row.conf.reasons >= 1)
end)

test("new finds can be widened to recent days and narrowed by quality", function()
  local A = rich()
  local Ov = A.Overview
  Ov.SetFilter("newfinds", "quality", 4)
  H.eq(ids(Ov.View("newfinds", { expanded = true })), { 20005 }, "epic or better")
  Ov.SetFilter("newfinds", "quality", nil)
  Ov.SetFilter("newfinds", "window", 0)
  H.eq(#Ov.View("newfinds", { expanded = true }), 4)
end)

test("the new-finds window applies to the compact table as well", function()
  local A = rich()
  local Ov = A.Overview
  -- put Fresh Pebble's first sighting a few days back
  A.db.discovery.first[20006] = 1002
  Ov.Invalidate()
  H.eq(has(Ov.View("newfinds"), 20006), nil, "not new on the last scan")
  Ov.SetFilter("newfinds", "window", 3)
  H.truthy(has(Ov.View("newfinds"), 20006), "within three days")
  H.truthy(has(Ov.Compact("newfinds"), 20006))
end)

test("with one day of data new finds explains that it needs another scan", function()
  local A, env = Boot.boot({ fixture = { AUCTIONATOR_PRICE_DATABASE = nil } })
  local realm = env.AUCTIONATOR_PRICE_DATABASE.TestRealm
  for _, entry in pairs(realm) do
    if type(entry) == "table" then
      entry.h, entry.l, entry.a = { ["1005"] = entry.m or 100 }, {}, { ["1005"] = 5 }
    end
  end
  A.Discovery.Reset()
  A.Controller.Reload()
  env.C_Timer.flush()
  H.eq(#A.Overview.View("newfinds"), 0)
  local lead = table.concat(A.Overview.Lead("newfinds"), " "):lower()
  H.truthy(lead:find("another scan", 1, true) or lead:find("second scan", 1, true), lead)
end)

test("a scan where nearly everything is new carries a warning", function()
  local A, env = Boot.boot({ noReload = true })
  local realm = env.AUCTIONATOR_PRICE_DATABASE.TestRealm
  for id = 1, 60 do
    local day = (id == 1) and 1000 or 1005
    realm[tostring(30000 + id)] = { m = 500, h = { [tostring(day)] = 500, ["1005"] = 500 }, l = {}, a = { ["1005"] = 9 } }
    Boot.ITEMS[30000 + id] = { name = "Bulk " .. id, quality = 1, class = 7, sub = 7, sell = 0 }
  end
  realm["30001"].h = { ["1000"] = 500, ["1005"] = 500 }
  for id = 2, 60 do realm[tostring(30000 + id)].h = { ["1005"] = 500 } end
  A.Controller.Reload()
  env.C_Timer.flush()
  local lead = table.concat(A.Overview.Lead("newfinds"), " "):lower()
  H.truthy(lead:find("scan", 1, true) and lead:find("new", 1, true), lead)
end)

-- ---------------------------------------------------------------------------
-- Watchlist
-- ---------------------------------------------------------------------------
test("the watchlist shows watched items with how they have moved since they were added", function()
  local A = rich()
  local Ov = A.Overview
  H.eq(#Ov.View("watchlist"), 0)
  A.History.Watch(20001, true, { price = 1000, day = 1000, time = Fx.NOW - 5 * 86400 })
  local rows = Ov.View("watchlist")
  H.eq(#rows, 1, "the list updates when something is watched")
  H.eq(rows[1].id, 20001)
  H.near(rows[1].since, 1300 / 1000 - 1)
  H.eq(rows[1].added, 1000)
  A.History.Watch(20001, false)
  H.eq(#Ov.View("watchlist"), 0, "and when it is dropped")
end)

test("a watched item with no known starting price still appears", function()
  local A = rich()
  A.History.Watch(20001, true)
  local rows = A.Overview.View("watchlist")
  H.eq(rows[1].id, 20001)
  H.eq(rows[1].since, nil)
  H.eq(plain(A.Overview.Section("watchlist").columns[3].text(rows[1])), "—")
end)

test("a watched item Auctionator has no price for yet is still listed", function()
  local A = rich()
  A.History.Watch(99999, true)
  local rows = A.Overview.View("watchlist")
  H.eq(rows[1].id, 99999)
  H.eq(rows[1].price, nil)
end)

-- ---------------------------------------------------------------------------
-- Recent activity
-- ---------------------------------------------------------------------------
local function seedLedger(A)
  local now = Fx.NOW
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 20, total = 220000, time = now - 3600, source = "mail", party = "Buyer", char = "T" })
  A.Ledger.Add({ kind = "bought", itemID = 12363, qty = 1, total = 1400000, time = now - 86400 * 2, source = "ah", char = "T" })
  A.Ledger.Add({ kind = "posted", itemID = 12359, qty = 20, total = 230000, time = now - 100, source = "auctionator" })
  A.Ledger.Add({ kind = "expired", itemID = 10620, qty = 5, time = now - 86400 * 3, source = "mail", char = "T" })
  A.Ledger.Add({ kind = "cancelled", itemName = "Mystery Goods", qty = 2, time = now - 86400 * 4, source = "mail", char = "T" })
  A.Bus.Fire("LEDGER_UPDATED")
end

test("recent activity in the overview is sales and purchases, newest first", function()
  local A = rich()
  seedLedger(A)
  local rows = A.Overview.Compact("activity")
  H.eq(#rows, 2, "postings, expiries and cancellations are not in the short list")
  H.eq(rows[1].kind, "sold")
  H.eq(rows[2].kind, "bought")
end)

test("the full activity list holds everything and can be filtered by type", function()
  local A = rich()
  seedLedger(A)
  local Ov = A.Overview
  local all = Ov.View("activity", { expanded = true })
  H.eq(#all, 5, "sold, bought, posted, expired, cancelled")
  H.eq(all[1].kind, "posted", "newest first")
  H.eq(#Ov.View("activity", { expanded = true, filters = { type = "sold" } }), 1)
  H.eq(#Ov.View("activity", { expanded = true, filters = { type = "trades" } }), 2)
  H.eq(#Ov.View("activity", { expanded = true, filters = { type = "expired" } }), 1)
end)

test("activity can be searched by item name, including items Almanac could not identify", function()
  local A = rich()
  seedLedger(A)
  local Ov = A.Overview
  H.eq(#Ov.View("activity", { expanded = true, query = "thorium" }), 3, "Thorium Bar sold and posted, Thorium Ore expired")
  H.eq(#Ov.View("activity", { expanded = true, query = "thorium bar" }), 2)
  H.eq(#Ov.View("activity", { expanded = true, query = "mystery" }), 1)
  H.eq(#Ov.View("activity", { expanded = true, query = "buyer" }), 1, "and by who you traded with")
end)

test("activity columns show the event, quantity, total and when", function()
  local A = rich()
  seedLedger(A)
  local def = A.Overview.Section("activity")
  local row = A.Overview.Compact("activity")[1]
  local text = {}
  for _, col in ipairs(def.columns) do text[col.key] = plain(col.text(row)) end
  H.truthy(text.event:find("Sold", 1, true) and text.event:find("20", 1, true), text.event)
  H.truthy(text.total:find("22g", 1, true), text.total)
  H.eq(text.when, "1h")
end)

-- ---------------------------------------------------------------------------
-- Inventory and shopping lists
-- ---------------------------------------------------------------------------
test("inventory lists what you own by value and says what it is worth", function()
  local A = rich()
  A.Inventory.EnsureChar({ name = "Thornwick", realm = "Whitemane" })
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [12359] = 14, [12363] = 1, [19019] = 1, [55555] = 9 }, 1)
  A.Bus.Fire("INVENTORY_UPDATED")
  local rows = A.Overview.View("inventory")
  H.eq(ids(rows), { 19019, 12363, 12359 }, "most valuable first")
  H.eq(rows[3].count, 14)
  local lead = plain(table.concat(A.Overview.Lead("inventory"), " "))
  H.truthy(lead:find("worth", 1, true), lead)
  H.truthy(lead:find("without", 1, true) or lead:find("no auction price", 1, true), "mentions the unpriced item")
end)

test("an empty inventory explains how it fills", function()
  local A = rich()
  H.eq(#A.Overview.View("inventory"), 0)
  H.truthy(plain(table.concat(A.Overview.Lead("inventory"), " ")):lower():find("bags", 1, true))
end)

test("shopping lists show each term with its current price, grouped by list", function()
  local A = rich()
  local rows = A.Overview.View("shopping")
  H.eq(rows[1].list, "Smithing")
  H.eq(rows[1].id, 12359, "an exact term resolves to Thorium Bar")
  H.eq(rows[2].id, 12363, "a plain term resolves by name")
  H.eq(A.Overview.Section("shopping").group(rows[1]), "Smithing")
  H.near(rows[1].price, 11240)
end)

test("a shopping term with no match is listed, not dropped", function()
  local A = rich()
  A.Overview.Invalidate()
  A.env.AUCTIONATOR_SHOPPING_LISTS = { { name = "Odd", items = { "Nonexistent Thing" } } }
  A.Overview.Invalidate()
  local rows = A.Overview.View("shopping")
  H.eq(#rows, 1)
  H.eq(rows[1].id, nil)
  H.truthy(plain(A.Overview.Section("shopping").columns[1].text(rows[1])):find("Nonexistent Thing", 1, true))
end)

test("the overview data works with no Auctionator data at all", function()
  local A = Boot.boot({ fixture = { Auctionator = false } })
  for _, def in ipairs(A.Overview.Sections()) do
    H.nothrows(function()
      A.Overview.View(def.key)
      A.Overview.Compact(def.key)
      A.Overview.Lead(def.key)
    end)
  end
end)

-- ---------------------------------------------------------------------------
-- Rebuilding at the right moments
-- ---------------------------------------------------------------------------
test("new finds are rebuilt when item names arrive, since each find is judged against its category", function()
  local A = rich()
  local first = A.Overview.Rows("newfinds")
  A.Bus.Fire("ITEM_NAMES_UPDATED")
  H.truthy(A.Overview.Rows("newfinds") ~= first)
  local movers = A.Overview.Rows("movers")
  A.Bus.Fire("ITEM_NAMES_UPDATED")
  H.eq(A.Overview.Rows("movers"), movers, "movers do not depend on names, so they are kept")
end)

test("new finds are rebuilt after the first-seen memory is updated, not before", function()
  local A = rich()
  local before = A.Overview.Rows("newfinds")
  A.Main.OnDataReloaded()
  H.truthy(A.Overview.Rows("newfinds") ~= before, "rebuilt once Almanac has noted what it saw")
end)

test("a list built before anything was remembered is corrected, not stuck", function()
  local A, env = Boot.boot({ noReload = true })
  A.Discovery.Reset()
  A.Controller.Reload()
  env.C_Timer.flush()
  -- on a first-ever load nothing is remembered yet when the reload event goes out; building
  -- the list at that moment must not leave it stuck saying "needs another scan"
  A.Discovery.Reset()
  local stuck = A.Overview.Rows("newfinds")
  H.eq(#stuck, 0)
  A.Main.OnDataReloaded()
  H.truthy(#A.Overview.Rows("newfinds") > 0, "Arcane Crystal first appeared on the newest day")
end)

-- ---------------------------------------------------------------------------
-- Recent activity: a short "when", and how the price compared with the latest scan
-- ---------------------------------------------------------------------------
local function activityText(A, row)
  local out = {}
  for _, col in ipairs(A.Overview.Section("activity").columns) do out[col.key] = plain(col.text(row)) end
  return out
end

local function addSale(A, spec)
  local e = { kind = spec.kind or "sold", itemID = spec.id, qty = spec.qty or 1, total = spec.total,
    time = Fx.NOW - (spec.ago or 3600), source = "mail", party = "Someone", char = "T" }
  A.Ledger.Add(e)
  A.Bus.Fire("LEDGER_UPDATED")
end

test("activity shows when as minutes, then a single unit", function()
  local A = rich()
  local cases = {
    { 45 * 60, "45m" }, { 3600, "1h" }, { 15 * 3600 + 20 * 60, "15h" }, { 2 * 86400 + 3 * 3600, "2d" }, { 9 * 86400, "1w" },
  }
  for i, c in ipairs(cases) do addSale(A, { id = 12359, qty = i, total = 1000 * i, ago = c[1] }) end
  local seen = {}
  for _, row in ipairs(A.Overview.View("activity", { expanded = true })) do seen[#seen + 1] = activityText(A, row).when end
  table.sort(seen)
  local want = {}
  for _, c in ipairs(cases) do want[#want + 1] = c[2] end
  table.sort(want)
  H.eq(seen, want)
end)

test("a sale shows how far above or below the latest scan price it went", function()
  local A = rich()
  -- Thorium Bar's lowest price in the latest scan is 11,240 each
  addSale(A, { id = 12359, qty = 20, total = 20 * 12382 })       -- sold 10% above
  local row = A.Overview.View("activity", { expanded = true })[1]
  H.near(row.vsNow, 12382 / 11240 - 1, 1e-9)
  H.eq(activityText(A, row).vsnow, "+10%")
end)

test("selling below the latest scan price is a negative percentage", function()
  local A = rich()
  addSale(A, { id = 12359, qty = 10, total = 10 * 10116 })       -- sold 10% below
  H.eq(activityText(A, A.Overview.View("activity", { expanded = true })[1]).vsnow, "-10%")
end)

test("green means it went your way: sold high or bought low", function()
  local A = rich()
  local good, bad = A.UI.Theme.hex.good, A.UI.Theme.hex.bad
  local function colourOf(row)
    local raw = A.Overview.Section("activity").columns
    for _, col in ipairs(raw) do
      if col.key == "vsnow" then return col.text(row) end
    end
  end
  addSale(A, { kind = "sold", id = 12359, qty = 1, total = 12382, ago = 100 })       -- sold above: good
  addSale(A, { kind = "sold", id = 12359, qty = 1, total = 10116, ago = 200 })       -- sold below: bad
  addSale(A, { kind = "bought", id = 12363, qty = 1, total = 1200000, ago = 300 })   -- bought 20% under 1,500,000: good
  addSale(A, { kind = "bought", id = 12363, qty = 1, total = 1650000, ago = 400 })   -- bought 10% over: bad
  local rows = A.Overview.View("activity", { expanded = true, sortKey = "when", asc = false })
  H.truthy(colourOf(rows[1]):find(good, 1, true), "sold above the scan is green: " .. colourOf(rows[1]))
  H.truthy(colourOf(rows[2]):find(bad, 1, true), "sold below is red")
  H.eq(plain(colourOf(rows[3])), "-20%")
  H.truthy(colourOf(rows[3]):find(good, 1, true), "bought cheaper is green even though the sign is minus")
  H.eq(plain(colourOf(rows[4])), "+10%")
  H.truthy(colourOf(rows[4]):find(bad, 1, true), "bought dearer is red")
end)

test("a posting is compared too, but is not judged good or bad", function()
  local A = rich()
  addSale(A, { kind = "posted", id = 12359, qty = 5, total = 5 * 11800 })
  local row = A.Overview.View("activity", { expanded = true })[1]
  local text = A.Overview.Section("activity").columns
  local cell
  for _, col in ipairs(text) do if col.key == "vsnow" then cell = col.text(row) end end
  H.eq(plain(cell), "+5%")
  H.falsy(cell:find(A.UI.Theme.hex.good, 1, true) or cell:find(A.UI.Theme.hex.bad, 1, true), cell)
end)

test("entries with no price to compare show a dash", function()
  local A = rich()
  addSale(A, { kind = "expired", id = 10620, qty = 5, ago = 100 })                            -- no money involved
  addSale(A, { kind = "sold", id = 99999, qty = 1, total = 5000, ago = 200 })                 -- Auctionator has no price
  A.Ledger.Add({ kind = "cancelled", itemName = "Mystery Goods", qty = 2, time = Fx.NOW - 300, source = "mail", char = "T" })
  A.Bus.Fire("LEDGER_UPDATED")
  for _, row in ipairs(A.Overview.View("activity", { expanded = true })) do
    H.eq(activityText(A, row).vsnow, "—", row.kind)
    H.eq(row.vsNow, nil)
  end
end)

test("the comparison column sorts, with unknowns last", function()
  local A = rich()
  addSale(A, { id = 12359, qty = 1, total = 12382, ago = 100 })      -- +10%
  addSale(A, { id = 12359, qty = 1, total = 10116, ago = 200 })      -- -10%
  addSale(A, { kind = "expired", id = 10620, qty = 1, ago = 300 })   -- nothing to compare
  A.Overview.SetSort("activity", "vsnow", false)
  local rows = A.Overview.View("activity", { expanded = true })
  H.near(rows[1].vsNow, 0.10, 0.01)
  H.near(rows[2].vsNow, -0.10, 0.01)
  H.eq(rows[3].vsNow, nil)
  A.Overview.SetSort("activity", "vsnow", true)
  rows = A.Overview.View("activity", { expanded = true })
  H.near(rows[1].vsNow, -0.10, 0.01)
  H.eq(rows[3].vsNow, nil, "unknowns stay last either way")
end)

test("the comparison follows the latest scan, not the price when the data was first loaded", function()
  local A, env = rich()
  addSale(A, { id = 12359, qty = 1, total = 12000 })
  local before = A.Overview.View("activity", { expanded = true })[1].vsNow
  env.AUCTIONATOR_PRICE_DATABASE.TestRealm["12359"].m = 24000
  A.Controller.Reload()
  env.C_Timer.flush()
  local after = A.Overview.View("activity", { expanded = true })[1].vsNow
  H.near(before, 12000 / 11240 - 1, 1e-9)
  H.near(after, 12000 / 24000 - 1, 1e-9)
end)

test("hovering an activity row says in words how it compared", function()
  local A = rich()
  addSale(A, { kind = "sold", id = 12359, qty = 1, total = 12382, ago = 600 })
  addSale(A, { kind = "bought", id = 12363, qty = 1, total = 1200000, ago = 3600 })
  local def = A.Overview.Section("activity")
  local rows = A.Overview.View("activity", { expanded = true, sortKey = "when", asc = false })
  local sold = plain(table.concat(def.tip(rows[1]), " "))
  H.truthy(sold:find("sold", 1, true) and sold:find("above", 1, true), sold)
  H.truthy(sold:find("1g 12s 40c", 1, true), "names the scan price: " .. sold)
  local bought = plain(table.concat(def.tip(rows[2]), " "))
  H.truthy(bought:find("bought", 1, true) and bought:find("below", 1, true), bought)
end)

test("an activity row with nothing to compare has no comparison in its tooltip", function()
  local A = rich()
  addSale(A, { kind = "expired", id = 10620, qty = 5 })
  local row = A.Overview.View("activity", { expanded = true })[1]
  local tip = A.Overview.Section("activity").tip(row)
  H.truthy(tip == nil or not plain(table.concat(tip, " ")):find("scan", 1, true))
end)
