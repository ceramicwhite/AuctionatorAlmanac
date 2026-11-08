local ADDON, A = ...

-- A small button on the minimap's edge: click to open, right-click for options,
-- drag to slide it around the rim.
local Button = {}
A.UI.Minimap = Button

local EDGE_GAP = 5
local ICON = "Interface\\Icons\\INV_Misc_Coin_02"

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

function Button.Place()
  local b = Button.button
  if not b then return end
  local angle = math.rad((A.db and A.db.minimap.angle) or 215)
  local radius = Minimap:GetWidth() / 2 + EDGE_GAP
  local x, y = math.cos(angle), math.sin(angle)
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  if shape == "ROUND" then
    x, y = x * radius, y * radius
  else
    -- square minimaps: follow the rim of the square instead of a circle
    local reach = radius * math.sqrt(2)
    x = math.max(-radius, math.min(radius, x * reach))
    y = math.max(-radius, math.min(radius, y * reach))
  end
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function Button.Refresh()
  if Button.button then Button.button:SetShown(A.Get("minimap") ~= false) end
end

local function onUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  cx, cy = cx / scale, cy / scale
  A.db.minimap.angle = math.deg(atan2(cy - my, cx - mx)) % 360
  Button.Place()
end

function Button.Create()
  if Button.button then return Button.button end
  local b = CreateFrame("Button", "AuctionatorAlmanacMinimapButton", Minimap)
  Button.button = b
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", b, "CENTER", 0, 1)
  icon:SetTexture(ICON)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  b:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then A.UI.Settings.Toggle() else A.UI.Window.Toggle() end
  end)
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onUpdate) end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Auctionator Almanac", 1, 0.82, 0)
    GameTooltip:AddLine("Left-click: open or close the window", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Right-click: options", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  A.Bus.On("SETTINGS_CHANGED", function(key)
    if key == "minimap" then Button.Refresh() end
  end)
  Button.Place()
  Button.Refresh()
  return b
end
