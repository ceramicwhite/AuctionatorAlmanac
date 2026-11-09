local ADDON, A = ...

-- The main window shell: title bar, status strip, search row and a three-panel
-- body (categories | results | detail). Every region is anchored, so resizing
-- from the bottom-right grip re-lays-out the whole window; only the detail
-- panel's width is computed: a share of the window by default, or the width the
-- player dragged the divider to. The item list in the middle can be hidden with
-- the button on the divider, which hands its room to the detail panel.
local Theme = A.UI.Theme
local W = A.UI.Widgets
local C = Theme.color
local Window = {}
A.UI.Window = Window

Window.NAME = "AuctionatorAlmanacFrame"
Window.DEFAULT_W, Window.DEFAULT_H = 1000, 620
Window.MIN_W, Window.MIN_H = 960, 540
Window.CAT_WIDTH = 150
Window.DETAIL_MIN, Window.DETAIL_MAX, Window.DETAIL_SHARE = 330, 560, 0.36
Window.RESULTS_MIN = 300       -- the item list never gets narrower than this when shown

local PAD = 8
local TITLE_H, STATUS_H, SEARCH_H = 28, 22, 38
local GRIP = 16
local GAP = 6                  -- between the three panels; the divider lives in it

local builders = {}
local win
local layout          -- defined below; ResetGeometry needs it first

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Other modules register a function(win) that fills in their part of the window.
function Window.AddBuilder(fn) builders[#builders + 1] = fn end

local function maxSize()
  return math.floor(UIParent:GetWidth() * 0.96), math.floor(UIParent:GetHeight() * 0.94)
end

local function applyGeometry(f)
  local g = (A.db and A.db.window) or {}
  local maxW, maxH = maxSize()
  f:SetSize(clamp(tonumber(g.w) or Window.DEFAULT_W, Window.MIN_W, maxW),
            clamp(tonumber(g.h) or Window.DEFAULT_H, Window.MIN_H, maxH))
  f:ClearAllPoints()
  if g.point and tonumber(g.x) and tonumber(g.y) then
    f:SetPoint(g.point, UIParent, g.relPoint or g.point, g.x, g.y)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

-- Back to the default size, centered.
function Window.ResetGeometry()
  if A.db then A.db.window = {} end
  if win then
    applyGeometry(win)
    layout(win:GetWidth())
  end
end

function Window.SaveGeometry()
  if not (win and A.db) then return end
  local g = A.db.window
  g.w, g.h = win:GetWidth(), win:GetHeight()
  local point, _, relPoint, x, y = win:GetPoint(1)
  if point then g.point, g.relPoint, g.x, g.y = point, relPoint, x, y end
end

local function saved()
  return (A.db and A.db.window) or {}
end

function Window.IsCollapsed()
  return saved().collapsed == true
end

-- The body is the window less its 1px edge and the side margins.
local function bodyWidth(width) return width - 1 - 2 * PAD end

-- Detail panel width limits: at least DETAIL_MIN, at most what leaves the list RESULTS_MIN.
-- `avail` is everything to the right of the categories, which the detail panel takes when
-- the list is hidden.
local function limits(width)
  local avail = bodyWidth(width) - Window.CAT_WIDTH - GAP
  return Window.DETAIL_MIN, math.max(Window.DETAIL_MIN, avail - GAP - Window.RESULTS_MIN), avail
end

local function paintDivider()
  local collapsed = Window.IsCollapsed()
  win.collapseButton:SetLabel(collapsed and ">" or "<")
  win.collapseButton.tip = collapsed and "Show the item list" or "Hide the item list"
end

function layout(width)
  if not win then return end
  local lo, hi, avail = limits(width)
  local g = saved()
  local w
  if g.collapsed then
    w = avail
  elseif tonumber(g.detailW) then
    w = clamp(math.floor(g.detailW), lo, hi)
  else
    w = clamp(math.floor(width * Window.DETAIL_SHARE), lo, Window.DETAIL_MAX)
  end
  win.detailPanel:SetWidth(w)
  win.resultsPanel:SetShown(not g.collapsed)
  paintDivider()
end

-- Hide or show the item list. Announces LAYOUT_CHANGED when that really changes something.
function Window.SetCollapsed(on)
  on = on and true or false
  if not A.db or Window.IsCollapsed() == on then return end
  A.db.window.collapsed = on or nil
  if win then layout(win:GetWidth()) end
  A.Bus.Fire("LAYOUT_CHANGED")
end

-- Searching or picking a category needs the list, so those bring it back.
function Window.ExpandResults()
  Window.SetCollapsed(false)
end

-- Width of the detail panel as chosen by dragging the divider. Dragging while the list is
-- hidden brings it back.
function Window.SetDetailWidth(px)
  if not (A.db and win) then return end
  local lo, hi = limits(win:GetWidth())
  local g = A.db.window
  g.detailW = clamp(math.floor(px), lo, hi)
  local wasCollapsed = g.collapsed
  g.collapsed = nil
  layout(win:GetWidth())
  if wasCollapsed then A.Bus.Fire("LAYOUT_CHANGED") end
end

local function buildTitleBar(f)
  local bar = CreateFrame("Frame", nil, f)
  bar:SetHeight(TITLE_H)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  Theme.Fill(bar, C.title)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() f:StartMoving() end)
  bar:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    Window.SaveGeometry()
  end)

  local line = bar:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  line:SetHeight(1)
  Theme.SetColor(line, C.border)

  f.title = Theme.Text(bar, "title", "LEFT")
  f.title:SetPoint("LEFT", bar, "LEFT", 12, 0)
  f.title:SetText("Auctionator Almanac")

  f.closeButton = W.Button(bar, "x", function() f:Hide() end, { width = 24, height = 20, plainText = true })
  f.closeButton:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
  f.optionsButton = W.Button(bar, "Options", function()
    if A.UI.Settings then A.UI.Settings.Toggle() end
  end, { width = 64, height = 20 })
  f.optionsButton:SetPoint("RIGHT", f.closeButton, "LEFT", -6, 0)
  return bar
