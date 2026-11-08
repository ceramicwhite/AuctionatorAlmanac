local ADDON, A = ...

-- "My Activity" tab: what you posted, sold, bought, and had expire or cancelled
-- for this item, newest first, with totals.
local Theme = A.UI.Theme
local Table = A.UI.Table
local Fmt = A.Format
local TabActivity = {}
A.UI.TabActivity = TabActivity

local ROW_HEIGHT = 20

local EVENT = {
  sold = { "Sold", Theme.hex.good },
  bought = { "Bought", "4db8ff" },
  posted = { "Posted", Theme.hex.gold },
  expired = { "Expired", Theme.hex.dim },
  cancelled = { "Cancelled", Theme.hex.dim },
}

local EMPTY = "Nothing recorded for this item yet. Almanac records your sales and purchases from Auction House "
  .. "mail and purchases from now on; earlier ones cannot be recovered. Posted auctions come from Auctionator."

function TabActivity.SummaryText(entries)
  local s = A.Ledger.Summary(entries)
  local lines, first = {}, {}
  if s.sold.n > 0 then
    first[#first + 1] = Theme.Colorize("Sold " .. Fmt.Count(s.sold.qty), Theme.hex.good) .. " for " .. Fmt.Money(s.sold.gross, { short = true })
  end
  if s.bought.n > 0 then
    first[#first + 1] = Theme.Colorize("Bought " .. Fmt.Count(s.bought.qty), "4db8ff") .. " for " .. Fmt.Money(s.bought.spent, { short = true })
  end
  if s.posted.n > 0 then
    first[#first + 1] = "Posted " .. s.posted.n .. "x"
  end
  lines[1] = #first > 0 and table.concat(first, "   ·   ") or "No sales or purchases yet"
  if s.sold.n > 0 or s.bought.n > 0 then
    local net = s.net
    local color = net >= 0 and Theme.hex.good or Theme.hex.bad
    local text = "Net " .. Theme.Colorize((net >= 0 and "+" or "") .. Fmt.Money(net, { short = true, plain = true }), color)
    if s.sold.fees > 0 then text = text .. "  after " .. Fmt.Money(s.sold.fees, { short = true }) .. " in fees" end
    if s.sold.avg then text = text .. "   ·   avg sale " .. Fmt.Money(math.floor(s.sold.avg), { short = true }) end
    lines[2] = text
  end
  return table.concat(lines, "\n")
end

local function showTooltip(row, e)
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  local def = EVENT[e.kind] or { e.kind, Theme.hex.text }
  GameTooltip:AddLine(def[1] .. " " .. (e.qty or 1) .. " " .. A.Items.Name(e.itemID or 0), 1, 0.82, 0)
  GameTooltip:AddDoubleLine("When", Fmt.DateTime(e.time), 0.8, 0.8, 0.8, 1, 1, 1)
  if e.party then GameTooltip:AddDoubleLine(e.kind == "sold" and "Buyer" or "Seller", e.party, 0.8, 0.8, 0.8, 1, 1, 1) end
  if e.unit then GameTooltip:AddDoubleLine("Each", Fmt.Money(e.unit), 0.8, 0.8, 0.8, 1, 1, 1) end
  if e.total then GameTooltip:AddDoubleLine("Total", Fmt.Money(e.total), 0.8, 0.8, 0.8, 1, 1, 1) end
  if e.fee then GameTooltip:AddDoubleLine("Auction House cut", Fmt.Money(e.fee), 0.8, 0.8, 0.8, 1, 1, 1) end
  if e.deposit then GameTooltip:AddDoubleLine("Deposit", Fmt.Money(e.deposit), 0.8, 0.8, 0.8, 1, 1, 1) end
  if e.char then GameTooltip:AddDoubleLine("Character", e.char .. (e.realm and ("-" .. e.realm) or ""), 0.8, 0.8, 0.8, 1, 1, 1) end
  if e.source == "auctionator" then GameTooltip:AddLine("From Auctionator's posting history", 0.6, 0.6, 0.6) end
  if e.approx then GameTooltip:AddLine("Approximate: the invoice was not available", 0.95, 0.7, 0.2) end
  if e.source == "ah" and not e.confirmed then GameTooltip:AddLine("Not yet confirmed by an invoice mail", 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end

function TabActivity.Build(parent)
  local view = CreateFrame("Frame", nil, parent)
  view:SetAllPoints(parent)

  view.summary = Theme.Text(view, "normal", "LEFT")
  view.summary:SetWordWrap(true)
  view.summary:SetHeight(34)
  view.summary:SetPoint("TOPLEFT", view, "TOPLEFT", 4, -2)
  view.summary:SetPoint("TOPRIGHT", view, "TOPRIGHT", -4, -2)
  view.summary:SetJustifyV("TOP")

  view.table = Table.New(view, {
    columns = {
      Table.TextColumn("date", "Date", { flex = 1, sortable = false }, function(e) return Fmt.Date(e.time) end),
      Table.TextColumn("event", "Event", { width = 64, sortable = false }, function(e)
        local def = EVENT[e.kind] or { e.kind, Theme.hex.text }
        return Theme.Colorize(def[1], def[2])
      end),
      Table.TextColumn("qty", "Qty", { width = 38, align = "RIGHT", sortable = false }, function(e) return Fmt.Count(e.qty) end),
      Table.TextColumn("unit", "Each", { width = 82, align = "RIGHT", sortable = false }, function(e)
        return e.unit and Fmt.Money(e.unit, { short = true }) or "—"
      end),
      Table.TextColumn("total", "Total", { width = 88, align = "RIGHT", sortable = false }, function(e)
        if not e.total then return "—" end
        return (e.approx and "~" or "") .. Fmt.Money(e.total, { short = true })
      end),
    },
    rowHeight = ROW_HEIGHT,
    onEnter = showTooltip,
    onLeave = function() GameTooltip:Hide() end,
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

function TabActivity.Update(view, id)
  view.itemID = id
  local entries = A.Ledger.ForItem(id)
  view.summary:SetText(TabActivity.SummaryText(entries))
  view.table:SetData(entries)
  view.empty:SetShown(#entries == 0)
end
