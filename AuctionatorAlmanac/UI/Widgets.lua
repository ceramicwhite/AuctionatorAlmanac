local ADDON, A = ...

-- Small widget set built from plain frames and colour textures: panel, button,
-- checkbox, edit box, tabs, cycle button, scrollbar.
local Theme = A.UI.Theme
local C = Theme.color
local W = {}
A.UI.Widgets = W

local floor = math.floor

function W.Panel(parent, fill, border)
  local f = CreateFrame("Frame", nil, parent)
  Theme.Fill(f, fill or C.panel)
  f.edges = Theme.Border(f, border or C.border, 1)
  return f
end

-- ---------------------------------------------------------------------------
-- Button
-- ---------------------------------------------------------------------------
local function paintButton(b)
  local c
  if not b:IsEnabled() then c = C.buttonDisabled
  elseif b.active then c = C.active
  elseif b.hover then c = C.buttonHover
  else c = b.fillColor end
  Theme.SetColor(b.bg, c)
  local t = b:IsEnabled() and (b.active and C.bright or C.gold) or C.dim
  if b.plainText and b:IsEnabled() then t = C.text end
  b.label:SetTextColor(t[1], t[2], t[3], 1)
end

function W.Button(parent, text, onClick, opts)
  opts = opts or {}
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(opts.width or 80, opts.height or 22)
  b.fillColor = opts.fill or C.button
  b.plainText = opts.plainText
  b.bg = Theme.Fill(b, b.fillColor)
  b.edges = Theme.Border(b, opts.border or C.border, 1)
  b.label = Theme.Text(b, opts.style or "gold", "CENTER")
  b.label:SetPoint("LEFT", b, "LEFT", 4, 0)
  b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
  b.label:SetText(text or "")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  function b:SetLabel(t) self.label:SetText(t) end
  function b:SetActive(on)
    self.active = on and true or false
    paintButton(self)
  end
  local setEnabled = b.SetEnabled
  function b:SetEnabled(on)
    setEnabled(self, on)
    paintButton(self)
  end

  b:SetScript("OnEnter", function(self) self.hover = true; paintButton(self) end)
  b:SetScript("OnLeave", function(self) self.hover = false; paintButton(self) end)
  b:SetScript("OnClick", function(self, button)
    if self:IsEnabled() and onClick then onClick(self, button) end
  end)
  paintButton(b)
  return b
end

-- ---------------------------------------------------------------------------
-- Sort arrow: a small chevron on a column header showing the sort direction (points up when
-- ascending). It sits on the side opposite the header text so the two never collide.
-- ---------------------------------------------------------------------------
function W.SortArrow(button)
  local arrow = {}
  local a = button:CreateLine(nil, "OVERLAY")
  local b = button:CreateLine(nil, "OVERLAY")
  for _, line in ipairs({ a, b }) do
    line:SetThickness(2)
    line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    line:Hide()
  end
  function arrow:Hide()
    self.visible = false
    a:Hide()
    b:Hide()
  end
  -- align is the header text's justification ("LEFT", "RIGHT" or "CENTER").
  function arrow:Show(align, ascending)
    local nearRight = align ~= "RIGHT"
    local x = nearRight and -14 or 14
    local up, down = 2, -2
    local y1, y2 = ascending and down or up, ascending and up or down
    local edge = nearRight and "RIGHT" or "LEFT"
    a:SetStartPoint(edge, button, x - 4, y1)
    a:SetEndPoint(edge, button, x, y2)
    b:SetStartPoint(edge, button, x, y2)
    b:SetEndPoint(edge, button, x + 4, y1)
    self.visible = true
    a:Show()
    b:Show()
  end
  return arrow
end

