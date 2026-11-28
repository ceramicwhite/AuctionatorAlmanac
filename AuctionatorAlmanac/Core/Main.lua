local ADDON, A = ...

-- Startup orchestration: saved variables on ADDON_LOADED, then wait for
-- Auctionator's database on PLAYER_LOGIN (it deserializes at login, so it may
-- not be ready the instant we are).
local Main = {}
A.Main = Main

local WAIT_STEP = 0.5
local WAIT_ATTEMPTS = 40          -- 20 seconds
local setupDone = false

local function now() return (time and time()) or 0 end

-- Set up saved variables and the modules that keep state in them.
function Main.InitModules(saved)
  A.db = A.InitDB(saved)
  A.Items.Init(A.db)
  A.Ledger.Init(A.db)
  A.Inventory.Init(A.db)
  A.History.Init(A.db)
  A.Discovery.Init(A.db)
  A.Recents.Init(A.db)
  A.Depth.Init(A.db)
end

-- Event hooks and widgets that exist from login on. Safe to call twice.
function Main.Setup()
  if setupDone then return end
  setupDone = true
  A.Items.Start()
  A.Tracker.Start()
  A.Tooltip.Install()
  A.AutoScan.Start()
  A.Depth.Install()
  A.UI.Minimap.Create()
  A.UI.Settings.RegisterWithGame()
  A.Bus.On("DATA_RELOADED", Main.OnDataReloaded)
  A.Bus.On("AH_CLOSED", function()
    -- give Auctionator a moment to finish saving the scan it just made
    A.After(1, function() A.Controller.CheckForNewData(true) end)
  end)
  A.Bus.On("WINDOW_SHOWN", function() A.Controller.CheckForNewData() end)
  A.Bus.On("WINDOW_SHOWN", function() A.Recents.Sync() end)     -- searches made in Auctionator since last time
end

-- After every (re)load of Auctionator's data: bring in its posting history,
-- trim old ledger entries, and snapshot long-term history for tracked items.
function Main.OnDataReloaded()
  A.Depth.Install()                       -- in case Auctionator made its Database some way the mixin hook did not cover
  A.Depth.Prune(A.Adapter.Today() - A.Adapter.HistoryDays())
  local added = A.Ledger.ImportPosting(A.Adapter)
  local keep = A.Get("ledgerKeepDays")
  local pruned = (keep and keep > 0) and A.Ledger.Prune(keep, now()) or 0
  A.Discovery.Observe(A.Controller.summaries, A.Controller.oldestDay)
  A.Overview.Invalidate("newfinds")       -- anything built before this saw an empty memory
  local tracked = A.History.TrackedIDs({ A.Ledger.ItemSet(), A.Inventory.Totals() })
  A.History.Snapshot(A.Adapter, tracked, A.Adapter.Today(), A.Get("historyKeepDays") or 365)
  if added > 0 or pruned > 0 then A.Bus.Fire("LEDGER_UPDATED") end
end

function Main.OnLogin()
  local attempts = 0
  local function wait()
    attempts = attempts + 1
    if A.Adapter.IsReady() then
      Main.gaveUp = false
      A.Controller.Reload()
    elseif attempts >= WAIT_ATTEMPTS then
      Main.gaveUp = true
      A.Print("Auctionator's saved prices are not available yet. Check that Auctionator is enabled; Almanac will try again when you open it.")
    else
      A.After(WAIT_STEP, wait)
    end
  end
  wait()
end

-- what: ledger | inventory | history | items | discovery | searches
function Main.Reset(what)
  if what == "ledger" then
    A.Ledger.Reset()
    A.Bus.Fire("LEDGER_UPDATED")
  elseif what == "inventory" then
    A.Inventory.Reset()
    A.Bus.Fire("INVENTORY_UPDATED")
  elseif what == "history" then
    A.History.Reset()
    A.Controller.CheckForNewData(true)
  elseif what == "items" then
    A.Items.Reset()
    A.Controller.CheckForNewData(true)
  elseif what == "discovery" then
    A.Discovery.Reset()
    A.Controller.CheckForNewData(true)
  elseif what == "searches" then
    A.Recents.Clear()
  else
    return false
  end
  return true
end

A.RegisterEvent("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  Main.InitModules(ALMANAC_DB)
  ALMANAC_DB = A.db
  Main.Setup()
end)

A.RegisterEvent("PLAYER_LOGIN", function() Main.OnLogin() end)
