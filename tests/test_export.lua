local H = require("harness")
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

-- The addon booted with a character, so the export can say who wrote it.
local function boot(extra)
  local env = {
    UnitName = function() return "Thrall" end,
    GetRealmName = function() return "TestRealm" end,
    UnitFactionGroup = function() return "Horde" end,
    GetAddOnMetadata = function(_, field) if field == "Version" then return "1.3.0" end end,
  }
  for k, v in pairs(extra or {}) do env[k] = v end
  return Boot.boot({ env = env })
end

-- ---------------------------------------------------------------------------
-- Packing one item
-- ---------------------------------------------------------------------------
test("Pack renders the last price and each day as day,low,high,qty", function()
  local A = boot()
  local packed = A.Export.Pack({
    last = 11240,
    days = { { day = 1000, low = 11000, high = 11500, qty = 40 }, { day = 1001, low = 11300, high = 11300, qty = 35 } },
  })
  H.eq(packed, "11240|1000,11000,11500,40;1001,11300,11300,35")
end)

test("Pack leaves quantity empty when unknown and the last price empty when absent", function()
  local A = boot()
  H.eq(A.Export.Pack({ days = { { day = 5, low = 100, high = 100 } } }), "|5,100,100,")
  H.eq(A.Export.Pack({ last = 9, days = {} }), "9|")
end)

test("Pack writes whole numbers whatever float it is given", function()
  local A = boot()
  H.eq(A.Export.Pack({ last = 1234.0, days = { { day = 7.0, low = 1000.0, high = 1100.0, qty = 3.0 } } }), "1234|7,1000,1100,3")
end)

