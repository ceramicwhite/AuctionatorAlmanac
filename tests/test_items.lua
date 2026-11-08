local H = require("harness")
local test = H.test

-- Fake C_Item: `data[id]` has the item's facts; `loaded[id]` says whether the
-- client has the name cached yet (GetItemInfo returns nothing until then).
local function setup(opts)
  opts = opts or {}
  local data = opts.data or {
    [12359] = { name = "Thorium Bar", quality = 2, icon = 135000, class = 7, sub = 12, equip = "", sell = 400, minLevel = 0, ilvl = 40 },
    [19019] = { name = "Thunderfury", quality = 5, icon = 135349, class = 2, sub = 7, equip = "INVTYPE_WEAPON", sell = 0, minLevel = 60, ilvl = 80 },
    [10620] = { name = "Thorium Ore", quality = 1, icon = 135001, class = 7, sub = 7, equip = "", sell = 150, minLevel = 0, ilvl = 40 },
  }
  local loaded = opts.loaded or {}
  local requested = {}
  local C_Item = {
    GetItemInfoInstant = function(id)
      local d = data[id]
      if not d then return nil end
      return id, "type", "subtype", d.equip, d.icon, d.class, d.sub
    end,
    GetItemInfo = function(id)
      local d = data[id]
      if not d or not loaded[id] then return nil end
      return d.name, "|link|", d.quality, d.ilvl, d.minLevel, "t", "s", 20, d.equip, d.icon, d.sell, d.class, d.sub
    end,
    RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end,
  }
  local timer = H.fakeTimer()
  local A = H.newA({ "Core/Init.lua", "Data/Items.lua" }, { C_Item = opts.noItemAPI and nil or C_Item, C_Timer = timer })
  A.db = A.InitDB(opts.saved)
  A.Items.Init(A.db)
  return A.Items, { data = data, loaded = loaded, requested = requested, timer = timer, A = A }
end

