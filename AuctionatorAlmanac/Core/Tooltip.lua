local ADDON, A = ...

-- Adds the lowest known price and your ownership across characters to item
-- tooltips. Uses the modern tooltip data hook, never touches secret values, and
-- swallows its own errors so a tooltip can never break.
local Fmt = A.Format
local Tooltip = {}
A.Tooltip = Tooltip

local MAX_CHARACTERS = 5

-- { {left, right} } for an item id; empty when there is nothing to say.
function Tooltip.LinesFor(id)
  local lines = {}
  local Ct = A.Controller
  local s = Ct.Summary(id)
  if s then
    local when = ""
    if s.ageDays then when = s.ageDays <= 0 and "  (today)" or ("  (" .. s.ageDays .. "d ago)") end
    lines[#lines + 1] = { left = "Almanac · lowest price", right = Fmt.Money(s.last) .. when }
  end

  local owned = A.Inventory.Owned(id)
  if owned.total > 0 then
    local order, perChar = {}, {}
    for _, row in ipairs(owned.rows) do
      if not row.shared then
        local key = row.charKey or "warband"
        if not perChar[key] then
          perChar[key] = { name = row.name or "Warband", count = 0 }
          order[#order + 1] = key
        end
        perChar[key].count = perChar[key].count + row.count
      end
    end
    local parts = {}
    for i = 1, math.min(#order, MAX_CHARACTERS) do
      local c = perChar[order[i]]
      parts[#parts + 1] = c.name .. " " .. Fmt.Count(c.count)
    end
    if #order > MAX_CHARACTERS then parts[#parts + 1] = "+" .. (#order - MAX_CHARACTERS) .. " more" end
    lines[#lines + 1] = { left = "Almanac · you own " .. Fmt.Count(owned.total), right = nil }
    lines[#lines + 1] = { left = table.concat(parts, " · "), right = nil, dim = true }
  end
  return lines
end

function Tooltip.Decorate(tooltip, data)
  if not A.Get("tooltips") then return end
  if type(data) ~= "table" then return end
  local id = data.id
  if issecretvalue and issecretvalue(id) then return end
  if type(id) ~= "number" then return end
  for _, line in ipairs(Tooltip.LinesFor(id)) do
    if line.right then
      tooltip:AddDoubleLine(line.left, line.right, 1, 0.82, 0, 1, 1, 1)
    elseif line.dim then
      tooltip:AddLine(line.left, 0.7, 0.7, 0.7)
    else
      tooltip:AddLine(line.left, 1, 0.82, 0)
    end
  end
end

-- Returns true when the hook was installed.
function Tooltip.Install()
  local processor = TooltipDataProcessor
  local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
  if not (processor and processor.AddTooltipPostCall and itemType) then return false end
  processor.AddTooltipPostCall(itemType, function(tooltip, data)
    pcall(Tooltip.Decorate, tooltip, data)
  end)
  return true
end
