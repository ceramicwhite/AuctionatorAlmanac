local ADDON, A = ...

-- Starts Auctionator's scan for you when the Auction House opens, so you do not have to click
-- Full Scan on its tab.
--
-- It presses the same internal button the Full Scan button does (Auctionator's own scan frame,
-- with its progress bar, throttling and saving), and only when Auctionator itself says a scan is
-- due: Auctionator's autoscan interval (15 minutes by default) and the server's own limit on
-- full scans both still apply. Nothing of Auctionator's is changed: its settings are never
-- written, so Auctionator's own "autoscan" option keeps meaning what the player set it to.
local AutoScan = {}
A.AutoScan = AutoScan

AutoScan.DELAY = 3         -- seconds after opening. Auctionator builds its frames as the window shows and
                           -- its own autoscan (if the player turned it on) fires at 2s; this comes after.
AutoScan.RETRY = 1         -- Auctionator may not have built its frames yet: look again this often...
AutoScan.ATTEMPTS = 8      -- ...this many times, then give up for this visit
AutoScan.last = nil        -- what the most recent check found, for /almanac debug

local generation = 0

-- The scan frame Auctionator's Full Scan button would use: the full (replicate) scan frame when
-- Auctionator is set to that, otherwise the browse scan frame. Returns frame|nil, "full"|"browse"|nil.
function AutoScan.Frame()
  local auctionator = A.env.Auctionator
  local state = type(auctionator) == "table" and auctionator.State
  if type(state) ~= "table" then return nil, nil end
  local replicate = false
  local config = auctionator.Config
  if type(config) == "table" and type(config.Get) == "function"
    and type(config.Options) == "table" and config.Options.REPLICATE_SCAN then
    local ok, value = pcall(config.Get, config.Options.REPLICATE_SCAN)
    replicate = ok and value and true or false
  end
  return replicate and state.FullScanFrameRef or state.IncrementalScanFrameRef, replicate and "full" or "browse"
end

-- state: "ok" | "not built" (Auctionator makes the frame when the Auction House first opens) |
--        "unsupported" (a version of Auctionator without the functions used) | "no auctionator"
function AutoScan.Status()
  local frame, mode = AutoScan.Frame()
  if mode == nil then return { state = "no auctionator" } end
  if type(frame) ~= "table" then return { state = "not built", mode = mode } end
  if type(frame.IsAutoscanReady) ~= "function" or type(frame.InitiateScan) ~= "function" then
    return { state = "unsupported", mode = mode }
  end
  return { state = "ok", mode = mode }
end

-- One attempt. Returns "started", "not ready" (a scan is not due), "waiting" (Auctionator has not
-- built its frames yet), "unsupported" or "failed".
function AutoScan.TryStart()
  local status = AutoScan.Status()
  if status.state == "no auctionator" or status.state == "not built" then return "waiting" end
  if status.state == "unsupported" then return "unsupported" end
  local frame = AutoScan.Frame()
  local ok, ready = pcall(frame.IsAutoscanReady, frame)
  if not ok then return "unsupported" end
  if not ready then return "not ready" end
  if not pcall(frame.InitiateScan, frame) then return "failed" end
  return "started"
end

local function auctionHouseOpen()
  local frame = A.env.AuctionHouseFrame
  if frame == nil then return true end
  local ok, shown = pcall(frame.IsShown, frame)
  return ok and shown and true or false
end

-- The Auction House has just opened. Several events announce this, so each call replaces the
-- last: only the newest pending check runs, which keeps it to one scan per visit.
function AutoScan.OnOpened()
  if A.Get("autoScan") == false then return end
  generation = generation + 1
  local mine = generation
  local function attempt(n)
    if mine ~= generation then return end
    if A.Get("autoScan") == false then return end      -- switched off while waiting
    if not auctionHouseOpen() then return end          -- closed again, nothing to scan
    local result = AutoScan.TryStart()
    AutoScan.last = result
    if result == "waiting" and n < AutoScan.ATTEMPTS then
      A.After(AutoScan.RETRY, function() attempt(n + 1) end)
    end
  end
  A.After(AutoScan.DELAY, function() attempt(1) end)
end

function AutoScan.OnClosed()
  generation = generation + 1      -- cancels any check still waiting
end

function AutoScan.Start()
  A.RegisterEvent("AUCTION_HOUSE_SHOW", function() AutoScan.OnOpened() end)
  -- the newer way the game announces it; also what Auctionator itself listens to
  A.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, paneType)
    local enum = A.env.Enum
    local kinds = enum and enum.PlayerInteractionType
    if kinds and paneType ~= nil and paneType == kinds.Auctioneer then AutoScan.OnOpened() end
  end)
  A.RegisterEvent("AUCTION_HOUSE_CLOSED", function() AutoScan.OnClosed() end)
end
