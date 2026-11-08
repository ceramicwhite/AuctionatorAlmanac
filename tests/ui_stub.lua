-- A fake WoW widget environment for headless UI tests.
--
-- * Only real WoW widget methods exist. Calling anything else is a nil-call error,
--   so a mistyped API name fails a test instead of failing in game.
-- * A small anchor resolver computes real rectangles, so resizing behavior can be
--   asserted (sizes, overlaps, containment).
-- * Scripts are stored and can be fired the way the client would.
local Stub = {}

local ANCHOR = {
  TOPLEFT = { 0, 0 }, TOP = { 0.5, 0 }, TOPRIGHT = { 1, 0 },
  LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 1 }, BOTTOM = { 0.5, 1 }, BOTTOMRIGHT = { 1, 1 },
}

local M = {}                                  -- implemented methods
local NOOP = {}                               -- real methods that do nothing observable here
for name in ([[
  SetFrameStrata SetFrameLevel SetToplevel EnableMouse EnableMouseWheel SetMovable SetResizable
  SetMinResize SetMaxResize SetClampedToScreen SetUserPlaced StartSizing
  RegisterForDrag SetScale SetClipsChildren SetID SetHitRectInsets EnableKeyboard
  SetPropagateKeyboardInput SetAlpha SetTexture SetColorTexture SetTexCoord SetVertexColor SetBlendMode
  SetDrawLayer SetRotation SetDesaturated SetAtlas SetTextColor SetFontObject SetFont SetJustifyH
  SetJustifyV SetWordWrap SetNonSpaceWrap SetMaxLines SetShadowColor SetShadowOffset SetSpacing
  SetNormalTexture SetPushedTexture SetHighlightTexture SetDisabledTexture RegisterForClicks
  LockHighlight UnlockHighlight SetAutoFocus SetMultiLine SetMaxLetters SetFocus ClearFocus
  SetTextInsets HighlightText SetNumeric SetCursorPosition SetOrientation SetValueStep SetObeyStepOnDrag
  SetThumbTexture SetOwner AddLine AddDoubleLine ClearLines SetHyperlink SetItemByID SetStartPoint
  SetEndPoint SetThickness RegisterEvent UnregisterEvent UnregisterAllEvents SetFixedFrameStrata
  SetPropagateMouseClicks SetPropagateMouseMotion SetIgnoreParentAlpha SetBackdrop SetBackdropColor
  SetBackdropBorderColor SetFrameStrata SetAllowLooseEmbed SetStatusBarTexture SetStatusBarColor
  SetHighlightFontObject SetNormalFontObject SetDisabledFontObject Raise Lower SetSnapToPixelGrid
  SetTexelSnappingBias SetScrollChild UpdateScrollChildRect SetHorizontalScroll SetMask
]]):gmatch("%S+") do NOOP[name] = true end

local function newObject(kind, name, parent, env)
  local o = {
    __kind = kind, __name = name, __parent = parent, __env = env,
    __points = {}, __children = {}, __regions = {}, __scripts = {}, __hooks = {},
    __shown = true, __text = "", __value = 0, __min = 0, __max = 1, __checked = false, __enabled = true,
    __alpha = 1, __level = 1, __lastSize = nil, __events = {},
  }
  return setmetatable(o, Stub.mt)
end

Stub.mt = { __index = function(t, k)
  local m = M[k]
  if m then return m end
  if NOOP[k] then return function() end end
  return nil
end }

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
local rect
local generation = 0      -- bumped by anything that can change a rectangle
local function bump() generation = generation + 1 end

local function resolveAnchors(f)
  local xs, ys = {}, {}
  for _, p in ipairs(f.__points) do
    local rel = p.rel or f.__parent
    local rl, rt, rw, rh = rect(rel)
    local relFrac = ANCHOR[p.relPoint] or ANCHOR.TOPLEFT
    local frac = ANCHOR[p.point] or ANCHOR.TOPLEFT
    xs[frac[1]] = rl + relFrac[1] * rw + p.x
    ys[frac[2]] = rt + relFrac[2] * rh - p.y
  end
  return xs, ys
