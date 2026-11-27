local ADDON, A = ...

-- The searches the player has made, newest first, merged with the ones made in Auctionator (its Shopping tab and its item-link
-- search keep a list of their own, AUCTIONATOR_RECENT_SEARCHES). The merged list feeds the search box's autofill and its Recent
-- menu. Nothing is ever written into Auctionator's list; this only reads it.
--
-- Auctionator's list has an order but no times, so "newest" is a logical clock: every search, ours or one noticed in
-- Auctionator's list, takes the next number. Auctionator's newest entry is remembered (`head`), so each look only has to bring in
-- what is in front of it, oldest first, and the newest search ends up on top whichever addon it was made in.
local Recents = {}
A.Recents = Recents

Recents.MIN_LENGTH = 2        -- a single letter is not worth remembering, and would complete far too eagerly
Recents.MAX_LENGTH = 64       -- bytes: what the search box holds (it keeps 64 characters)
Recents.MAX_ENTRIES = 50

local state = { entries = {}, seq = 0, head = "" }

local function keyOf(text) return text:lower() end

-- ---------------------------------------------------------------------------
-- Saved state
-- ---------------------------------------------------------------------------
-- db.recents = { entries = { {text, seq}... }, seq = last number handed out, head = key of Auctionator's newest search last seen }
function Recents.Init(db)
  if type(db.recents) ~= "table" then db.recents = {} end
  local saved = db.recents
  if type(saved.entries) ~= "table" then saved.entries = {} end
  if type(saved.seq) ~= "number" then saved.seq = 0 end
  if type(saved.head) ~= "string" then saved.head = "" end
  state = saved
end

-- The text as it will be kept, or nil if it is not worth keeping: spaces trimmed and collapsed, nothing shorter than
-- MIN_LENGTH, and nothing with a "|" in it (a pasted link or colour code would show as raw escape text in the box).
function Recents.Normalize(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if #text < Recents.MIN_LENGTH or #text > Recents.MAX_LENGTH then return nil end
  if text:find("|", 1, true) then return nil end
  return text
end

local function valid(entry)
  return type(entry) == "table" and type(entry.text) == "string" and entry.text ~= ""
end

-- Puts a search in front of the rest, however it was spelled before.
local function touch(text)
  local key = keyOf(text)
  state.seq = state.seq + 1
  for _, entry in ipairs(state.entries) do
    if valid(entry) and keyOf(entry.text) == key then
      entry.text, entry.seq = text, state.seq
      return
    end
  end
  state.entries[#state.entries + 1] = { text = text, seq = state.seq }
end

-- Newest first, one per spelling-insensitive search; anything damaged in the saved file is skipped.
local function ordered()
  local out = {}
  for i, entry in ipairs(state.entries) do
    if valid(entry) then out[#out + 1] = { text = entry.text, seq = tonumber(entry.seq) or 0, index = i } end
  end
  table.sort(out, function(a, b)
    if a.seq ~= b.seq then return a.seq > b.seq end
    return a.index > b.index
  end)
  return out
end

-- Keeps the newest MAX_ENTRIES, oldest first in the file; entries damaged in the saved file go with the rest.
local function trim()
  local all = ordered()
  local keep = {}
  for i = math.min(#all, Recents.MAX_ENTRIES), 1, -1 do
    keep[#keep + 1] = { text = all[i].text, seq = all[i].seq }
  end
  state.entries = keep
end

-- ---------------------------------------------------------------------------
-- Using the list
-- ---------------------------------------------------------------------------
-- Remember a search. Returns true if it was kept.
function Recents.Add(text)
  local normal = Recents.Normalize(text)
  if not normal then return false end
  touch(normal)
  trim()
  return true
end

-- Auctionator's recent searches as plain text, newest first, one per search, without the ones that are not worth keeping.
local function fromAuctionator()
  local items, seen = {}, {}
  for _, raw in ipairs(A.Adapter.RecentSearches()) do
    local normal = Recents.Normalize(raw)
    if normal and not seen[keyOf(normal)] then
      seen[keyOf(normal)] = true
      items[#items + 1] = normal
    end
  end
  return items
end

-- Bring in what Auctionator has searched since the last look. Returns how many searches were new to us.
function Recents.Sync()
  local items = fromAuctionator()
  if #items == 0 then return 0 end

  -- everything in front of the search that was newest last time is new (or was searched again); with nothing remembered, all of it
  local fresh = #items
  if state.head ~= "" then
    for i, text in ipairs(items) do
      if keyOf(text) == state.head then fresh = i - 1; break end
    end
  end
  for i = fresh, 1, -1 do touch(items[i]) end
  state.head = keyOf(items[1])
  if fresh > 0 then trim() end
  return fresh
end

-- The merged list of searches, newest first.
function Recents.List()
  local out = {}
  for i, entry in ipairs(ordered()) do out[i] = entry.text end
  return out
end

function Recents.Count() return #ordered() end

-- What to complete `typed` to: the newest search that starts with it, else a term from one of the player's Auctionator shopping
-- lists, as Auctionator's own search box does. Only a longer text counts, and the player's own casing of the rest is kept.
function Recents.Suggest(typed)
  if type(typed) ~= "string" or typed == "" then return nil end
  local want = typed:lower()
  local function completes(text)
    return #text > #typed and text:lower():sub(1, #want) == want and not text:find("|", 1, true)
  end
  for _, entry in ipairs(ordered()) do
    if completes(entry.text) then return entry.text end
  end
  for _, term in ipairs(A.Adapter.ShoppingTerms()) do
    if completes(term) then return term end
  end
  return nil
end

-- Forget every search made here. Auctionator's own list is not touched, and what is in it now is not brought back in.
function Recents.Clear()
  state.entries, state.seq = {}, 0
  local newest = fromAuctionator()[1]
  state.head = newest and keyOf(newest) or ""
end
