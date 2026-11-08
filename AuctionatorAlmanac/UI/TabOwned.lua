local ADDON, A = ...

-- "Where I Own It" tab: every character and location holding the item, when each
-- snapshot was taken, and the total with its value at the current lowest price.
local Theme = A.UI.Theme
local Table = A.UI.Table
local Fmt = A.Format
local TabOwned = {}
A.UI.TabOwned = TabOwned

local ROW_HEIGHT = 20
local STALE_AFTER = 7 * 86400

local WHERE = {
  bags = "Bags", equipped = "Equipped", bank = "Bank", mail = "Mail", auctions = "Auctions",
  warband = "Warband", guildbank = "Guild bank", reagents = "Reagents",
}

local EMPTY = "None tracked yet. Almanac learns what each character owns as you log in and open the bank or mailbox."

local function nowSeconds() return (time and time()) or 0 end

-- Realm names only matter once characters on more than one realm are tracked.
local function multipleRealms()
  local first
  for _, rec in pairs(A.db.chars) do
    if first and rec.realm ~= first then return true end
    first = rec.realm
  end
  return false
end

local function whoText(row)
  if row.loc == "warband" then return "Warband bank" end
  if row.loc == "guildbank" then return "<" .. (row.guild or "Guild") .. ">" end
  local name = row.name
  if row.realm and multipleRealms() then name = name .. "-" .. row.realm end
  local rec = A.db and A.db.chars[row.charKey]
  local color = rec and rec.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[rec.class]
  if color and color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
  return name
end

local function updatedText(row)
  if not row.stamp or row.stamp == 0 then return "—" end
  local age = nowSeconds() - row.stamp
  local text = Fmt.Ago(age) .. " ago"
  if age >= STALE_AFTER then return Theme.Colorize(text, Theme.hex.amber) end
  return text
end

function TabOwned.SummaryText(id)
  local owned = A.Inventory.Owned(id)
  local text = "You own " .. Theme.Colorize(Fmt.Count(owned.total), Theme.hex.bright)
  local price = A.Controller.PriceOf(id)
  if owned.total > 0 and price then
    text = text .. "   ·   worth " .. Fmt.Money(owned.total * price) .. " at the lowest price"
  elseif owned.total > 0 then
    text = text .. "   ·   no auction price yet"
  end
  return text
end

function TabOwned.Build(parent)
  local view = CreateFrame("Frame", nil, parent)
  view:SetAllPoints(parent)

  view.summary = Theme.Text(view, "normal", "LEFT")
  view.summary:SetWordWrap(true)
  view.summary:SetHeight(34)
  view.summary:SetJustifyV("TOP")
  view.summary:SetPoint("TOPLEFT", view, "TOPLEFT", 4, -2)
  view.summary:SetPoint("TOPRIGHT", view, "TOPRIGHT", -4, -2)

  view.table = Table.New(view, {
    columns = {
      Table.TextColumn("who", "Character", { flex = 1, sortable = false }, whoText),
      Table.TextColumn("where", "Where", { width = 78, sortable = false }, function(row) return WHERE[row.loc] or row.loc end),
      Table.TextColumn("count", "Count", { width = 46, align = "RIGHT", sortable = false }, function(row) return Fmt.Count(row.count) end),
      Table.TextColumn("updated", "Updated", { width = 84, align = "RIGHT", sortable = false }, updatedText),
    },
    rowHeight = ROW_HEIGHT,
  })
  view.table.frame:SetPoint("TOPLEFT", view.summary, "BOTTOMLEFT", -4, -4)
  view.table.frame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)

  view.empty = Theme.Text(view, "dim", "CENTER")
  view.empty:SetWordWrap(true)
  view.empty:SetPoint("LEFT", view.table.frame, "LEFT", 20, 0)
  view.empty:SetPoint("RIGHT", view.table.frame, "RIGHT", -30, 0)
  view.empty:SetPoint("TOP", view.table.frame, "TOP", 0, -50)
  view.empty:SetText(EMPTY)
  view.empty:Hide()
  return view
end

function TabOwned.Update(view, id)
  view.itemID = id
  local owned = A.Inventory.Owned(id)
  view.summary:SetText(TabOwned.SummaryText(id))
  view.table:SetData(owned.rows)
  view.empty:SetShown(#owned.rows == 0)
end
