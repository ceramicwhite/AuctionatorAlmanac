local ADDON, A = ...

-- Visual constants and tiny helpers. The look is built from solid colour
-- textures and the stock game fonts, so it does not depend on any art asset
-- that might be missing on a given client.
A.UI = A.UI or {}
local Theme = {}
A.UI.Theme = Theme

Theme.color = {
  window   = { 0.055, 0.043, 0.027, 0.98 },
  panel    = { 0.085, 0.066, 0.040, 1 },
  panelAlt = { 0.105, 0.082, 0.049, 1 },
  header   = { 0.17, 0.125, 0.048, 1 },
  title    = { 0.20, 0.145, 0.05, 1 },
  input    = { 0.035, 0.028, 0.018, 1 },
  button   = { 0.20, 0.14, 0.05, 1 },
  buttonHover = { 0.30, 0.21, 0.07, 1 },
  buttonDisabled = { 0.11, 0.09, 0.06, 1 },
  active   = { 0.42, 0.12, 0.10, 1 },
  select   = { 0.26, 0.185, 0.06, 1 },
  hover    = { 0.15, 0.115, 0.05, 1 },
  zebra    = { 0.10, 0.078, 0.046, 1 },
  border   = { 0.42, 0.33, 0.125, 1 },
  borderDim = { 0.25, 0.195, 0.085, 1 },
  gold     = { 1, 0.82, 0, 1 },
  text     = { 0.85, 0.79, 0.64, 1 },
  bright   = { 0.95, 0.90, 0.75, 1 },
  dim      = { 0.55, 0.50, 0.38, 1 },
  track    = { 0.05, 0.04, 0.025, 1 },
  thumb    = { 0.45, 0.35, 0.14, 1 },
  good     = { 0.37, 0.83, 0.37, 1 },
  bad      = { 1, 0.42, 0.35, 1 },
  amber    = { 0.95, 0.70, 0.2, 1 },
  graphLine = { 1, 0.82, 0, 1 },
  graphBand = { 0.55, 0.43, 0.15, 0.45 },
  graphBars = { 0.30, 0.24, 0.10, 0.9 },
}

Theme.hex = {
  gold = "ffd100", text = "d8c9a3", bright = "f2e6bf", dim = "8c8061",
  good = "5fd35f", bad = "ff6a5a", amber = "f2b333",
}

local FONT = {
  normal = "GameFontHighlight",
  small = "GameFontHighlightSmall",
  dim = "GameFontHighlightSmall",
  gold = "GameFontNormal",
  goldSmall = "GameFontNormalSmall",
  title = "GameFontNormalLarge",
}

function Theme.SetColor(texture, c)
  texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

function Theme.Fill(frame, c, layer)
  local t = frame:CreateTexture(nil, layer or "BACKGROUND")
  t:SetAllPoints(frame)
  Theme.SetColor(t, c)
  return t
end

-- Four edge textures; returns them so a caller can recolour the border later.
function Theme.Border(frame, c, size)
  size = size or 1
  local top = frame:CreateTexture(nil, "BORDER")
  top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  top:SetHeight(size)
  local bottom = frame:CreateTexture(nil, "BORDER")
  bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  bottom:SetHeight(size)
  local left = frame:CreateTexture(nil, "BORDER")
  left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  left:SetWidth(size)
  local right = frame:CreateTexture(nil, "BORDER")
  right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  right:SetWidth(size)
  local edges = { top = top, bottom = bottom, left = left, right = right }
  for _, e in pairs(edges) do Theme.SetColor(e, c) end
  function edges.SetColor(self, color)
    for _, e in pairs(self) do
      if type(e) == "table" then Theme.SetColor(e, color) end
    end
  end
  return edges
end

-- style: normal | small | dim | gold | goldSmall | title
function Theme.Text(parent, style, justify, layer)
  style = style or "normal"
  local fs = parent:CreateFontString(nil, layer or "OVERLAY", FONT[style] or FONT.normal)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  if style == "dim" then
    local c = Theme.color.dim
    fs:SetTextColor(c[1], c[2], c[3], c[4])
  elseif style == "normal" or style == "small" then
    local c = Theme.color.text
    fs:SetTextColor(c[1], c[2], c[3], c[4])
  end
  return fs
end

function Theme.Colorize(text, hex)
  return "|cff" .. hex .. tostring(text) .. "|r"
end
