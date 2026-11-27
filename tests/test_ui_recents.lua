local H = require("harness")
local Stub = require("ui_stub")
local Boot = require("boot_ui")
local test = H.test

local function plain(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  return s
end

-- A keystroke: the client changes the text and reports it as typed. (Setting the text from code, which the stub reports as not
-- typed, is what the program does; this is what the player does.)
local function type_(win, text)
  local edit = win.searchBox.edit
  edit.__text = text
  Stub.fire(edit, "OnTextChanged", true)
end

local function settle(env)
  env.C_Timer.flush()
  Stub.settle(env)
end

local function shown(win)
  local out = {}
  for _, row in ipairs(win.searchesList.rows) do
    if row:IsShown() then out[#out + 1] = plain(row.label:GetText()) end
  end
  return out
end

local function names(win, n)
  local out = {}
  for i = 1, n do
    local row = win.resultsTable.list.rows[i]
    out[i] = row:IsShown() and plain(row.cells[1].name:GetText()) or nil
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Autofill
-- ---------------------------------------------------------------------------
test("typing completes from a remembered search, highlighting what was added", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  local edit = win.searchBox.edit
  edit:SetFocus()
  type_(win, "th")
  H.eq(edit:GetText(), "thorium bar")
  H.eq(edit.__highlight, { 2, 11 }, "the part that was not typed is selected")
  H.eq(edit:GetCursorPosition(), 2, "the cursor stays after what was typed")
  H.falsy(win.searchBox.hint:IsShown())
end)

test("the list follows what was typed, not the completion, until the completion is accepted", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  win.searchBox.edit:SetFocus()
  type_(win, "th")
  settle(env)
  H.eq(A.Controller.state.text, "th")
  H.eq(names(win, 4), { "Thorium Bar", "Thorium Ore", "Thunderfury" }, "everything that starts like what was typed")
  Stub.fire(win.searchBox.edit, "OnEnterPressed")
  settle(env)
  H.eq(win.searchBox.edit:GetText(), "thorium bar")
  H.eq(A.Controller.state.text, "thorium bar")
  H.eq(names(win, 2), { "Thorium Bar" })
end)

test("Enter accepts the completion, leaves the box, and remembers the search", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  A.Recents.Add("arcane crystal")
  local win = Boot.open(A, env)
  local edit = win.searchBox.edit
  edit:SetFocus()
  type_(win, "th")
  Stub.fire(edit, "OnEnterPressed")
  H.falsy(edit:HasFocus())
  H.eq(A.Recents.List(), { "thorium bar", "arcane crystal" }, "the completed search is now the newest")
end)

test("Enter remembers a search that was typed in full, once", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  local edit = win.searchBox.edit
  edit:SetFocus()
  type_(win, "mongoose")
  H.eq(edit:GetText(), "mongoose", "nothing to complete")
  H.eq(A.Recents.List(), {}, "not remembered while typing")
  Stub.fire(edit, "OnEnterPressed")
  H.eq(A.Recents.List(), { "mongoose" })
end)

test("Escape drops the completion, keeps what was typed, and remembers nothing", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  local edit = win.searchBox.edit
  edit:SetFocus()
  type_(win, "th")
  Stub.fire(edit, "OnEscapePressed")
  settle(env)
  H.eq(edit:GetText(), "th")
  H.eq(A.Controller.state.text, "th")
  H.falsy(edit:HasFocus())
  H.eq(A.Recents.List(), { "thorium bar" }, "a half-typed word is not a search")
end)

test("leaving the box with a completion showing accepts it, so the box and the list agree", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  local edit = win.searchBox.edit
  edit:SetFocus()
  type_(win, "th")
  edit:ClearFocus()
  settle(env)
  H.eq(edit:GetText(), "thorium bar")
  H.eq(A.Controller.state.text, "thorium bar")
  H.eq(names(win, 2), { "Thorium Bar" })
end)

test("closing the window while a completion shows accepts it", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  win.searchBox.edit:SetFocus()
  type_(win, "th")
  win:Hide()                         -- hiding the window takes the keyboard from the box
  H.eq(A.Controller.state.text, "thorium bar")
  H.eq(win.searchBox.edit:GetText(), "thorium bar")
end)

test("deleting never brings the completion back, and typing on goes past it", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  local edit = win.searchBox.edit
  edit:SetFocus()
  type_(win, "th")
  H.eq(edit:GetText(), "thorium bar")
  type_(win, "th")                   -- Backspace removed the selected completion: the text is what was typed again
  H.eq(edit:GetText(), "th", "no completion when the text did not grow")
  type_(win, "tho")
  H.eq(edit:GetText(), "thorium bar", "typing another letter completes again")
  type_(win, "thx")                  -- the next letter was not the one the completion expected
  H.eq(edit:GetText(), "thx")
  H.eq(A.Controller.state.text, "thx")
end)

test("nothing is completed when the text is set by the program, or cleared", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  win.searchBox:SetText("th")
  H.eq(win.searchBox.edit:GetText(), "th")
  win.searchBox.edit:SetFocus()
  type_(win, "")
  H.eq(win.searchBox.edit:GetText(), "")
  type_(win, "t")                    -- the first letter after clearing completes, as it does in Auctionator
  H.eq(win.searchBox.edit:GetText(), "thorium bar")
end)

test("the clear button empties the box even with a completion showing", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  win.searchBox.edit:SetFocus()
  type_(win, "th")
  win.searchBox.clear:Click()
  settle(env)
  H.eq(win.searchBox.edit:GetText(), "")
  H.eq(A.Controller.state.text, "")
  H.eq(#A.Controller.results, 5)
end)

test("searches made in Auctionator complete too, once the box has the keyboard", function()
  local A, env = Boot.boot({ fixture = { AUCTIONATOR_RECENT_SEARCHES = { '"Black Lotus"', "arcane crystal;;;;3" } } })
  local win = Boot.open(A, env)
  win.searchBox.edit:SetFocus()
  type_(win, "bl")
  H.eq(win.searchBox.edit:GetText(), "Black Lotus")
  type_(win, "")
  type_(win, "arc")
  H.eq(win.searchBox.edit:GetText(), "arcane crystal")
end)

test("a term from an Auctionator shopping list completes when no search matches", function()
  local A, env = Boot.boot()          -- the fixture's shopping list has "Thorium Bar" and "Arcane Crystal"
  local win = Boot.open(A, env)
  win.searchBox.edit:SetFocus()
  type_(win, "arc")
  H.eq(win.searchBox.edit:GetText(), "Arcane Crystal")
end)

test("a search made in Auctionator while the window was closed is there when it opens", function()
  local A, env = Boot.boot({ fixture = { AUCTIONATOR_RECENT_SEARCHES = { "elixir" } } })
  local win = Boot.open(A, env)
  H.eq(A.Recents.List(), { "elixir" })
  win:Hide()
  table.insert(env.AUCTIONATOR_RECENT_SEARCHES, 1, "mongoose")       -- Auctionator puts a new search at the front
  win:Show()
  H.eq(A.Recents.List(), { "mongoose", "elixir" })
end)

-- ---------------------------------------------------------------------------
-- Remembering searches
-- ---------------------------------------------------------------------------
test("opening a result remembers the search that found it", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  win.searchBox.edit:SetFocus()
  type_(win, "eagle")
  settle(env)
  H.eq(win.searchBox.edit:GetText(), "eagle", "nothing to complete")
  Stub.fire(win.resultsTable.list.rows[1], "OnClick", "LeftButton")
  H.eq(A.Recents.List(), { "eagle" })
  H.eq(A.Controller.state.selected, 15001)
end)

test("opening a result while the box still offers a completion takes the completion first, so what is remembered is what is shown", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  A.Recents.Add("thunderfury")
  local win = Boot.open(A, env)
  win.searchBox.edit:SetFocus()
  type_(win, "thu")
  H.eq(win.searchBox.edit:GetText(), "thunderfury")
  settle(env)
  Stub.fire(win.resultsTable.list.rows[1], "OnClick", "LeftButton")   -- clicking does not take the keyboard from the box
  H.truthy(win.searchBox.edit:HasFocus())
  H.eq(A.Recents.List(), { "thunderfury", "thorium bar" }, "the whole search, not the three letters")
  H.eq(A.Controller.state.text, "thunderfury")
  H.eq(win.searchBox.edit.__highlight, { 0, 0 }, "nothing is left highlighted")
  H.eq(win.searchBox.edit:GetCursorPosition(), #"thunderfury")
  Stub.fire(win.searchBox.edit, "OnEscapePressed")
  H.eq(win.searchBox.edit:GetText(), "thunderfury", "Escape now has no completion to drop")
end)

test("opening a result with nothing searched, or linking one in chat, remembers nothing", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  Stub.fire(win.resultsTable.list.rows[1], "OnClick", "LeftButton")
  H.eq(A.Recents.List(), {})
  win.searchBox.edit:SetFocus()
  type_(win, "thor")
  settle(env)
  Stub.fire(win.resultsTable.list.rows[1], "OnClick", "RightButton")
  H.eq(A.Recents.List(), {})
end)

test("/almanac search remembers its search", function()
  local A, env = Boot.boot()
  A.Slash.Handle("search thorium bar")
  H.eq(A.Recents.List(), { "thorium bar" })
  H.eq(A.Controller.state.text, "thorium bar")
  A.Slash.Handle("search")
  H.eq(A.Recents.List(), { "thorium bar" }, "an empty search is not kept")
end)

test("the history is kept in the saved database", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  win.searchBox.edit:SetFocus()
  type_(win, "mongoose")
  Stub.fire(win.searchBox.edit, "OnEnterPressed")
  H.eq(#A.db.recents.entries, 1)
  H.eq(A.db.recents.entries[1].text, "mongoose")
  local again = Boot.boot({ saved = A.db })
  H.eq(again.Recents.List(), { "mongoose" })
end)

-- ---------------------------------------------------------------------------
-- The Recent menu
-- ---------------------------------------------------------------------------
test("the Recent button lists the newest searches from here and from Auctionator", function()
  local A, env = Boot.boot({ fixture = { AUCTIONATOR_RECENT_SEARCHES = { "lotus", "runecloth" } } })
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)        -- opening brings in Auctionator's
  H.falsy(win.searchesList:IsOpen())
  win.searchesButton:Click()
  H.truthy(win.searchesList:IsOpen())
  H.eq(shown(win), { "lotus", "runecloth", "thorium bar" }, "Auctionator's two came in after the one made here")
end)

test("the Recent menu shows at most twelve searches, newest first", function()
  local A, env = Boot.boot()
  for i = 1, 20 do A.Recents.Add("search " .. i) end
  local win = Boot.open(A, env)
  win.searchesButton:Click()
  local rows = shown(win)
  H.eq(#rows, 12)
  H.eq(rows[1], "search 20")
  H.eq(rows[12], "search 9")
end)

test("the Recent menu says so when there is nothing to show", function()
  local A, env = Boot.boot()
  local win = Boot.open(A, env)
  win.searchesButton:Click()
  H.truthy(win.searchesList:IsOpen())
  H.eq(shown(win), {})
  H.truthy(win.searchesList.emptyText:IsShown())
  H.eq(win.searchesList.emptyText:GetText(), "No searches yet.")
end)

test("choosing a search from the menu runs it, remembers it as the newest, and closes the menu", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  A.Recents.Add("arcane crystal")
  local win = Boot.open(A, env)
  win.searchesButton:Click()
  H.eq(shown(win), { "arcane crystal", "thorium bar" })
  Stub.fire(win.searchesList.rows[2], "OnClick", "LeftButton")
  settle(env)
  H.falsy(win.searchesList:IsOpen())
  H.eq(win.searchBox.edit:GetText(), "thorium bar")
  H.eq(A.Controller.state.text, "thorium bar")
  H.eq(names(win, 2), { "Thorium Bar" })
  H.eq(A.Recents.List(), { "thorium bar", "arcane crystal" })
end)

test("a search picked from the menu is not completed to a longer one", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium")
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  win.searchesButton:Click()
  Stub.fire(win.searchesList.rows[2], "OnClick", "LeftButton")
  H.eq(win.searchBox.edit:GetText(), "thorium", "no completion on a search picked from the menu")
end)

test("clicking anywhere else, Escape, or closing the window shuts the menu", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  local list = win.searchesList
  win.searchesButton:Click()
  Stub.fire(list.catcher, "OnMouseDown", "LeftButton")
  H.falsy(list:IsOpen(), "a click elsewhere")
  win.searchesButton:Click()
  Stub.fire(list.catcher, "OnKeyDown", "ESCAPE")
  H.falsy(list:IsOpen(), "Escape")
  win.searchesButton:Click()
  Stub.fire(list.catcher, "OnKeyDown", "A")
  H.truthy(list:IsOpen(), "other keys do not close it")
  win:Hide()
  H.falsy(list:IsOpen(), "closing the window")
  H.eq(A.Controller.state.text, "", "nothing was chosen")
end)

test("the menu sits under the search box, as wide as it, and inside the window's layout", function()
  local A, env = Boot.boot()
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  win.searchesButton:Click()
  local frame = win.searchesList.frame
  H.eq(frame:GetWidth(), win.searchBox:GetWidth())
  H.truthy(Stub.within(win.searchesButton, win.searchBox), "the button is inside the box")
  H.falsy(Stub.overlaps(win.searchesButton, win.searchBox.clear), "and clear of its clear button")
  H.eq(win.searchesList.catcher:GetFrameStrata(), "FULLSCREEN_DIALOG")
end)

-- ---------------------------------------------------------------------------
-- Erasing
-- ---------------------------------------------------------------------------
test("the options dialog erases the search history, after asking", function()
  local A, env = Boot.boot({ fixture = { AUCTIONATOR_RECENT_SEARCHES = { "lotus" } } })
  A.Recents.Add("thorium bar")
  A.Recents.Sync()
  A.UI.Settings.Toggle()
  local b = A.UI.Settings.resetButtons.searches
  H.truthy(b, "there is a button for it")
  b:Click()
  local dlg = A.UI.Widgets.confirmFrame
  local text = plain(dlg.message:GetText()):lower()
  H.truthy(text:find("the 2 searches almanac", 1, true), text)
  H.truthy(text:find("auctionator's own", 1, true), "it says Auctionator's list is untouched")
  H.truthy(text:find("cannot be undone", 1, true))
  dlg.cancelButton:Click()
  H.eq(A.Recents.Count(), 2, "cancel keeps them")
  b:Click()
  A.UI.Widgets.confirmFrame.confirmButton:Click()
  H.eq(A.Recents.List(), {})
  H.eq(env.AUCTIONATOR_RECENT_SEARCHES, { "lotus" }, "Auctionator's list is not touched")
  local win = Boot.open(A, env)
  H.eq(A.Recents.List(), {}, "opening the window does not bring the old Auctionator search back")
  H.truthy(win)
end)

test("/almanac reset searches asks to be confirmed, then erases", function()
  local out = {}
  local A = Boot.boot({ env = { print = function(m) out[#out + 1] = plain(tostring(m)) end } })
  A.Recents.Add("thorium bar")
  A.Slash.Handle("reset searches")
  H.eq(A.Recents.Count(), 1)
  H.truthy(out[#out]:find("reset searches confirm", 1, true), out[#out])
  A.Slash.Handle("reset searches confirm")
  H.eq(A.Recents.Count(), 0)
  H.truthy(out[#out]:find("Erased", 1, true), out[#out])
end)

test("erasing the search history leaves everything else alone", function()
  local A, env = Boot.boot()
  A.History.Watch(5, true)
  A.Recents.Add("thorium bar")
  A.Main.Reset("searches")
  H.eq(A.Recents.Count(), 0)
  H.truthy(A.History.IsWatched(5))
  H.truthy(A.db.items[12359], "the item cache stays")
end)

-- ---------------------------------------------------------------------------
-- The menu and the keyboard
-- ---------------------------------------------------------------------------
test("the menu lets keys through to the game and only Escape is kept back, and never changes that in combat", function()
  local inCombat = false
  local A, env = Boot.boot({ env = { InCombatLockdown = function() return inCombat end } })
  A.Recents.Add("thorium bar")
  local win = Boot.open(A, env)
  local catcher = win.searchesList.catcher
  H.eq(catcher.__propagate, true, "keys pass through from the start")
  win.searchesButton:Click()
  Stub.fire(catcher, "OnKeyDown", "W")
  Stub.fire(catcher, "OnKeyDown", "A")
  H.eq(catcher.__propagate, true, "ordinary keys change nothing")
  H.truthy(win.searchesList:IsOpen())
  Stub.fire(catcher, "OnKeyDown", "ESCAPE")
  H.falsy(win.searchesList:IsOpen())
  H.eq(catcher.__propagate, false, "Escape stops here, so it does not also close the window")
  win.searchesButton:Click()
  H.eq(catcher.__propagate, true, "and keys pass again the next time it opens")

  inCombat = true
  Stub.fire(catcher, "OnKeyDown", "ESCAPE")
  H.falsy(win.searchesList:IsOpen(), "Escape still closes it in combat")
  win.searchesButton:Click()
  Stub.fire(catcher, "OnKeyDown", "ESCAPE")
  H.falsy(win.searchesList:IsOpen())
  H.eq(catcher.__propagate, true, "nothing about keys is changed in combat")
end)
