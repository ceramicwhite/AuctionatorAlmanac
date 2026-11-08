local ADDON, A = ...

-- The options dialog (also reachable from the game's addon settings list).
local Theme = A.UI.Theme
local W = A.UI.Widgets
local C = Theme.color
local Settings_ = {}
A.UI.Settings = Settings_

local WIDTH = 440
local PAD = 16
local CONFIRM_SECONDS = 4

local RANGE = { { value = 7, label = "7 days" }, { value = 21, label = "21 days" }, { value = 90, label = "90 days" }, { value = 0, label = "Everything" } }
local LEDGER_KEEP = { { value = 730, label = "2 years" }, { value = 365, label = "1 year" }, { value = 180, label = "6 months" }, { value = 0, label = "Forever" } }
local HISTORY_KEEP = { { value = 365, label = "1 year" }, { value = 180, label = "6 months" }, { value = 90, label = "3 months" } }

local function section(parent, y, text)
  local fs = Theme.Text(parent, "goldSmall", "LEFT")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
  fs:SetText(text)
  local rule = parent:CreateTexture(nil, "BORDER")
  rule:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y - 16)
  rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, y - 16)
  rule:SetHeight(1)
  Theme.SetColor(rule, C.borderDim)
  return y - 24
end

-- A button that must be clicked twice within a few seconds before it acts.
local function confirmButton(parent, label, action)
  local token = 0
  local b
  b = W.Button(parent, label, function(self)
    if self.armed then
      self.armed = false
      self:SetLabel(label)
      action()
      return
    end
    self.armed = true
    self:SetLabel("Click again to confirm")
    token = token + 1
    local mine = token
    A.After(CONFIRM_SECONDS, function()
      if token == mine and b.armed then
        b.armed = false
        b:SetLabel(label)
      end
    end)
  end, { width = (WIDTH - 2 * PAD - 8) / 2, height = 24 })
  return b
end

local function create()
  local f = CreateFrame("Frame", "AuctionatorAlmanacOptions", UIParent)
  Settings_.frame = f
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetSize(WIDTH, 372)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  Theme.Fill(f, C.window)
  Theme.Border(f, C.border, 2)

  local bar = CreateFrame("Frame", nil, f)
  bar:SetHeight(28)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  Theme.Fill(bar, C.title)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() f:StartMoving() end)
  bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  local title = Theme.Text(bar, "title", "LEFT")
  title:SetPoint("LEFT", bar, "LEFT", 12, 0)
  title:SetText("Almanac Options")
  local close = W.Button(bar, "x", function() f:Hide() end, { width = 24, height = 20, plainText = true })
  close:SetPoint("RIGHT", bar, "RIGHT", -6, 0)

  local inner = WIDTH - 2 * PAD
  local y = -40
  y = section(f, y, "Display")
  Settings_.minimapCheck = W.Checkbox(f, "Show the minimap button", function() return A.Get("minimap") ~= false end,
    function(v) A.Set("minimap", v) end, { width = inner })
  Settings_.minimapCheck:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
  y = y - 24
  Settings_.tooltipCheck = W.Checkbox(f, "Add price and ownership lines to item tooltips", function() return A.Get("tooltips") ~= false end,
    function(v) A.Set("tooltips", v) end, { width = inner })
  Settings_.tooltipCheck:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
  y = y - 32

  y = section(f, y, "History")
  local function cycle(title_, options, key)
    local c = W.Cycle(f, title_, options, function(v) A.Set(key, v) end, { width = inner, height = 24, plain = true })
    c:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    c:SetValue(A.Get(key))
    y = y - 30
    return c
  end
  Settings_.rangeCycle = cycle("Default graph range", RANGE, "historyRange")
  Settings_.ledgerCycle = cycle("Keep sales and purchases for", LEDGER_KEEP, "ledgerKeepDays")
  Settings_.historyCycle = cycle("Keep long-term price history for", HISTORY_KEEP, "historyKeepDays")
  y = y - 8

  y = section(f, y, "Data")
  local half = (inner - 8) / 2
  Settings_.resetButtons = {}
  local defs = {
    { "ledger", "Erase sales and purchases", 0, 0 },
    { "inventory", "Erase inventory snapshots", 1, 0 },
    { "history", "Erase long-term history", 0, 1 },
    { "items", "Erase item name cache", 1, 1 },
  }
  for _, d in ipairs(defs) do
    local b = confirmButton(f, d[2], function() A.Main.Reset(d[1]) end)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + d[3] * (half + 8), y - d[4] * 30)
    Settings_.resetButtons[d[1]] = b
  end
  y = y - 66
  Settings_.diagnosticsButton = W.Button(f, "Show diagnostics in chat", function() A.Debug.Print() end,
    { width = inner, height = 24 })
  Settings_.diagnosticsButton:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)

  table.insert(UISpecialFrames, "AuctionatorAlmanacOptions")
  f:Hide()      -- new frames start visible; Toggle decides when to show it
  return f
end

function Settings_.Toggle()
  local f = Settings_.frame or create()
  if f:IsShown() then
    f:Hide()
  else
    Settings_.minimapCheck:Refresh()
    Settings_.tooltipCheck:Refresh()
    Settings_.rangeCycle:SetValue(A.Get("historyRange"))
    Settings_.ledgerCycle:SetValue(A.Get("ledgerKeepDays"))
    Settings_.historyCycle:SetValue(A.Get("historyKeepDays"))
    f:Show()
  end
end

-- Adds a small page to the game's own settings list that opens this dialog.
-- Returns true when the client accepted it.
function Settings_.RegisterWithGame()
  local api = Settings
  if not (api and api.RegisterCanvasLayoutCategory and api.RegisterAddOnCategory) then return false end
  local ok = pcall(function()
    local panel = CreateFrame("Frame", nil)
    local text = Theme.Text(panel, "normal", "LEFT")
    text:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    text:SetText("Auctionator Almanac browses Auctionator's saved prices anywhere.")
    local open = W.Button(panel, "Open Almanac", function() A.UI.Window.Show() end, { width = 130, height = 24 })
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
    local options = W.Button(panel, "Options", function() Settings_.Toggle() end, { width = 100, height = 24 })
    options:SetPoint("LEFT", open, "RIGHT", 8, 0)
    local category = api.RegisterCanvasLayoutCategory(panel, "Auctionator Almanac")
    api.RegisterAddOnCategory(category)
  end)
  return ok
end
