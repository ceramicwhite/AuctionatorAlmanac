-- Boots the real addon, in real TOC order, inside the widget stub with Auctionator
-- fixture data. Used by the UI tests.
local H = require("harness")
local Stub = require("ui_stub")
local Fx = require("fixtures")

local M = {}

-- File list straight from the TOC, so the load order the game will use is the one tested.
function M.tocFiles()
  local files = {}
  for raw in io.lines(H.addonDir .. "/AuctionatorAlmanac.toc") do
    local line = raw:gsub("\r", "")
    if line ~= "" and not line:match("^#") then
      files[#files + 1] = (line:gsub("\\", "/"))
    end
  end
  return files
end

M.ITEMS = {
  [12359] = { name = "Thorium Bar", quality = 2, class = 7, sub = 12, sell = 400 },
  [10620] = { name = "Thorium Ore", quality = 1, class = 7, sub = 7, sell = 150 },
  [12363] = { name = "Arcane Crystal", quality = 3, class = 7, sub = 10, sell = 0 },
  [19019] = { name = "Thunderfury", quality = 5, class = 2, sub = 7, sell = 0, equip = "INVTYPE_WEAPON" },
  [15001] = { name = "Eagle Pants", quality = 2, class = 4, sub = 1, sell = 10, equip = "INVTYPE_LEGS" },
}

local CLASS = { [2] = "Weapon", [4] = "Armor", [7] = "Trade Goods" }
local SUB = { [7] = { [7] = "Metal & Stone", [12] = "Enchanting" }, [4] = { [1] = "Cloth" } }

-- opts.fixture: overrides for the Auctionator fixture; opts.saved: saved ALMANAC_DB; opts.noReload: skip data load
function M.boot(opts)
  opts = opts or {}
  local env = Stub.new()
  local fixture = Fx.env(opts.fixture)
  -- most UI tests want an empty ledger, so Auctionator's posting history is opt-in
  if not opts.keepPostings and not (opts.fixture and opts.fixture.AUCTIONATOR_POSTING_HISTORY ~= nil) then
    fixture.AUCTIONATOR_POSTING_HISTORY = {}
  end
  for k, v in pairs(fixture) do env[k] = v end
  env.C_Timer = H.fakeTimer()
  env.SlashCmdList = {}
  env.C_Item = {
    GetItemInfoInstant = function(id)
      local d = M.ITEMS[id]
      if d then return id, "t", "s", d.equip or "", 100000 + id, d.class, d.sub end
    end,
    GetItemInfo = function(id)
      local d = M.ITEMS[id]
      if d then return d.name, "|link|", d.quality, 10, 0, "t", "s", 20, d.equip or "", 100000 + id, d.sell, d.class, d.sub end
    end,
    RequestLoadItemDataByID = function() end,
    GetItemClassInfo = function(c) return CLASS[c] end,
    GetItemSubClassInfo = function(c, s) return SUB[c] and SUB[c][s] end,
  }
  for k, v in pairs(opts.env or {}) do env[k] = v end

  local A, leaks = H.newUI(M.tocFiles(), env)
  if opts.raw then return A, env, leaks end     -- loaded, but nothing initialised
  A.Main.InitModules(opts.saved)
  A.Main.Setup()
  if not opts.noReload then
    A.Controller.Reload()
    env.C_Timer.flush()
  end
  return A, env, leaks
end


-- A richer market than the stock fixture: two clear movers, a thin-market spike, a bargain (which
-- is also a faller) and two items Auctionator has only just seen. Day 1005 is the newest scan.
M.ITEMS[20001] = { name = "Rising Bar", quality = 2, class = 7, sub = 12, sell = 0 }
M.ITEMS[20002] = { name = "Thin Spike", quality = 1, class = 7, sub = 12, sell = 0 }
M.ITEMS[20003] = { name = "Falling Cloth", quality = 1, class = 7, sub = 12, sell = 0 }
M.ITEMS[20004] = { name = "Bargain Herb", quality = 1, class = 7, sub = 12, sell = 0 }
M.ITEMS[20005] = { name = "Crown of the Unseen", quality = 4, class = 4, sub = 1, sell = 0, equip = "INVTYPE_HEAD" }
M.ITEMS[20006] = { name = "Fresh Pebble", quality = 1, class = 7, sub = 7, sell = 0 }

M.STEADY = { 1000, 1010, 990, 1005, 995, 1010, 1000 }

-- Write a series ending on day 1005 into an Auctionator realm table.
function M.put(realm, id, lows, qty, last)
  local h, a = {}, {}
  local first = 1005 - #lows + 1
  for i, v in ipairs(lows) do
    local day = tostring(first + i - 1)
    h[day] = v
    a[day] = qty
  end
  realm[tostring(id)] = { m = last or lows[#lows], h = h, l = {}, a = a }
end

function M.withLast(base, last)
  local out = {}
  for i, v in ipairs(base) do out[i] = v end
  out[#out + 1] = last
  return out
end

function M.rich(opts)
  opts = opts or {}
  opts.noReload = true
  local A, env = M.boot(opts)
  local realm = env.AUCTIONATOR_PRICE_DATABASE.TestRealm
  M.put(realm, 20001, M.withLast(M.STEADY, 1300), 40)
  M.put(realm, 20002, M.withLast(M.STEADY, 2000), 1)
  M.put(realm, 20003, M.withLast(M.STEADY, 700), 40)
  M.put(realm, 20004, M.withLast(M.STEADY, 600), 40)
  M.put(realm, 20005, { 500000 }, 1)
  M.put(realm, 20006, { 300 }, 30)
  A.Controller.Reload()
  env.C_Timer.flush()
  return A, env
end

-- Open the window and let layout settle.
function M.open(A, env, w, h)
  local win = A.UI.Window.Get()
  if w then win:SetSize(w, h) end
  win:Show()
  Stub.settle(env)
  env.C_Timer.flush()
  Stub.settle(env)
  return win
end

-- Open the window on the Search page (categories, the item list, the search row) and let layout settle.
function M.search(A, env, w, h)
  local win = M.open(A, env, w, h)
  A.UI.Window.SetMode("search")
  Stub.settle(env)
  return win
end

-- A scan saved the way Auctionator saves one: Database:ProcessScan with every auction, then Database:SetPrice per key
-- with the lowest unit price and the count listed. Almanac hears both (Data/Depth.lua); the timers are run after.
function M.scan(A, env, scan)
  A.Depth.OnScan(scan)
  local keys = {}
  for key in pairs(scan) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local low, _, total = A.Depth.Summarize(scan[key])
    A.Depth.OnPrice(key, low, total)
  end
  if env.C_Timer and env.C_Timer.flush then env.C_Timer.flush() end
end

-- The cell of a results row under the column with this key ("price", "atmin", "onah", "owned", ...).
function M.cell(win, row, key)
  for i, col in ipairs(win.resultsTable.columns) do
    if col.key == key then return row.cells[i] end
  end
end

return M
