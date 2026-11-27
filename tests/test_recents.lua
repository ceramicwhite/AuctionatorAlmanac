local H = require("harness")
local test = H.test

-- A fresh module with its own saved table; `env` is what Auctionator has saved.
local function load(env)
  env = env or {}
  local A = H.newA({ "Core/Init.lua", "Data/Adapter.lua", "Data/Recents.lua" }, env)
  local db = A.InitDB(nil)
  A.Recents.Init(db)
  return A, db, env
end

test("a new database has an empty search history", function()
  local A = load()
  H.eq(A.NewDB().recents, { entries = {}, seq = 0, head = "" })
  H.eq(A.Recents.List(), {})
  H.eq(A.Recents.Count(), 0)
end)

test("Normalize trims and collapses spaces and refuses what is not worth keeping", function()
  local R = load().Recents
  H.eq(R.Normalize("  black   lotus  "), "black lotus")
  H.eq(R.Normalize("Thorium\tBar"), "Thorium Bar")
  H.eq(R.Normalize("ab"), "ab")
  H.eq(R.Normalize("a"), nil, "one letter")
  H.eq(R.Normalize("   "), nil)
  H.eq(R.Normalize(""), nil)
  H.eq(R.Normalize(nil), nil)
  H.eq(R.Normalize(12345), nil, "only text")
  H.eq(R.Normalize(("x"):rep(64)), ("x"):rep(64))
  H.eq(R.Normalize(("x"):rep(65)), nil, "longer than the search box holds")
  H.eq(R.Normalize("|cff1eff00|Hitem:12359|h[Thorium Bar]|h|r"), nil, "a pasted link would show as raw escape codes")
end)

test("Add keeps the newest search first and says whether it kept it", function()
  local R = load().Recents
  H.eq(R.Add("thorium"), true)
  H.eq(R.Add("arcane"), true)
  H.eq(R.Add("mongoose"), true)
  H.eq(R.List(), { "mongoose", "arcane", "thorium" })
  H.eq(R.Add("x"), false)
  H.eq(R.Add(""), false)
  H.eq(R.Add(nil), false)
  H.eq(R.List(), { "mongoose", "arcane", "thorium" }, "refused searches change nothing")
end)

test("searching again moves a search to the front and keeps the newest spelling, once", function()
  local R = load().Recents
  R.Add("thorium bar")
  R.Add("arcane crystal")
  R.Add("  Thorium   BAR ")
  H.eq(R.List(), { "Thorium BAR", "arcane crystal" })
  H.eq(R.Count(), 2)
end)