end

local function buildGrip(f)
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(GRIP, GRIP)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  grip:EnableMouse(true)
  local lines = {}
  for _, d in ipairs({ 4, 8, 12 }) do
    local line = grip:CreateLine(nil, "OVERLAY")
    line:SetThickness(1.5)
    line:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    line:SetStartPoint("BOTTOMRIGHT", grip, -d, 2)
    line:SetEndPoint("BOTTOMRIGHT", grip, -2, d)
    lines[#lines + 1] = line
  end
  local function tint(c)
    for _, line in ipairs(lines) do line:SetColorTexture(c[1], c[2], c[3], 1) end
  end
  grip:SetScript("OnEnter", function() tint(C.gold) end)
  grip:SetScript("OnLeave", function() tint(C.border) end)
  grip:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
  end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    Window.SaveGeometry()
  end)
  return grip
end

-- The strip between the item list and the detail panel (or between the categories and the
-- detail panel while the list is hidden). Drag it to move the edge; click the button on it to
-- hide or show the list.
local function buildDivider(f)
  local splitter = CreateFrame("Button", nil, f.body)
  f.splitter = splitter
  splitter:SetWidth(GAP)
  splitter:SetPoint("TOPRIGHT", f.detailPanel, "TOPLEFT", 0, 0)
  splitter:SetPoint("BOTTOMRIGHT", f.detailPanel, "BOTTOMLEFT", 0, 0)
  splitter:SetHitRectInsets(-3, -3, 0, 0)
  splitter:RegisterForDrag("LeftButton")

  local bar = splitter:CreateTexture(nil, "ARTWORK")
  bar:SetWidth(2)
  bar:SetPoint("TOP", splitter, "TOP", 0, -60)
  bar:SetPoint("BOTTOM", splitter, "BOTTOM", 0, 0)
  Theme.SetColor(bar, C.borderDim)
  local function tint(c) Theme.SetColor(bar, c) end

  splitter:SetScript("OnEnter", function() tint(C.gold) end)
  splitter:SetScript("OnLeave", function(self) if not self.dragging then tint(C.borderDim) end end)
  splitter:SetScript("OnDragStart", function(self)
    self.dragging = true
    tint(C.gold)
    self:SetScript("OnUpdate", function()
      local x = GetCursorPosition() / UIParent:GetEffectiveScale()
      Window.SetDetailWidth(f.body:GetRight() - x - GAP / 2)
    end)
  end)
  splitter:SetScript("OnDragStop", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
    tint(C.borderDim)
  end)

  local button = W.Button(f.body, "<", function() Window.SetCollapsed(not Window.IsCollapsed()) end,
    { width = 16, height = 44, plainText = true })
  f.collapseButton = button
  button:SetPoint("TOP", splitter, "TOP", 0, -8)
  button:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.tip or "", 1, 1, 1)
    GameTooltip:AddLine("Drag the divider to resize", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  button:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function create()
  local f = CreateFrame("Frame", Window.NAME, UIParent)
  win = f
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  local maxW, maxH = maxSize()
  if f.SetResizeBounds then
    f:SetResizeBounds(Window.MIN_W, Window.MIN_H, maxW, maxH)
  else
    f:SetMinResize(Window.MIN_W, Window.MIN_H)
    f:SetMaxResize(maxW, maxH)
  end
  applyGeometry(f)

  Theme.Fill(f, C.window)
  f.edges = Theme.Border(f, C.border, 2)

  f.titleBar = buildTitleBar(f)

  f.statusBar = CreateFrame("Frame", nil, f)
  f.statusBar:SetHeight(STATUS_H)
  f.statusBar:SetPoint("TOPLEFT", f.titleBar, "BOTTOMLEFT", 0, 0)
  f.statusBar:SetPoint("TOPRIGHT", f.titleBar, "BOTTOMRIGHT", 0, 0)
  Theme.Fill(f.statusBar, C.panelAlt)

  f.searchRow = CreateFrame("Frame", nil, f)
  f.searchRow:SetHeight(SEARCH_H)
  f.searchRow:SetPoint("TOPLEFT", f.statusBar, "BOTTOMLEFT", PAD, 0)
  f.searchRow:SetPoint("TOPRIGHT", f.statusBar, "BOTTOMRIGHT", -PAD, 0)

  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", f.searchRow, "BOTTOMLEFT", 0, 0)
  f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, GRIP + 6)

  f.catPanel = W.Panel(f.body, C.panel)
  f.catPanel:SetWidth(Window.CAT_WIDTH)
  f.catPanel:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, 0)
  f.catPanel:SetPoint("BOTTOMLEFT", f.body, "BOTTOMLEFT", 0, 0)

  f.detailPanel = W.Panel(f.body, C.panel)
  f.detailPanel:SetWidth(Window.DETAIL_MIN)
  f.detailPanel:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, 0)
  f.detailPanel:SetPoint("BOTTOMRIGHT", f.body, "BOTTOMRIGHT", 0, 0)

  f.resultsPanel = W.Panel(f.body, C.panel)
  f.resultsPanel:SetPoint("TOPLEFT", f.catPanel, "TOPRIGHT", 6, 0)
  f.resultsPanel:SetPoint("BOTTOMRIGHT", f.detailPanel, "BOTTOMLEFT", -6, 0)

  buildDivider(f)
  f.grip = buildGrip(f)

  f:SetScript("OnSizeChanged", function(_, width) layout(width) end)
  f:SetScript("OnShow", function() A.Bus.Fire("WINDOW_SHOWN") end)
  f:SetScript("OnHide", function() A.Bus.Fire("WINDOW_HIDDEN") end)
  layout(f:GetWidth())

  table.insert(UISpecialFrames, Window.NAME)

  for _, build in ipairs(builders) do
    local ok, err = pcall(build, f)
    if not ok then
      local handler = geterrorhandler and geterrorhandler()
      if handler then handler(err) end
    end
  end

  f:Hide()
  return f
end

function Window.Get()
  return win or create()
end

function Window.Show() Window.Get():Show() end
function Window.Hide() if win then win:Hide() end end

function Window.Toggle()
  local f = Window.Get()
  if f:IsShown() then f:Hide() else f:Show() end
end
