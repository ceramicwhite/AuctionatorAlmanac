local ADDON, A = ...

-- The options dialog (also reachable from the game's addon settings list).
local Theme = A.UI.Theme
local W = A.UI.Widgets
local C = Theme.color
local Settings_ = {}
A.UI.Settings = Settings_

local WIDTH = 440
local PAD = 16

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

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

local function plural(n, word) return A.Format.Count(n) .. " " .. word .. (n == 1 and "" or "s") end

-- Each erase asks first, in a window of its own, and says exactly what would be lost.
-- `what` is built when the question is asked so the numbers are current.
local ERASE = {
  ledger = {
    label = "Erase sales and purchases", title = "Erase sales and purchases?",
    what = function()
      local n = #A.db.ledger.entries
      return "all " .. A.Format.Count(n) .. (n == 1 and " recorded entry" or " recorded entries")
        .. " (sales, purchases, postings, expired and cancelled auctions)"
    end,
  },
  inventory = {
    label = "Erase inventory snapshots", title = "Erase inventory snapshots?",
    what = function()
      return "what Almanac knows about the bags, bank, mail and auctions of " .. plural(count(A.db.chars), "character")
        .. ". Each fills in again the next time that character logs in"
    end,
  },
  history = {
    label = "Erase long-term history", title = "Erase long-term history?",
    what = function()
      return "the long-term price history of " .. plural(count(A.db.history.items), "item")
        .. ", plus your watch list (" .. A.Format.Count(count(A.db.history.watched)) .. ") and recently viewed items"
    end,
  },
  items = {
    label = "Erase item name cache", title = "Erase the item name cache?",
    what = function()
      return "the cached names and icons of " .. plural(count(A.db.items), "item")
        .. ". They reload by themselves, which takes about half a minute"
    end,
  },
  discovery = {
    label = "Erase new-find memory", title = "Erase the new-find memory?",
    what = function()
      return "what Almanac remembers about when " .. plural(A.Discovery.Count(), "item")
        .. " were first seen. The New finds list starts over from today"
    end,
  },
}

local function eraseButton(parent, key)
  local def = ERASE[key]
  return W.Button(parent, def.label, function()
    W.Confirm({
      title = def.title,
      message = "This will permanently erase " .. def.what() .. ".\n\n"
        .. Theme.Colorize("This cannot be undone.", Theme.hex.bad),
      confirmLabel = "Erase",
      onConfirm = function() A.Main.Reset(key) end,
    })
  end, { width = (WIDTH - 2 * PAD - 8) / 2, height = 24 })
end

local function create()
  local f = CreateFrame("Frame", "AuctionatorAlmanacOptions", UIParent)
  Settings_.frame = f
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetSize(WIDTH, 402)
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
    { "ledger", 0, 0 }, { "inventory", 1, 0 },
    { "history", 0, 1 }, { "items", 1, 1 },
    { "discovery", 0, 2 },
  }
  for _, d in ipairs(defs) do
    local b = eraseButton(f, d[1])
    b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + d[2] * (half + 8), y - d[3] * 30)
    Settings_.resetButtons[d[1]] = b
  end
  y = y - 96
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
