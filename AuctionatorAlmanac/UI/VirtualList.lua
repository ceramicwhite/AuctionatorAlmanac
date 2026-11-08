local ADDON, A = ...

-- A scrolling list that only ever builds the rows that fit on screen. With
-- 15,000 items it still creates ~20 row frames; scrolling just re-binds them.
local Theme = A.UI.Theme
local W = A.UI.Widgets
local C = Theme.color
local VL = {}
A.UI.VirtualList = VL

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local WHEEL_STEP = 3
local BAR = W.SCROLLBAR_WIDTH + 2     -- scrollbar plus gap; always reserved so columns do not jump

--[[
opts = {
  rowHeight = 20,
  createRow = function(row, slot)                 -- build the row's child widgets once
  update    = function(row, item, index, selected) -- bind data to a row
  onClick   = function(item, index, button)
  onEnter   = function(row, item, index)
  onLeave   = function(row, item, index)
}
]]
function VL.New(parent, opts)
  local list = { rows = {}, data = {}, offset = 0, visible = 0, rowHeight = opts.rowHeight or 20, opts = opts }
  local frame = CreateFrame("Frame", nil, parent)
  frame:EnableMouseWheel(true)
  frame:SetClipsChildren(true)
  list.frame = frame

  list.scrollbar = W.Scrollbar(frame, function(offset) list:SetOffset(offset, true) end)
  list.scrollbar.frame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  list.scrollbar.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  list.scrollbar.frame:Hide()

  local function paintRow(row)
    local c
    if row.selected then c = C.select
    elseif row.hover then c = C.hover
    elseif row.slot % 2 == 0 then c = C.zebra
    else c = C.panel end
    Theme.SetColor(row.bg, c)
  end

  local function createRow(slot)
    local row = CreateFrame("Button", nil, frame)
    row.slot = slot
    row:SetHeight(list.rowHeight)
    local y = -(slot - 1) * list.rowHeight
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -BAR, y)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
      if self.item ~= nil and opts.onClick then opts.onClick(self.item, self.index, button) end
    end)
    row:SetScript("OnEnter", function(self)
      self.hover = true
      paintRow(self)
      if self.item ~= nil and opts.onEnter then opts.onEnter(self, self.item, self.index) end
    end)
    row:SetScript("OnLeave", function(self)
      self.hover = false
      paintRow(self)
      if self.item ~= nil and opts.onLeave then opts.onLeave(self, self.item, self.index) end
    end)
    if opts.createRow then opts.createRow(row, slot) end
    paintRow(row)
    row:Hide()
    list.rows[slot] = row
    return row
  end

  function list:Refresh()
    local n = #self.data
    for slot, row in ipairs(self.rows) do
      local index = self.offset + slot
      if index <= n and slot <= self.visible + 1 then
        local item = self.data[index]
        row.item, row.index = item, index
        row.selected = (self.selected ~= nil and item == self.selected)
        paintRow(row)
        row:Show()
        if opts.update then opts.update(row, item, index, row.selected) end
      else
        row.item, row.index = nil, nil
        row:Hide()
      end
    end
  end

  function list:MaxOffset() return max(0, #self.data - self.visible) end

  function list:SyncScrollbar()
    self.scrollbar:SetRange(self:MaxOffset(), self.visible, #self.data)
    self.scrollbar:SetOffset(self.offset)
  end

  function list:SetOffset(offset, fromScrollbar)
    offset = max(0, min(self:MaxOffset(), floor(offset + 0.5)))
    self.offset = offset
    if not fromScrollbar then self.scrollbar:SetOffset(offset) end
    self:Refresh()
  end

  function list:GetOffset() return self.offset end

  function list:SetData(data)
    self.data = data or {}
    self.offset = max(0, min(self:MaxOffset(), self.offset))
    self:SyncScrollbar()
    self:Refresh()
  end

  function list:SetSelectedItem(item)
    self.selected = item
    self:Refresh()
  end

  function list:ScrollTo(index)
    if index <= self.offset then
      self:SetOffset(index - 1)
    elseif index > self.offset + self.visible then
      self:SetOffset(index - self.visible)
    end
  end

  function list:OnResize(height)
    self.visible = max(0, floor(height / self.rowHeight))
    for slot = #self.rows + 1, self.visible + 1 do createRow(slot) end
    self.offset = max(0, min(self:MaxOffset(), self.offset))
    self:SyncScrollbar()
    self:Refresh()
  end

  frame:SetScript("OnSizeChanged", function(_, _, height) list:OnResize(height) end)
  frame:SetScript("OnMouseWheel", function(_, delta) list:SetOffset(list.offset - delta * WHEEL_STEP) end)
  return list
end

VL.BAR = BAR
