local H = require("harness")
local Boot = require("boot_ui")
local test = H.test

local function plain(s)
  s = tostring(s):gsub("|c%x%x%x%x%x%x%x%x", "")
  return (s:gsub("|r", ""))
end

local function rowFor(A, id)
  for _, row in ipairs(A.Overview.Rows("top500")) do
    if row.id == id then return row end
  end
end

local function column(def, key)
  for _, col in ipairs(def.columns) do
    if col.key == key then return col end
  end
end

-- Non-nil values in order (ascending or descending), and every nil after them.
local function ordered(rows, valueOf, ascending)
  local last, sawNil = nil, false
  for i, row in ipairs(rows) do
    local v = valueOf(row)
    if v == nil then
      sawNil = true
    else
      if sawNil then return false, "a value after a blank at row " .. i end
      if last ~= nil and (ascending and v < last or not ascending and v > last) then
        return false, "out of order at row " .. i .. ": " .. tostring(last) .. " then " .. tostring(v)
      end
      last = v
    end
  end
  return true
end

test("the Top 500 is 500 different items, each with a name, a quality and a kind the page can filter by", function()
  local A = Boot.boot()
  local def = A.Overview.Section("top500")
  local kinds = {}
  for _, f in ipairs(def.filters) do
    if f.key == "kind" then
      for _, o in ipairs(f.options) do if o.value then kinds[o.value] = true end end
    end
  end
  H.eq(#A.Top500, 500)
  local seen = {}
  for i, e in ipairs(A.Top500) do
    H.truthy(type(e.id) == "number" and not seen[e.id], "a new item at " .. i)
    seen[e.id] = true
    H.truthy(type(e.name) == "string" and e.name ~= "", "named at " .. i)
    H.truthy(type(e.q) == "number" and e.q >= 0 and e.q <= 5, "quality at " .. i)
    H.truthy(kinds[e.kind], "kind " .. tostring(e.kind) .. " at " .. i)
    H.truthy(e.note == nil or (type(e.note) == "string" and e.note ~= ""), "note at " .. i)
  end
end)

test("the Top 500 is a page of its own, not a table on the overview", function()
  local A = Boot.boot()
  H.truthy(A.Overview.Section("top500"))
  for _, def in ipairs(A.Overview.Sections()) do H.truthy(def.key ~= "top500") end
end)

test("every item on the list is a row, priced from this house where Auctionator has it", function()
  local A = Boot.boot()
  local rows = A.Overview.Rows("top500")
  H.eq(#rows, 500)
  local crystal = rowFor(A, 12363)
  H.eq(crystal.price, A.Controller.Summary(12363).last)
  H.eq(crystal.kind, "reagent")
  local flask = rowFor(A, 13513)
  H.eq(flask.price, nil, "not on this house")
  H.eq(flask.name, "Flask of Chromatic Resistance")
end)

test("an item the client has not named yet shows the list's name in its quality colour", function()
  local A = Boot.boot()
  local def = A.Overview.Section("top500")
  local text = def.columns[1].text(rowFor(A, 13513))
  H.eq(text, A.Format.ColorName("Flask of Chromatic Resistance", 1))
  H.eq(plain(def.columns[1].text(rowFor(A, 12363))), "Arcane Crystal")
end)

test("every column sorts both ways, with the items it has nothing for last", function()
  local A = Boot.boot()
  local def = A.Overview.Section("top500")
  H.truthy(#def.columns >= 8, "item, kind, price, at lowest, on AH, 7d, own, seen")
  for _, col in ipairs(def.columns) do
    H.truthy(col.value, col.key .. " can be sorted")
    for _, asc in ipairs({ true, false }) do
      local rows = A.Overview.View("top500", { expanded = true, sortKey = col.key, asc = asc })
      H.eq(#rows, 500)
      local ok, why = ordered(rows, col.value, asc)
      H.truthy(ok, col.key .. (asc and " ascending: " or " descending: ") .. tostring(why))
    end
  end
  local dearest = A.Overview.View("top500", { expanded = true, sortKey = "price", asc = false })[1]
  local cheapest = A.Overview.View("top500", { expanded = true, sortKey = "price", asc = true })[1]
  H.truthy(dearest.price and cheapest.price and dearest.price > cheapest.price, "high to low, and low to high")
end)

test("the kind filter keeps one kind of item", function()
  local A = Boot.boot()
  local pets = 0
  for _, e in ipairs(A.Top500) do if e.kind == "pet" then pets = pets + 1 end end
  A.Overview.SetFilter("top500", "kind", "pet")
  local rows, total = A.Overview.View("top500", { expanded = true })
  H.eq(#rows, pets)
  H.eq(total, pets)
  for _, row in ipairs(rows) do H.eq(row.kind, "pet") end
  A.Overview.SetFilter("top500", "kind", nil)
  H.eq(#A.Overview.View("top500", { expanded = true }), 500)
end)

test("the Own column follows what you own", function()
  local A = Boot.boot()
  local def = A.Overview.Section("top500")
  H.eq(column(def, "owned").text(rowFor(A, 12359)), "")
  A.Inventory.SetLocation("Thornwick-Whitemane", "bags", { [12359] = 14 }, 1)
  A.Bus.Fire("INVENTORY_UPDATED")
  H.eq(rowFor(A, 12359).owned, 14)
  H.eq(column(def, "owned").text(rowFor(A, 12359)), "14")
end)

test("the lead says how many of the list this house has a price for", function()
  local A = Boot.boot()
  local priced = 0
  for _, e in ipairs(A.Top500) do if A.Controller.Summary(e.id) then priced = priced + 1 end end
  H.truthy(priced > 0)
  local text = table.concat(A.Overview.Lead("top500"), " ")
  H.truthy(text:find(priced .. " of 500", 1, true), text)
end)

test("hovering a row says what the item is and why it is on the list", function()
  local A = Boot.boot()
  local def = A.Overview.Section("top500")
  local lines = def.tip(rowFor(A, 13510))
  H.eq(lines[1], "Consumable · Flasks · req. level 50")
  H.truthy(lines[2]:find("tanks' flask", 1, true), lines[2])
  H.eq(def.tip(rowFor(A, 5500)), { "Reagent" }, "Iridescent Pearl has no subtitle or note: just the kind")
end)