end

local compute
rect = function(f)
  if f.__root then return 0, 0, f.__w, f.__h end
  local cache = f.__rectCache
  if cache and cache.gen == generation then return cache[1], cache[2], cache[3], cache[4] end
  local l, t, w, h = compute(f)
  f.__rectCache = { l, t, w, h, gen = generation }
  return l, t, w, h
end

compute = function(f)
  local pl, pt = rect(f.__parent)
  local w, h = f.__w, f.__h
  if f.__kind == "FontString" then
    w = w or (#f.__text * 6)
    h = h or 12
  end
  local xs, ys = resolveAnchors(f)
  local left, top
  if xs[0] and xs[1] then left, w = xs[0], xs[1] - xs[0]
  elseif xs[0] then left = xs[0]
  elseif xs[1] then left = xs[1] - (w or 0)
  elseif xs[0.5] then left = xs[0.5] - (w or 0) / 2
  else left = pl end
  if ys[0] and ys[1] then top, h = ys[0], ys[1] - ys[0]
  elseif ys[0] then top = ys[0]
  elseif ys[1] then top = ys[1] - (h or 0)
  elseif ys[0.5] then top = ys[0.5] - (h or 0) / 2
  else top = pt end
  return left, top, w or 0, h or 0
end
Stub.rect = rect

-- ---------------------------------------------------------------------------
-- Methods
-- ---------------------------------------------------------------------------
local function addChild(parent, child, list)
  if parent then parent[list][#parent[list] + 1] = child end
end

function M.CreateTexture(self, name) local o = newObject("Texture", name, self, self.__env); addChild(self, o, "__regions"); self.__env.__all[#self.__env.__all + 1] = o; return o end
function M.CreateFontString(self, name) local o = newObject("FontString", name, self, self.__env); addChild(self, o, "__regions"); self.__env.__all[#self.__env.__all + 1] = o; return o end
function M.CreateLine(self, name) local o = newObject("Line", name, self, self.__env); addChild(self, o, "__regions"); self.__env.__all[#self.__env.__all + 1] = o; return o end

function M.SetResizeBounds(self, minW, minH, maxW, maxH) self.__bounds = { minW, minH, maxW, maxH } end
function M.StartSizing(self, point) self.__sizing = point end
function M.StartMoving(self) self.__moving = true end
function M.StopMovingOrSizing(self) self.__sizing, self.__moving = nil, nil end

function M.SetPoint(self, point, a, b, c, d)
  local rel, relPoint, x, y
  if type(a) == "number" or a == nil then
    x, y = a or 0, b or 0
  else
    rel = type(a) == "string" and self.__env[a] or a
    if type(b) == "number" or b == nil then
      relPoint, x, y = point, b or 0, c or 0
    else
      relPoint, x, y = b, c or 0, d or 0
    end
  end
  if rel == self.__parent then rel = nil end
  self.__points[#self.__points + 1] = { point = point, rel = rel, relPoint = relPoint or point, x = x, y = y }
  bump()
end
function M.ClearAllPoints(self) self.__points = {}; bump() end
function M.SetAllPoints(self, rel)
  self.__points = {
    { point = "TOPLEFT", rel = rel ~= self.__parent and rel or nil, relPoint = "TOPLEFT", x = 0, y = 0 },
    { point = "BOTTOMRIGHT", rel = rel ~= self.__parent and rel or nil, relPoint = "BOTTOMRIGHT", x = 0, y = 0 },
  }
  bump()
end
function M.GetNumPoints(self) return #self.__points end
function M.GetPoint(self, i)
  local p = self.__points[i or 1]
  if not p then return nil end
  return p.point, p.rel or self.__parent, p.relPoint, p.x, p.y
end

function M.SetSize(self, w, h) self.__w, self.__h = w, h; bump() end
function M.SetWidth(self, w) self.__w = w; bump() end
function M.SetHeight(self, h) self.__h = h; bump() end
function M.GetWidth(self) local _, _, w = rect(self); return w end
function M.GetHeight(self) local _, _, _, h = rect(self); return h end
function M.GetSize(self) local _, _, w, h = rect(self); return w, h end
function M.GetLeft(self) local l = rect(self); return l end
function M.GetTop(self) local _, t = rect(self); return t end
function M.GetRight(self) local l, _, w = rect(self); return l + w end
function M.GetBottom(self) local _, t, _, h = rect(self); return t + h end
function M.GetCenter(self) local l, t, w, h = rect(self); return l + w / 2, t + h / 2 end
function M.GetRect(self) return rect(self) end

function M.GetParent(self) return self.__parent end
function M.GetName(self) return self.__name end
function M.GetObjectType(self) return self.__kind end
function M.GetChildren(self) return unpack(self.__children) end
function M.GetRegions(self) return unpack(self.__regions) end
function M.GetFrameLevel(self) return self.__level end
function M.GetAlpha(self) return self.__alpha end
function M.SetAlpha(self, a) self.__alpha = a end
function M.SetFrameLevel(self, l) self.__level = l end
function M.GetScale() return 1 end
function M.GetEffectiveScale() return 1 end
function M.SetParent(self, p) self.__parent = p; bump() end

function M.Show(self)
  if not self.__shown then
    self.__shown = true
    Stub.fire(self, "OnShow")
  end
end
function M.Hide(self)
  if self.__shown then
    self.__shown = false
    Stub.fire(self, "OnHide")
  end
end
function M.SetShown(self, shown) if shown then self:Show() else self:Hide() end end
function M.IsShown(self) return self.__shown end
function M.IsVisible(self)
  local f = self
  while f and not f.__root do
    if not f.__shown then return false end
    f = f.__parent
  end
  return true
end
function M.IsMouseOver() return false end

function M.SetScript(self, name, fn) self.__scripts[name] = fn end
function M.GetScript(self, name) return self.__scripts[name] end
function M.HookScript(self, name, fn)
  self.__hooks[name] = self.__hooks[name] or {}
  table.insert(self.__hooks[name], fn)
end
function M.HasScript() return true end

-- text and fonts
function M.SetText(self, text)
  self.__text = tostring(text == nil and "" or text)
  if self.__kind == "FontString" then bump() end
  -- the client reports programmatic edit box changes too, flagged as not typed
  if self.__kind == "EditBox" then Stub.fire(self, "OnTextChanged", false) end
end
function M.GetText(self) return self.__text end
function M.GetStringWidth(self) return #self.__text * 6 end
function M.GetStringHeight() return 12 end
function M.GetFontString(self)
  if not self.__fs then self.__fs = newObject("FontString", nil, self, self.__env) end
  return self.__fs
end
function M.GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function M.GetNumLines(self) return 1 end

-- buttons, checks, edit boxes, sliders
function M.Enable(self) self.__enabled = true end
function M.Disable(self) self.__enabled = false end
function M.SetEnabled(self, on) self.__enabled = on and true or false end
function M.IsEnabled(self) return self.__enabled end
function M.Click(self, button) Stub.fire(self, "OnClick", button or "LeftButton") end
function M.SetChecked(self, v) self.__checked = v and true or false end
function M.GetChecked(self) return self.__checked end
function M.GetNumber(self) return tonumber(self.__text) or 0 end
function M.HasFocus() return false end
function M.Insert(self, s) self.__text = self.__text .. s end
function M.SetMinMaxValues(self, lo, hi) self.__min, self.__max = lo, hi end
function M.GetMinMaxValues(self) return self.__min, self.__max end
function M.SetValue(self, v)
  v = math.max(self.__min, math.min(self.__max, v))
  if v ~= self.__value then
    self.__value = v
    Stub.fire(self, "OnValueChanged", v)
  end
end
function M.GetValue(self) return self.__value end
function M.GetThumbTexture(self) return self.__thumb or newObject("Texture", nil, self, self.__env) end
function M.SetVerticalScroll(self, v) self.__vscroll = v end
function M.GetVerticalScroll(self) return self.__vscroll or 0 end
function M.GetVerticalScrollRange() return 0 end

-- tooltip
function M.NumLines() return 0 end
function M.SetText_(self) end

-- line objects
function M.GetStartPoint() return nil end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function Stub.fire(frame, script, ...)
  local fn = frame.__scripts[script]
  if fn then fn(frame, ...) end
  for _, hook in ipairs(frame.__hooks[script] or {}) do hook(frame, ...) end
end

-- Fire OnSizeChanged for every frame whose resolved size changed since last time,
-- repeating until layout is stable (as the client cascades size changes).
function Stub.settle(env)
  for _ = 1, 12 do
    local changed = false
    for _, f in ipairs(env.__all) do
      if f.__kind ~= "Texture" and f.__kind ~= "FontString" and f.__kind ~= "Line" then
        local _, _, w, h = rect(f)
        local last = f.__lastSize
        if not last or last[1] ~= w or last[2] ~= h then
          f.__lastSize = { w, h }
          changed = true
          Stub.fire(f, "OnSizeChanged", w, h)
        end
      end
    end
    if not changed then return end
  end
  error("layout did not settle: a size handler keeps changing sizes")
end

-- Resize a (top level) frame the way a drag of the grip would.
function Stub.resize(env, frame, w, h)
  frame:SetSize(w, h)
  Stub.settle(env)
end

function Stub.click(frame, button)
  Stub.fire(frame, "OnMouseDown", button or "LeftButton")
  Stub.fire(frame, "OnMouseUp", button or "LeftButton")
  Stub.fire(frame, "OnClick", button or "LeftButton")
end

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------
function Stub.new(overrides)
  local env = { __all = {} }
  local root = newObject("Frame", "UIParent", nil, env)
  root.__root, root.__w, root.__h = true, 1920, 1080
  env.UIParent = root

  env.CreateFrame = function(kind, name, parent, template)
    local f = newObject(kind, name, parent or root, env)
    if kind == "GameTooltip" then f.__shown = false end
    addChild(f.__parent, f, "__children")
    env.__all[#env.__all + 1] = f
    if name then env[name] = f end
    return f
  end

  env.GameTooltip = env.CreateFrame("GameTooltip", "GameTooltip", root)
  env.UISpecialFrames = {}
  env.tinsert = table.insert
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  env.GetTime = function() return 1000 end
  env.GetCursorPosition = function() return 500, 500 end
  env.IsShiftKeyDown = function() return false end
  env.IsModifiedClick = function() return false end
  env.IsControlKeyDown = function() return false end
  env.date = function(fmt, t) return os.date("!" .. fmt, t) end
  env.time = os.time
  env.unpack = unpack
  env.GetScreenWidth = function() return 1920 end
  env.GetScreenHeight = function() return 1080 end
  env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  env.Minimap = env.CreateFrame("Frame", "Minimap", root)
  env.Minimap:SetSize(140, 140)
  env.Minimap:SetPoint("TOPRIGHT", root, "TOPRIGHT", -20, -20)
  env.ChatEdit_InsertLink = function() return true end
  for k, v in pairs(overrides or {}) do env[k] = v end
  return env
end

-- Utility for tests: every frame (not region) reachable from `frame`.
function Stub.descendants(frame, out)
  out = out or {}
  for _, child in ipairs(frame.__children) do
    out[#out + 1] = child
    Stub.descendants(child, out)
  end
  return out
end

function Stub.find(env, predicate)
  for _, f in ipairs(env.__all) do
    if predicate(f) then return f end
  end
end

function Stub.findAll(env, predicate)
  local out = {}
  for _, f in ipairs(env.__all) do
    if predicate(f) then out[#out + 1] = f end
  end
  return out
end

function Stub.within(inner, outer, slack)
  slack = slack or 0.5
  local il, it, iw, ih = rect(inner)
  local ol, ot, ow, oh = rect(outer)
  return il >= ol - slack and it >= ot - slack and il + iw <= ol + ow + slack and it + ih <= ot + oh + slack
end

function Stub.overlaps(a, b)
  local al, at, aw, ah = rect(a)
  local bl, bt, bw, bh = rect(b)
  return al < bl + bw and bl < al + aw and at < bt + bh and bt < at + ah
end

return Stub
