local H = require("harness")
local Boot = require("boot_ui")
local test = H.test

-- A stand-in for one of Auctionator's scan frames (the thing its Full Scan button presses).
local function scanFrame(ready)
  local f = { ready = ready ~= false, started = 0, asked = 0 }
  function f:IsAutoscanReady() self.asked = self.asked + 1; return self.ready end
  function f:InitiateScan() self.started = self.started + 1 end
  return f
end

-- Boots the whole addon with Auctionator's scan frames and an open Auction House.
-- o.replicate: Auctionator's "full (replicate) scan" setting; o.frames = false: Auctionator has not built them yet.
local function setup(o)
  o = o or {}
  local A, env = Boot.boot({ env = { Enum = { PlayerInteractionType = { Auctioneer = 21, Banker = 8 } } } })
  local s = { A = A, env = env, full = scanFrame(), browse = scanFrame(), ah = { shown = true }, sets = {}, replicate = o.replicate }
  local auctionator = env.Auctionator
  if o.frames ~= false then
    auctionator.State.FullScanFrameRef = s.full
    auctionator.State.IncrementalScanFrameRef = s.browse
  end
  auctionator.Config.Options.REPLICATE_SCAN = "replicate_scan_3"
  local original = auctionator.Config.Get
  auctionator.Config.Get = function(option)
    if option == "replicate_scan_3" then return s.replicate end
    return original(option)
  end
  auctionator.Config.Set = function(...) s.sets[#s.sets + 1] = { ... } end     -- Almanac must never call this
  env.AuctionHouseFrame = { IsShown = function() return s.ah.shown end }
  function s.open() A.FireEvent("AUCTION_HOUSE_SHOW") end
  function s.close() s.ah.shown = false; A.FireEvent("AUCTION_HOUSE_CLOSED") end
  return s
end

-- ---------------------------------------------------------------------------
-- When it scans
-- ---------------------------------------------------------------------------
test("opening the Auction House starts the same scan the Full Scan button would", function()
  local s = setup({ replicate = true })
  s.open()
  H.eq(s.full.started, 0, "not instantly: Auctionator is still setting up")
  s.env.C_Timer.flush()
  H.eq(s.full.started, 1, "a full (replicate) scan when Auctionator is set to those")
  H.eq(s.browse.started, 0)
end)

test("with Auctionator on its browse scan, that is the one it starts", function()
  local s = setup({ replicate = false })
  s.open()
  s.env.C_Timer.flush()
  H.eq(s.browse.started, 1)
  H.eq(s.full.started, 0)
end)

test("it waits until after Auctionator's own two-second autoscan could have run", function()
  local s = setup()
  s.open()
  local first = s.env.C_Timer.queue[1]
  H.truthy(first and first.sec >= 3, "first check after " .. tostring(first and first.sec) .. "s")
end)

test("it only scans when Auctionator says a scan is due", function()
  local s = setup({ replicate = true })
  s.full.ready = false                       -- scanned recently, or its interval has not passed
  s.open()
  s.env.C_Timer.flush()
  H.eq(s.full.started, 0)
  H.truthy(s.full.asked >= 1, "it did ask")
  H.eq(s.A.AutoScan.last, "not ready")
end)

test("it does not scan again if Auctionator's own autoscan already did", function()
  local s = setup({ replicate = true })
  -- Auctionator's autoscan ran at 2s, which makes its own frame report "not ready" afterwards
  s.A.env.C_Timer.After(0, function() s.full.ready = false end)
  s.open()
  s.env.C_Timer.flush()
  H.eq(s.full.started, 0)
end)

test("a later visit scans again once a scan is due", function()
  local s = setup({ replicate = true })
  s.open(); s.env.C_Timer.flush()
  H.eq(s.full.started, 1)
  s.full.ready = false
  s.open(); s.env.C_Timer.flush()
  H.eq(s.full.started, 1, "too soon")
  s.full.ready = true
  s.open(); s.env.C_Timer.flush()
  H.eq(s.full.started, 2)
end)

-- ---------------------------------------------------------------------------
-- The switch
-- ---------------------------------------------------------------------------
test("it is on by default, and switching it off stops it", function()
  local s = setup({ replicate = true })
  H.eq(s.A.Get("autoScan"), true)
  s.A.Set("autoScan", false)
  s.open(); s.env.C_Timer.flush()
  H.eq(s.full.started, 0)
  H.eq(s.full.asked, 0, "does not even ask Auctionator")
  s.A.Set("autoScan", true)
  s.open(); s.env.C_Timer.flush()
  H.eq(s.full.started, 1)
end)

test("switching it off while a check is waiting also stops it", function()
  local s = setup({ replicate = true })
  s.open()
  s.A.Set("autoScan", false)
  s.env.C_Timer.flush()
  H.eq(s.full.started, 0)
end)

-- ---------------------------------------------------------------------------
-- Not scanning a closed Auction House
-- ---------------------------------------------------------------------------
test("closing the Auction House before the check cancels it", function()
  local s = setup({ replicate = true })
  s.open()
  s.close()
  s.env.C_Timer.flush()
  H.eq(s.full.started, 0)
end)

test("it checks the Auction House is still on screen before scanning", function()
  local s = setup({ replicate = true })
  s.open()
  s.ah.shown = false
  s.env.C_Timer.flush()
  H.eq(s.full.started, 0)
end)

-- ---------------------------------------------------------------------------
-- Auctionator not ready yet
-- ---------------------------------------------------------------------------
test("if Auctionator has not built its scan frames yet it tries again shortly, then scans", function()
  local s = setup({ replicate = true, frames = false })
  s.open()
  s.env.C_Timer.flush(1)
  H.eq(s.full.started, 0)
  H.eq(s.A.AutoScan.last, "waiting")
  H.eq(#s.env.C_Timer.queue, 1, "another try is queued")
  s.env.Auctionator.State.FullScanFrameRef = s.full
  s.env.C_Timer.flush(1)
  H.eq(s.full.started, 1)
end)

test("it gives up after a few tries instead of waiting forever", function()
  local s = setup({ replicate = true, frames = false })
  s.open()
  local ran = s.env.C_Timer.flush()
  H.truthy(ran <= s.A.AutoScan.ATTEMPTS + 2, "stopped after " .. ran .. " timer runs")
  H.eq(#s.env.C_Timer.queue, 0)
  H.eq(s.A.AutoScan.last, "waiting")
end)

test("it stops retrying when the Auction House closes meanwhile", function()
  local s = setup({ replicate = true, frames = false })
  s.open()
  s.env.C_Timer.flush(1)
  s.close()
  s.env.C_Timer.flush()
  H.eq(s.full.started, 0)
  H.eq(#s.env.C_Timer.queue, 0)
end)

-- ---------------------------------------------------------------------------
-- Once per opening
-- ---------------------------------------------------------------------------
test("two open events for the same visit start one scan", function()
  local s = setup({ replicate = true })
  s.open()
  s.open()
  s.A.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
  s.env.C_Timer.flush()
  H.eq(s.full.started, 1)
end)

test("the interaction-manager event opens it too, but only for the Auction House", function()
  local s = setup({ replicate = true })
  s.A.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)      -- a banker, not the Auction House
  s.env.C_Timer.flush()
  H.eq(s.full.started, 0)
  s.A.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
  s.env.C_Timer.flush()
  H.eq(s.full.started, 1)
end)

-- ---------------------------------------------------------------------------
-- Safety
-- ---------------------------------------------------------------------------
test("Almanac never writes to Auctionator's settings", function()
  local s = setup({ replicate = true })
  s.open(); s.env.C_Timer.flush()
  s.A.Set("autoScan", false)
  s.A.Set("autoScan", true)
  H.eq(#s.sets, 0)
  H.eq(s.env.Auctionator.Config.Options.AUTOSCAN, nil, "and it never touches Auctionator's own autoscan option")
end)

test("a failing scan call or a broken frame does not break Almanac", function()
  local s = setup({ replicate = true })
  function s.full:InitiateScan() error("boom") end
  s.open()
  H.nothrows(function() s.env.C_Timer.flush() end)
  H.eq(s.A.AutoScan.last, "failed")
  local t = setup({ replicate = true })
  function t.full:IsAutoscanReady() error("boom") end
  t.open()
  H.nothrows(function() t.env.C_Timer.flush() end)
  H.eq(t.A.AutoScan.last, "unsupported")
end)

test("a version of Auctionator without these scan frames is left alone", function()
  local s = setup({ replicate = true })
  s.env.Auctionator.State.FullScanFrameRef = { }       -- no methods
  s.open()
  H.nothrows(function() s.env.C_Timer.flush() end)
  H.eq(s.A.AutoScan.last, "unsupported")
end)

test("with Auctionator missing or oddly shaped nothing happens and nothing errors", function()
  local s = setup({ replicate = true })
  s.env.Auctionator.State = nil
  s.open()
  H.nothrows(function() s.env.C_Timer.flush() end)
  s.env.Auctionator = nil
  s.open()
  H.nothrows(function() s.env.C_Timer.flush() end)
  H.eq(s.full.started, 0)
end)

test("the scan request is made through Auctionator's own frame, not by calling the game directly", function()
  local s = setup({ replicate = true })
  local called = false
  s.env.C_AuctionHouse = { ReplicateItems = function() called = true end }
  s.open(); s.env.C_Timer.flush()
  H.falsy(called, "Auctionator's frame does the scan, with its progress bar and saving")
end)

-- ---------------------------------------------------------------------------
-- Telling the player and the debug report
-- ---------------------------------------------------------------------------
test("the debug report says whether auto-scan is on and whether Auctionator's frames were found", function()
  local s = setup({ replicate = true })
  local text = table.concat(s.A.Debug.Lines(), "\n")
  H.truthy(text:find("Auto-scan: on", 1, true), text)
  H.truthy(text:find("full scan", 1, true), text)
  s.A.Set("autoScan", false)
  H.truthy(table.concat(s.A.Debug.Lines(), "\n"):find("Auto-scan: off", 1, true))
  local t = setup({ frames = false })
  H.truthy(table.concat(t.A.Debug.Lines(), "\n"):find("not built yet", 1, true))
end)
