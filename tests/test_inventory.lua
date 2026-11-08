local H = require("harness")
local test = H.test

local function load(env)
  local A = H.newA({ "Core/Init.lua", "Tracker/Inventory.lua" }, env)
  A.db = A.InitDB(nil)
  A.Inventory.Init(A.db)
  return A.Inventory, A
end

-- Retail-style bag indexes (character bank tabs and warband tabs exist).
local retailEnum = { BagIndex = {
  Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,
  Bank = -1, Reagentbank = -3, Keyring = -2,
  CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
  AccountBankTab_1 = 12, AccountBankTab_2 = 13,
} }

-- Fake containers: bags[bagID] = { [slot] = {itemID, stackCount} }
local function containers(bags)
  return {
    GetContainerNumSlots = function(bag)
      local b = bags[bag]
      if not b then return 0 end
      local max = 0
      for slot in pairs(b) do if slot > max then max = slot end end
      return max
    end,
    GetContainerItemInfo = function(bag, slot)
      local entry = bags[bag] and bags[bag][slot]
      if not entry then return nil end
      return { itemID = entry[1], stackCount = entry[2] }
    end,
  }
end

local function name(n, realm) return { name = n, realm = realm or "Whitemane", class = "WARRIOR", faction = "Alliance" } end

test("CharKey and EnsureChar", function()
  local Inv = load()
  H.eq(Inv.CharKey("Thornwick", "Whitemane"), "Thornwick-Whitemane")
  local rec = Inv.EnsureChar(name("Thornwick"))
  H.eq(rec.name, "Thornwick")
  H.eq(rec.class, "WARRIOR")
  H.truthy(rec.loc and rec.stamps)
  local again = Inv.EnsureChar({ name = "Thornwick", realm = "Whitemane", class = "MAGE" })
  H.eq(again.class, "MAGE", "updates metadata in place")
  H.eq(again, rec)
end)

