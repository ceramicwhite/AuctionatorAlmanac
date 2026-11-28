local H = require("harness")
local test = H.test

local function load(env) return H.newA({ "Core/Init.lua", "Data/Categories.lua", "Data/Search.lua" }, env) end

local infos = {
  [12359] = { id = 12359, name = "Thorium Bar", lname = "thorium bar", quality = 2, class = 7, sub = 12 },
  [10620] = { id = 10620, name = "Thorium Ore", lname = "thorium ore", quality = 1, class = 7, sub = 7 },
  [12363] = { id = 12363, name = "Arcane Crystal", lname = "arcane crystal", quality = 3, class = 7, sub = 10 },
  [19019] = { id = 19019, name = "Thunderfury, Blessed Blade", lname = "thunderfury, blessed blade", quality = 5, class = 2, sub = 7, invType = 13 },
  [13452] = { id = 13452, name = "Elixir of the Mongoose", lname = "elixir of the mongoose", quality = 2, class = 0, sub = 2 },
  [55555] = { id = 55555, class = 15, sub = 0 },               -- name not loaded yet
}
local sums = {
  [12359] = { last = 11240, ageDays = 0, change1d = 0.05 },
  [10620] = { last = 4810, ageDays = 3, change1d = -0.10 },
  [12363] = { last = 1500000, ageDays = 0, change1d = nil },
  [19019] = { last = 5000000, ageDays = 9 },
}
local owned = { [12359] = 14, [19019] = 1 }
local ctx = {
  info = function(id) return infos[id] end,
  summary = function(id) return sums[id] end,
  owned = function(id) return owned[id] or 0 end,
}
local ALL = { 12359, 10620, 12363, 19019, 13452, 55555 }
local function copy(t) local o = {} for i, v in ipairs(t) do o[i] = v end return o end
local function sorted(t) table.sort(t) return t end

test("Tokenize lowercases, splits and keeps quoted phrases", function()
  local S = load().Search
  H.eq(S.Tokenize("Thorium  Bar"), { "thorium", "bar" })
  H.eq(S.Tokenize('"Arcane Crystal" bar'), { "arcane crystal", "bar" })
  H.eq(S.Tokenize('  "unterminated phrase'), { "unterminated phrase" })
  H.eq(S.Tokenize(""), {})
  H.eq(S.Tokenize("   "), {})
  H.eq(S.Tokenize(nil), {})
end)

test("all tokens must match, case-insensitively", function()
  local S = load().Search
  H.eq(sorted(S.Run(copy(ALL), { text = "thor" }, ctx)), { 10620, 12359 })
  H.eq(S.Run(copy(ALL), { text = "THORIUM bar" }, ctx), { 12359 })
  H.eq(S.Run(copy(ALL), { text = "bar thorium" }, ctx), { 12359 }, "token order does not matter")
  H.eq(S.Run(copy(ALL), { text = "zzz" }, ctx), {})
  H.eq(S.Run(copy(ALL), { text = '"blessed blade"' }, ctx), { 19019 })
  H.eq(S.Run(copy(ALL), { text = '"blade blessed"' }, ctx), {}, "phrases keep word order")
end)

