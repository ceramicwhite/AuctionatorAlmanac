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

local function printer()
  local out = {}
  return out, function(msg) out[#out + 1] = plain(tostring(msg)) end
end

local function joined(out) return table.concat(out, "\n") end

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------
test("the diagnostics report lists every API the addon relies on and Auctionator's state", function()
  local A = Boot.boot()
  local text = table.concat(A.Debug.Lines(), "\n")
  H.truthy(text:find("C_Item.GetItemInfo: ok", 1, true), text)
  H.truthy(text:find("Auctionator: ready", 1, true), text)
  H.truthy(text:find("Items priced: 5", 1, true), text)
  H.truthy(text:find("Ledger entries: 0", 1, true), text)
  A.env.C_Container = nil
  text = table.concat(A.Debug.Lines(), "\n")
  H.truthy(text:find("C_Container.GetContainerNumSlots: MISSING", 1, true), text)
end)

test("diagnostics explain when Auctionator is not ready", function()
  local A = Boot.boot({ fixture = { Auctionator = false } })
  H.truthy(table.concat(A.Debug.Lines(), "\n"):find("Auctionator: NOT ready", 1, true))
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
test("/almanac is registered and toggles the window", function()
  local A, env = Boot.boot()
  H.eq(env.SLASH_ALMANAC1, "/almanac")
  H.eq(type(env.SlashCmdList.ALMANAC), "function")
  env.SlashCmdList.ALMANAC("")
  H.truthy(A.UI.Window.Get():IsShown())
  env.SlashCmdList.ALMANAC("")
  H.falsy(A.UI.Window.Get():IsShown())
  H.eq(type(env.AuctionatorAlmanac_Toggle), "function")
  env.AuctionatorAlmanac_Toggle()
  H.truthy(A.UI.Window.Get():IsShown())
end)

test("/almanac search opens the window with that search", function()
  local A, env = Boot.boot()
  A.Slash.Handle("search thorium")
  env.C_Timer.flush()
  H.truthy(A.UI.Window.Get():IsShown())
  H.eq(A.Controller.state.text, "thorium")
  H.eq(#A.Controller.results, 2)
  H.eq(A.UI.Window.Get().searchBox:GetText(), "thorium")
end)

test("/almanac debug prints the report and unknown commands print help", function()
  local out, print = printer()
  local A = Boot.boot({ env = { print = print } })
  A.Slash.Handle("debug")
  H.truthy(joined(out):find("Auctionator: ready", 1, true))
  local before = #out
  A.Slash.Handle("frobnicate")
  H.truthy(#out > before)
  H.truthy(joined(out):lower():find("/almanac", 1, true))
end)

test("reset commands only erase data when confirmed", function()
  local out, print = printer()
  local A = Boot.boot({ env = { print = print } })
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 1, total = 10, time = Fx.NOW, source = "mail", party = "x" })
  A.Slash.Handle("reset ledger")
  H.eq(#A.Ledger.ForItem(12359), 1, "not erased without confirm")
  H.truthy(joined(out):find("confirm", 1, true))
  A.Slash.Handle("reset ledger confirm")
  H.eq(#A.Ledger.ForItem(12359), 0)
  A.Inventory.EnsureChar({ name = "T", realm = "R" })
  A.Inventory.SetLocation("T-R", "bags", { [1] = 2 }, 5)
  A.Slash.Handle("reset inventory confirm")
  H.eq(A.Inventory.Owned(1).total, 0)
  A.History.Watch(5, true)
  A.Slash.Handle("reset history confirm")
  H.falsy(A.History.IsWatched(5))
  A.db.items[99999] = { "Planted junk" }
  A.Slash.Handle("reset items confirm")
  H.eq(A.db.items[99999], nil, "the old cache is gone")
  H.truthy(A.db.items[12359], "and the real items are loaded again straight away")
  A.db.window.w = 1234
  A.Slash.Handle("reset window")
  H.eq(A.db.window.w, nil)
end)

test("/almanac refresh reloads Auctionator's data", function()
  local A, env = Boot.boot()
  local reloads = 0
  A.Bus.On("DATA_RELOADED", function() reloads = reloads + 1 end)
  A.Slash.Handle("refresh")
  env.C_Timer.flush()
  H.eq(reloads, 1)
end)

-- ---------------------------------------------------------------------------
-- Tooltip lines
-- ---------------------------------------------------------------------------
local function fakeTooltip()
  local t = { lines = {} }
  function t:AddLine(text) self.lines[#self.lines + 1] = plain(text) end
  function t:AddDoubleLine(l, r) self.lines[#self.lines + 1] = plain(l) .. " | " .. plain(r) end
  return t
end

test("tooltip lines show the lowest price and where you own the item", function()
  local A = Boot.boot()
  A.Inventory.EnsureChar({ name = "Thornwick", realm = "Whitemane" })
  A.Inventory.EnsureChar({ name = "Mule", realm = "Whitemane" })
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [12359] = 6 }, 1)
  A.Inventory.SetLocation("Mule-Whitemane", "mail", { [12359] = 4 }, 1)
  local lines = A.Tooltip.LinesFor(12359)
  local text = {}
  for _, l in ipairs(lines) do text[#text + 1] = plain(l.left) .. (l.right and (" | " .. plain(l.right)) or "") end
  local joinedText = table.concat(text, "\n")
  H.truthy(joinedText:find("Almanac", 1, true), joinedText)
  H.truthy(joinedText:find("1g 12s 40c", 1, true), joinedText)
  H.truthy(joinedText:find("You own 10", 1, true) or joinedText:find("own", 1, true), joinedText)
  H.truthy(joinedText:find("Thornwick 6", 1, true), joinedText)
  H.truthy(joinedText:find("Mule 4", 1, true), joinedText)
  H.eq(A.Tooltip.LinesFor(99999), {})
end)

test("the tooltip hook adds lines to item tooltips and respects the setting", function()
  local captured
  local A = Boot.boot({ env = {
    Enum = { TooltipDataType = { Item = 0 }, BagIndex = {}, AuctionStatus = { Active = 0 } },
    TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) captured = { kind = kind, fn = fn } end },
  } })
  H.truthy(A.Tooltip.Install())
  H.eq(captured.kind, 0)
  local quiet = fakeTooltip()
  captured.fn(quiet, { id = 12359 })
  H.eq(#quiet.lines, 0, "off by default")
  A.db.settings.tooltips = true
  local tip = fakeTooltip()
  captured.fn(tip, { id = 12359 })
  H.truthy(#tip.lines >= 1)
  A.db.settings.tooltips = false
  local off = fakeTooltip()
  captured.fn(off, { id = 12359 })
  H.eq(#off.lines, 0)
  A.db.settings.tooltips = true
  local none = fakeTooltip()
  H.nothrows(function() captured.fn(none, nil); captured.fn(none, {}); captured.fn(none, { id = "x" }) end)
  H.eq(#none.lines, 0)
  A.env.issecretvalue = function() return true end
  local secret = fakeTooltip()
  captured.fn(secret, { id = 12359 })
  H.eq(#secret.lines, 0, "secret values are never touched")
end)

test("the tooltip hook is skipped quietly when the client has no tooltip processor", function()
  local A = Boot.boot()
  H.falsy(A.Tooltip.Install())
end)

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------
test("ADDON_LOADED sets up saved variables once, for this addon only", function()
  local A, env = Boot.boot({ raw = true })
  env.ALMANAC_DB = { version = 1, ledger = { entries = { { id = 1, kind = "sold", itemID = 5, qty = 1, time = 1, source = "mail" } }, seq = 1 } }
  A.FireEvent("ADDON_LOADED", "SomeOtherAddon")
  H.eq(A.db, nil)
  A.FireEvent("ADDON_LOADED", "AuctionatorAlmanac")
  H.truthy(A.db)
  H.eq(env.ALMANAC_DB, A.db, "the saved variable is the live database")
  H.eq(#A.Ledger.ForItem(5), 1, "saved ledger survives")
end)

test("PLAYER_LOGIN loads Auctionator's data once it is ready and imports postings", function()
  local A, env = Boot.boot({ raw = true, keepPostings = true })
  A.FireEvent("ADDON_LOADED", "AuctionatorAlmanac")
  A.FireEvent("PLAYER_LOGIN")
  env.C_Timer.flush()
  H.truthy(A.Controller.ready)
  H.eq(#A.Controller.ids, 5)
  H.eq(#A.Ledger.ForItem(12359), 2, "two posting-history rows imported")
  H.eq(#A.Ledger.ForItem(19019), 1)
end)

test("login waits for Auctionator, then gives up quietly", function()
  local out, print = printer()
  local A, env = Boot.boot({ raw = true, fixture = { Auctionator = false }, env = { print = print } })
  A.FireEvent("ADDON_LOADED", "AuctionatorAlmanac")
  A.FireEvent("PLAYER_LOGIN")
  local ran = env.C_Timer.flush(1000)
  H.truthy(ran < 1000, "the retry loop ends")
  H.falsy(A.Controller.ready)
  H.truthy(A.Main.gaveUp)
  H.eq(#out, 1, "one message, not a flood")
end)

test("a late Auctionator is picked up the next time the window opens", function()
  local _, quiet = printer()
  local A, env = Boot.boot({ raw = true, env = { print = quiet } })
  local real = env.Auctionator
  env.Auctionator = nil
  A.FireEvent("ADDON_LOADED", "AuctionatorAlmanac")
  A.FireEvent("PLAYER_LOGIN")
  env.C_Timer.flush(1000)
  H.falsy(A.Controller.ready)
  env.Auctionator = real
  A.UI.Window.Show()
  env.C_Timer.flush()
  H.truthy(A.Controller.ready)
end)

test("leaving the Auction House refreshes the data and re-imports postings", function()
  local A, env = Boot.boot({ raw = true, keepPostings = true })
  A.FireEvent("ADDON_LOADED", "AuctionatorAlmanac")
  A.FireEvent("PLAYER_LOGIN")
  env.C_Timer.flush()
  local reloads = 0
  A.Bus.On("DATA_RELOADED", function() reloads = reloads + 1 end)
  table.insert(env.AUCTIONATOR_POSTING_HISTORY["12359"], { price = 12500, quantity = 3, time = Fx.NOW - 10 })
  A.Bus.Fire("AH_CLOSED")
  env.C_Timer.flush()
  H.eq(reloads, 1)
  H.eq(#A.Ledger.ForItem(12359), 3)
end)

test("a reload snapshots long-term history for items you own or trade", function()
  local A, env = Boot.boot({ raw = true })
  A.FireEvent("ADDON_LOADED", "AuctionatorAlmanac")
  A.Inventory.EnsureChar({ name = "T", realm = "R" })
  A.Inventory.SetLocation("T-R", "bags", { [12359] = 3 }, 1)
  A.FireEvent("PLAYER_LOGIN")
  env.C_Timer.flush()
  H.truthy(A.History.Series(12359), "owned item is tracked")
  H.eq(A.History.Series(10620), nil, "unrelated item is not")
end)

test("old ledger entries are pruned on reload", function()
  local A, env = Boot.boot({ raw = true })
  A.FireEvent("ADDON_LOADED", "AuctionatorAlmanac")
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 1, total = 1, time = Fx.NOW - 900 * 86400, source = "mail", party = "old" })
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 1, total = 2, time = Fx.NOW - 86400, source = "mail", party = "new" })
  A.FireEvent("PLAYER_LOGIN")
  env.C_Timer.flush()
  local rows = A.Ledger.ForItem(12359)
  local sold = 0
  for _, r in ipairs(rows) do if r.kind == "sold" then sold = sold + 1 end end
  H.eq(sold, 1)
end)

-- ---------------------------------------------------------------------------
-- New-find memory is wired into startup and the reset commands
-- ---------------------------------------------------------------------------
test("the first data load remembers when each item was first seen", function()
  local Boot = require("boot_ui")
  local A = Boot.boot()
  H.eq(A.Discovery.Floor(), 1000, "the first day of data is the floor")
  H.eq(A.Discovery.FirstSeen(12359), 1000)
  H.eq(A.Discovery.FirstSeen(12363), 1005, "Arcane Crystal first appeared on the newest day")
end)

test("a later scan reveals items that appeared since, and a reset forgets what was seen", function()
  local Boot = require("boot_ui")
  local A, env = Boot.boot()
  env.AUCTIONATOR_PRICE_DATABASE.TestRealm["10620"].h["1006"] = 4900
  env.AUCTIONATOR_PRICE_DATABASE.TestRealm["99999"] = { m = 7000, h = { ["1006"] = 7000 }, l = {}, a = { ["1006"] = 5 } }
  env.time = function() return require("fixtures").NOW + 86400 end
  A.Controller.Reload()
  env.C_Timer.flush()
  H.eq(A.Discovery.FirstSeen(99999), 1006)
  A.db.discovery.first[424242] = 900          -- something the reset must forget
  H.truthy(A.Main.Reset("discovery"))
  H.eq(A.Discovery.FirstSeen(424242), nil, "the old memory is gone")
  H.eq(A.Discovery.FirstSeen(99999), 1006, "and it starts over from what Auctionator has now")
  H.eq(A.Discovery.Floor(), 1000)
  H.eq(A.Main.Reset("nonsense"), false)
end)
