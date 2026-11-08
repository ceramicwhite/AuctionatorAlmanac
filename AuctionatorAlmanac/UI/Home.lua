local ADDON, A = ...

-- The overview shown when no item is selected: what is moving, what looks cheap,
-- what your stock is worth, what you did lately, and your Auctionator shopping lists.
local Theme = A.UI.Theme
local VL = A.UI.VirtualList
local Fmt = A.Format
local C = Theme.color
local Home = {}
A.UI.Home = Home

local LIMIT = 5
local MAX_LISTS, MAX_TERMS = 6, 8
local ROW_HEIGHT = 22
local QUESTION_MARK = 134400

local resolved = {}      -- shopping-list term -> item id | false

local function nowSeconds() return (time and time()) or 0 end

-- ---------------------------------------------------------------------------
-- Shopping list terms
-- ---------------------------------------------------------------------------
local function resolveTerm(parsed)
  local Ct = A.Controller
  local key = (parsed.exact and "=" or "~") .. parsed.query:lower()
  local cached = resolved[key]
  if cached ~= nil then return cached or nil end

  local id = A.Items.IDByName(parsed.query)
  if id and not Ct.summaries[id] then id = nil end
  if not id and not parsed.exact then
    local matches = A.Search.Run(Ct.ids, { text = parsed.query }, {
      info = Ct.Info, summary = Ct.Summary, owned = function() return 0 end,
    })
    local best, bestLength
    for i = 1, math.min(#matches, 60) do
      local info = Ct.Info(matches[i])
      local length = info and info.lname and #info.lname or math.huge
      if not bestLength or length < bestLength then best, bestLength = matches[i], length end
    end
    id = best
  end
  resolved[key] = id or false
  return id
end

-- ---------------------------------------------------------------------------
-- Content
-- ---------------------------------------------------------------------------
function Home.Lines()
  local Ct = A.Controller
  local lines = {}
  local function add(line) lines[#lines + 1] = line end
  local function header(text) add({ kind = "header", text = text }) end
  local function text(t) add({ kind = "text", text = t }) end
  local function item(id, value, extra) add({ kind = "item", id = id, value = value or "", extra = extra or "" }) end

  text("Select an item to see its price history,")
  text("your sales and where you own it.")

  local priced = {}
  for _, id in ipairs(Ct.ids) do
    local s = Ct.summaries[id]
    if s then priced[#priced + 1] = { id = id, s = s } end
  end

  header("Biggest movers (7 days)")
  local up, down = A.Stats.Movers(priced, { limit = LIMIT })
  for _, group in ipairs({ up, down }) do
    for _, m in ipairs(group) do item(m.id, Fmt.Money(m.s.last, { short = true }), Fmt.Change(m.change)) end
  end
  if #up + #down == 0 then text("No big movers yet; needs a few days of scans.") end

  header("Below their average")
  local cheap = A.Stats.BelowAverage(priced, { limit = LIMIT })
  for _, b in ipairs(cheap) do
    item(b.id, Fmt.Money(b.s.last, { short = true }), Theme.Colorize(Fmt.Percent(b.ratio - 1), Theme.hex.good))
  end
  if #cheap == 0 then text("Nothing is priced well below its average.") end

  header("Your inventory")
  local totals = A.Inventory.Totals()
  local count = 0
  for _, n in pairs(totals) do count = count + n end
  if count == 0 then
    text("No items tracked yet.")
    text("Almanac learns as you open bags, bank and mail.")
  else
    local inv = A.Stats.InventoryValue(totals, Ct.PriceOf, Ct.VendorOf)
    text(Fmt.Count(count) .. " items worth " .. Fmt.Money(inv.value))
    if #inv.unpriced > 0 then
      local note = Fmt.Count(#inv.unpriced) .. " kinds have no auction price"
      if inv.vendorValue > 0 then note = note .. " (" .. Fmt.Money(inv.vendorValue, { short = true }) .. " vendor)" end
      text(note)
    end
    for i = 1, math.min(LIMIT, #inv.lines) do
      local line = inv.lines[i]
      item(line.id, Fmt.Money(line.value, { short = true }), "x" .. Fmt.Count(line.count))
    end
  end

  header("Recent activity")
  local recent = A.Ledger.Recent(6, { sold = true, bought = true })
  for _, e in ipairs(recent) do
    local verb = e.kind == "sold" and Theme.Colorize("Sold", Theme.hex.good) or Theme.Colorize("Bought", "4db8ff")
    local when = Fmt.Ago(nowSeconds() - e.time)
    if e.itemID then
      item(e.itemID, e.total and Fmt.Money(e.total, { short = true }) or "—", verb .. " " .. Fmt.Count(e.qty) .. " · " .. when)
    else
      text(verb .. " " .. Fmt.Count(e.qty) .. " " .. (e.itemName or "item") .. " · " .. when)
    end
  end
  if #recent == 0 then text("No sales or purchases recorded yet.") end

  header("Shopping lists")
  local lists = A.Adapter.ShoppingLists()
  if #lists == 0 then text("No Auctionator shopping lists found.") end
  for li = 1, math.min(#lists, MAX_LISTS) do
    local list = lists[li]
    text(Theme.Colorize(list.name, Theme.hex.gold))
    for ti = 1, math.min(#list.items, MAX_TERMS) do
      local parsed = A.Adapter.ParseSearchTerm(list.items[ti])
      if parsed.query ~= "" then
        local id = resolveTerm(parsed)
        if id then
          local s = Ct.Summary(id)
          local extra = (s and s.avg and s.avg > 0) and Fmt.Change(s.last / s.avg - 1) or ""
          item(id, s and Fmt.Money(s.last, { short = true }) or "—", extra)
        else
          text(Theme.Colorize(parsed.query .. " (no match)", Theme.hex.dim))
        end
      end
    end
    if #list.items > MAX_TERMS then text(Theme.Colorize("+ " .. (#list.items - MAX_TERMS) .. " more", Theme.hex.dim)) end
  end
  if #lists > MAX_LISTS then text(Theme.Colorize("+ " .. (#lists - MAX_LISTS) .. " more lists", Theme.hex.dim)) end
  return lines
end

function Home.Update()
  if Home.list then Home.list:SetData(Home.Lines()) end
end

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------
local function onClick(line)
  if line.id then A.Controller.Select(line.id) end
end

local function onEnter(row, line)
  if not line.id then return end
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  GameTooltip:SetHyperlink("item:" .. line.id)
  GameTooltip:Show()
end

A.UI.Window.AddBuilder(function(win)
  local list = VL.New(win.homeView, {
    rowHeight = ROW_HEIGHT,
    createRow = function(row)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(16, 16)
      row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
      row.extra = Theme.Text(row, "small", "RIGHT")
      row.extra:SetPoint("RIGHT", row, "RIGHT", -6, 0)
      row.extra:SetWidth(92)
      row.value = Theme.Text(row, "normal", "RIGHT")
      row.value:SetPoint("RIGHT", row.extra, "LEFT", -4, 0)
      row.value:SetWidth(78)
      row.name = Theme.Text(row, "normal", "LEFT")
      row.rule = row:CreateTexture(nil, "BORDER")
      row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 1)
      row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 1)
      row.rule:SetHeight(1)
      Theme.SetColor(row.rule, C.border)
    end,
    update = function(row, line)
      row.name:ClearAllPoints()
      if line.kind == "header" then
        row.icon:Hide(); row.rule:Show()
        row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.name:SetText(Theme.Colorize(line.text, Theme.hex.gold))
        row.value:SetText(""); row.extra:SetText("")
      elseif line.kind == "item" then
        row.rule:Hide()
        local info = A.Items.Ensure(line.id)
        row.icon:SetTexture(info.icon or QUESTION_MARK)
        row.icon:Show()
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
        row.name:SetText(info.name and Fmt.ColorName(info.name, info.quality) or Theme.Colorize("Item " .. line.id, Theme.hex.dim))
        row.value:SetText(line.value)
        row.extra:SetText(line.extra)
      else
        row.icon:Hide(); row.rule:Hide()
        row.name:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.name:SetText(line.text)
        row.value:SetText(""); row.extra:SetText("")
      end
    end,
    onClick = onClick,
    onEnter = onEnter,
    onLeave = function() GameTooltip:Hide() end,
  })
  list.frame:SetAllPoints(win.homeView)
  Home.list = list
  win.homeList = list

  A.Bus.On("DATA_RELOADED", function() resolved = {} end)
  A.Bus.On("ITEM_NAMES_UPDATED", function() resolved = {} end)
  Home.Update()
end)
