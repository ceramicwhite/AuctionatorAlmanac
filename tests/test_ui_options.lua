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
  H.falsy(S.tooltipCheck.check:IsShown(), "tooltip lines start off")
  S.tooltipCheck:Click()
  H.eq(A.db.settings.tooltips, true)
  H.truthy(S.tooltipCheck.check:IsShown())
  S.tooltipCheck:Click()
  H.eq(A.db.settings.tooltips, false)
end)

test("the Auction House scan option is on by default and can be switched off", function()
  local A, env = Boot.boot()
  A.UI.Settings.Toggle()
  local S = A.UI.Settings
  H.truthy(S.autoScanCheck, "there is an option for it")
  H.truthy(S.autoScanCheck.check:IsShown(), "on by default")
  S.autoScanCheck:Click()
  H.eq(A.db.settings.autoScan, false)
  H.falsy(S.autoScanCheck.check:IsShown())
  S.autoScanCheck:Click()
  H.eq(A.db.settings.autoScan, true)
  H.truthy(plain(S.autoScanNote:GetText()):lower():find("15 minutes", 1, true), "says how often it can scan")
  H.truthy(plain(S.autoScanCheck.label:GetText()):lower():find("auction house", 1, true))
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

test("an erase button asks first and erases nothing until the player confirms", function()
  local A, env = Boot.boot()
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 1, total = 10, time = Fx.NOW, source = "mail", party = "x" })
  A.UI.Settings.Toggle()
  local b = A.UI.Settings.resetButtons.ledger
  local label = b.label:GetText()
  b:Click()
  local dlg = A.UI.Widgets.confirmFrame
  H.truthy(dlg:IsShown(), "a confirmation window opens")
  H.eq(#A.Ledger.ForItem(12359), 1, "nothing is erased yet")
  H.eq(b.label:GetText(), label, "the button itself does not change")
  local text = plain(dlg.message:GetText()):lower()
  H.truthy(text:find("cannot be undone", 1, true), text)
  H.truthy(plain(dlg.title:GetText()):lower():find("erase", 1, true))
  dlg.cancelButton:Click()
  H.falsy(dlg:IsShown())
  H.eq(#A.Ledger.ForItem(12359), 1, "cancel keeps the data")
  b:Click()
  A.UI.Widgets.confirmFrame.confirmButton:Click()
  H.eq(#A.Ledger.ForItem(12359), 0, "confirm erases it")
  H.falsy(A.UI.Widgets.confirmFrame:IsShown())
end)

test("the question says what will be lost and how much", function()
  local A, env = Boot.boot()
  for i = 1, 3 do
    A.Ledger.Add({ kind = "sold", itemID = 12359, qty = i, total = 10 * i, time = Fx.NOW - i, source = "mail", party = "x" })
  end
  A.Inventory.EnsureChar({ name = "T", realm = "R" })
  A.Inventory.SetLocation("T-R", "bags", { [1] = 2 }, 5)
  A.History.Watch(5, true)
  A.UI.Settings.Toggle()
  local r = A.UI.Settings.resetButtons
  local function question(key)
    r[key]:Click()
    local text = plain(A.UI.Widgets.confirmFrame.message:GetText())
    A.UI.Widgets.confirmFrame.cancelButton:Click()
    return text:lower()
  end
  H.truthy(question("ledger"):find("3", 1, true) and question("ledger"):find("sales", 1, true))
  H.truthy(question("inventory"):find("character", 1, true))
  H.truthy(question("history"):find("watch", 1, true), "erasing history also clears the watch list, so it says so")
  H.truthy(question("items"):find("name", 1, true))
  H.truthy(question("discovery"):find("new find", 1, true))
  H.truthy(question("searches"):find("search", 1, true))
end)

test("the question appears in front of the options dialog", function()
  local A, env = Boot.boot()
  A.UI.Settings.Toggle()
  A.UI.Settings.resetButtons.items:Click()
  H.eq(A.UI.Widgets.confirmFrame:GetFrameStrata(), "FULLSCREEN_DIALOG")
  H.eq(A.UI.Settings.frame:GetFrameStrata(), "DIALOG")
  A.UI.Widgets.confirmFrame.cancelButton:Click()
end)

test("every erase button erases only its own data, and only after confirmation", function()
  local A, env = Boot.boot()
  local function confirm(button)
    button:Click()
    A.UI.Widgets.confirmFrame.confirmButton:Click()
  end
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 1, total = 10, time = Fx.NOW, source = "mail", party = "x" })
  A.Inventory.EnsureChar({ name = "T", realm = "R" })
  A.Inventory.SetLocation("T-R", "bags", { [1] = 2 }, 5)
  A.History.Watch(5, true)
  A.UI.Settings.Toggle()
  local r = A.UI.Settings.resetButtons
  confirm(r.inventory)
  H.eq(A.Inventory.Owned(1).total, 0)
  H.eq(#A.Ledger.ForItem(12359), 1)
  H.truthy(A.History.IsWatched(5))
  confirm(r.history)
  H.falsy(A.History.IsWatched(5))
  H.truthy(A.Discovery.Count() > 0, "history is separate from the new-find memory")
  A.db.items[99999] = { "Planted junk" }
  confirm(r.items)
  H.eq(A.db.items[99999], nil)
  H.truthy(A.db.items[12359], "real items reload")
  H.eq(#A.Ledger.ForItem(12359), 1)
  A.db.discovery.first[424242] = 900
  confirm(r.discovery)
  H.eq(A.Discovery.FirstSeen(424242), nil)
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
  local controls = { S.autoScanCheck, S.autoScanNote, S.siteExportCheck, S.siteExportNote, S.minimapCheck, S.tooltipCheck, S.rangeCycle, S.ledgerCycle, S.historyCycle,
    S.resetButtons.ledger, S.resetButtons.inventory, S.resetButtons.history, S.resetButtons.items, S.resetButtons.discovery,
    S.resetButtons.searches, S.diagnosticsButton }
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
