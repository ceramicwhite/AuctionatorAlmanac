local ADDON, A = ...

-- Price history chart: the daily lowest price as a gold line, the day's low-to-high
-- as a shaded band, quantity as bars along the bottom, and your sales, purchases
-- and postings as markers. `Graph.Layout` is pure geometry (unit tested);
-- `Graph.New` draws it with pooled lines and textures and handles hover.
local Theme = A.UI.Theme
local C = Theme.color
local Graph = {}
A.UI.Graph = Graph

Graph.PAD = 6               -- horizontal inset inside the plot
Graph.BAR_FRACTION = 0.2    -- the tallest quantity bar fills this share of the plot height
Graph.MARGIN = { left = 58, right = 10, top = 10, bottom = 24 }

local floor, max, min = math.floor, math.max, math.min

local MARKER_COLOR = {
  sold = { 0.37, 0.83, 0.37, 1 },
  bought = { 0.30, 0.72, 1, 1 },
  posted = { 0.85, 0.70, 0.30, 1 },
}
Graph.MARKER_COLOR = MARKER_COLOR

local function money(v)
  return A.Format.Money(v, { plain = true, short = true })
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------
-- days: ascending { {day, low, high, qty} }. opts: { range = 7|21|90|0 (all), today = day,
-- markers = { {day, kind, text} }, dayToTime = function(day) }.
-- Returns nil when nothing falls in the window. Coordinates are plot-local with the
-- origin at the bottom left.
function Graph.Layout(days, opts, W, H)
  if type(days) ~= "table" or #days == 0 then return nil end
  opts = opts or {}
  W, H = max(W or 0, 1), max(H or 0, 1)
  local range = opts.range or 0

  local selected, firstDay, lastDay = {}, nil, nil
  if range > 0 then
    lastDay = opts.today or days[#days].day
    firstDay = lastDay - range + 1
    for _, d in ipairs(days) do
      if d.day >= firstDay and d.day <= lastDay then selected[#selected + 1] = d end
    end
  else
    selected = days
    firstDay, lastDay = days[1].day, days[#days].day
  end
  if #selected == 0 then return nil end

  local pad = Graph.PAD
  local function xOf(day)
    if lastDay == firstDay then return W / 2 end
    return pad + (day - firstDay) / (lastDay - firstDay) * (W - 2 * pad)
  end

  local lo, hi, maxQty
  for _, d in ipairs(selected) do
    if not lo or d.low < lo then lo = d.low end
    local top = d.high or d.low
    if not hi or top > hi then hi = top end
    if d.qty and (not maxQty or d.qty > maxQty) then maxQty = d.qty end
  end
  local span = hi - lo
  local margin = span == 0 and max(1, hi * 0.1) or span * 0.08
  local yMin, yMax = max(0, lo - margin), hi + margin
  if yMax <= yMin then yMax = yMin + 1 end
  local function yOf(v) return (v - yMin) / (yMax - yMin) * H end

  local layout = { firstDay = firstDay, lastDay = lastDay, yMin = yMin, yMax = yMax, points = {}, yTicks = {}, xTicks = {}, markers = {}, W = W, H = H }
  for i, d in ipairs(selected) do
    local qty = d.qty
    layout.points[i] = {
      x = xOf(d.day), day = d.day, low = d.low, high = d.high or d.low, qty = qty,
      yLow = yOf(d.low), yHigh = yOf(d.high or d.low),
      yQty = (qty and maxQty and maxQty > 0) and (qty / maxQty * Graph.BAR_FRACTION * H) or 0,
    }
  end
  local slots = lastDay - firstDay + 1
  layout.barWidth = max(2, min(24, (W - 2 * pad) / slots * 0.7))

  for i = 0, 3 do
    local value = yMin + (yMax - yMin) * i / 3
    layout.yTicks[#layout.yTicks + 1] = { y = H * i / 3, value = value, label = money(value) }
  end

  local dayToTime = opts.dayToTime or (A.Adapter and A.Adapter.DayToTime)
  local function dayLabel(day)
    if dayToTime then return A.Format.Date(dayToTime(day)) end
    return tostring(day)
  end
  if firstDay == lastDay then
    layout.xTicks[1] = { x = xOf(firstDay), day = firstDay, label = dayLabel(firstDay) }
  else
    local count = min(5, lastDay - firstDay + 1)
    for i = 0, count - 1 do
      local day = floor(firstDay + (lastDay - firstDay) * i / (count - 1) + 0.5)
      layout.xTicks[#layout.xTicks + 1] = { x = xOf(day), day = day, label = dayLabel(day) }
    end
  end

  local grouped, order = {}, {}
  for _, m in ipairs(opts.markers or {}) do
    if m.day >= firstDay and m.day <= lastDay then
      local key = m.day .. ":" .. m.kind
      local g = grouped[key]
      if not g then
        g = { x = xOf(m.day), day = m.day, kind = m.kind, count = 0, events = {} }
        grouped[key] = g
        order[#order + 1] = g
      end
      g.count = g.count + 1
      g.events[#g.events + 1] = m
    end
  end
  table.sort(order, function(a, b)
    if a.x ~= b.x then return a.x < b.x end
    return a.kind < b.kind
  end)
  layout.markers = order
  return layout
end

function Graph.NearestPoint(layout, x)
  if not layout or #layout.points == 0 then return nil end
  local best, bestDistance
  for i, p in ipairs(layout.points) do
    local d = math.abs(p.x - x)
    if not bestDistance or d < bestDistance then best, bestDistance = i, d end
  end
  return best
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
local function pool(owner, kind, create)
  local items = { used = 0 }
  function items.next()
    items.used = items.used + 1
    local item = items[items.used]
    if not item then
      item = create(owner)
      items[items.used] = item
    end
    item:Show()
    return item
  end
  function items.reset()
    for i = 1, #items do items[i]:Hide() end
    items.used = 0
  end
  return items
end

local function setColor(region, c, alpha)
  region:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end

function Graph.New(parent)
  local g = { }
  local frame = CreateFrame("Frame", nil, parent)
  g.frame = frame
  local m = Graph.MARGIN

  local plot = CreateFrame("Frame", nil, frame)
  plot:SetPoint("TOPLEFT", frame, "TOPLEFT", m.left, -m.top)
  plot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -m.right, m.bottom)
  Theme.Fill(plot, C.input)
  Theme.Border(plot, C.borderDim, 1)
  plot:EnableMouse(true)
  g.plot = plot

  g.empty = Theme.Text(plot, "dim", "CENTER")
  g.empty:SetPoint("CENTER", plot, "CENTER", 0, 0)
  g.empty:SetText("No price history recorded for this item yet.")
  g.empty:Hide()

  local function rect(layer) return function(owner)
    local t = owner:CreateTexture(nil, layer)
    return t
  end end
  local function line(layer) return function(owner)
    local l = owner:CreateLine(nil, layer)
    return l
  end end
  local function label(owner)
    return Theme.Text(frame, "dim", "RIGHT")
  end

  g.grid = pool(plot, "line", line("BACKGROUND"))
  g.bars = pool(plot, "rect", rect("BACKGROUND"))
  g.bands = pool(plot, "rect", rect("BORDER"))
  g.markerLines = pool(plot, "rect", rect("ARTWORK"))
  g.markerDiamonds = pool(plot, "rect", rect("ARTWORK"))
  g.segments = pool(plot, "line", line("ARTWORK"))
  g.dots = pool(plot, "rect", rect("OVERLAY"))
  g.labels = pool(plot, "label", label)

  g.cross = plot:CreateTexture(nil, "OVERLAY")
  setColor(g.cross, C.bright, 0.5)
  g.cross:SetWidth(1)
  g.cross:Hide()
  g.hit = plot:CreateTexture(nil, "OVERLAY")
  setColor(g.hit, C.bright, 1)
  g.hit:SetSize(9, 9)
  g.hit:Hide()

  -- -------------------------------------------------------------------------
  function g:SetSeries(series, opts)
    self.days = series and series.days or nil
    self.opts = opts or {}
    self:Redraw()
  end

  -- W, H: the plot's size. The resize handler passes it from the event's own numbers,
  -- because child frames may not have been re-laid-out yet when it fires.
  function g:Redraw(W, H)
    W, H = W or plot:GetWidth(), H or plot:GetHeight()
    for _, p in ipairs({ self.grid, self.bars, self.bands, self.markerLines, self.markerDiamonds, self.segments, self.dots, self.labels }) do
      p.reset()
    end
    self.cross:Hide(); self.hit:Hide()
    self.hoverIndex = nil
    local layout = Graph.Layout(self.days, self.opts, W, H)
    self.layout = layout
    if not layout then
      self.empty:Show()
      return
    end
    self.empty:Hide()

    for _, tick in ipairs(layout.yTicks) do
      local l = self.grid.next()
      l:SetThickness(1)
      setColor(l, C.borderDim, 0.5)
      l:SetStartPoint("BOTTOMLEFT", plot, 0, tick.y)
      l:SetEndPoint("BOTTOMLEFT", plot, W, tick.y)
      local fs = self.labels.next()
      fs:ClearAllPoints()
      fs:SetPoint("RIGHT", plot, "BOTTOMLEFT", -6, tick.y)
      fs:SetText(tick.label)
    end
    for _, tick in ipairs(layout.xTicks) do
      local fs = self.labels.next()
      fs:ClearAllPoints()
      fs:SetPoint("TOP", plot, "BOTTOMLEFT", tick.x, -5)
      fs:SetText(tick.label)
    end

    local bw = layout.barWidth
    for _, p in ipairs(layout.points) do
      if p.yQty >= 1 then
        local bar = self.bars.next()
        setColor(bar, C.graphBars)
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", p.x - bw / 2, 0)
        bar:SetSize(bw, p.yQty)
      end
      if p.yHigh - p.yLow >= 1 then
        local band = self.bands.next()
        setColor(band, C.graphBand)
        band:ClearAllPoints()
        band:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", p.x - bw / 2, p.yLow)
        band:SetSize(bw, p.yHigh - p.yLow)
      end
    end

    for _, mk in ipairs(layout.markers) do
      local c = MARKER_COLOR[mk.kind] or C.dim
      local vline = self.markerLines.next()
      setColor(vline, c, 0.35)
      vline:ClearAllPoints()
      vline:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", mk.x - 1, 0)
      vline:SetSize(2, H)
      local d = self.markerDiamonds.next()
      setColor(d, c, 1)
      d:ClearAllPoints()
      d:SetSize(8, 8)
      d:SetRotation(math.rad(45))
      d:SetPoint("CENTER", plot, "BOTTOMLEFT", mk.x, H - 6)
    end

    local pts = layout.points
    for i = 1, #pts - 1 do
      local seg = self.segments.next()
      seg:SetThickness(2)
      setColor(seg, C.graphLine)
      seg:SetStartPoint("BOTTOMLEFT", plot, pts[i].x, pts[i].yLow)
      seg:SetEndPoint("BOTTOMLEFT", plot, pts[i + 1].x, pts[i + 1].yLow)
    end
    if #pts <= 60 then
      for _, p in ipairs(pts) do
        local dot = self.dots.next()
        setColor(dot, C.graphLine)
        dot:ClearAllPoints()
        dot:SetSize(5, 5)
        dot:SetPoint("CENTER", plot, "BOTTOMLEFT", p.x, p.yLow)
      end
    end
  end

  -- -------------------------------------------------------------------------
  -- Hover: crosshair plus a tooltip for the nearest day
  function g:HoverAt(x)
    local layout = self.layout
    local index = Graph.NearestPoint(layout, x)
    if not index then
      self:ClearHover()
      return
    end
    if index == self.hoverIndex then return end
    self.hoverIndex = index
    local p = layout.points[index]
    self.cross:ClearAllPoints()
    self.cross:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", p.x, 0)
    self.cross:SetHeight(layout.H)
    self.cross:Show()
    self.hit:ClearAllPoints()
    self.hit:SetPoint("CENTER", plot, "BOTTOMLEFT", p.x, p.yLow)
    self.hit:Show()

    local dayToTime = self.opts.dayToTime or (A.Adapter and A.Adapter.DayToTime)
    GameTooltip:SetOwner(plot, "ANCHOR_CURSOR")
    GameTooltip:AddLine(dayToTime and A.Format.Date(dayToTime(p.day)) or tostring(p.day), 1, 0.82, 0)
    GameTooltip:AddDoubleLine("Lowest", A.Format.Money(p.low), 0.8, 0.8, 0.8, 1, 1, 1)
    if p.high ~= p.low then GameTooltip:AddDoubleLine("Highest", A.Format.Money(p.high), 0.8, 0.8, 0.8, 1, 1, 1) end
    if p.qty then GameTooltip:AddDoubleLine("Quantity", A.Format.Count(p.qty), 0.8, 0.8, 0.8, 1, 1, 1) end
    for _, mk in ipairs(layout.markers) do
      if mk.day == p.day then
        local c = MARKER_COLOR[mk.kind] or C.text
        for _, ev in ipairs(mk.events) do GameTooltip:AddLine(ev.text, c[1], c[2], c[3], true) end
      end
    end
    GameTooltip:Show()
  end

  function g:ClearHover()
    self.hoverIndex = nil
    self.cross:Hide()
    self.hit:Hide()
    GameTooltip:Hide()
  end

  local function cursorX()
    local scale = plot:GetEffectiveScale()
    local x = GetCursorPosition()
    return x / scale - plot:GetLeft()
  end

  plot:SetScript("OnEnter", function()
    plot:SetScript("OnUpdate", function() g:HoverAt(cursorX()) end)
  end)
  plot:SetScript("OnLeave", function()
    plot:SetScript("OnUpdate", nil)
    g:ClearHover()
  end)
  frame:SetScript("OnSizeChanged", function(_, width, height)
    g:Redraw(width - m.left - m.right, height - m.top - m.bottom)
  end)
  return g
end
