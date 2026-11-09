local ADDON, A = ...

-- Column header + virtual list. Column widths are fixed pixels or flex weights;
-- the header cells and every row cell are re-laid-out whenever the width changes.
local Theme = A.UI.Theme
local W = A.UI.Widgets
local VL = A.UI.VirtualList
local C = Theme.color
local Table = {}
A.UI.Table = Table

local HEADER_HEIGHT = 22

-- spec: { width = px | flex = weight, align = "LEFT"|"RIGHT"|"CENTER", sortable = true,
--         defaultAsc = true, style = font style }
function Table.TextColumn(key, title, spec, textFn)
  spec = spec or {}
  local align = spec.align or "LEFT"
  return {
    key = key, title = title, width = spec.width, flex = spec.flex, align = align, minWidth = spec.minWidth,
    sortable = spec.sortable ~= false, defaultAsc = spec.defaultAsc ~= false,
    build = function(cell)
      cell.text = Theme.Text(cell, spec.style or "normal", align)
      cell.text:SetPoint("LEFT", cell, "LEFT", 4, 0)
      cell.text:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
    end,
    update = function(cell, item, index)
      cell.text:SetText(textFn(item, index) or "")
    end,
  }
end

--[[
opts = {
  columns = { {key, title, width|flex, align, sortable, defaultAsc, build(cell), update(cell, item, index)} },
  rowHeight = 20,
  onSort = function(key, ascending),
  onClick/onEnter/onLeave = as VirtualList,
  update = function(row, item, index, selected)   -- optional extra per-row binding
}
]]
function Table.New(parent, opts)
  local t = { columns = opts.columns, headers = {}, colX = {}, colW = {}, sortKey = nil, sortAsc = true }
  local frame = CreateFrame("Frame", nil, parent)
  t.frame = frame

  local header = CreateFrame("Frame", nil, frame)
  header:SetHeight(HEADER_HEIGHT)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  Theme.Fill(header, C.header)
  t.header = header

  local function layoutCell(cell, parentRow, x, w)
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", parentRow, "TOPLEFT", x, 0)
    cell:SetPoint("BOTTOMLEFT", parentRow, "BOTTOMLEFT", x, 0)
    cell:SetWidth(w)
  end

  -- A column whose width is 0 is dropped from this layout (see col.minWidth below).
  local function layoutRow(row)
    for i, cell in ipairs(row.cells) do
      local w = t.colW[i] or 0
      cell:SetShown(w > 0)
      if w > 0 then layoutCell(cell, row, t.colX[i] or 0, w) end
    end
  end

  -- A column can carry `minWidth`: the table width below which it is dropped, so a narrow pane
  -- keeps its important columns readable and a wide one shows the extras.
  function t:Layout(width)
    local avail = math.max(0, width - VL.BAR)
    local shown, fixed, flex = {}, 0, 0
    for i, col in ipairs(self.columns) do
      shown[i] = not col.minWidth or width >= col.minWidth
      if shown[i] then
        fixed = fixed + (col.width or 0)
        flex = flex + (col.flex or 0)
      end
    end
    local remaining = math.max(0, avail - fixed)
    local x = 0
    for i, col in ipairs(self.columns) do
      if shown[i] then
        local w = col.width or (flex > 0 and remaining * (col.flex or 0) / flex or 0)
        self.colX[i], self.colW[i] = x, w
        self.headers[i]:Show()
        layoutCell(self.headers[i], header, x, w)
        x = x + w
      else
        self.colX[i], self.colW[i] = 0, 0
        self.headers[i]:Hide()
      end
    end
    for _, row in ipairs(self.list.rows) do layoutRow(row) end
  end

  function t:SetSort(key, asc)
    self.sortKey, self.sortAsc = key, asc and true or false
    for i, col in ipairs(self.columns) do
      local h = self.headers[i]
      local active = col.key == key
      local color = active and C.gold or C.text
      h.label:SetTextColor(color[1], color[2], color[3], 1)
      if active then h.arrow:Show(col.align, self.sortAsc) else h.arrow:Hide() end
    end
  end

  for i, col in ipairs(t.columns) do
    local h = CreateFrame("Button", nil, header)
    h:RegisterForClicks("LeftButtonUp")
    h.label = Theme.Text(h, "goldSmall", col.align)
    h.label:SetPoint("LEFT", h, "LEFT", 4, 0)
    h.label:SetPoint("RIGHT", h, "RIGHT", -4, 0)
    h.label:SetText(col.title)
    h.arrow = W.SortArrow(h)
    h:SetScript("OnClick", function()
      if not col.sortable then return end
      local asc
      if t.sortKey == col.key then asc = not t.sortAsc else asc = col.defaultAsc end
      t:SetSort(col.key, asc)
      if opts.onSort then opts.onSort(col.key, asc) end
    end)
    h:SetScript("OnEnter", function(self) if col.sortable then self.label:SetTextColor(1, 1, 1, 1) end end)
    h:SetScript("OnLeave", function() t:SetSort(t.sortKey, t.sortAsc) end)
    t.headers[i] = h
  end

  t.list = VL.New(frame, {
    rowHeight = opts.rowHeight or 20,
    createRow = function(row, slot)
      row.cells = {}
      for i, col in ipairs(t.columns) do
        local cell = CreateFrame("Frame", nil, row)
        col.build(cell, row)
        row.cells[i] = cell
      end
      layoutRow(row)
      if opts.createRow then opts.createRow(row, slot) end
    end,
    update = function(row, item, index, selected)
      for i, col in ipairs(t.columns) do col.update(row.cells[i], item, index) end
      if opts.update then opts.update(row, item, index, selected) end
    end,
    onClick = opts.onClick, onEnter = opts.onEnter, onLeave = opts.onLeave,
  })
  t.list.frame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  t.list.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

  frame:SetScript("OnSizeChanged", function(_, width) t:Layout(width) end)

  function t:SetData(data) self.list:SetData(data) end
  function t:SetSelectedItem(item) self.list:SetSelectedItem(item) end
  function t:Refresh() self.list:Refresh() end

  if opts.sortKey then t:SetSort(opts.sortKey, opts.sortAsc ~= false) end
  return t
end