test("the history holds the newest 50 searches", function()
  local R = load().Recents
  for i = 1, 60 do R.Add("search " .. i) end
  local list = R.List()
  H.eq(#list, 50)
  H.eq(list[1], "search 60")
  H.eq(list[50], "search 11")
end)

test("the history lives in the saved database and carries on from it", function()
  local A, db = load()
  A.Recents.Add("thorium")
  A.Recents.Add("arcane")
  H.eq(#db.recents.entries, 2)
  local again = load()
  again.Recents.Init(db)         -- the next session: the same saved table
  H.eq(again.Recents.List(), { "arcane", "thorium" })
  again.Recents.Add("mongoose")
  H.eq(again.Recents.List(), { "mongoose", "arcane", "thorium" }, "new searches go in front of old ones")
end)

test("a damaged saved database is repaired, and damaged entries are skipped", function()
  local A = H.newA({ "Core/Init.lua", "Data/Adapter.lua", "Data/Recents.lua" }, {})
  for _, bad in ipairs({ "text", 5, true }) do
    local db = { recents = bad }
    A.Recents.Init(db)
    H.eq(db.recents, { entries = {}, seq = 0, head = "" })
  end
  local db = { recents = { entries = "x", seq = "y", head = 7 } }
  A.Recents.Init(db)
  H.eq(db.recents, { entries = {}, seq = 0, head = "" })

  db = { recents = { entries = { { text = "good one", seq = 4 }, "junk", { text = 5 }, { seq = 9 }, { text = "", seq = 8 }, { text = "older", seq = 2 } }, seq = 9, head = "" } }
  A.Recents.Init(db)
  H.eq(A.Recents.List(), { "good one", "older" })
  A.Recents.Add("new")
  H.eq(A.Recents.List(), { "new", "good one", "older" })
  H.eq(#db.recents.entries, 3, "the damaged entries go when the list is next saved")
end)

-- ---------------------------------------------------------------------------
-- Auctionator's recent searches
-- ---------------------------------------------------------------------------
test("the adapter reads Auctionator's recent searches as plain text, newest first", function()
  local A = load({
    AUCTIONATOR_RECENT_SEARCHES = { '"Black Lotus"', "arcane crystal;;;;;;;;;;;;;;", ";;;;;;;;;;;;;;", 42, "thorium", "" },
  })
  H.eq(A.Adapter.RecentSearches(), { "Black Lotus", "arcane crystal", "thorium" })
  H.eq(load({}).Adapter.RecentSearches(), {})
  H.eq(load({ AUCTIONATOR_RECENT_SEARCHES = "nope" }).Adapter.RecentSearches(), {})
end)

test("the adapter reads the search terms of the shopping lists as plain text", function()
  local A = load({
    AUCTIONATOR_SHOPPING_LISTS = {
      { name = "Smithing", items = { '"Thorium Bar";;;;;;;;;;;;;;', "Arcane Crystal", 5, ";;;;;;;;;;;;;;" } },
      { name = "Empty", items = {} },
      "not a list",
    },
  })
  H.eq(A.Adapter.ShoppingTerms(), { "Thorium Bar", "Arcane Crystal" })
  H.eq(load({}).Adapter.ShoppingTerms(), {})
end)

test("the first Sync brings in Auctionator's whole list, in its order", function()
  local A, _, env = load({ AUCTIONATOR_RECENT_SEARCHES = { '"Black Lotus"', "arcane crystal;;;3", ";;;;4", "thorium" } })
  H.eq(A.Recents.Sync(), 3)
  H.eq(A.Recents.List(), { "Black Lotus", "arcane crystal", "thorium" })
  H.eq(A.Recents.Sync(), 0, "nothing new the second time")
  H.eq(A.Recents.List(), { "Black Lotus", "arcane crystal", "thorium" })
  env.AUCTIONATOR_RECENT_SEARCHES = nil
  H.eq(A.Recents.Sync(), 0, "no Auctionator list is not an error")
  H.eq(A.Recents.Count(), 3)
end)

test("a search made in Auctionator after the first look goes in front of the ones already here", function()
  local A, _, env = load({ AUCTIONATOR_RECENT_SEARCHES = { "thorium", "arcane" } })
  A.Recents.Sync()
  A.Recents.Add("mongoose")
  H.eq(A.Recents.List(), { "mongoose", "thorium", "arcane" })
  -- Auctionator puts a new search at the front of its list
  table.insert(env.AUCTIONATOR_RECENT_SEARCHES, 1, '"Black Lotus"')
  H.eq(A.Recents.Sync(), 1)
  H.eq(A.Recents.List(), { "Black Lotus", "mongoose", "thorium", "arcane" })
  A.Recents.Add("elixir")
  table.insert(env.AUCTIONATOR_RECENT_SEARCHES, 1, "runecloth")
  table.insert(env.AUCTIONATOR_RECENT_SEARCHES, 1, "mithril")
  H.eq(A.Recents.Sync(), 2)
  H.eq(A.Recents.List(), { "mithril", "runecloth", "elixir", "Black Lotus", "mongoose", "thorium", "arcane" }, "the newest of two new searches is on top")
end)

test("a search made again in Auctionator moves up, and one made in both addons is listed once", function()
  local A, _, env = load({ AUCTIONATOR_RECENT_SEARCHES = { "thorium", "arcane", "mongoose" } })
  A.Recents.Sync()
  A.Recents.Add("lotus")
  -- Auctionator searches "mongoose" again: it leaves the end of its list for the front
  env.AUCTIONATOR_RECENT_SEARCHES = { "mongoose", "thorium", "arcane" }
  H.eq(A.Recents.Sync(), 1)
  H.eq(A.Recents.List(), { "mongoose", "lotus", "thorium", "arcane" })
  -- the same search typed here, then found in Auctionator's list with other casing and a filter
  A.Recents.Add("Arcane")
  env.AUCTIONATOR_RECENT_SEARCHES = { "ARCANE;;;3", "mongoose", "thorium" }
  A.Recents.Sync()
  H.eq(A.Recents.Count(), 4)
  H.eq(A.Recents.List()[1], "ARCANE", "the newest spelling")
end)

test("when the search Almanac last saw at the front of Auctionator's list is gone, the whole list is looked at again", function()
  local A, _, env = load({ AUCTIONATOR_RECENT_SEARCHES = { "thorium", "arcane" } })
  A.Recents.Sync()
  A.Recents.Add("mongoose")
  env.AUCTIONATOR_RECENT_SEARCHES = { "arcane" }        -- "thorium" was deleted in Auctionator
  A.Recents.Sync()
  H.eq(A.Recents.List(), { "arcane", "mongoose", "thorium" }, "nothing is lost; the search still in Auctionator is the newest")
end)

test("Sync keeps the history within its limit", function()
  local saved = {}
  for i = 1, 30 do saved[i] = "auction " .. i end
  local A = load({ AUCTIONATOR_RECENT_SEARCHES = saved })
  for i = 1, 40 do A.Recents.Add("mine " .. i) end
  A.Recents.Sync()
  H.eq(A.Recents.Count(), 50)
  H.eq(A.Recents.List()[1], "auction 1")
  H.eq(A.Recents.List()[30], "auction 30")
  H.eq(A.Recents.List()[31], "mine 40")
end)

-- ---------------------------------------------------------------------------
-- Autofill
-- ---------------------------------------------------------------------------
test("Suggest completes what was typed from the newest search that starts with it", function()
  local R = load().Recents
  R.Add("thorium ore")
  R.Add("thorium bar")
  R.Add("arcane crystal")
  H.eq(R.Suggest("th"), "thorium bar", "the newest of two")
  H.eq(R.Suggest("thorium o"), "thorium ore")
  H.eq(R.Suggest("ARC"), "arcane crystal", "whatever the case typed")
  H.eq(R.Suggest("thorium "), "thorium bar")
  R.Add("Thorium Ore")
  H.eq(R.Suggest("thor"), "Thorium Ore", "the player's own spelling is kept")
end)

test("Suggest offers nothing when there is nothing longer to complete to", function()
  local R = load().Recents
  R.Add("thorium bar")
  H.eq(R.Suggest("thorium bar"), nil, "already all of it")
  H.eq(R.Suggest("thorium bars"), nil)
  H.eq(R.Suggest("zzz"), nil)
  H.eq(R.Suggest(""), nil)
  H.eq(R.Suggest(nil), nil)
  H.eq(R.Suggest("bar"), nil, "only the start of a search completes")
end)

test("Suggest completes from searches made in Auctionator once they have been brought in", function()
  local A = load({ AUCTIONATOR_RECENT_SEARCHES = { '"Black Lotus"', "arcane crystal" } })
  H.eq(A.Recents.Suggest("bl"), nil, "not until they are brought in")
  A.Recents.Sync()
  H.eq(A.Recents.Suggest("bl"), "Black Lotus")
  H.eq(A.Recents.Suggest("arc"), "arcane crystal")
end)

test("Suggest falls back to the terms in the Auctionator shopping lists, after every recent search", function()
  local A = load({ AUCTIONATOR_SHOPPING_LISTS = { { name = "Smithing", items = { '"Thorium Bar";;;;;;;;;;;;;;', "Arcane Crystal", "Thorium Ore" } } } })
  H.eq(A.Recents.Suggest("arc"), "Arcane Crystal")
  H.eq(A.Recents.Suggest("thorium o"), "Thorium Ore")
  A.Recents.Add("thorium plate")
  H.eq(A.Recents.Suggest("thor"), "thorium plate", "a recent search wins over a shopping list term")
  H.eq(A.Recents.Suggest("thorium b"), "Thorium Bar")
end)

-- ---------------------------------------------------------------------------
-- Erasing
-- ---------------------------------------------------------------------------
test("Clear forgets what was searched here, and does not bring Auctionator's current list back", function()
  local A, _, env = load({ AUCTIONATOR_RECENT_SEARCHES = { "thorium", "arcane" } })
  A.Recents.Sync()
  A.Recents.Add("mongoose")
  A.Recents.Clear()
  H.eq(A.Recents.List(), {})
  H.eq(A.Recents.Suggest("th"), nil)
  H.eq(A.Recents.Sync(), 0, "what Auctionator already had is not imported again")
  H.eq(A.Recents.List(), {})
  table.insert(env.AUCTIONATOR_RECENT_SEARCHES, 1, "lotus")
  H.eq(A.Recents.Sync(), 1, "but a search made afterwards is")
  H.eq(A.Recents.List(), { "lotus" })
  H.eq(env.AUCTIONATOR_RECENT_SEARCHES, { "lotus", "thorium", "arcane" }, "Auctionator's list is never changed")
end)