test("empty text returns everything including unnamed items", function()
  local S = load().Search
  H.eq(#S.Run(copy(ALL), { text = "" }, ctx), 6)
  H.eq(#S.Run(copy(ALL), {}, ctx), 6)
end)

test("numeric text matches the item ID, even without a name", function()
  local S = load().Search
  H.eq(S.Run(copy(ALL), { text = "55555" }, ctx), { 55555 })
  H.eq(S.Run(copy(ALL), { text = "12359" }, ctx), { 12359 })
  H.eq(S.Run(copy(ALL), { text = "thorium 55555" }, ctx), {}, "ids only match when typed alone")
end)

test("unnamed items match only by id or when no text is typed", function()
  local S = load().Search
  H.eq(S.Run({ 55555 }, { text = "item" }, ctx), {})
end)

test("category narrows and combines with text", function()
  local A = load()
  local tradeGoods = { name = "Trade Goods", filters = { { classID = 7 } }, children = {} }
  local metal = { name = "Metal", filters = { { classID = 7, subClassID = 12 } }, children = {} }
  H.eq(sorted(A.Search.Run(copy(ALL), { category = tradeGoods }, ctx)), { 10620, 12359, 12363 })
  H.eq(A.Search.Run(copy(ALL), { category = metal }, ctx), { 12359 })
  H.eq(A.Search.Run(copy(ALL), { category = tradeGoods, text = "arcane" }, ctx), { 12363 })
  H.eq(A.Search.Run(copy(ALL), { category = tradeGoods, text = "elixir" }, ctx), {})
end)

test("quality, ownedOnly, price and recency filters", function()
  local S = load().Search
  H.eq(S.Run(copy(ALL), { quality = 5 }, ctx), { 19019 })
  H.eq(sorted(S.Run(copy(ALL), { ownedOnly = true }, ctx)), { 12359, 19019 })
  H.eq(sorted(S.Run(copy(ALL), { minPrice = 5000, maxPrice = 20000 }, ctx)), { 12359 })
  H.eq(sorted(S.Run(copy(ALL), { minPrice = 1000000 }, ctx)), { 12363, 19019 })
  H.eq(sorted(S.Run(copy(ALL), { recent = 1 }, ctx)), { 12359, 12363 })
  H.eq(S.Run(copy(ALL), { minPrice = 1 }, { info = ctx.info, summary = function() return nil end, owned = ctx.owned }), {},
    "price filters exclude items with no price data")
end)

test("Sort orders by key with missing values last in both directions", function()
  local S = load().Search
  local ids = S.Sort(copy({ 12359, 10620, 12363, 19019 }), "price", true, ctx)
  H.eq(ids, { 10620, 12359, 12363, 19019 })
  ids = S.Sort(copy({ 12359, 10620, 12363, 19019 }), "price", false, ctx)
  H.eq(ids, { 19019, 12363, 12359, 10620 })
  ids = S.Sort(copy({ 12359, 10620, 12363, 19019 }), "change", false, ctx)
  H.eq(ids, { 12359, 10620, 12363, 19019 }, "nil changes sort last, then by name")
  ids = S.Sort(copy({ 12359, 10620, 12363, 19019 }), "change", true, ctx)
  H.eq(ids, { 10620, 12359, 12363, 19019 })
end)

test("Sort by name, owned and age; ties fall back to name then id", function()
  local S = load().Search
  H.eq(S.Sort(copy(ALL), "name", true, ctx), { 12363, 13452, 12359, 10620, 19019, 55555 }, "unnamed last")
  H.eq(S.Sort(copy(ALL), "name", false, ctx), { 19019, 10620, 12359, 13452, 12363, 55555 }, "unnamed still last")
  H.eq(S.Sort({ 12359, 19019, 10620 }, "owned", false, ctx), { 12359, 19019, 10620 })
  H.eq(S.Sort({ 19019, 12359, 10620 }, "age", true, ctx), { 12359, 10620, 19019 })
end)

test("Sort by owned keeps the items you own none of last, in both directions", function()
  local S = load().Search
  H.eq(S.Sort({ 10620, 12359, 19019 }, "owned", true, ctx), { 19019, 12359, 10620 }, "fewest owned first, then the blanks")
  H.eq(S.Sort({ 10620, 19019, 12359 }, "owned", false, ctx), { 12359, 19019, 10620 })
end)

test("Sort copes with an empty list and an unknown key", function()
  local S = load().Search
  H.eq(S.Sort({}, "price", true, ctx), {})
  H.nothrows(function() S.Sort(copy(ALL), "nonsense", true, ctx) end)
end)

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------
local classNames = {
  [0] = "Consumable", [1] = "Container", [2] = "Weapon", [3] = "Gem", [4] = "Armor", [7] = "Trade Goods",
  [6] = "Projectile", [9] = "Recipe", [11] = "Quiver", [12] = "Quest", [15] = "Miscellaneous",
}
local subNames = {
  [4] = { [0] = "Miscellaneous", [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shield" },
  [2] = { [0] = "One-Handed Axes", [7] = "One-Handed Swords" },
  [7] = { [7] = "Metal & Stone", [12] = "Enchanting" },
}
local catEnv = {
  C_Item = {
    GetItemClassInfo = function(c) return classNames[c] end,
    GetItemSubClassInfo = function(c, s) return subNames[c] and subNames[c][s] or nil end,
  },
}

test("generated tree follows the classic Auction House order and skips unknown classes", function()
  local A = load(catEnv)
  local tree = A.Categories.Build(catEnv)
  local names = {}
  for _, node in ipairs(tree) do names[#names + 1] = node.name end
  H.eq(names, { "Weapon", "Armor", "Container", "Consumable", "Trade Goods", "Projectile", "Quiver", "Recipe", "Gem", "Miscellaneous", "Quest" })
  local noQuiver = { C_Item = { GetItemClassInfo = function(c) if c ~= 11 then return classNames[c] end end, GetItemSubClassInfo = catEnv.C_Item.GetItemSubClassInfo } }
  local count = #A.Categories.Build(noQuiver)
  H.eq(count, 10)
end)

test("generated tree adds subclasses and armor slots with real filters", function()
  local A = load(catEnv)
  local tree = A.Categories.Build(catEnv)
  local weapon = tree[1]
  H.eq(weapon.children[1].name, "One-Handed Axes")
  H.eq(weapon.children[1].filters, { { classID = 2, subClassID = 0 } })
  local armor = tree[2]
  H.eq(armor.filters, { { classID = 4 } })
  local cloth
  for _, c in ipairs(armor.children) do if c.name == "Cloth" then cloth = c end end
  H.eq(cloth.filters, { { classID = 4, subClassID = 1 } })
  H.eq(cloth.children[1].name, "Head")
  H.eq(cloth.children[1].filters, { { classID = 4, subClassID = 1, inventoryType = 1 } })
  local chest
  for _, c in ipairs(cloth.children) do if c.name == "Chest" then chest = c end end
  H.eq(#chest.filters, 2, "chest includes robes")
end)

test("Blizzard's AuctionCategories table is used when present", function()
  local env = { AuctionCategories = {
    { name = "Weapons", filters = { { classID = 2 } }, subCategories = {
      { name = "Axes", filters = { { classID = 2, subClassID = 0 } } } } },
    { name = "Misc", filters = { { classID = 15 } } },
  } }
  local A = load(env)
  local tree = A.Categories.Build(env)
  H.eq(#tree, 2)
  H.eq(tree[1].name, "Weapons")
  H.eq(tree[1].children[1].name, "Axes")
  H.eq(tree[1].children[1].filters, { { classID = 2, subClassID = 0 } })
  H.eq(tree[2].children, {})
end)

test("Matches checks class, subclass and inventory type", function()
  local C = load().Categories
  local node = { filters = { { classID = 4, subClassID = 1, inventoryType = 1 } } }
  H.truthy(C.Matches(node, { class = 4, sub = 1, invType = 1 }))
  H.falsy(C.Matches(node, { class = 4, sub = 1, invType = 3 }))
  H.falsy(C.Matches(node, { class = 4, sub = 2, invType = 1 }))
  H.falsy(C.Matches(node, { class = 2, sub = 1, invType = 1 }))
  H.falsy(C.Matches(node, { class = nil }))
  H.falsy(C.Matches(node, nil))
  H.truthy(C.Matches({ filters = { { classID = 4 }, { classID = 2 } } }, { class = 2, sub = 9 }))
  H.falsy(C.Matches({ filters = {} }, { class = 2 }), "no filters match nothing")
end)

test("Count tallies items per node and parents before children", function()
  local A = load(catEnv)
  local tree = A.Categories.Build(catEnv)
  A.Categories.Count(tree, ALL, ctx.info)
  local function find(nodes, name) for _, n in ipairs(nodes) do if n.name == name then return n end end end
  H.eq(find(tree, "Trade Goods").count, 3)
  H.eq(find(find(tree, "Trade Goods").children, "Metal & Stone").count, 1, "the ore is sub 7")
  H.eq(find(find(tree, "Trade Goods").children, "Enchanting").count, 1, "the bar is sub 12 in this fixture")
  H.eq(find(tree, "Weapon").count, 1)
  H.eq(find(tree, "Armor").count, 0)
end)

test("the moved filter keeps items whose price rose or fell by at least five percent", function()
  local S = load().Search
  H.eq(S.Run(copy(ALL), { moved = "up" }, ctx), { 12359 })
  H.eq(S.Run(copy(ALL), { moved = "down" }, ctx), { 10620 })
  H.eq(#S.Run(copy(ALL), {}, ctx), 6)
  H.eq(S.Run(copy(ALL), { moved = "up", minPrice = 99999999 }, ctx), {}, "combines with the other filters")
end)
