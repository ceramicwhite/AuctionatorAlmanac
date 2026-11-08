local ADDON, A = ...

-- The Auction House category tree: { name, filters = {{classID, subClassID, inventoryType}}, children, count }.
-- Uses Blizzard's own AuctionCategories table when it is loaded, otherwise
-- generates the same shape from the client's item class data.
local Categories = {}
A.Categories = Categories

-- Classic Auction House order (item class IDs).
local ORDER = { 2, 4, 1, 0, 7, 6, 11, 9, 3, 15, 12 }
local ARMOR = 4
local ARMOR_SUBS_WITH_SLOTS = { [1] = true, [2] = true, [3] = true, [4] = true }  -- Cloth, Leather, Mail, Plate

local SLOTS = {
  { "INVTYPE_HEAD", "Head", { 1 } },
  { "INVTYPE_SHOULDER", "Shoulders", { 3 } },
  { "INVTYPE_CHEST", "Chest", { 5, 20 } },
  { "INVTYPE_WAIST", "Waist", { 6 } },
  { "INVTYPE_LEGS", "Legs", { 7 } },
  { "INVTYPE_FEET", "Feet", { 8 } },
  { "INVTYPE_WRIST", "Wrist", { 9 } },
  { "INVTYPE_HAND", "Hands", { 10 } },
  { "INVTYPE_CLOAK", "Back", { 16 } },
}

local function convert(c)
  local node = { name = c.name, filters = c.filters or {}, children = {} }
  for _, sub in ipairs(c.subCategories or {}) do
    node.children[#node.children + 1] = convert(sub)
  end
  return node
end

local function infoGetters(env)
  local C = env.C_Item
  local classInfo = (C and C.GetItemClassInfo) or env.GetItemClassInfo
  local subInfo = (C and C.GetItemSubClassInfo) or env.GetItemSubClassInfo
  return classInfo, subInfo
end

local function usableName(name)
  return type(name) == "string" and name ~= ""
end

local function armorSlots(env, classID, subID)
  local out = {}
  for _, slot in ipairs(SLOTS) do
    local filters = {}
    for _, inv in ipairs(slot[3]) do
      filters[#filters + 1] = { classID = classID, subClassID = subID, inventoryType = inv }
    end
    out[#out + 1] = { name = env[slot[1]] or slot[2], filters = filters, children = {} }
  end
  return out
end

function Categories.Build(env)
  env = env or A.env
  if type(env.AuctionCategories) == "table" then
    local tree = {}
    for _, c in ipairs(env.AuctionCategories) do tree[#tree + 1] = convert(c) end
    return tree
  end

  local classInfo, subInfo = infoGetters(env)
  local tree = {}
  if not classInfo then return tree end
  for _, classID in ipairs(ORDER) do
    local name = classInfo(classID)
    if usableName(name) then
      local node = { name = name, filters = { { classID = classID } }, children = {} }
      if subInfo then
        for subID = 0, 30 do
          local subName = subInfo(classID, subID)
          if usableName(subName) then
            local child = {
              name = subName,
              filters = { { classID = classID, subClassID = subID } },
              children = {},
            }
            if classID == ARMOR and ARMOR_SUBS_WITH_SLOTS[subID] then
              child.children = armorSlots(env, classID, subID)
            end
            node.children[#node.children + 1] = child
          end
        end
      end
      tree[#tree + 1] = node
    end
  end
  return tree
end

function Categories.Matches(node, info)
  if not node or not info or info.class == nil then return false end
  for _, f in ipairs(node.filters or {}) do
    if info.class == f.classID
        and (f.subClassID == nil or info.sub == f.subClassID)
        and (f.inventoryType == nil or info.invType == f.inventoryType) then
      return true
    end
  end
  return false
end

local function reset(nodes)
  for _, n in ipairs(nodes) do
    n.count = 0
    reset(n.children)
  end
end

local function tally(nodes, info)
  for _, n in ipairs(nodes) do
    if Categories.Matches(n, info) then
      n.count = n.count + 1
      tally(n.children, info)
    end
  end
end

-- Fill node.count for every node. infoFn(id) -> item view with class/sub/invType.
function Categories.Count(tree, ids, infoFn)
  reset(tree)
  for i = 1, #ids do
    local info = infoFn(ids[i])
    if info and info.class ~= nil then tally(tree, info) end
  end
end