test("Ensure stores instant info immediately without a name", function()
  local Items, ctx = setup()
  local info = Items.Ensure(12359)
  H.eq(info.id, 12359)
  H.eq(info.name, nil)
  H.eq(info.icon, 135000)
  H.eq(info.class, 7)
  H.eq(info.sub, 12)
  H.eq(Items.Name(12359), "Item 12359")
  H.eq(#ctx.requested, 0, "requests go out on the next tick, not inline")
  ctx.timer.flush()
  H.eq(ctx.requested, { 12359 }, "name load requested")
  Items.Ensure(12359)
  ctx.timer.flush()
  H.eq(#ctx.requested, 1, "not re-requested while pending")
end)

test("OnLoaded fills in the name and details and persists them", function()
  local Items, ctx = setup()
  Items.Ensure(12359)
  ctx.loaded[12359] = true
  Items.OnLoaded(12359, true)
  local info = Items.Get(12359)
  H.eq(info.name, "Thorium Bar")
  H.eq(info.lname, "thorium bar")
  H.eq(info.quality, 2)
  H.eq(info.sell, 400)
  H.eq(info.minLevel, 0)
  H.eq(info.ilvl, 40)
  H.eq(Items.Name(12359), "Thorium Bar")
  H.eq(Items.NameIndex()[12359], "thorium bar")
  local row = ctx.A.db.items[12359]
  H.eq(row[1], "Thorium Bar")
  H.eq(row[2], 2)
  H.eq(row[3], 135000)
  H.eq(row[7], 400)
end)

test("a name the client already has is used without a server request", function()
  local Items, ctx = setup({ loaded = { [12359] = true } })
  local info = Items.Ensure(12359)
  ctx.timer.flush()
  H.eq(info.name, "Thorium Bar")
  H.eq(#ctx.requested, 0)
end)

test("items named in saved data are never re-requested after a reload", function()
  local saved = { version = 1, items = { [12359] = { "Thorium Bar", 2, 135000, 7, 12, 0, 400, 0, 40 } } }
  local Items, ctx = setup({ saved = saved })
  H.eq(Items.Get(12359).name, "Thorium Bar")
  H.eq(Items.NameIndex()[12359], "thorium bar")
  Items.Ensure(12359)
  H.eq(#ctx.requested, 0)
end)

test("an unnamed saved item gets its name requested again", function()
  local saved = { version = 1, items = { [12359] = { nil, nil, 135000, 7, 12 } } }
  local Items, ctx = setup({ saved = saved })
  Items.Ensure(12359)
  ctx.timer.flush()
  H.eq(ctx.requested, { 12359 })
end)

test("name loads are throttled per tick and each id is requested once", function()
  local data = {}
  for id = 1, 120 do data[id] = { name = "Item" .. id, quality = 1, icon = 1, class = 15, sub = 0, equip = "", sell = 1, minLevel = 0, ilvl = 1 } end
  local Items, ctx = setup({ data = data })
  local ids = {}
  for id = 1, 120 do ids[id] = id end
  Items.EnsureAll(ids)
  ctx.timer.flush(1)            -- first scheduled chunk only
  H.truthy(#ctx.requested <= Items.BATCH, "first tick requests at most BATCH, got " .. #ctx.requested)
  ctx.timer.flush()
  H.eq(#ctx.requested, 120)
  local seen = {}
  for _, id in ipairs(ctx.requested) do
    H.falsy(seen[id], "requested twice: " .. id)
    seen[id] = true
  end
end)

test("an item the client does not know does not break anything", function()
  local Items, ctx = setup()
  local info = Items.Ensure(999999)
  H.eq(info.missing, true)
  H.eq(Items.Name(999999), "Item 999999")
  H.eq(#ctx.requested, 0, "nothing to load for an invalid id")
  Items.OnLoaded(999999, true)
  H.eq(Items.Get(5), nil, "never-seen ids have no entry")
end)

test("a failed load is not retried forever", function()
  local Items, ctx = setup()
  Items.Ensure(12359)
  ctx.timer.flush()
  Items.OnLoaded(12359, false)
  Items.Ensure(12359)
  ctx.timer.flush()
  H.eq(#ctx.requested, 1)
end)

test("Progress counts named items among those ensured", function()
  local Items, ctx = setup()
  Items.EnsureAll({ 12359, 19019, 10620 })
  ctx.timer.flush()
  local have, total = Items.Progress()
  H.eq(have, 0); H.eq(total, 3)
  ctx.loaded[12359] = true; Items.OnLoaded(12359, true)
  ctx.loaded[19019] = true; Items.OnLoaded(19019, true)
  have, total = Items.Progress()
  H.eq(have, 2); H.eq(total, 3)
end)

test("EnsureAll reports progress and tolerates an empty list", function()
  local Items, ctx = setup()
  local calls = {}
  Items.EnsureAll({ 12359, 19019 }, function(done, total) calls[#calls + 1] = done .. "/" .. total end)
  ctx.timer.flush()
  H.eq(calls[#calls], "2/2")
  H.nothrows(function() Items.EnsureAll({}) end)
  ctx.timer.flush()
end)

test("naming an item fires ITEM_NAMES_UPDATED once for a batch", function()
  local Items, ctx = setup()
  local fired = 0
  ctx.A.Bus.On("ITEM_NAMES_UPDATED", function() fired = fired + 1 end)
  Items.Ensure(12359); Items.Ensure(19019)
  ctx.loaded[12359] = true; ctx.loaded[19019] = true
  Items.OnLoaded(12359, true); Items.OnLoaded(19019, true)
  ctx.timer.flush()
  H.eq(fired, 1)
end)

test("EquipToInventoryType maps equip locations", function()
  local Items = setup()
  H.eq(Items.EquipToInventoryType("INVTYPE_HEAD"), 1)
  H.eq(Items.EquipToInventoryType("INVTYPE_CLOAK"), 16)
  H.eq(Items.EquipToInventoryType("INVTYPE_2HWEAPON"), 17)
  H.eq(Items.EquipToInventoryType("INVTYPE_ROBE"), 20)
  H.eq(Items.EquipToInventoryType(""), nil)
  H.eq(Items.EquipToInventoryType(nil), nil)
  H.eq(Items.EquipToInventoryType("INVTYPE_NOPE"), nil)
end)

test("works with no item API at all", function()
  local Items = setup({ noItemAPI = true })
  local info
  H.nothrows(function() info = Items.Ensure(12359) end)
  H.eq(Items.Name(12359), "Item 12359")
  H.nothrows(function() Items.EnsureAll({ 1, 2, 3 }) end)
end)

test("invType is stored from the equip location", function()
  local Items = setup()
  H.eq(Items.Ensure(19019).invType, 13)
  H.eq(Items.Ensure(12359).invType, nil)
end)

test("IDByName finds loaded items case-insensitively and prefers the lowest id on a clash", function()
  local saved = { version = 1, items = {
    [12359] = { "Thorium Bar", 2, 1, 7, 12 },
    [20000] = { "Twin", 1, 1, 15, 0 },
    [19000] = { "Twin", 1, 1, 15, 0 },
  } }
  local Items, ctx = setup({ saved = saved })
  H.eq(Items.IDByName("thorium BAR"), 12359)
  H.eq(Items.IDByName("Twin"), 19000)
  H.eq(Items.IDByName("Nothing Here"), nil)
  H.eq(Items.IDByName(nil), nil)
  ctx.loaded[19019] = true
  Items.Ensure(19019)
  H.eq(Items.IDByName("Thunderfury"), 19019, "names loaded later are indexed too")
end)

test("IDByName falls back to the client's cache by name", function()
  local Items, ctx = setup()
  ctx.A.env.C_Item.GetItemInfoInstant = function(arg) if arg == "Mystery Item" then return 424242 end end
  H.eq(Items.IDByName("Mystery Item"), 424242)
end)

test("uncached items are never queried outside the throttled loader", function()
  local Items, ctx = setup()
  local infoCalls = 0
  local C = ctx.A.env.C_Item
  local realInfo = C.GetItemInfo
  C.GetItemInfo = function(id) infoCalls = infoCalls + 1; return realInfo(id) end
  C.IsItemDataCachedByID = function(id) return ctx.loaded[id] == true end
  Items.EnsureAll({ 12359, 19019, 10620 })
  H.eq(infoCalls, 0, "GetItemInfo would trigger an unthrottled server query for uncached items")
  ctx.timer.flush()
  H.eq(#ctx.requested, 3, "they are requested by the throttled loader instead")
  ctx.loaded[12359] = true
  Items.OnLoaded(12359, true)
  H.eq(Items.Get(12359).name, "Thorium Bar")
  Items.Ensure(10620)
  ctx.loaded[10620] = true
  Items.OnLoaded(10620, true)
  H.eq(Items.Name(10620), "Thorium Ore")
end)

test("items the client already has cached are named without any request", function()
  local Items, ctx = setup({ loaded = { [12359] = true } })
  ctx.A.env.C_Item.IsItemDataCachedByID = function(id) return ctx.loaded[id] == true end
  H.eq(Items.Ensure(12359).name, "Thorium Bar")
  ctx.timer.flush()
  H.eq(#ctx.requested, 0)
end)
