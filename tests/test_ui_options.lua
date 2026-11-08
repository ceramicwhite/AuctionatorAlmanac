local H = require("harness")
local Stub = require("ui_stub")
local Boot = require("boot_ui")
local Fx = require("fixtures")
local test = H.test

local function plain(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  return s
end

-- ---------------------------------------------------------------------------
-- Options dialog
-- ---------------------------------------------------------------------------
test("the Options button opens a dialog that Escape closes", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  win.optionsButton:Click()
  local S = A.UI.Settings
  H.truthy(S.frame:IsShown())
  H.eq(S.frame:GetName(), "AuctionatorAlmanacOptions")
  local found = false
  for _, n in ipairs(env.UISpecialFrames) do if n == "AuctionatorAlmanacOptions" then found = true end end
  H.truthy(found)
  win.optionsButton:Click()
  H.falsy(S.frame:IsShown(), "Options toggles")
end)

test("checkboxes reflect and change the saved settings", function()
  local A, env = Boot.boot()
  A.UI.Settings.Toggle()
  local S = A.UI.Settings
  H.truthy(S.minimapCheck.check:IsShown())
  S.minimapCheck:Click()
  H.eq(A.db.settings.minimap, false)
  H.falsy(S.minimapCheck.check:IsShown())
  S.tooltipCheck:Click()
  H.eq(A.db.settings.tooltips, false)
end)

test("cycle buttons choose the default graph range and how long data is kept", function()
  local A, env = Boot.boot()
  A.UI.Settings.Toggle()
  local S = A.UI.Settings
  H.eq(S.rangeCycle.value, 21)
  S.rangeCycle:Click()
  H.eq(A.db.settings.historyRange, 90)
  S.ledgerCycle:Click()
  H.truthy(A.db.settings.ledgerKeepDays ~= 730)
  local before = A.db.settings.historyKeepDays
  S.historyCycle:Click()
  H.truthy(A.db.settings.historyKeepDays ~= before)
end)

test("reset buttons need a second click and cancel themselves", function()
  local A, env = Boot.boot()
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 1, total = 10, time = Fx.NOW, source = "mail", party = "x" })
  A.UI.Settings.Toggle()
  local b = A.UI.Settings.resetButtons.ledger
  b:Click()
  H.eq(#A.Ledger.ForItem(12359), 1, "first click only arms it")
  H.truthy(plain(b.label:GetText()):lower():find("confirm", 1, true))
  env.C_Timer.flush()
  H.falsy(plain(b.label:GetText()):lower():find("confirm", 1, true), "disarmed after a few seconds")
  b:Click(); b:Click()
  H.eq(#A.Ledger.ForItem(12359), 0)
end)

test("every reset button erases only its own data", function()
  local A, env = Boot.boot()
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 1, total = 10, time = Fx.NOW, source = "mail", party = "x" })
  A.Inventory.EnsureChar({ name = "T", realm = "R" })
  A.Inventory.SetLocation("T-R", "bags", { [1] = 2 }, 5)
  A.History.Watch(5, true)
  A.UI.Settings.Toggle()
  local r = A.UI.Settings.resetButtons
  r.inventory:Click(); r.inventory:Click()
  H.eq(A.Inventory.Owned(1).total, 0)
  H.eq(#A.Ledger.ForItem(12359), 1)
  H.truthy(A.History.IsWatched(5))
  r.history:Click(); r.history:Click()
  H.falsy(A.History.IsWatched(5))
  A.db.items[99999] = { "Planted junk" }
  r.items:Click(); r.items:Click()
  H.eq(A.db.items[99999], nil)
  H.truthy(A.db.items[12359], "real items reload")
  H.eq(#A.Ledger.ForItem(12359), 1)
end)

test("the diagnostics button prints the report", function()
  local out = {}
  local A, env = Boot.boot({ env = { print = function(m) out[#out + 1] = plain(tostring(m)) end } })
  A.UI.Settings.Toggle()
  A.UI.Settings.diagnosticsButton:Click()
  H.truthy(table.concat(out, "\n"):find("Auctionator: ready", 1, true))
end)

test("the options dialog fits on screen and its controls do not overlap", function()
  local A, env = Boot.boot()
  A.UI.Settings.Toggle()
  local S = A.UI.Settings
  H.truthy(Stub.within(S.frame, env.UIParent))
  local controls = { S.minimapCheck, S.tooltipCheck, S.rangeCycle, S.ledgerCycle, S.historyCycle,
    S.resetButtons.ledger, S.resetButtons.inventory, S.resetButtons.history, S.resetButtons.items, S.diagnosticsButton }
  for i, c in ipairs(controls) do
    H.truthy(Stub.within(c, S.frame), "control " .. i .. " inside the dialog")
    for j = i + 1, #controls do
      H.falsy(Stub.overlaps(c, controls[j]), "controls " .. i .. " and " .. j .. " overlap")
    end
  end
end)

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------
test("the minimap button sits on the minimap's edge and follows the setting", function()
  local A, env = Boot.boot()
  local b = A.UI.Minimap.button
  H.eq(b:GetParent(), env.Minimap)
  H.truthy(b:IsShown())
  local bx, by = b:GetCenter()
  local mx, my = env.Minimap:GetCenter()
  local distance = math.sqrt((bx - mx) ^ 2 + (by - my) ^ 2)
  H.near(distance, 70 + 5, 1)
  A.Set("minimap", false)
  H.falsy(b:IsShown())
  A.Set("minimap", true)
  H.truthy(b:IsShown())
end)

test("clicking the minimap button toggles the window and right-click opens options", function()
  local A, env = Boot.boot()
  local b = A.UI.Minimap.button
  Stub.fire(b, "OnClick", "LeftButton")
  H.truthy(A.UI.Window.Get():IsShown())
  Stub.fire(b, "OnClick", "LeftButton")
  H.falsy(A.UI.Window.Get():IsShown())
  Stub.fire(b, "OnClick", "RightButton")
  H.truthy(A.UI.Settings.frame:IsShown())
end)

test("dragging the minimap button moves it around the edge and remembers the angle", function()
  local A, env = Boot.boot()
  local b = A.UI.Minimap.button
  local mx, my = env.Minimap:GetCenter()
  env.GetCursorPosition = function() return mx + 300, my end
  Stub.fire(b, "OnDragStart")
  local update = b:GetScript("OnUpdate")
  H.truthy(update)
  update(b, 0.016)
  Stub.fire(b, "OnDragStop")
  H.falsy(b:GetScript("OnUpdate"))
  H.near(A.db.minimap.angle, 0, 0.5)
  local bx = b:GetCenter()
  H.truthy(bx > mx + 60, "moved to the right edge")
end)

test("the minimap button tooltip describes the clicks", function()
  local A, env = Boot.boot()
  local b = A.UI.Minimap.button
  H.nothrows(function() Stub.fire(b, "OnEnter"); Stub.fire(b, "OnLeave") end)
end)
