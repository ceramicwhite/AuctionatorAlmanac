local ADDON, A = ...

-- "Price History" tab: the chart, range buttons, and a day-by-day table.
local Theme = A.UI.Theme
local W = A.UI.Widgets
local Table = A.UI.Table
local Graph = A.UI.Graph
local Fmt = A.Format
local TabHistory = {}
A.UI.TabHistory = TabHistory

local RANGES = { { 7, "7d" }, { 21, "21d" }, { 90, "90d" }, { 0, "All" } }
local GRAPH_SHARE, GRAPH_MIN, GRAPH_MAX = 0.5, 110, 320
local ROW_HEIGHT = 20

local function validRange(r)
  for _, def in ipairs(RANGES) do
    if def[1] == r then return r end
  end
  return 21
end

local function variantLabel(key)
  if key:match("^%d+$") then return "Base" end
  local ilvl = key:match("^g:%d+:(%d+)$")
  if ilvl then return "iLvl " .. ilvl end
  local suffix = key:match("^gr:%d+:(.+)$")
  return suffix or key
end

-- Marker events from the player's ledger, positioned by Auctionator day number.
local function markersFor(id)
  local out = {}
  for _, e in ipairs(A.Ledger.ForItem(id)) do
    if e.kind == "sold" or e.kind == "bought" or e.kind == "posted" then
      local verb = e.kind == "sold" and "Sold" or (e.kind == "bought" and "Bought" or "Posted")
      local text = verb .. " " .. (e.qty or 1)
      if e.total then text = text .. " for " .. Fmt.Money(e.total, { short = true }) end
      out[#out + 1] = { day = A.Adapter.TimeToDay(e.time), kind = e.kind, text = text }
    end
  end
  return out
end

function TabHistory.Build(parent)
  local view = CreateFrame("Frame", nil, parent)
  view:SetAllPoints(parent)
  view.range = validRange(A.Get("historyRange"))

  view.graph = Graph.New(view)
  view.graph.frame:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
  view.graph.frame:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, 0)
  view.graph.frame:SetHeight(GRAPH_MIN)

  view.rangeRow = CreateFrame("Frame", nil, view)
  view.rangeRow:SetHeight(24)
  view.rangeRow:SetPoint("TOPLEFT", view.graph.frame, "BOTTOMLEFT", 0, -4)
  view.rangeRow:SetPoint("TOPRIGHT", view.graph.frame, "BOTTOMRIGHT", 0, -4)

  view.rangeButtons = {}
  local previous
  for _, def in ipairs(RANGES) do
    local b = W.Button(view.rangeRow, def[2], function()
      view.range = def[1]
      A.Set("historyRange", def[1])
      TabHistory.Update(view, view.itemID)
    end, { width = 44, height = 22 })
    if previous then b:SetPoint("LEFT", previous, "RIGHT", 3, 0) else b:SetPoint("LEFT", view.rangeRow, "LEFT", 0, 0) end
    view.rangeButtons[def[1]] = b
    previous = b
  end

  view.variantCycle = nil   -- created on demand for gear with several versions

  view.table = Table.New(view, {
    columns = {
      Table.TextColumn("date", "Date", { flex = 1, sortable = false }, function(d)
        return Fmt.Date(A.Adapter.DayToTime(d.day))
      end),
      Table.TextColumn("low", "Low", { width = 86, align = "RIGHT", sortable = false }, function(d)
        return Fmt.Money(d.low)
      end),
      Table.TextColumn("high", "High", { width = 86, align = "RIGHT", sortable = false }, function(d)
        return Fmt.Money(d.high)
      end),
      Table.TextColumn("qty", "Qty", { width = 50, align = "RIGHT", sortable = false }, function(d)
        return d.qty and Fmt.Count(d.qty) or "—"
      end),
    },
    rowHeight = ROW_HEIGHT,
  })
  view.table.frame:SetPoint("TOPLEFT", view.rangeRow, "BOTTOMLEFT", 0, -4)
  view.table.frame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)

  view:SetScript("OnSizeChanged", function(_, _, height)
    local h = math.max(GRAPH_MIN, math.min(GRAPH_MAX, math.floor(height * GRAPH_SHARE)))
    view.graph.frame:SetHeight(h)
  end)
  return view
end

-- One selector per distinct set of versions, created once and reused.
local function ensureVariantCycle(view, keys)
  if #keys <= 1 then
    if view.variantCycle then view.variantCycle:Hide() end
    return
  end
  view.variantCycles = view.variantCycles or {}
  local signature = table.concat(keys, "|")
  local cycle = view.variantCycles[signature]
  if not cycle then
    local options = {}
    for _, key in ipairs(keys) do options[#options + 1] = { value = key, label = variantLabel(key) } end
    cycle = W.Cycle(view.rangeRow, "Version", options, function(key)
      view.variantKey = key
      TabHistory.Update(view, view.itemID)
    end, { width = 130, height = 22, plain = true })
    cycle:SetPoint("RIGHT", view.rangeRow, "RIGHT", 0, 0)
    view.variantCycles[signature] = cycle
  end
  if view.variantCycle and view.variantCycle ~= cycle then view.variantCycle:Hide() end
  view.variantCycle = cycle
  cycle:SetValue(view.variantKey or keys[1])
  cycle:Show()
end

function TabHistory.Update(view, id)
  if view.itemID ~= id then
    view.itemID, view.variantKey = id, nil
  end
  for range, b in pairs(view.rangeButtons) do b:SetActive(range == view.range) end

  local Ct = A.Controller
  local keys = Ct.Variants(id)
  ensureVariantCycle(view, keys)

  local all = Ct.Series(id)
  local baseKey = all and all.live and all.live.key
  local series
  if view.variantKey and view.variantKey ~= baseKey then
    series = A.Adapter.GetSeries(view.variantKey)
  else
    series = all and all.merged
  end
  local today = Ct.Today()
  view.graph:SetSeries(series, {
    range = view.range, today = today, markers = markersFor(id), dayToTime = A.Adapter.DayToTime,
  })

  local rows = {}
  local days = series and series.days or {}
  local first = view.range > 0 and (today - view.range + 1) or nil
  for i = #days, 1, -1 do
    local d = days[i]
    if not first or (d.day >= first and d.day <= today) then rows[#rows + 1] = d end
  end
  view.table:SetData(rows)
end
