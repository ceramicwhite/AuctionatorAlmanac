local H = require("harness")
local Stub = require("ui_stub")
local test = H.test

local FILES = { "Core/Init.lua", "Core/Format.lua", "UI/Theme.lua", "UI/Widgets.lua", "UI/VirtualList.lua", "UI/Table.lua", "UI/Window.lua" }

local function boot(savedWindow)
  local env = Stub.new()
  env.C_Timer = H.fakeTimer()
  local A, leaks = H.newUI(FILES, env)
  A.db = A.InitDB(savedWindow and { version = 1, window = savedWindow } or nil)
  return A, env, leaks
end

test("window defines no stray globals", function()
  local _, _, leaks = boot()
  H.eq(leaks, {})
end)

test("Get creates one named frame that Escape closes, hidden at first", function()
  local A, env = boot()
  local win = A.UI.Window.Get()
  H.eq(win:GetName(), "AuctionatorAlmanacFrame")
  H.eq(A.UI.Window.Get(), win, "created once")
  H.falsy(win:IsShown())
  local found = false
  for _, name in ipairs(env.UISpecialFrames) do if name == "AuctionatorAlmanacFrame" then found = true end end
  H.truthy(found, "registered for Escape")
end)

test("Toggle shows and hides, and announces when shown", function()
  local A, env = boot()
  local shown = 0
  A.Bus.On("WINDOW_SHOWN", function() shown = shown + 1 end)
  A.UI.Window.Toggle()
  H.truthy(A.UI.Window.Get():IsShown())
  H.eq(shown, 1)
  A.UI.Window.Toggle()
  H.falsy(A.UI.Window.Get():IsShown())
end)

test("default size is 1000x620 with 960x540 minimum, resizable from the corner", function()
  local A, env = boot()
  local win = A.UI.Window.Get()
  Stub.settle(env)
  H.eq({ win:GetWidth(), win:GetHeight() }, { 1000, 620 })
  H.eq(win.__bounds[1], 960)
  H.eq(win.__bounds[2], 540)
  H.truthy(win.__bounds[3] <= 1920 and win.__bounds[4] <= 1080, "max is on screen")
  H.truthy(win.grip)
  local gl, gt, gw, gh = Stub.rect(win.grip)
  local wl, wt, ww, wh = Stub.rect(win)
  H.truthy(gl + gw <= wl + ww + 0.5 and gt + gh <= wt + wh + 0.5, "grip is inside the bottom-right corner")
  H.truthy(gl > wl + ww / 2 and gt > wt + wh / 2)
end)

test("dragging the grip starts and stops sizing, and saves the new size", function()
  local A, env = boot()
  local win = A.UI.Window.Get()
  Stub.settle(env)
  Stub.fire(win.grip, "OnMouseDown", "LeftButton")
  H.eq(win.__sizing, "BOTTOMRIGHT")
  Stub.resize(env, win, 1200, 700)
  Stub.fire(win.grip, "OnMouseUp", "LeftButton")
  H.eq(win.__sizing, nil)
  H.eq({ A.db.window.w, A.db.window.h }, { 1200, 700 })
end)

test("dragging the title bar moves the window and saves its position", function()
  local A, env = boot()
  local win = A.UI.Window.Get()
  Stub.fire(win.titleBar, "OnDragStart")
  H.truthy(win.__moving)
  win:ClearAllPoints()
  win:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 120, -80)
  Stub.fire(win.titleBar, "OnDragStop")
  H.falsy(win.__moving)
  H.eq({ A.db.window.point, A.db.window.x, A.db.window.y }, { "TOPLEFT", 120, -80 })
  H.eq(A.db.window.relPoint, "TOPLEFT")
end)

test("a saved position keeps its relative anchor point", function()
  local A, env = boot({ w = 1000, h = 620, point = "BOTTOMLEFT", relPoint = "TOPLEFT", x = 40, y = -700 })
  local win = A.UI.Window.Get()
  local point, _, relPoint, x, y = win:GetPoint(1)
  H.eq({ point, relPoint, x, y }, { "BOTTOMLEFT", "TOPLEFT", 40, -700 })
end)

test("saved geometry is restored and clamped to sane bounds", function()
  local A, env = boot({ w = 1100, h = 700, point = "TOPLEFT", x = 50, y = -60 })
  local win = A.UI.Window.Get()
  Stub.settle(env)
  H.eq({ win:GetWidth(), win:GetHeight() }, { 1100, 700 })
  H.eq({ win:GetLeft(), win:GetTop() }, { 50, 60 })

  local B, env2 = boot({ w = 100, h = 100 })
  local small = B.UI.Window.Get()
  Stub.settle(env2)
  H.eq({ small:GetWidth(), small:GetHeight() }, { 960, 540 })

  local C, env3 = boot({ w = 99999, h = 99999 })
  local big = C.UI.Window.Get()
  Stub.settle(env3)
  H.truthy(big:GetWidth() <= 1920 and big:GetHeight() <= 1080)
end)

local SIZES = { { 960, 540 }, { 1000, 620 }, { 1400, 900 }, { 1800, 1000 } }

test("every region stays inside the window and never overlaps at any size", function()
  local A, env = boot()
  local win = A.UI.Window.Get()
  win:Show()
  for _, size in ipairs(SIZES) do
    Stub.resize(env, win, size[1], size[2])
    local label = size[1] .. "x" .. size[2]
    local regions = { win.titleBar, win.statusBar, win.searchRow, win.body, win.catPanel, win.resultsPanel, win.detailPanel }
    for _, r in ipairs(regions) do
      H.truthy(r:GetWidth() > 0 and r:GetHeight() > 0, "region has size at " .. label)
      H.truthy(Stub.within(r, win), "region inside the window at " .. label)
    end
    H.eq(win.catPanel:GetWidth(), 150)
    local detail = win.detailPanel:GetWidth()
    H.truthy(detail >= 330 and detail <= 560, "detail width " .. detail .. " at " .. label)
    H.truthy(win.resultsPanel:GetWidth() >= 300, "results get room at " .. label .. ": " .. win.resultsPanel:GetWidth())
    H.falsy(Stub.overlaps(win.catPanel, win.resultsPanel), "cats/results at " .. label)
    H.falsy(Stub.overlaps(win.resultsPanel, win.detailPanel), "results/detail at " .. label)
    H.falsy(Stub.overlaps(win.titleBar, win.statusBar))
    H.falsy(Stub.overlaps(win.statusBar, win.searchRow))
    H.falsy(Stub.overlaps(win.searchRow, win.body))
    H.falsy(Stub.overlaps(win.grip, win.body), "the grip sits in the margin at " .. label)
  end
end)

test("the detail panel grows with the window but is capped", function()
  local A, env = boot()
  local win = A.UI.Window.Get()
  Stub.resize(env, win, 960, 540)
  local small = win.detailPanel:GetWidth()
  Stub.resize(env, win, 1500, 800)
  local large = win.detailPanel:GetWidth()
  Stub.resize(env, win, 1900, 1000)
  local huge = win.detailPanel:GetWidth()
  H.truthy(large > small)
  H.eq(huge, 560)
end)

test("builders registered by other modules run once when the window is created", function()
  local A, env = boot()
  local calls = 0
  A.UI.Window.AddBuilder(function(win) calls = calls + 1; win.custom = true end)
  local win = A.UI.Window.Get()
  A.UI.Window.Get()
  H.eq(calls, 1)
  H.truthy(win.custom)
end)

test("the close button hides the window", function()
  local A, env = boot()
  local win = A.UI.Window.Get()
  win:Show()
  win.closeButton:Click()
  H.falsy(win:IsShown())
end)
