local H = require("harness")
local test = H.test

local function load(env) return H.newA({ "Core/Init.lua" }, env) end

test("InitDB(nil) returns defaults", function()
  local A = load()
  local db = A.InitDB(nil)
  H.eq(db.version, 2)
  H.eq(#db.ledger.entries, 0)
  H.eq(db.settings.tooltips, false, "tooltip lines are opt-in")
  H.eq(db.settings.autoScan, true, "scanning when the Auction House opens is on")
  H.eq(db.settings.minimap, true)
  H.eq(A.DB_VERSION, 2)
end)

test("InitDB keeps ledger entries from an older version", function()
  local A = load()
  local db = A.InitDB({ version = 0, ledger = { entries = { { id = 1, kind = "sold" } } } })
  H.eq(db.version, 2)
  H.eq(db.ledger.entries[1].id, 1)
  H.eq(db.settings.tooltips, false, "missing sections are filled in")
  H.eq(db.settings.autoScan, true)
end)

test("InitDB repairs garbage and wrong-typed sections", function()
  local A = load()
  H.eq(A.InitDB("garbage").version, 2)
  local db = A.InitDB({ version = 1, ledger = "oops", settings = 5, items = { [5] = { "x" } } })
  H.eq(type(db.ledger), "table")
  H.eq(#db.ledger.entries, 0)
  H.eq(db.settings.tooltips, false)
  H.eq(db.items[5][1], "x", "valid data survives repair")
end)

test("InitDB keeps user-changed settings", function()
  local A = load()
  local db = A.InitDB({ version = 2, settings = { tooltips = true, autoScan = false } })
  H.eq(db.settings.tooltips, true, "a choice made under the current version is kept")
  H.eq(db.settings.autoScan, false)
  H.eq(db.settings.minimap, true)
end)

test("upgrading from version 1 turns tooltip lines off once, whatever was saved", function()
  local A = load()
  -- version 1 wrote its default (on) into the file, so a saved "on" cannot be told from a choice
  local db = A.InitDB({ version = 1, settings = { tooltips = true, minimap = false } })
  H.eq(db.version, 2)
  H.eq(db.settings.tooltips, false)
  H.eq(db.settings.minimap, false, "nothing else is touched")
  H.eq(db.settings.autoScan, true)
  -- and from then on the player's own choice sticks
  db.settings.tooltips = true
  local again = A.InitDB(db)
  H.eq(again.settings.tooltips, true)
end)

test("Bus delivers args and survives a failing listener", function()
  local A = load()
  local got = {}
  A.Bus.On("X", function(a, b) error("boom") end)
  A.Bus.On("X", function(a, b) got[#got + 1] = a .. b end)
  A.Bus.Fire("X", "p", "q")
  H.eq(got, { "pq" })
end)

test("Get/Set settings fire SETTINGS_CHANGED", function()
  local A = load()
  A.db = A.InitDB(nil)
  local seen
  A.Bus.On("SETTINGS_CHANGED", function(key, value) seen = key .. "=" .. tostring(value) end)
  A.Set("tooltips", false)
  H.eq(A.Get("tooltips"), false)
  H.eq(seen, "tooltips=false")
end)

test("FireEvent dispatches to handlers registered with RegisterEvent", function()
  local A = load()
  local n = 0
  H.truthy(A.RegisterEvent("MAIL_SHOW", function(event, x) n = n + x end))
  A.FireEvent("MAIL_SHOW", 2)
  A.FireEvent("MAIL_SHOW", 3)
  H.eq(n, 5)
end)

test("RegisterEvent returns false when the client rejects the event name", function()
  local frame = { RegisterEvent = function() error("unknown event") end, SetScript = function() end }
  local A = load({ CreateFrame = function() return frame end })
  H.falsy(A.RegisterEvent("NOT_A_REAL_EVENT", function() end))
end)

test("After runs through C_Timer when present, immediately otherwise", function()
  local timer = H.fakeTimer()
  local A = load({ C_Timer = timer })
  local ran = false
  A.After(1, function() ran = true end)
  H.falsy(ran)
  timer.flush()
  H.truthy(ran)
  local B = load()
  local ran2 = false
  B.After(1, function() ran2 = true end)
  H.truthy(ran2)
end)

test("RunBudgeted stops at the cap, resumes where it left off, and covers everything", function()
  local A = load()
  local seen = {}
  local function work(k) seen[#seen + 1] = k end
  local nextIndex = A.RunBudgeted(1, 10, 4, 6, work)
  H.eq(nextIndex, 5)
  H.eq(seen, { 1, 2, 3, 4 })
  nextIndex = A.RunBudgeted(nextIndex, 10, 4, 6, work)
  nextIndex = A.RunBudgeted(nextIndex, 10, 4, 6, work)
  H.eq(nextIndex, 11)
  H.eq(#seen, 10)
  H.eq(A.RunBudgeted(1, 0, 4, 6, work), 1, "nothing to do")
end)

test("RunBudgeted yields once the time budget is spent", function()
  local now = 0
  local A = load({ debugprofilestop = function() return now end })
  local count = 0
  local nextIndex = A.RunBudgeted(1, 1000, 1000, 6, function() count = count + 1; now = now + 1 end)
  H.truthy(count < 1000, "stopped early, did " .. count)
  H.truthy(count >= 6, "but did real work first")
  H.eq(nextIndex, count + 1)
end)

test("a database saved before the search history existed gains an empty one, and keeps its data", function()
  local A = H.newA({ "Core/Init.lua" }, {})
  local old = { version = 2, settings = { minimap = false }, ledger = { entries = { { id = 1 } }, seq = 1 } }
  local db = A.InitDB(old)
  H.eq(db.recents, { entries = {}, seq = 0, head = "" })
  H.eq(db.settings.minimap, false)
  H.eq(#db.ledger.entries, 1)
  local saved = A.InitDB({ recents = { entries = { { text = "thorium", seq = 3 } }, seq = 3, head = "thorium" } })
  H.eq(saved.recents.entries[1].text, "thorium", "an existing history is kept")
  H.eq(saved.recents.head, "thorium")
end)