test("Owned lists characters and locations with totals", function()
  local Inv = load()
  Inv.EnsureChar(name("Thornwick")); Inv.EnsureChar(name("Mule"))
  Inv.SetLocation("Thornwick-Whitemane", "bags", { [12359] = 6 }, 1000)
  Inv.SetLocation("Thornwick-Whitemane", "bank", { [12359] = 4, [10620] = 9 }, 900)
  Inv.SetLocation("Mule-Whitemane", "mail", { [12359] = 4 }, 800)
  local owned = Inv.Owned(12359)
  H.eq(owned.total, 14)
  H.eq(#owned.rows, 3)
  H.eq({ owned.rows[1].name, owned.rows[1].loc, owned.rows[1].count, owned.rows[1].stamp }, { "Mule", "mail", 4, 800 })
  H.eq({ owned.rows[2].name, owned.rows[2].loc }, { "Thornwick", "bags" }, "bags before bank")
  H.eq({ owned.rows[3].name, owned.rows[3].loc }, { "Thornwick", "bank" })
  H.eq(Inv.Owned(10620).total, 9)
  H.eq(Inv.Owned(99999), { total = 0, rows = {} })
end)

test("setting a location replaces its previous snapshot and empty counts clear it", function()
  local Inv = load()
  Inv.EnsureChar(name("Thornwick"))
  Inv.SetLocation("Thornwick-Whitemane", "bags", { [1] = 5 }, 10)
  Inv.SetLocation("Thornwick-Whitemane", "bags", { [2] = 3 }, 20)
  H.eq(Inv.Owned(1).total, 0)
  H.eq(Inv.Owned(2).total, 3)
  Inv.SetLocation("Thornwick-Whitemane", "bags", {}, 30)
  H.eq(Inv.Owned(2).total, 0)
end)

test("Totals is memoized and invalidated by any snapshot change", function()
  local Inv = load()
  Inv.EnsureChar(name("Thornwick"))
  Inv.SetLocation("Thornwick-Whitemane", "bags", { [1] = 5 }, 10)
  local t1 = Inv.Totals()
  H.eq(t1[1], 5)
  H.eq(Inv.Totals(), t1, "same table while nothing changed")
  Inv.SetLocation("Thornwick-Whitemane", "bank", { [1] = 2 }, 11)
  H.eq(Inv.Totals()[1], 7)
  Inv.SetWarband({ [1] = 1 }, 12)
  H.eq(Inv.Totals()[1], 8)
end)

test("guild bank items are listed but not counted as owned", function()
  local Inv = load()
  Inv.EnsureChar(name("Thornwick"))
  Inv.SetLocation("Thornwick-Whitemane", "bags", { [1] = 5 }, 10)
  Inv.SetGuildTab("Boss-Whitemane", "Boss", 1, { [1] = 100 }, 20)
  Inv.SetGuildTab("Boss-Whitemane", "Boss", 2, { [1] = 50 }, 21)
  local owned = Inv.Owned(1)
  H.eq(owned.total, 5)
  H.eq(#owned.rows, 2)
  local guild = owned.rows[2]
  H.eq({ guild.guild, guild.loc, guild.count, guild.shared }, { "Boss", "guildbank", 150, true })
  H.eq(Inv.Totals()[1], 5)
end)

test("warband bank counts as owned and shows as its own location", function()
  local Inv = load()
  Inv.SetWarband({ [1] = 7 }, 50)
  local owned = Inv.Owned(1)
  H.eq(owned.total, 7)
  H.eq({ owned.rows[1].loc, owned.rows[1].count, owned.rows[1].stamp }, { "warband", 7, 50 })
end)

test("snapshots are copies, not references to the caller's table", function()
  local Inv, A = load()
  Inv.EnsureChar(name("Thornwick"))
  local counts = { [1] = 5 }
  Inv.SetLocation("Thornwick-Whitemane", "bags", counts, 10)
  counts[1] = 99
  H.eq(Inv.Owned(1).total, 5)
  H.eq(A.db.chars["Thornwick-Whitemane"].loc.bags[1], 5)
end)

test("an unknown character key is created on demand", function()
  local Inv = load()
  H.nothrows(function() Inv.SetLocation("Stranger-Realm", "bags", { [1] = 1 }, 5) end)
  H.eq(Inv.Owned(1).rows[1].name, "Stranger")
end)

test("Characters lists known characters, most recently seen first", function()
  local Inv = load()
  Inv.EnsureChar(name("Old")); Inv.SetLocation("Old-Whitemane", "bags", {}, 100)
  Inv.EnsureChar(name("New")); Inv.SetLocation("New-Whitemane", "bags", {}, 900)
  local list = Inv.Characters()
  H.eq({ list[1].name, list[2].name }, { "New", "Old" })
end)

test("ClassifyBag with retail-style indexes", function()
  local Inv = load()
  local ctx = { Enum = retailEnum, numBagSlots = 4 }
  for _, id in ipairs({ 0, 1, 4, 5 }) do H.eq(Inv.ClassifyBag(id, ctx), "bags", "bag " .. id) end
  for _, id in ipairs({ -1, 6, 7, 8, -3 }) do H.eq(Inv.ClassifyBag(id, ctx), "bank", "bank " .. id) end
  for _, id in ipairs({ 12, 13 }) do H.eq(Inv.ClassifyBag(id, ctx), "warband", "warband " .. id) end
  H.eq(Inv.ClassifyBag(40, ctx), nil)
end)

test("ClassifyBag with classic-style indexes", function()
  local Inv = load()
  local ctx = { Enum = nil, numBagSlots = 4 }
  for _, id in ipairs({ 0, 1, 2, 3, 4 }) do H.eq(Inv.ClassifyBag(id, ctx), "bags") end
  H.eq(Inv.ClassifyBag(-1, ctx), "bank")
  for _, id in ipairs({ 5, 6, 7, 8, 9, 10, 11 }) do H.eq(Inv.ClassifyBag(id, ctx), "bank", "bank bag " .. id) end
  H.eq(Inv.ClassifyBag(12, ctx), nil)
end)

local function scanEnv()
  return {
    Enum = retailEnum, NUM_BAG_SLOTS = 4,
    C_Container = containers({
      [0] = { [1] = { 12359, 20 }, [2] = { 12359, 5 }, [4] = { 10620, 10 } },
      [3] = { [1] = { 19019, 1 } },
      [5] = { [1] = { 14047, 12 } },                          -- reagent bag
      [-1] = { [1] = { 12363, 1 } },                           -- bank
      [6] = { [2] = { 12359, 200 } },                          -- bank tab
      [12] = { [1] = { 13452, 3 } },                           -- warband tab
    }),
  }
end

test("ScanBags sums stacks over carried bags only", function()
  local Inv, A = load(scanEnv())
  local counts = Inv.ScanBags(A.env)
  H.eq(counts, { [12359] = 25, [10620] = 10, [19019] = 1, [14047] = 12 })
end)

test("ScanBank and ScanWarband read their own containers", function()
  local Inv, A = load(scanEnv())
  H.eq(Inv.ScanBank(A.env), { [12363] = 1, [12359] = 200 })
  H.eq(Inv.ScanWarband(A.env), { [13452] = 3 })
end)

test("collectors return nil when the container API is missing", function()
  local Inv, A = load({})
  H.eq(Inv.ScanBags(A.env), nil)
  H.eq(Inv.ScanBank(A.env), nil)
  H.eq(Inv.ScanEquipped(A.env), nil)
  H.eq(Inv.ScanMail(A.env), nil)
  H.eq(Inv.ScanOwnedAuctions(A.env), nil)
  H.eq(Inv.ScanGuildBank(1, A.env), nil)
end)

test("ScanEquipped counts worn items", function()
  local worn = { [1] = 16000, [16] = 16001, [17] = 16001, [21] = 14156 }
  local Inv, A = load({ GetInventoryItemID = function(unit, slot) return worn[slot] end })
  H.eq(Inv.ScanEquipped(A.env), { [16000] = 1, [16001] = 2, [14156] = 1 })
end)

test("ScanMail reads attachments through the classic return shape", function()
  local items = { [1] = { [1] = { "Thorium Bar", 12359, 1, 20 }, [2] = { "Ore", 10620, 1, 5 } }, [2] = { [1] = { "Thorium Bar", 12359, 1, 3 } } }
  local Inv, A = load({
    GetInboxNumItems = function() return 2 end,
    GetInboxItem = function(i, j) local it = items[i] and items[i][j]; if it then return it[1], it[2], it[3], it[4] end end,
  })
  H.eq(Inv.ScanMail(A.env), { [12359] = 23, [10620] = 5 })
end)

test("ScanMail falls back to item links and table-returning APIs", function()
  local Inv, A = load({
    C_Mail = {
      GetInboxNumItems = function() return 1 end,
      GetInboxItem = function(i, j) if j == 1 then return { itemID = 12359, count = 4 } end end,
    },
  })
  H.eq(Inv.ScanMail(A.env), { [12359] = 4 })
  local Inv2, A2 = load({
    GetInboxNumItems = function() return 1 end,
    GetInboxItem = function(i, j) if j == 1 then return "Thorium Bar", nil, 1, 6 end end,
    GetInboxItemLink = function(i, j) return "|cff1eff00|Hitem:12359::::::::60:::::|h[Thorium Bar]|h|r" end,
  })
  H.eq(Inv2.ScanMail(A2.env), { [12359] = 6 })
end)

test("ScanOwnedAuctions counts only active auctions", function()
  local rows = {
    { itemKey = { itemID = 12359 }, quantity = 20, status = 0 },
    { itemKey = { itemID = 12359 }, quantity = 5 },                    -- no status field: treated as active
    { itemKey = { itemID = 10620 }, quantity = 8, status = 1 },        -- sold
  }
  local Inv, A = load({
    Enum = { AuctionStatus = { Active = 0, Sold = 1 } },
    C_AuctionHouse = {
      GetNumOwnedAuctions = function() return #rows end,
      GetOwnedAuctionInfo = function(i) return rows[i] end,
    },
  })
  H.eq(Inv.ScanOwnedAuctions(A.env), { [12359] = 25 })
end)

test("ScanGuildBank reads one tab from links and counts", function()
  local slots = { [1] = { "|Hitem:12359:0:0|h[Bar]|h", 100 }, [5] = { "|Hitem:12359:0:0|h[Bar]|h", 20 }, [9] = { "|Hitem:10620:0|h[Ore]|h", 7 } }
  local Inv, A = load({
    GetGuildBankItemLink = function(tab, slot) return slots[slot] and slots[slot][1] end,
    GetGuildBankItemInfo = function(tab, slot) if slots[slot] then return 1, slots[slot][2] end end,
  })
  H.eq(Inv.ScanGuildBank(1, A.env), { [12359] = 120, [10620] = 7 })
end)

test("snapshots round-trip through saved variables", function()
  local Inv, A = load()
  Inv.EnsureChar(name("Thornwick"))
  Inv.SetLocation("Thornwick-Whitemane", "bags", { [1] = 5 }, 10)
  local B = H.newA({ "Core/Init.lua", "Tracker/Inventory.lua" })
  B.Inventory.Init(A.db)
  H.eq(B.Inventory.Owned(1).total, 5)
end)

test("MailAttachments lists one mail's attachments", function()
  local items = { [1] = { [1] = { "Thorium Bar", 12359, 1, 20 }, [3] = { "Ore", 10620, 1, 5 } } }
  local Inv, A = load({
    GetInboxItem = function(i, j) local it = items[i] and items[i][j]; if it then return it[1], it[2], it[3], it[4] end end,
  })
  H.eq(Inv.MailAttachments(A.env, 1), { { itemID = 12359, count = 20 }, { itemID = 10620, count = 5 } })
  H.eq(Inv.MailAttachments(A.env, 2), {})
  H.eq(Inv.MailAttachments({}, 1), {}, "no API: empty")
end)
