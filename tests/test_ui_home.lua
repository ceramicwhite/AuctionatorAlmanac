local H = require("harness")
local Stub = require("ui_stub")
local Boot = require("boot_ui")
local Fx = require("fixtures")
local test = H.test

local function plain(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  return s
end

local function headers(lines)
  local out = {}
  for _, l in ipairs(lines) do if l.kind == "header" then out[#out + 1] = l.text end end
  return out
end

local function itemsUnder(lines, header)
  local out, inside = {}, false
  for _, l in ipairs(lines) do
    if l.kind == "header" then inside = (l.text == header) elseif inside and l.kind == "item" then out[#out + 1] = l end
  end
  return out
end

local function textsUnder(lines, header)
  local out, inside = {}, false
  for _, l in ipairs(lines) do
    if l.kind == "header" then inside = (l.text == header) elseif inside and l.kind == "text" then out[#out + 1] = plain(l.text) end
  end
  return out
end

test("the overview has its sections in order", function()
  local A = Boot.boot()
  local lines = A.UI.Home.Lines()
  H.eq(headers(lines), { "Biggest movers (7 days)", "Below their average", "Your inventory", "Recent activity", "Shopping lists" })
  H.eq(lines[1].kind, "text", "starts with a hint")
  H.truthy(plain(lines[1].text):lower():find("select", 1, true))
end)

test("movers lists items whose price moved, with the change", function()
  local A = Boot.boot()
  local up = itemsUnder(A.UI.Home.Lines(), "Biggest movers (7 days)")
  H.eq(#up, 1)
  H.eq(up[1].id, 12359)
  H.truthy(plain(up[1].extra):find("+2%", 1, true), up[1].extra)
  H.eq(plain(up[1].value), "1g 12s")
end)

test("empty sections say why they are empty", function()
  local A = Boot.boot()
  local lines = A.UI.Home.Lines()
  H.truthy(#textsUnder(lines, "Below their average") == 1)
  H.truthy(plain(textsUnder(lines, "Below their average")[1]):lower():find("nothing", 1, true))
  H.truthy(plain(textsUnder(lines, "Your inventory")[1]):lower():find("no items", 1, true))
  H.truthy(plain(textsUnder(lines, "Recent activity")[1]):lower():find("no sales", 1, true))
end)

test("items well under their average are flagged", function()
  local A = Boot.boot()
  -- make Thorium Bar's current price a bargain: m far below its recent lows
  A.Controller.Reload()
  local s = A.Controller.summaries[12359]
  s.last, s.avg, s.nDays, s.qty = 5000, 11000, 6, 40
  local found = itemsUnder(A.UI.Home.Lines(), "Below their average")
  H.eq(found[1].id, 12359)
  H.truthy(plain(found[1].extra):find("-55%", 1, true), found[1].extra)
end)

test("inventory shows the total value and the most valuable items", function()
  local A = Boot.boot()
  A.Inventory.EnsureChar({ name = "Thornwick", realm = "Whitemane" })
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [12359] = 14, [12363] = 1, [19019] = 1, [55555] = 9 }, 1)
  local lines = A.UI.Home.Lines()
  local summary = textsUnder(lines, "Your inventory")[1]
  H.truthy(summary:find("17 items", 1, true) or summary:find("worth", 1, true), summary)
  local items = itemsUnder(lines, "Your inventory")
  H.eq(items[1].id, 19019, "most valuable first: 5,000,000")
  H.eq(items[2].id, 12363)
  H.eq(items[3].id, 12359)
  H.truthy(plain(items[3].extra):find("14", 1, true))
  H.truthy(summary:find("1 item without", 1, true) or textsUnder(lines, "Your inventory")[2], "unpriced items are mentioned")
end)

test("recent activity lists your latest sales and purchases", function()
  local A = Boot.boot()
  local now = Fx.NOW
  A.Ledger.Add({ kind = "sold", itemID = 12359, qty = 20, total = 220000, time = now - 3600, source = "mail", party = "Buyer", char = "T" })
  A.Ledger.Add({ kind = "bought", itemID = 12363, qty = 1, total = 1400000, time = now - 86400 * 2, source = "ah", char = "T" })
  A.Ledger.Add({ kind = "posted", itemID = 12359, qty = 20, total = 230000, time = now - 100, source = "auctionator" })
  local items = itemsUnder(A.UI.Home.Lines(), "Recent activity")
  H.eq(#items, 2, "postings are not activity")
  H.eq(items[1].id, 12359)
  H.truthy(plain(items[1].extra):find("Sold 20", 1, true))
  H.truthy(plain(items[1].extra):find("1h", 1, true))
  H.eq(items[2].id, 12363)
  H.truthy(plain(items[2].extra):find("Bought 1", 1, true))
end)

test("Auctionator shopping lists show current prices for their items", function()
  local A = Boot.boot()
  local lines = A.UI.Home.Lines()
  local seen = {}
  local inside = false
  for _, l in ipairs(lines) do
    if l.kind == "header" then inside = l.text == "Shopping lists"
    elseif inside then seen[#seen + 1] = l end
  end
  H.eq(plain(seen[1].text), "Smithing")
  H.eq(seen[1].kind, "text")
  H.eq(seen[2].id, 12359, "exact term resolves to Thorium Bar")
  H.eq(seen[3].id, 12363, "a plain term resolves by name")
  H.eq(plain(seen[2].value), "1g 12s")
end)

test("shopping list terms with no matching item are listed, not dropped", function()
  local A = Boot.boot({ fixture = { AUCTIONATOR_SHOPPING_LISTS = { { name = "Odd", items = { "Nonexistent Thing" } } } } })
  local lines = A.UI.Home.Lines()
  local found = false
  for _, l in ipairs(lines) do
    if l.kind == "text" and plain(l.text):find("Nonexistent Thing", 1, true) then found = true end
  end
  H.truthy(found)
end)

test("the overview works with no Auctionator data at all", function()
  local A = Boot.boot({ fixture = { Auctionator = false } })
  H.nothrows(function() A.UI.Home.Lines() end)
  local lines = A.UI.Home.Lines()
  H.truthy(#lines >= 1)
end)

test("the overview renders in the detail panel and clicking an item selects it", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  H.truthy(win.homeView:IsShown())
  local list = win.homeList
  H.truthy(list.rows[1]:IsShown())
  local target
  for _, row in ipairs(list.rows) do
    if row:IsShown() and row.item and row.item.id == 12359 then target = row; break end
  end
  H.truthy(target, "a row for Thorium Bar is on screen")
  Stub.fire(target, "OnClick", "LeftButton")
  H.eq(A.Controller.state.selected, 12359)
  H.falsy(win.homeView:IsShown())
  H.truthy(win.itemView:IsShown())
  win.itemView.backButton:Click()
  Stub.settle(env)
  H.truthy(win.homeView:IsShown())
end)

test("the overview refreshes when inventory or the ledger changes", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  local function count()
    local n = 0
    for _, l in ipairs(win.homeList.data) do if l.kind == "item" and l.id == 12363 then n = n + 1 end end
    return n
  end
  local before = count()
  A.Inventory.EnsureChar({ name = "Thornwick", realm = "Whitemane" })
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [12363] = 2 }, 1)
  A.Bus.Fire("INVENTORY_UPDATED")
  env.C_Timer.flush()
  H.truthy(count() > before)
end)

test("the overview fits at every window size", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  for _, size in ipairs({ { 960, 540 }, { 1400, 900 } }) do
    Stub.resize(env, win, size[1], size[2])
    H.truthy(Stub.within(win.homeList.frame, win.detailPanel), "list inside the panel")
    H.truthy(win.homeList.frame:GetHeight() > 200)
    local row = win.homeList.rows[2]
    H.truthy(Stub.within(row.name, row), "name inside its row")
  end
end)
