local ADDON, A = ...

A.name = ADDON
A.env = A.env or _G
A.DB_VERSION = 1

-- ---------------------------------------------------------------------------
-- Internal pub/sub. Listeners are isolated: one failing listener never stops
-- the others, and the error is surfaced through the game's error handler.
-- ---------------------------------------------------------------------------
A.Bus = { listeners = {} }

function A.Bus.On(name, fn)
  local list = A.Bus.listeners[name]
  if not list then
    list = {}
    A.Bus.listeners[name] = list
  end
  list[#list + 1] = fn
end

function A.Bus.Fire(name, ...)
  local list = A.Bus.listeners[name]
  if not list then return end
  local copy = {}
  for i = 1, #list do copy[i] = list[i] end
  for i = 1, #copy do
    local ok, err = pcall(copy[i], ...)
    if not ok then
      A.Bus.lastError = err
      local getHandler = A.env.geterrorhandler
      local handler = getHandler and getHandler()
      if handler then handler(err) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------
function A.NewDB()
  return {
    version = A.DB_VERSION,
    settings = {
      minimap = true,
      tooltips = true,
      historyRange = 21,       -- default graph range in days (0 = everything available)
      ledgerKeepDays = 730,
      historyKeepDays = 365,
    },
    window = {},                -- saved geometry
    ui = {},                    -- last selection and filters
    minimap = { angle = 215 },
    items = {},                 -- item cache: [itemID] = {name, quality, icon, class, sub, invType, sell, minLevel, ilvl}
    ledger = { entries = {}, seq = 0 },
    chars = {},                 -- inventory snapshots per character
    guilds = {},                -- guild bank snapshots
    warband = nil,              -- account bank snapshot, when the client has one
    history = { items = {}, viewed = {}, watched = {} },
    discovery = { first = {} },   -- [itemID] = the first scan day Almanac saw it; floor = first day of data
  }
end

-- Fill in anything missing or wrongly typed from the defaults without
-- discarding valid data. Tables the defaults leave empty (items, chars, ...)
-- keep whatever the player has.
local function fill(saved, defaults)
  for key, default in pairs(defaults) do
    local have = saved[key]
    if type(default) == "table" then
      if type(have) ~= "table" then
        saved[key] = default
      else
        fill(have, default)
      end
    elseif have == nil or type(have) ~= type(default) then
      saved[key] = default
    end
  end
end

-- migrations[n] upgrades a database at version n-1 to version n.
A.migrations = {}

function A.InitDB(saved)
  local db = type(saved) == "table" and saved or {}
  fill(db, A.NewDB())
  local from = tonumber(db.version) or 0
  for v = from + 1, A.DB_VERSION do
    local migrate = A.migrations[v]
    if migrate then migrate(db) end
  end
  db.version = A.DB_VERSION
  return db
end

function A.Get(key)
  local settings = A.db and A.db.settings
  if settings then return settings[key] end
end

function A.Set(key, value)
  if not A.db then return end
  A.db.settings[key] = value
  A.Bus.Fire("SETTINGS_CHANGED", key, value)
end

-- ---------------------------------------------------------------------------
-- Small environment helpers
-- ---------------------------------------------------------------------------
function A.Print(msg)
  local out = A.env.print
  if out then out("|cffffd100Almanac:|r " .. tostring(msg)) end
end

-- Milliseconds from a high-resolution clock; 0 where there is none (plain test
-- environments), in which case chunked work falls back to its fixed size cap.
function A.Clock()
  local f = A.env.debugprofilestop
  return f and f() or 0
end

-- Work through `count` items without hogging a frame: call work(k) for k = from..count
-- until `budgetMs` has passed (checked every few items) or `cap` items are done.
-- Returns the next index to resume from.
function A.RunBudgeted(from, count, cap, budgetMs, work)
  local started = A.Clock()
  local stop = math.min(count, from + cap - 1)
  local k = from
  while k <= stop do
    work(k)
    k = k + 1
    if k % 16 == 0 and A.Clock() - started > budgetMs then break end
  end
  return k
end

-- Run fn after `sec` seconds; without a timer (tests) it runs immediately.
function A.After(sec, fn)
  local timer = A.env.C_Timer
  if timer and timer.After then
    timer.After(sec, fn)
  else
    fn()
  end
end

A.eventHandlers = {}

function A.FireEvent(event, ...)
  local list = A.eventHandlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], event, ...)
    if not ok then
      local getHandler = A.env.geterrorhandler
      local handler = getHandler and getHandler()
      if handler then handler(err) end
    end
  end
end

-- Registers a handler; returns false if the client does not know the event
-- (RegisterEvent raises an error for unknown names).
function A.RegisterEvent(event, fn)
  local list = A.eventHandlers[event]
  if not list then
    list = {}
    A.eventHandlers[event] = list
  end
  list[#list + 1] = fn

  local create = A.env.CreateFrame
  if not create then return true end
  if not A.eventFrame then
    A.eventFrame = create("Frame")
    A.eventFrame:SetScript("OnEvent", function(_, e, ...) A.FireEvent(e, ...) end)
  end
  local ok = pcall(A.eventFrame.RegisterEvent, A.eventFrame, event)
  return ok
end
