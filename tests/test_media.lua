local H = require("harness")
local Boot = require("boot_ui")
local test = H.test

local MEDIA = H.addonDir .. "/Media"

local function readAll(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("a")
  f:close()
  return data
end

-- Parse an uncompressed 32-bit TGA the way the game's loader needs it.
local function readTga(path)
  local data = readAll(path)
  if not data then return nil, "missing" end
  local idLen, cmapType, imgType = data:byte(1), data:byte(2), data:byte(3)
  local width = data:byte(13) + data:byte(14) * 256
  local height = data:byte(15) + data:byte(16) * 256
  local bpp, descriptor = data:byte(17), data:byte(18)
  local tga = { idLen = idLen, cmapType = cmapType, imgType = imgType, width = width, height = height,
    bpp = bpp, descriptor = descriptor, size = #data }
  tga.dataStart = 18 + idLen + 1
  -- (x, y) with y = 0 at the TOP of the picture; the file stores rows bottom-up
  function tga.pixel(x, y)
    local row = (descriptor & 0x20) ~= 0 and y or (height - 1 - y)
    local at = tga.dataStart + (row * width + x) * 4
    local b, g, r, a = data:byte(at, at + 3)
    return r, g, b, a
  end
  return tga
end

local function isPowerOfTwo(n) return n > 0 and (n & (n - 1)) == 0 end

test("the media files are valid textures the game can load", function()
  for _, name in ipairs({ "minimap.tga", "logo.tga", "star.tga", "star-empty.tga" }) do
    local t, err = readTga(MEDIA .. "/" .. name)
    H.truthy(t, name .. ": " .. tostring(err))
    H.eq(t.imgType, 2, name .. " is uncompressed true-colour")
    H.eq(t.cmapType, 0, name .. " has no colour map")
    H.eq(t.bpp, 32, name .. " has an alpha channel")
    H.eq(t.descriptor & 0x0F, 8, name .. " declares 8 alpha bits")
    H.truthy(t.width == t.height, name .. " is square")
    H.truthy(isPowerOfTwo(t.width) and t.width >= 32 and t.width <= 512, name .. " is a power of two: " .. t.width)
    H.truthy(t.size >= t.dataStart - 1 + t.width * t.height * 4, name .. " holds every pixel")
  end
end)

test("the minimap icon is a disc: opaque in the middle, clear in the corners", function()
  local t = readTga(MEDIA .. "/minimap.tga")
  local n = t.width
  local _, _, _, centre = t.pixel(n // 2, n // 2)
  H.eq(centre, 255, "solid in the middle")
  for _, corner in ipairs({ { 0, 0 }, { n - 1, 0 }, { 0, n - 1 }, { n - 1, n - 1 } }) do
    local _, _, _, a = t.pixel(corner[1], corner[2])
    H.eq(a, 0, "transparent in the corner (" .. corner[1] .. "," .. corner[2] .. ")")
  end
  -- the edge of the disc: halfway to the rim on each side is still picture
  for _, p in ipairs({ { n // 2, 6 }, { n // 2, n - 7 }, { 6, n // 2 }, { n - 7, n // 2 } }) do
    local _, _, _, a = t.pixel(p[1], p[2])
    H.truthy(a > 200, "the disc reaches the rim at (" .. p[1] .. "," .. p[2] .. ")")
  end
end)

test("the minimap icon actually contains the gold letter on the dark disc", function()
  local t = readTga(MEDIA .. "/minimap.tga")
  local n = t.width
  local gold, dark = 0, 0
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local r, g, b, a = t.pixel(x, y)
      if a > 200 then
        if r >= 170 and g >= 110 and b <= 130 and r > b + 60 then gold = gold + 1 end
        if r < 90 and g < 70 and b < 45 then dark = dark + 1 end
      end
    end
  end
  -- measured at 9% gold and 60% dark; the bounds leave room but catch a blank or broken icon
  H.truthy(gold > n * n * 0.04, "gold letter pixels: " .. gold)
  H.truthy(dark > n * n * 0.30, "dark disc pixels: " .. dark)
end)

test("the logo is a full opaque square", function()
  local t = readTga(MEDIA .. "/logo.tga")
  local n = t.width
  for _, p in ipairs({ { 0, 0 }, { n - 1, 0 }, { 0, n - 1 }, { n - 1, n - 1 }, { n // 2, n // 2 } }) do
    local _, _, _, a = t.pixel(p[1], p[2])
    H.eq(a, 255, "opaque at " .. p[1] .. "," .. p[2])
  end
end)

-- How many pixels of a texture are solid and gold-warm (red well above blue), whatever their shade.
local function goldPixels(t)
  local n = 0
  for y = 0, t.height - 1 do
    for x = 0, t.width - 1 do
      local r, g, b, a = t.pixel(x, y)
      if a > 200 and r > 150 and r > b + 60 then n = n + 1 end
    end
  end
  return n
end

test("the watch stars: a solid gold star when on, a gold outline with a see-through middle when off", function()
  local on, off = readTga(MEDIA .. "/star.tga"), readTga(MEDIA .. "/star-empty.tga")
  local n = on.width
  for _, p in ipairs({ { 0, 1 }, { -2, 2 }, { 2, 2 }, { 0, 4 } }) do
    local x, y = n // 2 + p[1], n // 2 + p[2]
    local _, _, _, a = on.pixel(x, y)
    local _, _, _, b = off.pixel(x, y)
    H.eq(a, 255, "the on star is solid inside at " .. x .. "," .. y)
    H.truthy(b < 180, "the off star is see-through inside at " .. x .. "," .. y .. ": " .. b)
  end
  for _, t in ipairs({ on, off }) do
    for _, corner in ipairs({ { 0, n - 1 }, { n - 1, n - 1 } }) do
      local _, _, _, a = t.pixel(corner[1], corner[2])
      H.eq(a, 0, "clear in the bottom corners, between the star's feet")
    end
  end
  H.truthy(goldPixels(on) > n * n * 0.12, "the on star is gold: " .. goldPixels(on))
  H.truthy(goldPixels(off) > n * n * 0.08, "the outline is gold: " .. goldPixels(off))
end)

test("the TOC icon points at a file that ships in the addon", function()
  local path
  for line in io.lines(H.addonDir .. "/AuctionatorAlmanac.toc") do
    path = path or line:match("^## IconTexture:%s*(.-)%s*\r?$")
  end
  H.truthy(path, "the TOC names an icon")
  local rel = path:match("^Interface\\AddOns\\AuctionatorAlmanac\\(.+)$")
  H.truthy(rel, "inside the addon's own folder, not a stock game icon: " .. path)
  H.truthy(readAll(H.addonDir .. "/" .. rel:gsub("\\", "/")), "file exists: " .. rel)
end)

test("every media file the code refers to exists", function()
  local checked = 0
  local pipe = io.popen('find "' .. H.addonDir .. '" -name "*.lua"')
  for file in pipe:lines() do
    for line in io.lines(file) do
      if not line:match("^%s*%-%-") then
        for name in line:gmatch("Media\\\\([%w_%-%.]+)") do
          checked = checked + 1
          H.truthy(readAll(MEDIA .. "/" .. name), file .. " refers to Media\\" .. name .. " which does not exist")
        end
      end
    end
  end
  pipe:close()
  H.truthy(checked >= 1, "the code uses at least one media file")
end)

test("the minimap button wears the Almanac icon, not a stock game coin", function()
  local A = Boot.boot()
  local icon = A.UI.Minimap.icon
  H.truthy(icon, "the button keeps its icon")
  local path = icon:GetTexture()
  H.eq(path, "Interface\\AddOns\\AuctionatorAlmanac\\Media\\minimap.tga")
  H.falsy(path:find("Interface\\Icons", 1, true))
end)

test("the icon is not cropped, so the whole disc shows inside the ring", function()
  local A = Boot.boot()
  local icon = A.UI.Minimap.icon
  H.eq(icon.__texcoord, nil, "no crop of the artwork")
end)
