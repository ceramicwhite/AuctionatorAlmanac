local ADDON, A = ...

-- What the overview shows, as data: seven sections (movers, deals, new finds, watchlist,
-- recent activity, inventory, shopping lists), each a table with columns, rows, a sort,
-- optional filters and a search. The window draws them; nothing here touches a widget.
--
-- A section is shown twice: as a short "compact" table on the overview (the top few rows
-- under the player's chosen sort) and as a full list with a search box and filters.
-- Rows are built once per data change and cached; sorted and filtered views are cached too.
local Fmt = A.Format
local Overview = {}
A.Overview = Overview

local LIMIT = 6
local DASH = "—"

local sections, byKey = {}, {}
local rowCache, viewCache = {}, {}
local resolved = {}           -- shopping-list term -> item id | false
local extra = {}              -- facts a section's builder found out, for its lead lines

local function Ct() return A.Controller end

local function now() return (time and time()) or 0 end

-- Theme lives in the UI layer; it is looked up when text is made so this file does not depend
-- on load order.
local function theme() return A.UI and A.UI.Theme end
local function hex(name)
  local T = theme()
  return T and T.hex[name] or "ffffff"
end
local function colorize(text, color)
  local T = theme()
  return T and T.Colorize(text, color) or tostring(text)
end

-- ---------------------------------------------------------------------------
-- Saved choices: sorts and filters
-- ---------------------------------------------------------------------------
local function saved()
  local root = A.db and A.db.ui
  if type(root) ~= "table" then return { filters = {}, sort = {} } end
  if type(root.overview) ~= "table" then root.overview = {} end
  local o = root.overview
  if type(o.filters) ~= "table" then o.filters = {} end
  if type(o.sort) ~= "table" then o.sort = {} end
  return o
end

local function sortValueFn(def, key)
  for _, col in ipairs(def.columns) do
    if col.key == key then return col.value end
  end
  return def.hidden and def.hidden[key] or nil
end

-- colKey, ascending: what the section is sorted by (the default until the player clicks a header).
function Overview.GetSort(key)
  local def = byKey[key]
  if not def then return nil end
  local choice = saved().sort[key]
  if type(choice) == "table" and sortValueFn(def, choice[1]) then
    return choice[1], choice[2] and true or false
  end
  return def.sort[1], def.sort[2]
end

function Overview.SetSort(key, colKey, ascending)
  local def = byKey[key]
  if not (def and sortValueFn(def, colKey)) then return false end
  saved().sort[key] = { colKey, ascending and true or false }
  Overview.InvalidateViews(key)
  return true
end

local function findFilter(def, fkey)
  for _, f in ipairs(def.filters or {}) do
    if f.key == fkey then return f end
  end
end

function Overview.GetFilter(key, fkey)
  local def = byKey[key]
  local f = def and findFilter(def, fkey)
  if not f then return nil end
  local choices = saved().filters[key]
  local value
  if type(choices) == "table" then value = choices[fkey] end
  if value == nil then return f.default end
  return value
end

function Overview.SetFilter(key, fkey, value)
  local def = byKey[key]
  local f = def and findFilter(def, fkey)
  if not f then return false end
  local o = saved()
  if type(o.filters[key]) ~= "table" then o.filters[key] = {} end
  o.filters[key][fkey] = value
  if f.rebuild then Overview.Invalidate(key) else Overview.InvalidateViews(key) end
  return true
end

-- ---------------------------------------------------------------------------
-- Cache
-- ---------------------------------------------------------------------------
function Overview.InvalidateViews(key)
  if not key then
    viewCache = {}
    return
  end
  local prefix = key .. "|"
  for sig in pairs(viewCache) do
    if sig:sub(1, #prefix) == prefix then viewCache[sig] = nil end
  end
end

-- One section, or all of them when key is nil.
function Overview.Invalidate(key)
  if key then
    rowCache[key] = nil
    extra[key] = nil
  else
    rowCache, extra = {}, {}
  end
  Overview.InvalidateViews(key)
end

A.Bus.On("DATA_RELOADED", function()
  resolved = {}
  Overview.Invalidate()
end)
A.Bus.On("LEDGER_UPDATED", function() Overview.Invalidate("activity") end)
A.Bus.On("INVENTORY_UPDATED", function() Overview.Invalidate("inventory") end)
A.Bus.On("WATCH_CHANGED", function() Overview.Invalidate("watchlist") end)
A.Bus.On("ITEM_NAMES_UPDATED", function()
  resolved = {}
  Overview.Invalidate("shopping")
  Overview.Invalidate("newfinds")     -- each find is judged against its category, which names bring in
  Overview.InvalidateViews()      -- names decide the order when sorting by item, and break ties
end)

-- ---------------------------------------------------------------------------
-- Shared pieces
-- ---------------------------------------------------------------------------
local function itemName(row)
  if row.id then
    local info = Ct().Info(row.id)
    if info and info.lname then return info.lname end
  end
  return (row.name or row.term or ""):lower()
end

local function itemText(row)
  if row.id then
    local info = Ct().Info(row.id)
    if info and info.name then return Fmt.ColorName(info.name, info.quality) end
    return colorize("Item " .. row.id, hex("dim"))
  end
  if row.term then return colorize(row.term .. " (no match)", hex("dim")) end
  return row.name or "item"
end

local function itemColumn()
  return { key = "item", title = "Item", flex = 1, align = "LEFT", defaultAsc = true, value = itemName, text = itemText }
end

local function moneyColumn(key, title, field, width, opts)
  opts = opts or {}
  return {
    key = key, title = title, width = width or 62, align = "RIGHT", defaultAsc = false, compact = opts.compact,
    value = function(row) return row[field] end,
    text = function(row) return row[field] and Fmt.Money(row[field], { short = true }) or DASH end,
  }
end

local function confColumn()
  return {
    key = "conf", title = "Confidence", width = 84, align = "RIGHT", defaultAsc = false,
    value = function(row) return row.conf and row.conf.score or nil end,
    text = function(row)
      local c = row.conf
      if not c then return DASH end
      local color = c.label == "high" and hex("good") or (c.label == "medium" and hex("amber") or hex("bad"))
      return colorize(tostring(c.score), color)
    end,
  }
end

local function qtyColumn()
  return {
    key = "qty", title = "Qty", width = 48, align = "RIGHT", defaultAsc = false, compact = false,
    value = function(row) return row.qty end,
    text = function(row) return row.qty and Fmt.Count(row.qty) or DASH end,
  }
end

local function confTip(row, headline)
  local c = row.conf
  if not c then return nil end
  local lines = { "Confidence " .. c.score .. " (" .. c.label .. ")" }
  for _, reason in ipairs(c.reasons or {}) do lines[#lines + 1] = reason end
  if headline then table.insert(lines, 2, headline) end
  return lines
end

local function priced()
  local list = {}
  local Controller = Ct()
  for _, id in ipairs(Controller.ids) do
    local s = Controller.summaries[id]
    if s then list[#list + 1] = { id = id, s = s } end
  end
  return list
end

-- ---------------------------------------------------------------------------
-- Defining sections
-- ---------------------------------------------------------------------------
local function add(def)
  def.limit = def.limit or LIMIT
  def.lead = def.lead or function() return {} end
  sections[#sections + 1] = def
  byKey[def.key] = def
end

-- ----- Biggest movers -----
add({
  key = "movers", title = "Biggest movers (7 days)",
  note = "Ranked by size and trust. Click a column to sort.",
  hint = "Best first: size of the move weighed by how far it can be trusted. Click a column to re-sort.",
  empty = "No big movers yet; this needs a few days of scans.",
  sort = { "rank", false },
  hidden = { rank = function(row) return row.rank end },
  columns = {
    itemColumn(),
    moneyColumn("price", "Price", "price"),
    {
      key = "change", title = "7d", width = 46, align = "RIGHT", defaultAsc = false,
      value = function(row) return row.change end,
      text = function(row) return Fmt.Change(row.change) end,
    },
    confColumn(),
    qtyColumn(),
    {
      key = "seen", title = "Seen", width = 46, align = "RIGHT", defaultAsc = true, compact = false,
      value = function(row) return row.age end,
      text = function(row)
        if not row.age then return DASH end
        return row.age <= 0 and "today" or (row.age .. "d")
      end,
    },
  },
  filters = {
    {
      key = "dir", title = "Show",
      options = { { label = "Rises and falls" }, { value = "up", label = "Rises" }, { value = "down", label = "Falls" } },
      test = function(row, v)
        if v == "up" then return row.change > 0 end
        if v == "down" then return row.change < 0 end
        return true
      end,
    },
    {
      key = "minConf", title = "Confidence",
      options = { { label = "Any" }, { value = 40, label = "40+" }, { value = 60, label = "60+" }, { value = 80, label = "80+" } },
      test = function(row, v) return row.conf.score >= v end,
    },
  },
  tip = function(row)
    local lines = confTip(row)
    if lines and row.s and row.s.base then
      table.insert(lines, 2, "Now " .. Fmt.Money(row.price, { plain = true }) .. " against a recent average of "
        .. Fmt.Money(math.floor(row.s.base), { plain = true }))
    end
    return lines
  end,
  build = function()
    local rows = A.Stats.MoverRows(priced(), { newestDay = Ct().newestDay })
    for _, row in ipairs(rows) do
      row.price, row.qty, row.age = row.s.last, row.s.qty, row.s.ageDays
    end
    return rows
  end,
})

-- ----- Below their average -----
add({
  key = "deals", title = "Below their average",
  note = "Ranked by discount and trust. Click a column to sort.",
  hint = "Best first: depth of the discount weighed by how far it can be trusted. Click a column to re-sort.",
  empty = "Nothing is priced well below its average.",
  sort = { "rank", false },
  hidden = { rank = function(row) return row.rank end },
  columns = {
    itemColumn(),
    moneyColumn("price", "Price", "price"),
    {
      key = "vsavg", title = "vs avg", width = 50, align = "RIGHT", defaultAsc = true,
      value = function(row) return row.ratio end,
      text = function(row) return colorize(Fmt.Percent(row.ratio - 1), hex("good")) end,
    },
    confColumn(),
    moneyColumn("avg", "Average", "avg", 72, { compact = false }),
    qtyColumn(),
  },
  filters = {
    {
      key = "minConf", title = "Confidence",
      options = { { label = "Any" }, { value = 40, label = "40+" }, { value = 60, label = "60+" }, { value = 80, label = "80+" } },
      test = function(row, v) return row.conf.score >= v end,
    },
  },
  tip = function(row) return confTip(row) end,
  build = function()
    local rows = A.Stats.DealRows(priced(), { newestDay = Ct().newestDay })
    for _, row in ipairs(rows) do
      row.price, row.avg, row.qty = row.s.last, row.s.avg, row.s.qty
    end
    return rows
  end,
})

-- ----- New finds -----
local function className(class)
  local item = C_Item
  local get = item and item.GetItemClassInfo
  if not get then return nil end
  local ok, name = pcall(get, class)
  return ok and name or nil
end

add({
  key = "newfinds", title = "New finds",
  note = "Rarest first. Confidence says how sure it is new.",
  hint = "Items Auctionator saw for the first time on the last scan, rarest first.",
  empty = "Nothing new on the last scan.",
  sort = { "rank", false },
  hidden = {
    rank = function(row)
      local info = Ct().Info(row.id)
      return ((info and info.quality) or 0) * 1000 + (row.conf and row.conf.score or 0)
    end,
  },
  columns = {
    itemColumn(),
    moneyColumn("price", "Price", "price"),
    confColumn(),
    qtyColumn(),
    {
      key = "found", title = "Found", width = 62, align = "RIGHT", defaultAsc = false, compact = false,
      value = function(row) return row.first end,
      text = function(row) return Fmt.Date(A.Adapter.DayToTime(row.first)) end,
    },
  },
  filters = {
    {
      key = "window", title = "Found", default = 0, scope = "both", rebuild = true,
      options = { { value = 0, label = "Last scan" }, { value = 3, label = "3 days" }, { value = 7, label = "7 days" }, { value = 30, label = "30 days" } },
      test = function() return true end,
    },
    {
      key = "quality", title = "Quality",
      options = { { label = "Any" }, { value = 2, label = "Uncommon+" }, { value = 3, label = "Rare+" }, { value = 4, label = "Epic+" } },
      test = function(row, v)
        local info = Ct().Info(row.id)
        return info and (info.quality or 0) >= v or false
      end,
    },
  },
  tip = function(row)
    local lines = confTip(row)
    if lines then
      lines[1] = "Newness confidence " .. row.conf.score .. " (" .. row.conf.label .. ")"
    end
    return lines
  end,
  lead = function()
    local info = extra.newfinds
    if not info then return {} end
    if info.needsHistory then
      return { "Almanac needs another scan on a different day before it can tell what is new." }
    end
    local lines = {}
    if info.partial then
      lines[1] = string.format("%s of %s items on this scan are new. Earlier scans probably did not cover everything, "
        .. "so check the Confidence column.", Fmt.Count(info.newCount), Fmt.Count(info.seen))
    end
    return lines
  end,
  build = function()
    local Controller = Ct()
    local window = Overview.GetFilter("newfinds", "window") or 0
    local result = A.Discovery.NewFinds(Controller.summaries, Controller.newestDay, {
      window = window,
      classOf = function(id)
        local info = Controller.Info(id)
        return info and info.class
      end,
      className = className,
    })
    extra.newfinds = result
    for _, row in ipairs(result.rows) do
      row.price, row.qty = row.s.last, row.s.qty
    end
    return result.rows
  end,
})

-- ----- Watchlist -----
add({
  key = "watchlist", title = "Watchlist",
  hint = "Items you are watching. Use the Watch button on any item to add it.",
  empty = "Nothing watched yet. Open an item and click Watch to follow it here.",
  sort = { "item", true },
  columns = {
    itemColumn(),
    moneyColumn("price", "Price", "price"),
    {
      key = "since", title = "Since", width = 50, align = "RIGHT", defaultAsc = false,
      value = function(row) return row.since end,
      text = function(row) return Fmt.Change(row.since) end,
    },
    {
      key = "change", title = "7d", width = 46, align = "RIGHT", defaultAsc = false,
      value = function(row) return row.change end,
      text = function(row) return Fmt.Change(row.change) end,
    },
    moneyColumn("added", "Added at", "added", 72, { compact = false }),
    {
      key = "day", title = "Since day", width = 64, align = "RIGHT", defaultAsc = false, compact = false,
      value = function(row) return row.day end,
      text = function(row) return row.day and Fmt.Date(A.Adapter.DayToTime(row.day)) or DASH end,
    },
  },
  build = function()
    local rows = {}
    for _, id in ipairs(A.History.Watched()) do
      local s = Ct().summaries[id]
      local w = A.History.WatchInfo(id) or {}
      local row = { id = id, s = s, price = s and s.last, added = w.price, day = w.day, change = s and s.change7d }
      if s and s.last and w.price and w.price > 0 then row.since = s.last / w.price - 1 end
      rows[#rows + 1] = row
    end
    return rows
  end,
})

-- ----- Recent activity -----
local EVENT_NAME = { sold = "Sold", bought = "Bought", posted = "Posted", expired = "Expired", cancelled = "Cancelled" }
local EVENT_COLOR = { sold = "good", bought = false, posted = "gold", expired = "dim", cancelled = "dim" }
local EVENT_ORDER = { sold = 1, bought = 2, posted = 3, expired = 4, cancelled = 5 }

add({
  key = "activity", title = "Recent activity",
  hint = "Your sales and purchases. Open the list for postings, expiries and cancellations too.",
  empty = "No sales or purchases recorded yet.",
  sort = { "when", false },
  columns = {
    itemColumn(),
    {
      key = "event", title = "Event", width = 64, align = "LEFT", defaultAsc = true,
      value = function(row) return EVENT_ORDER[row.kind] end,
      text = function(row)
        local label = (EVENT_NAME[row.kind] or row.kind) .. " " .. Fmt.Count(row.qty or 1)
        local color = EVENT_COLOR[row.kind]
        if color == false then return colorize(label, "4db8ff") end
        return colorize(label, color and hex(color) or hex("text"))
      end,
    },
    {
      key = "total", title = "Total", width = 58, align = "RIGHT", defaultAsc = false,
      value = function(row) return row.total end,
      text = function(row) return row.total and Fmt.Money(row.total, { short = true }) or DASH end,
    },
    {
      -- the price each against the lowest price in the latest scan: +10% means 10% above it
      key = "vsnow", title = "vs now", width = 52, align = "RIGHT", defaultAsc = false,
      value = function(row) return row.vsNow end,
      text = function(row)
        local v = row.vsNow
        if v == nil then return DASH end
        local label = Fmt.Percent(v)
        if label == "0%" then return colorize(label, hex("dim")) end
        local good
        if row.kind == "sold" then good = v > 0 elseif row.kind == "bought" then good = v < 0 else return label end
        return colorize(label, good and hex("good") or hex("bad"))
      end,
    },
    {
      key = "when", title = "When", width = 40, align = "RIGHT", defaultAsc = false,
      value = function(row) return row.time end,
      text = function(row) return row.time and Fmt.AgoShort(now() - row.time) or DASH end,
    },
    moneyColumn("unit", "Each", "unit", 72, { compact = false }),
    {
      key = "date", title = "Date", width = 88, align = "RIGHT", defaultAsc = false, compact = false,
      value = function(row) return row.time end,
      text = function(row) return Fmt.DateTime(row.time) end,
    },
  },
  filters = {
    {
      key = "type", title = "Show", default = "all", compactValue = "trades",
      options = {
        { value = "all", label = "Everything" }, { value = "trades", label = "Sales & purchases" },
        { value = "sold", label = "Sold" }, { value = "bought", label = "Bought" },
        { value = "posted", label = "Posted" }, { value = "expired", label = "Expired" },
        { value = "cancelled", label = "Cancelled" },
      },
      test = function(row, v)
        if v == "all" then return true end
        if v == "trades" then return row.kind == "sold" or row.kind == "bought" end
        return row.kind == v
      end,
    },
  },
  search = function(row)
    return table.concat({ itemName(row), (row.e.party or ""):lower(), (row.e.char or ""):lower() }, " ")
  end,
  tip = function(row)
    if not (row.vsNow and row.now) then return nil end
    local verb = ({ sold = "sold", bought = "bought", posted = "listed" })[row.kind]
    if not verb then return nil end
    local pct = math.floor(math.abs(row.vsNow) * 100 + 0.5)
    local relation = pct == 0 and "the same as" or (pct .. "% " .. (row.vsNow > 0 and "above" or "below"))
    return {
      "You " .. verb .. " it for " .. Fmt.Money(row.unit, { plain = true }) .. " each: " .. relation .. " the latest scan.",
      "Lowest price in the latest scan: " .. Fmt.Money(row.now, { plain = true }),
    }
  end,
  build = function()
    local Controller = Ct()
    local rows = {}
    for _, e in ipairs(A.Ledger.Recent(math.huge)) do
      local row = {
        id = e.itemID, e = e, kind = e.kind, qty = e.qty, total = e.total, unit = e.unit, time = e.time, name = e.itemName,
      }
      -- how the price compares with the lowest price in the latest scan
      local latest = e.itemID and Controller.PriceOf(e.itemID)
      if row.unit and latest and latest > 0 then
        row.now = latest
        row.vsNow = row.unit / latest - 1
      end
      rows[#rows + 1] = row
    end
    return rows
  end,
})

-- ----- Inventory -----
add({
  key = "inventory", title = "Your inventory",
  hint = "What you own across your characters, worth most first.",
  empty = "No items tracked yet.",
  sort = { "value", false },
  columns = {
    itemColumn(),
    {
      key = "count", title = "Own", width = 46, align = "RIGHT", defaultAsc = false,
      value = function(row) return row.count end,
      text = function(row) return "x" .. Fmt.Count(row.count) end,
    },
    moneyColumn("value", "Worth", "value", 70),
    moneyColumn("price", "Each", "price", 72, { compact = false }),
  },
  limit = 5,
  lead = function()
    local info = extra.inventory
    if not info or info.count == 0 then
      return { "No items tracked yet.", "Almanac learns as you open your bags, bank and mail." }
    end
    local lines = { Fmt.Count(info.count) .. " items worth " .. Fmt.Money(info.inv.value) }
    if #info.inv.unpriced > 0 then
      local note = Fmt.Count(#info.inv.unpriced) .. " kinds have no auction price"
      if info.inv.vendorValue > 0 then note = note .. " (" .. Fmt.Money(info.inv.vendorValue, { short = true }) .. " vendor)" end
      lines[2] = note
    end
    return lines
  end,
  build = function()
    local Controller = Ct()
    local totals = A.Inventory.Totals()
    local count = 0
    for _, n in pairs(totals) do count = count + n end
    local inv = A.Stats.InventoryValue(totals, Controller.PriceOf, Controller.VendorOf)
    extra.inventory = { count = count, inv = inv }
    local rows = {}
    for _, line in ipairs(inv.lines) do
      rows[#rows + 1] = { id = line.id, count = line.count, value = line.value, price = line.price }
    end
    return rows
  end,
})

-- ----- Shopping lists -----
local function resolveTerm(parsed)
  local Controller = Ct()
  local key = (parsed.exact and "=" or "~") .. parsed.query:lower()
  local cached = resolved[key]
  if cached ~= nil then return cached or nil end

  local id = A.Items.IDByName(parsed.query)
  if id and not Controller.summaries[id] then id = nil end
  if not id and not parsed.exact then
    local matches = A.Search.Run(Controller.ids, { text = parsed.query }, {
      info = Controller.Info, summary = Controller.Summary, owned = function() return 0 end,
    })
    local best, bestLength
    for i = 1, math.min(#matches, 60) do
      local info = Controller.Info(matches[i])
      local length = info and info.lname and #info.lname or math.huge
      if not bestLength or length < bestLength then best, bestLength = matches[i], length end
    end
    id = best
  end
  resolved[key] = id or false
  return id
end

add({
  key = "shopping", title = "Shopping lists",
  hint = "Your Auctionator shopping lists with current prices.",
  empty = "No Auctionator shopping lists found.",
  sort = { "order", true },
  hidden = { order = function(row) return row.order end },
  limit = 10,
  columns = {
    itemColumn(),
    moneyColumn("price", "Price", "price"),
    {
      key = "vsavg", title = "vs avg", width = 50, align = "RIGHT", defaultAsc = true,
      value = function(row) return row.vsAvg end,
      text = function(row) return Fmt.Change(row.vsAvg) end,
    },
    {
      key = "list", title = "List", width = 100, align = "LEFT", defaultAsc = true, compact = false,
      value = function(row) return (row.list or ""):lower() end,
      text = function(row) return colorize(row.list or "", hex("gold")) end,
    },
  },
  group = function(row) return row.list end,
  build = function()
    local rows = {}
    for _, list in ipairs(A.Adapter.ShoppingLists()) do
      for _, term in ipairs(list.items) do
        local parsed = A.Adapter.ParseSearchTerm(term)
        if parsed.query ~= "" then
          local id = resolveTerm(parsed)
          local s = id and Ct().Summary(id)
          local row = { id = id, term = parsed.query, list = list.name, s = s, order = #rows + 1 }
          if s then
            row.price = s.last
            if s.avg and s.avg > 0 then row.vsAvg = s.last / s.avg - 1 end
          end
          rows[#rows + 1] = row
        end
      end
    end
    return rows
  end,
})

-- ---------------------------------------------------------------------------
-- Reading sections
-- ---------------------------------------------------------------------------
function Overview.Sections() return sections end
function Overview.Section(key) return byKey[key] end

-- Rows in the section's own order, built once until the data changes.
function Overview.Rows(key)
  local def = byKey[key]
  if not def then return {} end
  local rows = rowCache[key]
  if not rows then
    rows = def.build()
    for i, row in ipairs(rows) do row.seq = i end
    rowCache[key] = rows
  end
  return rows
end

function Overview.Lead(key)
  local def = byKey[key]
  if not def then return {} end
  Overview.Rows(key)      -- the lead reports what building the rows found out
  return def.lead()
end

local function matchesQuery(def, row, tokens)
  local text = def.search and def.search(row) or itemName(row)
  for _, token in ipairs(tokens) do
    if not text:find(token, 1, true) then return false end
  end
  return true
end

-- The filter values in force for a view: expanded lists use the saved choices (and any override
-- in opts.filters); the compact table ignores filters except those marked scope "both", and
-- those that fix their own compact value.
local function activeFilters(def, expanded, override)
  local out = {}
  for _, f in ipairs(def.filters or {}) do
    local value
    if expanded then
      value = override and override[f.key]
      if value == nil then value = Overview.GetFilter(def.key, f.key) end
    elseif f.compactValue ~= nil then
      value = f.compactValue
    elseif f.scope == "both" then
      value = Overview.GetFilter(def.key, f.key)
    end
    if value ~= nil then out[#out + 1] = { filter = f, value = value } end
  end
  return out
end

local function sortRows(rows, valueOf, ascending)
  local values, names = {}, {}
  for _, row in ipairs(rows) do
    values[row] = valueOf(row)
    names[row] = itemName(row)
  end
  table.sort(rows, function(a, b)
    local va, vb = values[a], values[b]
    if va ~= vb then
      if va == nil then return false end
      if vb == nil then return true end
      if ascending then return va < vb end
      return va > vb
    end
    local na, nb = names[a], names[b]
    if na ~= nb then return na < nb end
    return a.seq < b.seq
  end)
end

-- Rows after filters and the search, in the chosen order, plus how many rows the section holds
-- after filters (before the search). opts: expanded, query, sortKey, asc, filters.
function Overview.View(key, opts)
  opts = opts or {}
  local def = byKey[key]
  if not def then return {}, 0 end
  local colKey, ascending = Overview.GetSort(key)
  if opts.sortKey and sortValueFn(def, opts.sortKey) then colKey, ascending = opts.sortKey, opts.asc and true or false end

  local filters = activeFilters(def, opts.expanded, opts.filters)
  local tokens = {}
  if opts.query then tokens = A.Search.Tokenize(opts.query) end

  local parts = { key, opts.expanded and "x" or "c", colKey, ascending and "+" or "-", opts.query or "" }
  for _, entry in ipairs(filters) do parts[#parts + 1] = entry.filter.key .. "=" .. tostring(entry.value) end
  local sig = table.concat(parts, "|")
  local cached = viewCache[sig]
  if cached then return cached.rows, cached.total end

  local kept = {}
  for _, row in ipairs(Overview.Rows(key)) do
    local ok = true
    for _, entry in ipairs(filters) do
      if not entry.filter.test(row, entry.value) then ok = false; break end
    end
    if ok then kept[#kept + 1] = row end
  end
  local total = #kept

  if #tokens > 0 then
    local matched = {}
    for _, row in ipairs(kept) do
      if matchesQuery(def, row, tokens) then matched[#matched + 1] = row end
    end
    kept = matched
  end

  sortRows(kept, sortValueFn(def, colKey), ascending)
  viewCache[sig] = { rows = kept, total = total }
  return kept, total
end

-- The short table on the overview: the top rows of the whole sorted list, and how many there are.
function Overview.Compact(key)
  local def = byKey[key]
  if not def then return {}, 0 end
  local rows = Overview.View(key)
  local out = {}
  for i = 1, math.min(#rows, def.limit) do out[i] = rows[i] end
  return out, #rows
end

-- The columns drawn in the compact table.
function Overview.CompactColumns(key)
  local out = {}
  for _, col in ipairs(byKey[key].columns) do
    if col.compact ~= false then out[#out + 1] = col end
  end
  return out
end
