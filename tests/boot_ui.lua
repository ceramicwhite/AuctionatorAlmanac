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

return M
