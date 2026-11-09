local ADDON, A = ...

-- The Auction House side panel: All Items, then the category tree. A click
-- selects a category; clicking one that has subcategories also expands it (or
-- collapses it if it is already open). Empty categories are hidden.
local Theme = A.UI.Theme
local W = A.UI.Widgets
local VL = A.UI.VirtualList
local Fmt = A.Format
local C = Theme.color
local CategoryPanel = {}
A.UI.CategoryPanel = CategoryPanel

local ROW_HEIGHT = 20
local HEADER_HEIGHT = 24
local INDENT = 12

local entries = {}        -- node -> entry (stable tables so list selection compares by identity)
local ALL = { depth = 0, name = "All Items", all = true }
local expanded = {}

local function entryFor(node, depth)
  local e = entries[node]
  if not e then
    e = { node = node }
    entries[node] = e
  end
  e.depth, e.name = depth, node.name
  e.count = node.count
  e.hasChildren = #node.children > 0
  return e
end

local function collapse(node)
  expanded[node] = nil
  for _, child in ipairs(node.children) do collapse(child) end
end

-- The flat list of currently visible entries.
function CategoryPanel.Entries()
  ALL.count = #A.Controller.ids
  local out = { ALL }
  local function add(node, depth)
    if node.count == 0 then return end
    local e = entryFor(node, depth)
    out[#out + 1] = e
    if expanded[node] then
      for _, child in ipairs(node.children) do add(child, depth + 1) end
    end
  end
  for _, node in ipairs(A.Controller.CategoryTree()) do add(node, 0) end
  return out
end

function CategoryPanel.Click(entry)
  local Ct = A.Controller
  A.UI.Window.ExpandResults()
  if entry.all then
    expanded = {}
    Ct.SetCategory(nil)
  else
    local node = entry.node
    if entry.hasChildren then
      if expanded[node] then collapse(node) else expanded[node] = true end
    end
    Ct.SetCategory(node)
  end
  CategoryPanel.Rebuild()
end

function CategoryPanel.Rebuild()
  local list = CategoryPanel.list
  if not list then return end
  list:SetData(CategoryPanel.Entries())
  CategoryPanel.SyncSelection()
end

function CategoryPanel.SyncSelection()
  local list = CategoryPanel.list
  if not list then return end
  local node = A.Controller.state.category
  list:SetSelectedItem(node and entries[node] or ALL)
end

A.UI.Window.AddBuilder(function(win)
  local panel = win.catPanel
  local header = Theme.Text(panel, "goldSmall", "LEFT")
  header:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -6)
  header:SetText("Categories")

  local list = VL.New(panel, {
    rowHeight = ROW_HEIGHT,
    createRow = function(row)
      row.marker = Theme.Text(row, "small", "LEFT")
      row.label = Theme.Text(row, "normal", "LEFT")
      row.count = Theme.Text(row, "dim", "RIGHT")
      row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
      row.count:SetWidth(34)
    end,
    update = function(row, entry, _, selected)
      local x = 6 + entry.depth * INDENT
      row.marker:ClearAllPoints()
      row.marker:SetPoint("LEFT", row, "LEFT", x, 0)
      row.marker:SetText(entry.hasChildren and (expanded[entry.node] and "-" or "+") or "")
      row.label:ClearAllPoints()
      row.label:SetPoint("LEFT", row, "LEFT", x + 12, 0)
      row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
      row.label:SetText(entry.name)
      local color = selected and C.gold or (entry.depth == 0 and C.bright or C.text)
      row.label:SetTextColor(color[1], color[2], color[3], 1)
      row.count:SetText(entry.count and Fmt.Count(entry.count) or "")
    end,
    onClick = CategoryPanel.Click,
  })
  list.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -HEADER_HEIGHT)
  list.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)
  CategoryPanel.list = list
  win.catList = list

  A.Bus.On("DATA_UPDATED", CategoryPanel.Rebuild)
  A.Bus.On("WINDOW_SHOWN", CategoryPanel.Rebuild)
  A.Bus.On("RESULTS_UPDATED", CategoryPanel.SyncSelection)
  CategoryPanel.Rebuild()
end)
