-- Minimal test harness: no frameworks. Plain `lua tests/run.lua`.
local H = { passes = 0, failures = {} }

local here = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "."
H.root = here .. "/.."
H.addonDir = H.root .. "/AuctionatorAlmanac"

local function deepEq(a, b, seen)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do
    if not deepEq(v, b[k], seen) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  local out = {}
  for k, x in pairs(v) do out[#out + 1] = tostring(k) .. "=" .. show(x) end
  table.sort(out)
  return "{" .. table.concat(out, ",") .. "}"
end

function H.eq(actual, expected, msg)
  if not deepEq(actual, expected) then
    error((msg or "values differ") .. ": expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

function H.near(actual, expected, eps, msg)
  eps = eps or 1e-9
  if type(actual) ~= "number" or math.abs(actual - expected) > eps then
    error((msg or "not near") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

function H.truthy(v, msg)
  if not v then error((msg or "expected truthy") .. ", got " .. tostring(v), 2) end
end

function H.falsy(v, msg)
  if v then error((msg or "expected falsy") .. ", got " .. show(v), 2) end
end

function H.throws(fn, msg)
  local ok = pcall(fn)
  if ok then error(msg or "expected an error", 2) end
end

function H.nothrows(fn, msg)
  local ok, err = pcall(fn)
  if not ok then error((msg or "unexpected error") .. ": " .. tostring(err), 2) end
end

function H.test(name, fn)
  local ok, err = xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback("", 2) end)
  if ok then
    H.passes = H.passes + 1
  else
    H.failures[#H.failures + 1] = { name = name, err = err }
  end
end

-- Create the shared addon table and load addon files into it, the way WoW does:
-- each file is called with (addonName, A).
function H.newA(files, env)
  local A = { env = env or {} }
  for _, rel in ipairs(files or {}) do
    local f, err = loadfile(H.addonDir .. "/" .. rel)
    if not f then error("load " .. rel .. ": " .. tostring(err), 2) end
    f("AuctionatorAlmanac", A)
  end
  return A
end

-- Standard Lua names a WoW addon can see (no `os`, `io`, `require`, ...).
local STD = {}
for _, name in ipairs({ "string", "table", "math", "pairs", "ipairs", "next", "type", "tostring", "tonumber",
  "select", "pcall", "xpcall", "error", "assert", "setmetatable", "getmetatable", "rawget", "rawset",
  "rawequal", "print", "collectgarbage" }) do
  STD[name] = _G[name]
end
STD.unpack = table.unpack or unpack
STD.debugprofilestop = function() return os.clock() * 1000 end

-- Load addon files with `env` as their global environment, like the game does.
-- `env` should come from ui_stub.lua; its keys before loading are the "known" globals.
function H.newUI(files, env, A)
  setmetatable(env, { __index = STD })
  A = A or {}
  A.env = env
  local known = {}
  for k in pairs(env) do known[k] = true end
  for _, rel in ipairs(files) do
    local f, err = loadfile(H.addonDir .. "/" .. rel, "t", env)
    if not f then error("load " .. rel .. ": " .. tostring(err), 2) end
    f("AuctionatorAlmanac", A)
  end
  local leaks = {}
  for k in pairs(env) do
    if not known[k] and type(k) == "string" and k:sub(1, 2) ~= "__" then leaks[#leaks + 1] = k end
  end
  table.sort(leaks)
  return A, leaks
end

-- Controllable C_Timer for tests: timers run only when flushed.
function H.fakeTimer()
  local T = { queue = {} }
  T.After = function(sec, fn) T.queue[#T.queue + 1] = { sec = sec, fn = fn } end
  function T.flush(max)
    local n = 0
    while #T.queue > 0 and n < (max or 10000) do
      local item = table.remove(T.queue, 1)
      item.fn()
      n = n + 1
    end
    return n
  end
  return T
end

return H