-- ---------------------------------------------------------------------------
-- Checkbox
-- ---------------------------------------------------------------------------
function W.Checkbox(parent, label, get, set, opts)
  opts = opts or {}
  local cb = CreateFrame("Button", nil, parent)
  cb:SetSize(opts.width or 170, 20)
  local box = CreateFrame("Frame", nil, cb)
  box:SetSize(14, 14)
  box:SetPoint("LEFT", cb, "LEFT", 0, 0)
  Theme.Fill(box, C.input)
  Theme.Border(box, C.border, 1)
  cb.check = box:CreateTexture(nil, "OVERLAY")
  cb.check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
  cb.check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
  Theme.SetColor(cb.check, C.gold)
  cb.label = Theme.Text(cb, "normal", "LEFT")
  cb.label:SetPoint("LEFT", box, "RIGHT", 6, 0)
  cb.label:SetPoint("RIGHT", cb, "RIGHT", 0, 0)
  cb.label:SetText(label)

  function cb:Refresh() self.check:SetShown(get() and true or false) end
  cb:SetScript("OnClick", function(self)
    set(not get())
    self:Refresh()
  end)
  cb:Refresh()
  return cb
end

-- ---------------------------------------------------------------------------
-- Edit box with placeholder and clear button
-- ---------------------------------------------------------------------------
-- onChange(text, typed) runs on every change; `typed` is false when the text was set by code.
-- opts.suggest(typed) -> a longer text to complete what the player has typed to (autofill), or nil. The completion appears after the
--   typed text, highlighted, as it does in Auctionator's search box: typing on goes past it, Backspace removes it, Enter or leaving
--   the box accepts it, and Escape drops it. onChange only ever hears the typed text until the completion is accepted.
-- opts.onCommit(text) runs when the player presses Enter in a non-empty box, the one clear sign that a search was meant.
-- opts.onFocus() runs when the box gets the keyboard.
-- opts.reserveRight: extra room kept free at the right, beside the clear button, for something the caller adds.
function W.EditBox(parent, placeholder, onChange, opts)
  opts = opts or {}
  local box = CreateFrame("Frame", nil, parent)
  box:SetHeight(opts.height or 26)
  Theme.Fill(box, C.input)
  box.edges = Theme.Border(box, C.border, 1)

  local edit = CreateFrame("EditBox", nil, box)
  edit:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -2)
  edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -24 - (opts.reserveRight or 0), 2)
  edit:SetFontObject("GameFontHighlight")
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(opts.maxLetters or 64)
  box.edit = edit
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() edit:SetFocus() end)

  box.hint = Theme.Text(box, "dim", "LEFT")
  box.hint:SetPoint("LEFT", box, "LEFT", 10, 0)
  box.hint:SetText(placeholder or "")

  box.clear = W.Button(box, "x", function() box:Clear(); edit:ClearFocus() end, { width = 18, height = 18, plainText = true })
  box.clear:SetPoint("RIGHT", box, "RIGHT", -4, 0)

  local function refresh()
    local empty = edit:GetText() == ""
    box.hint:SetShown(empty)
    box.clear:SetShown(not empty)
  end

  local completion        -- the full text on offer while its highlighted tail is showing, else nil
  local typedText         -- what the player had typed when the completion was offered
  local completing = false  -- true while this code is the one changing the text
  local previous          -- the text at the player's last edit, so deleting never brings a completion back

  -- Make the offered completion the text.
  local function accept()
    if not completion then return end
    local full = completion
    completion = nil
    if onChange then onChange(full, true) end
  end

  local function commit()
    local text = edit:GetText()
    if opts.onCommit and text ~= "" then opts.onCommit(text) end
  end

  edit:SetScript("OnTextChanged", function(self, userInput)
    if completing then return end
    refresh()
    local text = self:GetText()
    completion = nil
    local offer
    if userInput and opts.suggest and text ~= "" and not (self.IsInIMECompositionMode and self:IsInIMECompositionMode()) then
      local grew = previous == nil or #previous < #text
      previous = text
      if grew then offer = opts.suggest(text) end
    elseif text == "" then
      previous = nil
    end
    if onChange then onChange(text, userInput and true or false) end
    if offer and #offer > #text then
      completing = true
      self:SetText(offer)
      completing = false
      self:SetCursorPosition(#text)
      self:HighlightText(#text, #offer)
      completion, typedText = offer, text
    end
  end)
  edit:SetScript("OnEscapePressed", function(self)
    if completion then
      local keep = typedText
      completion = nil
      completing = true
      self:SetText(keep)
      completing = false
    end
    self:ClearFocus()
  end)
  edit:SetScript("OnEnterPressed", function(self)
    accept()
    commit()
    self:ClearFocus()
  end)
  edit:SetScript("OnEditFocusGained", function()
    box.edges:SetColor(C.gold)
    previous = nil
    if opts.onFocus then opts.onFocus() end
  end)
  edit:SetScript("OnEditFocusLost", function()
    box.edges:SetColor(C.border)
    accept()          -- what is showing in the box is what it says
  end)

  function box:SetText(t) edit:SetText(t or ""); refresh() end
  function box:GetText() return edit:GetText() end
  function box:Clear() edit:SetText(""); refresh() end
  function box:Focus() edit:SetFocus() end
  refresh()
  return box
end

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------
function W.Tabs(parent, defs, onSelect)
  local tabs = CreateFrame("Frame", nil, parent)
  tabs:SetHeight(24)
  tabs.buttons = {}
  local previous
  for _, def in ipairs(defs) do
    local width = math.max(64, math.floor(#def.label * 6.2) + 16)
    local b = W.Button(tabs, def.label, function() tabs:Select(def.key) end, { width = width, height = 24 })
    if previous then b:SetPoint("LEFT", previous, "RIGHT", 2, 0) else b:SetPoint("LEFT", tabs, "LEFT", 0, 0) end
    tabs.buttons[def.key] = b
    previous = b
  end
  function tabs:Select(key)
    self.selected = key
    for k, b in pairs(self.buttons) do b:SetActive(k == key) end
    if onSelect then onSelect(key) end
  end
  return tabs
end

-- ---------------------------------------------------------------------------
-- Cycle button: each click moves to the next option and wraps
-- ---------------------------------------------------------------------------
function W.Cycle(parent, title, options, onChange, opts)
  opts = opts or {}
  local index = 1
  local b
  local function paint()
    local option = options[index]
    b.value = option.value
    b.label:SetText(title .. ": " .. option.label)
    if not opts.plain then b:SetActive(index ~= 1) end
  end
  b = W.Button(parent, "", function()
    index = index % #options + 1
    paint()
    if onChange then onChange(options[index].value) end
  end, { width = opts.width or 130, height = opts.height or 22 })
  function b:SetValue(value)
    for i, option in ipairs(options) do
      if option.value == value then index = i; break end
    end
    paint()
  end
  paint()
  return b
end

-- ---------------------------------------------------------------------------
-- Scrollbar (a thin vertical slider; min is the top)
-- ---------------------------------------------------------------------------
W.SCROLLBAR_WIDTH = 12

function W.Scrollbar(parent, onChange)
  local sb = {}
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(W.SCROLLBAR_WIDTH)
  Theme.Fill(frame, C.track)
  local slider = CreateFrame("Slider", nil, frame)
  slider:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  slider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  slider:SetOrientation("VERTICAL")
  slider:SetMinMaxValues(0, 0)
  slider:SetValueStep(1)
  slider:SetObeyStepOnDrag(true)
  local thumb = slider:CreateTexture(nil, "OVERLAY")
  Theme.SetColor(thumb, C.thumb)
  thumb:SetSize(W.SCROLLBAR_WIDTH - 2, 30)
  slider:SetThumbTexture(thumb)
  slider:SetScript("OnValueChanged", function(_, value)
    if not sb.silent and onChange then onChange(floor(value + 0.5)) end
  end)
  sb.frame, sb.slider, sb.thumb = frame, slider, thumb

  -- maxOffset: highest scroll offset; visible/total size the thumb.
  function sb:SetRange(maxOffset, visible, total)
    self.silent = true
    slider:SetMinMaxValues(0, math.max(0, maxOffset))
    self.silent = false
    local track = math.max(frame:GetHeight() - 2, 1)
    local size = (total and total > 0) and (track * visible / total) or track
    thumb:SetHeight(math.max(24, math.min(track, size)))
    frame:SetShown(maxOffset > 0)
  end

  function sb:SetOffset(value)
    self.silent = true
    slider:SetValue(value)
    self.silent = false
  end
  return sb
end

-- ---------------------------------------------------------------------------
-- Popup list: a short list of choices that opens under a button. It closes when a choice is made, when the player clicks anywhere
-- else, or on Escape; the caller closes it when the window holding the button goes away.
--
-- local list = W.PopupList(anchor, { width = 220, maxRows = 12, empty = "Nothing here yet." })   -- width: the anchor's, if left out
-- list:Open({ "first", "second" }, function(text) ... end)
-- list:Close()   list:IsOpen()
-- ---------------------------------------------------------------------------
local POPUP_ROW_H = 20

function W.PopupList(anchor, opts)
  opts = opts or {}
  local maxRows = opts.maxRows or 12
  local popup = {}

  -- A transparent sheet over the whole screen, so a click anywhere else lands on it and closes the list.
  local catcher = CreateFrame("Frame", nil, UIParent)
  catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  catcher:SetAllPoints(UIParent)
  catcher:EnableMouse(true)
  catcher:SetScript("OnMouseDown", function() popup:Close() end)
  catcher:EnableKeyboard(true)
  catcher:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      popup:Close()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)
  catcher:Hide()

  local frame = W.Panel(catcher, C.window, C.border)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  popup.frame, popup.catcher = frame, catcher
  popup.rows = {}

  popup.emptyText = Theme.Text(frame, "dim", "LEFT")
  popup.emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -5)
  popup.emptyText:SetText(opts.empty or "Nothing here yet.")

  local rows = popup.rows
  local function row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, frame)
    r:SetHeight(POPUP_ROW_H)
    local top = -(1 + (i - 1) * POPUP_ROW_H)
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, top)
    r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, top)
    r.bg = Theme.Fill(r, C.window)
    r.label = Theme.Text(r, "normal", "LEFT")
    r.label:SetPoint("LEFT", r, "LEFT", 8, 0)
    r.label:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnEnter", function(self) Theme.SetColor(self.bg, C.hover) end)
    r:SetScript("OnLeave", function(self) Theme.SetColor(self.bg, C.window) end)
    r:SetScript("OnClick", function(self)
      local pick, value = popup.onPick, self.value
      popup:Close()
      if pick and value then pick(value) end
    end)
    rows[i] = r
    return r
  end

  function popup:Open(items, onPick)
    self.onPick = onPick
    local n = math.min(#items, maxRows)
    for i = 1, math.max(n, #rows) do
      local r = row(i)
      if i <= n then
        r.value = items[i]
        r.label:SetText(items[i])
        Theme.SetColor(r.bg, C.window)
        r:Show()
      else
        r.value = nil
        r:Hide()
      end
    end
    self.emptyText:SetShown(n == 0)
    frame:SetWidth(opts.width or math.max(anchor:GetWidth(), 160))
    frame:SetHeight(2 + math.max(n, 1) * POPUP_ROW_H + (n == 0 and 4 or 0))
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    catcher:Show()
  end

  function popup:Close()
    self.onPick = nil
    catcher:Hide()
  end

  function popup:IsOpen() return catcher:IsShown() end
  return popup
end

-- ---------------------------------------------------------------------------
-- Confirm: an "are you sure?" window in front of everything. Used before anything
-- that cannot be undone. The screen behind is dimmed and its clicks are swallowed
-- until the player picks a button (or presses Escape, which counts as Cancel).
--
-- W.Confirm{ title, message, confirmLabel = "Confirm", cancelLabel = "Cancel",
--            danger = true, onConfirm = fn, onCancel = fn }
-- ---------------------------------------------------------------------------
local CONFIRM_NAME = "AuctionatorAlmanacConfirm"
local CONFIRM_W, CONFIRM_H, CONFIRM_BUTTON_W = 400, 200, 128

local function reportError(err)
  local getHandler = geterrorhandler
  local handler = getHandler and getHandler()
  if handler then handler(err) end
end

local function buildConfirm()
  local f = CreateFrame("Frame", CONFIRM_NAME, UIParent)
  W.confirmFrame = f
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetAllPoints(UIParent)
  local dim = f:CreateTexture(nil, "BACKGROUND")
  dim:SetAllPoints(f)
  dim:SetColorTexture(0, 0, 0, 0.6)

  local box = CreateFrame("Frame", nil, f)
  f.box = box
  box:SetSize(CONFIRM_W, CONFIRM_H)
  box:SetPoint("CENTER", f, "CENTER", 0, 0)
  box:EnableMouse(true)
  Theme.Fill(box, C.window)
  Theme.Border(box, C.border, 2)

  local bar = CreateFrame("Frame", nil, box)
  bar:SetHeight(28)
  bar:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", box, "TOPRIGHT", -1, -1)
  Theme.Fill(bar, C.title)
  f.title = Theme.Text(bar, "title", "LEFT")
  f.title:SetPoint("LEFT", bar, "LEFT", 12, 0)
  f.title:SetPoint("RIGHT", bar, "RIGHT", -12, 0)

  f.message = Theme.Text(box, "normal", "LEFT")
  f.message:SetWordWrap(true)
  f.message:SetJustifyV("TOP")
  f.message:SetPoint("TOPLEFT", box, "TOPLEFT", 16, -42)
  f.message:SetPoint("TOPRIGHT", box, "TOPRIGHT", -16, -42)
  f.message:SetHeight(96)

  f.confirmButton = W.Button(box, "Confirm", function()
    local pending = f.pending
    f.pending = nil
    f:Hide()
    if pending and pending.onConfirm then
      local ok, err = pcall(pending.onConfirm)
      if not ok then reportError(err) end
    end
  end, { width = CONFIRM_BUTTON_W, height = 26, fill = C.active })
  f.confirmButton:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -16, 14)

  f.cancelButton = W.Button(box, "Cancel", function() f:Hide() end, { width = CONFIRM_BUTTON_W, height = 26 })
  f.cancelButton:SetPoint("RIGHT", f.confirmButton, "LEFT", -10, 0)

  -- Hiding by any route (Cancel, Escape) means "no"; Confirm clears `pending` first.
  f:SetScript("OnHide", function()
    local pending = f.pending
    f.pending = nil
    if pending and pending.onCancel then
      local ok, err = pcall(pending.onCancel)
      if not ok then reportError(err) end
    end
  end)

  -- Escape answers "no" without also closing every other window, which is what
  -- UISpecialFrames would do. A keyboard-enabled frame sees the key first.
  f:EnableKeyboard(true)
  f:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      self:Hide()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)

  f:Hide()
  return f
end

function W.Confirm(opts)
  opts = opts or {}
  local f = W.confirmFrame or buildConfirm()
  f.pending = nil                      -- a new question replaces any that is still open
  f.title:SetText(opts.title or "Are you sure?")
  f.message:SetText(opts.message or "")
  f.confirmButton:SetLabel(opts.confirmLabel or "Confirm")
  f.cancelButton:SetLabel(opts.cancelLabel or "Cancel")
  f.confirmButton.fillColor = (opts.danger == false) and f.cancelButton.fillColor or C.active
  paintButton(f.confirmButton)
  f.pending = opts
  f:Show()
  return f
end
