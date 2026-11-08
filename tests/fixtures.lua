-- Fixtures shaped like Auctionator's real saved variables
-- (see Auctionator/Source/Database/Mixin.lua and Source/Variables/Main.lua).
local Fx = {}

Fx.DAY0 = 1577836800            -- Auctionator.Constants.SCAN_DAY_0 in the fake env
Fx.NOW = Fx.DAY0 + 1005 * 86400 + 3600 * 12   -- noon on scan day 1005
Fx.TODAY = 1005

-- Thorium Bar 12359, Thorium Ore 10620, Arcane Crystal 12363, Thunderfury 19019
function Fx.realm()
  return {
    version = 2,                                        -- non-table value Auctionator stores on the realm table
    ["12359"] = {                                       -- full data, with low < high on some days
      m = 11240,
      h = { ["1000"] = 11500, ["1001"] = 11300, ["1003"] = 11800, ["1004"] = 11000, ["1005"] = 11240 },
      l = { ["1000"] = 11000, ["1003"] = 10800, ["1005"] = 10900 },
      a = { ["1000"] = 40, ["1001"] = 35, ["1003"] = 52, ["1004"] = 30, ["1005"] = 44 },
    },
    ["10620"] = {                                       -- old data: no "a" field at all
      m = 4810,
      h = { ["1002"] = 5000, ["1005"] = 4810 },
      l = {},
    },
    ["12363"] = {                                       -- single day
      m = 1500000,
      h = { ["1005"] = 1500000 },
      l = {},
      a = { ["1005"] = 2 },
    },
    ["19019"] = { m = 5000000, h = { ["1004"] = 5000000 }, l = {}, a = { ["1004"] = 1 } },
    ["g:19019:60"] = { m = 5200000, h = { ["1005"] = 5200000 }, l = {}, a = { ["1005"] = 1 } },
    ["gr:15001:of the Eagle"] = { m = 900, h = { ["1005"] = 900 }, l = {}, a = { ["1005"] = 3 } },
    ["p:1234"] = { m = 100, h = { ["1005"] = 100 }, l = {}, a = {} },   -- battle pet: skipped
    ["garbage"] = { m = 1, h = {}, l = {}, a = {} },
    ["abc:5"] = { m = 1, h = {}, l = {}, a = {} },
  }
end

function Fx.env(overrides)
  local realm = Fx.realm()
  local env = {
    time = function() return Fx.NOW end,
    Auctionator = {
      State = { Loaded = true, CurrentRealm = "TestRealm" },
      Database = { db = realm },
      Constants = { SCAN_DAY_0 = Fx.DAY0 },
      Config = {
        Options = { PRICE_HISTORY_DAYS = "price_history_days" },
        Get = function(option) if option == "price_history_days" then return 21 end end,
      },
    },
    AUCTIONATOR_PRICE_DATABASE = { ["TestRealm"] = realm },
    AUCTIONATOR_SAVEDVARS = {
      TimeOfLastBrowseScan = Fx.NOW - 7200,
      TimeOfLastReplicateScan = Fx.NOW - 3 * 86400,
    },
    AUCTIONATOR_POSTING_HISTORY = {
      ["__dbversion"] = 1,
      ["12359"] = {
        { price = 11900, quantity = 20, bidPrice = 11900, time = Fx.NOW - 86400 },
        { price = 12100, quantity = 5, bidPrice = 12100, time = Fx.NOW - 3 * 86400 },
      },
      ["g:19019:60"] = { { price = 5300000, quantity = 1, time = Fx.NOW - 5000 } },
    },
    AUCTIONATOR_SHOPPING_LISTS = {
      { name = "Smithing", items = { '"Thorium Bar";;;;;;;;;;;;;;', "Arcane Crystal", 5 } },
      { name = "Empty", items = {} },
      "not a list",
    },
  }
  for k, v in pairs(overrides or {}) do env[k] = v end
  return env
end

return Fx