-- ---------------------------------------------------------------------------
-- Building the block
-- ---------------------------------------------------------------------------
test("Build covers plain, gear and suffix keys and skips pets and junk", function()
  local A = boot()
  local block = A.Export.Build()
  H.truthy(block, "a block is built")
  local keys = {}
  for k in pairs(block.market) do keys[#keys + 1] = k end
  table.sort(keys)
  H.eq(table.concat(keys, ","), "10620,12359,12363,19019,g:19019:60,gr:15001:of the Eagle")
  H.eq(block.market["12359"], "11240|1000,11000,11500,40;1001,11300,11300,35;1003,10800,11800,52;1004,11000,11000,30;1005,10900,11240,44")
  H.eq(block.market["10620"], "4810|1002,5000,5000,;1005,4810,4810,", "old data without quantities")
end)

test("Build records where, who and when", function()
  local A = boot()
  local block = A.Export.Build()
  H.eq(block.format, 1)
  H.eq(block.realm, "TestRealm")
  H.eq(block.faction, "Horde")
  H.eq(block.character, "Thrall-TestRealm")
  H.eq(block.today, Fx.TODAY)
  H.eq(block.generatedAt, Fx.NOW)
  H.eq(block.addon, "1.3.0")
  H.eq(block.house, nil, "the auction house is not known in this version")
end)

test("Build says why when Auctionator's data is not ready", function()
  local A, env = boot()
  env.Auctionator.State.Loaded = false
  local block, reason = A.Export.Build()
  H.eq(block, nil)
  H.truthy(type(reason) == "string" and reason ~= "", "a reason is given")
end)

test("Build skips a malformed series instead of failing, and counts it", function()
  local A, env = boot()
  env.Auctionator.Database.db["777"] = { m = "x", h = { ["1000"] = "bad" }, l = {}, a = {} }
  local block = A.Export.Build()
  H.truthy(block)
  H.eq(block.market["777"], nil)
  H.truthy(block.market["12359"], "everything else is still there")
  H.eq(A.Export.last.skipped, 1)
  H.eq(A.Export.last.items, 6)
end)

-- ---------------------------------------------------------------------------
-- Writing it into the saved variables
-- ---------------------------------------------------------------------------
test("the setting is on by default, including for saves from before it existed", function()
  local A = boot()
  H.eq(A.db.settings.siteExport, true)
  local B = Boot.boot({ saved = { version = 2, settings = { minimap = false } } })
  H.eq(B.db.settings.siteExport, true)
  H.eq(B.db.settings.minimap, false, "the player's other choices are kept")
end)

test("Write puts the block in the saved variables when the data is ready", function()
  local A = boot()
  H.eq(A.db.export, nil)
  H.eq(A.Export.Write(), "written")
  H.eq(A.db.export.format, 1)
  H.truthy(A.db.export.market["19019"])
end)

test("Write keeps the previous block when Auctionator is not ready, never wiping it", function()
  local A, env = boot()
  A.Export.Write()
  local before = A.db.export
  env.Auctionator.State.Loaded = false
  env.time = function() return Fx.NOW + 5000 end
  H.eq(A.Export.Write(), "kept")
  H.eq(A.db.export, before)
  H.eq(A.db.export.generatedAt, Fx.NOW)
end)

test("Write removes the block and reports off when the setting is off", function()
  local A = boot()
  A.Export.Write()
  A.Set("siteExport", false)
  H.eq(A.Export.Write(), "off")
  H.eq(A.db.export, nil)
end)

test("logging out or reloading writes the block", function()
  local A = boot()
  H.eq(A.db.export, nil)
  A.FireEvent("PLAYER_LOGOUT")
  H.truthy(A.db.export and A.db.export.market["12359"])
end)

test("a failing build never raises out of the logout handler", function()
  local A, env = boot()
  env.Auctionator.Database = { db = setmetatable({}, { __pairs = function() error("boom") end }) }
  A.FireEvent("PLAYER_LOGOUT")
  H.truthy(true, "no error escaped")
end)

-- ---------------------------------------------------------------------------
-- Telling the player
-- ---------------------------------------------------------------------------
test("/almanac export says what the next save will contain", function()
  local out, print = printer()
  local A = boot({ print = print })
  A.Slash.Handle("export")
  local text = table.concat(out, "\n")
  H.truthy(text:find("6 items", 1, true), text)
  H.truthy(text:find("TestRealm", 1, true), text)
  H.truthy(text:lower():find("/reload", 1, true) or text:lower():find("log out", 1, true), text)
end)

test("/almanac export says when it is off and when there is nothing to export", function()
  local out, print = printer()
  local A, env = boot({ print = print })
  A.Set("siteExport", false)
  A.Slash.Handle("export")
  H.truthy(table.concat(out, "\n"):lower():find("off", 1, true))
  A.Set("siteExport", true)
  env.Auctionator.State.Loaded = false
  out[#out + 1] = "--"
  A.Slash.Handle("export")
  H.truthy(table.concat(out, "\n"):lower():find("not loaded", 1, true) or table.concat(out, "\n"):lower():find("not ready", 1, true))
end)

test("/almanac debug includes a website export line", function()
  local A = boot()
  A.Export.Write()
  local text = table.concat(A.Debug.Lines(), "\n")
  H.truthy(text:find("Website export: on", 1, true), text)
  H.truthy(text:find("6 items", 1, true), text)
end)

-- ---------------------------------------------------------------------------
-- The option
-- ---------------------------------------------------------------------------
test("the Options window has a website checkbox, on by default, that changes the setting", function()
  local A = boot()
  A.UI.Settings.Toggle()
  local S = A.UI.Settings
  H.truthy(S.siteExportCheck, "there is an option for it")
  H.truthy(S.siteExportCheck.check:IsShown(), "on by default")
  local fired
  A.Bus.On("SETTINGS_CHANGED", function(key, value) fired = key .. "=" .. tostring(value) end)
  S.siteExportCheck:Click()
  H.eq(A.db.settings.siteExport, false)
  H.eq(fired, "siteExport=false")
  H.falsy(S.siteExportCheck.check:IsShown())
  H.truthy(plain(S.siteExportNote:GetText()):lower():find("website", 1, true))
end)
