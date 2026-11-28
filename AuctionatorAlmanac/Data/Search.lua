local ADDON, A = ...

-- Pure search, filter and sort over item IDs.
-- ctx = { info(id) -> item view|nil, summary(id) -> price summary|nil, owned(id) -> number,
--         depth(id) -> listed in all, listed at the lowest price (either may be nil; optional) }
local Search = {}
A.Search = Search

Search.MOVED_THRESHOLD = 0.05    -- 'moved' means the last price changed by at least this much

-- Lowercased tokens; "quoted phrases" stay together.
function Search.Tokenize(text)
  local tokens = {}
  if type(text) ~= "string" then return tokens end
  text = text:lower()
  local pos, len = 1, #text
  while pos <= len do
    local c = text:sub(pos, pos)
    if c:match("%s") then
      pos = pos + 1
    elseif c == '"' then
      local close = text:find('"', pos + 1, true)
      local phrase = text:sub(pos + 1, (close or (len + 1)) - 1)
      if phrase ~= "" then tokens[#tokens + 1] = phrase end
      pos = (close or len) + 1
    else
      local s, e = text:find("%S+", pos)
      tokens[#tokens + 1] = text:sub(s, e)
      pos = e + 1
    end
  end
  return tokens
end

local function textMatches(id, info, tokens, idMatch)
  if #tokens == 0 then return true end
  if idMatch and id == idMatch then return true end
  local lname = info and info.lname
  if not lname then return false end
  for i = 1, #tokens do
    if not lname:find(tokens[i], 1, true) then return false end
  end
  return true
end

-- params = { text, category (node), quality, ownedOnly, minPrice, maxPrice, recent (days), moved ("up"|"down") }
-- Returns a new array of ids; the input is not modified.
function Search.Run(ids, params, ctx)
  params = params or {}
  local tokens = Search.Tokenize(params.text)
  local idMatch
  if #tokens == 1 and tokens[1]:match("^%d+$") then idMatch = tonumber(tokens[1]) end
  local needSummary = params.minPrice or params.maxPrice or params.recent or params.moved
  local out = {}
  for i = 1, #ids do
    local id = ids[i]
    local info = ctx.info(id)
    local ok = true
    if params.category and not A.Categories.Matches(params.category, info) then ok = false end
    if ok and params.quality ~= nil and not (info and info.quality == params.quality) then ok = false end
    if ok and not textMatches(id, info, tokens, idMatch) then ok = false end
    if ok and params.ownedOnly and not (ctx.owned(id) > 0) then ok = false end
    if ok and needSummary then
      local s = ctx.summary(id)
      if not (s and s.last) then
        ok = false
      elseif params.minPrice and s.last < params.minPrice then
        ok = false
      elseif params.maxPrice and s.last > params.maxPrice then
        ok = false
      elseif params.recent and not (s.ageDays and s.ageDays <= params.recent) then
        ok = false
      elseif params.moved == "up" and not (s.change1d and s.change1d >= Search.MOVED_THRESHOLD) then
        ok = false
      elseif params.moved == "down" and not (s.change1d and s.change1d <= -Search.MOVED_THRESHOLD) then
        ok = false
      end
    end
    if ok then out[#out + 1] = id end
  end
  return out
end

local function keyValue(key, id, info, ctx)
  if key == "name" then return info and info.lname end
  if key == "owned" then                 -- none owned shows as a blank, so it sorts with the blanks: last
    local n = ctx.owned(id)
    return n > 0 and n or nil
  end
  if key == "onah" or key == "atmin" then
    if not ctx.depth then return nil end
    local onAH, atLow = ctx.depth(id)
    if key == "onah" then return onAH end
    return atLow
  end
  local s = ctx.summary(id)
  if not s then return nil end
  if key == "price" then return s.last end
  if key == "change" then return s.change1d end
  if key == "age" then return s.ageDays end
  return nil
end

-- Sorts `ids` in place. Missing values always sort last; ties fall back to name, then id.
function Search.Sort(ids, key, ascending, ctx)
  local vals, names = {}, {}
  for i = 1, #ids do
    local id = ids[i]
    local info = ctx.info(id)
    names[id] = info and info.lname
    vals[id] = keyValue(key, id, info, ctx)
  end
  table.sort(ids, function(a, b)
    local va, vb = vals[a], vals[b]
    if va ~= vb then
      if va == nil then return false end
      if vb == nil then return true end
      if ascending then return va < vb end
      return va > vb
    end
    local na, nb = names[a], names[b]
    if na ~= nb then
      if na == nil then return false end
      if nb == nil then return true end
      return na < nb
    end
    return a < b
  end)
  return ids
end
