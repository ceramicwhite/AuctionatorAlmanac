local H = require("harness")
local test = H.test

local function load()
  local A = H.newA({ "Core/Init.lua", "Data/Stats.lua", "Data/Discovery.lua" })
  A.db = A.InitDB(nil)
  A.Discovery.Init(A.db)
  return A, A.Discovery
end

-- summaries as Controller builds them: [itemID] = { firstDay, lastDay }
local function sums(spec)
  local out = {}
  for id, v in pairs(spec) do out[id] = { firstDay = v[1], lastDay = v[2], last = 1000 } end
  return out
end

test("the saved data has a discovery section that survives repair", function()
  local A = H.newA({ "Core/Init.lua", "Data/Stats.lua", "Data/Discovery.lua" })
  local db = A.InitDB({ version = 1, discovery = "oops" })
  H.eq(type(db.discovery.first), "table")
  A.Discovery.Init(db)
  H.nothrows(function() A.Discovery.Observe({}, 1000) end)
end)

test("Observe records the first day each item was seen and never moves it later", function()
  local _, D = load()
  D.Observe(sums({ [1] = { 1000, 1005 }, [2] = { 1003, 1005 } }), 1000)
  H.eq(D.FirstSeen(1), 1000)
  H.eq(D.FirstSeen(2), 1003)
  -- Auctionator later forgets the early days: the item looks newer than it is
  D.Observe(sums({ [1] = { 1004, 1010 } }), 1004)
  H.eq(D.FirstSeen(1), 1000, "the earlier sighting stands")
  -- but a discovery that an item was seen even earlier does move it back
  D.Observe(sums({ [2] = { 1001, 1010 } }), 1004)
  H.eq(D.FirstSeen(2), 1001)
  H.eq(D.FirstSeen(99), nil)
end)

test("the first sighting date is the floor: nothing at or before it can be called new", function()
  local _, D = load()
  D.Observe(sums({ [1] = { 1000, 1005 } }), 1000)
  H.eq(D.Floor(), 1000)
  D.Observe(sums({ [1] = { 1004, 1010 } }), 1004)
  H.eq(D.Floor(), 1000, "the floor is set once")
end)

test("NewFinds lists items first seen on the newest scan day", function()
  local _, D = load()
  D.Observe(sums({ [1] = { 1000, 1005 }, [2] = { 1000, 1005 }, [3] = { 1005, 1005 } }), 1000)
  local r = D.NewFinds(sums({ [1] = { 1000, 1005 }, [2] = { 1000, 1005 }, [3] = { 1005, 1005 } }), 1005, {})
  H.eq(#r.rows, 1)
  H.eq(r.rows[1].id, 3)
  H.eq(r.rows[1].first, 1005)
end)

test("items present on the oldest day are not new: we cannot tell when they first appeared", function()
  local _, D = load()
  local data = sums({ [1] = { 1000, 1005 }, [2] = { 1005, 1005 } })
  D.Observe(data, 1000)
  local r = D.NewFinds(data, 1005, { window = 99 })
  H.eq(#r.rows, 1)
  H.eq(r.rows[1].id, 2)
end)

test("with only one scan day there is nothing to compare against", function()
  local _, D = load()
  local data = sums({ [1] = { 1005, 1005 }, [2] = { 1005, 1005 } })
  D.Observe(data, 1005)
  local r = D.NewFinds(data, 1005, {})
  H.eq(#r.rows, 0)
  H.eq(r.needsHistory, true)
end)

test("the window widens what counts as new", function()
  local _, D = load()
  local data = sums({ [1] = { 1000, 1010 }, [2] = { 1008, 1010 }, [3] = { 1010, 1010 } })
  D.Observe(data, 1000)
  H.eq(#D.NewFinds(data, 1010, { window = 0 }).rows, 1)
  H.eq(#D.NewFinds(data, 1010, { window = 3 }).rows, 2)
  H.eq(#D.NewFinds(data, 1010, { window = 30 }).rows, 2)
end)

test("an item Auctionator forgot and then saw again is not new", function()
  local _, D = load()
  D.Observe(sums({ [1] = { 1000, 1005 }, [9] = { 1002, 1005 } }), 1000)
  -- 30 days on, Auctionator's window has moved and item 9 reappears as if brand new
  local later = sums({ [1] = { 1030, 1035 }, [9] = { 1035, 1035 }, [10] = { 1035, 1035 } })
  D.Observe(later, 1030)
  local r = D.NewFinds(later, 1035, {})
  H.eq(#r.rows, 1)
  H.eq(r.rows[1].id, 10, "only the genuinely unseen item")
end)

test("a category that is mostly new is probably one that was not scanned before", function()
  local _, D = load()
  local spec = {}
  for id = 1, 100 do spec[id] = { 1000, 1005 } end                  -- class 7: old, all known
  for id = 101, 200 do spec[id] = { 1005, 1005 } end                -- class 4: all new today
  for id = 201, 300 do spec[id] = { 1000, 1005 } end                -- class 2: old
  spec[301] = { 1005, 1005 }                                         -- class 2: a single new one
  local data = sums(spec)
  D.Observe(sums({ [1] = { 1000, 1000 } }), 1000)     -- baseline day
  for id = 101, 301 do D.Observe({ [id] = data[id] }, 1000) end
  for id = 1, 100 do D.Observe({ [id] = data[id] }, 1000) end
  for id = 201, 300 do D.Observe({ [id] = data[id] }, 1000) end
  local classOf = function(id)
    if id <= 100 then return 7 elseif id <= 200 then return 4 else return 2 end
  end
  local r = D.NewFinds(data, 1005, { classOf = classOf })
  local byId = {}
  for _, row in ipairs(r.rows) do byId[row.id] = row end
  H.truthy(byId[150].conf.score <= 15, "everything new in its class: " .. byId[150].conf.score)
  H.truthy(byId[301].conf.score >= 85, "one new item among a hundred known: " .. byId[301].conf.score)
  H.eq(byId[301].conf.label, "high")
  H.eq(byId[150].conf.label, "low")
  H.truthy(table.concat(byId[150].conf.reasons, " "):lower():find("not been scanned", 1, true)
    or table.concat(byId[150].conf.reasons, " "):lower():find("scanned before", 1, true))
end)

test("a very large share of new items raises the coverage warning", function()
  local _, D = load()
  local spec = { [1] = { 1000, 1005 } }
  for id = 2, 60 do spec[id] = { 1005, 1005 } end
  local data = sums(spec)
  D.Observe(data, 1000)
  local r = D.NewFinds(data, 1005, {})
  H.eq(r.partial, true)
  H.eq(r.seen, 60)
  H.eq(r.newCount, 59)
  local calm = sums({ [1] = { 1000, 1005 }, [2] = { 1000, 1005 }, [3] = { 1000, 1005 }, [4] = { 1000, 1005 }, [5] = { 1005, 1005 } })
  local _, D2 = load()
  D2.Observe(calm, 1000)
  H.eq(D2.NewFinds(calm, 1005, {}).partial, false)
end)

test("Reset forgets everything", function()
  local _, D = load()
  D.Observe(sums({ [1] = { 1000, 1005 } }), 1000)
  D.Reset()
  H.eq(D.FirstSeen(1), nil)
  H.eq(D.Floor(), nil)
  H.eq(#D.NewFinds(sums({ [1] = { 1000, 1005 } }), 1005, {}).rows, 0)
end)

test("Count reports how many items are being tracked", function()
  local _, D = load()
  D.Observe(sums({ [1] = { 1000, 1005 }, [2] = { 1001, 1005 } }), 1000)
  H.eq(D.Count(), 2)
end)
