-- Writes AuctionatorAlmanac/Data/Top500.lua from the Almanac website's Top 500 list, so the addon's Top 500 page shows the
-- same items as the website's. Run it from the repository root whenever the website's list changes:
--
--   lua scripts/make-top500.lua [path to the website's checkout, default ../AuctionatorAlmanacWeb]
--
-- It reads src/lib/top/data.ts (the items) and src/lib/top/notes.ts (a line about some of them) and stops with an error on
-- anything it does not understand rather than write a partial list.
local web = arg[1] or "../AuctionatorAlmanacWeb"
local OUT = "AuctionatorAlmanac/Data/Top500.lua"

local function read(path)
  local f = assert(io.open(web .. "/" .. path, "r"), "cannot open " .. web .. "/" .. path)
  local text = f:read("*a")
  f:close()
  return text
end

local function fail(msg) io.stderr:write("make-top500: " .. msg .. "\n"); os.exit(1) end

-- The items: one `{ id: 1, name: "...", q: 1, kind: "...", sub: "..." },` line each, between `ENTRIES ... = [` and `];`.
local data = read("src/lib/top/data.ts")
local body = data:match("export const ENTRIES[^=]*= %[\n(.-)\n%];")
if not body then fail("no ENTRIES list in data.ts") end
local list, seen = {}, {}
for line in body:gmatch("[^\n]+") do
  if line:match("%S") and not line:match("^%s*//") then
    local id, name, q, kind, sub = line:match('^%s*{ id: (%d+), name: "([^"]*)", q: (%d), kind: "([a-z]+)", sub: "([^"]*)" },?$')
    if not id then fail("cannot read this item line: " .. line) end
    id = tonumber(id)
    if seen[id] then fail("item " .. id .. " is on the list twice") end
    seen[id] = true
    list[#list + 1] = { id = id, name = name, q = tonumber(q), kind = kind, sub = sub }
  end
end

-- The notes: `const NAME = "...";` shared lines, then `id: value,` inside NOTES, where a value is "text", NAME, or
-- several of those joined with +.
local notesText = read("src/lib/top/notes.ts")
local shared = {}
for name, text in notesText:gmatch('\nconst (%u+) = "([^"]*)";') do shared[name] = text end
local notesBody = notesText:match("export const NOTES[^=]*= {\n(.-)\n};")
if not notesBody then fail("no NOTES table in notes.ts") end

local function value(expr, line)
  local parts, rest = {}, expr
  while rest ~= "" do
    local text, after = rest:match('^"([^"]*)"(.*)$')
    if not text then
      local name
      name, after = rest:match("^(%u+)(.*)$")
      text = name and shared[name]
    end
    if not text then fail("cannot read this note line: " .. line) end
    parts[#parts + 1] = text
    rest = after:match("^%s*%+%s*(.+)$") or after
    if rest == after and rest ~= "" then fail("cannot read this note line: " .. line) end
  end
  return table.concat(parts)
end

local notes = {}
for line in notesBody:gmatch("[^\n]+") do
  if line:match("%S") and not line:match("^%s*//") then
    local id, expr = line:match("^%s*(%d+): (.-),?$")
    if not id then fail("cannot read this note line: " .. line) end
    local text = value(expr, line)
    id = tonumber(id)
    if not seen[id] then fail("note for item " .. id .. ", which is not on the list") end
    notes[id] = text
  end
end

local out = {
  "local ADDON, A = ...",
  "",
  "-- The Top 500: the items that matter most on the WoW Forever auction house, the same list as the Almanac website's",
  "-- Top 500 page. Written by scripts/make-top500.lua from the website's list; do not edit by hand, run the script again.",
  "-- No prices here: the Top 500 page prices every item from Auctionator's scans of this house.",
  "-- { id, name, q = quality, kind, sub = what the game says under the name, note = why people want it (or nil) }",
  "A.Top500 = {",
}
for _, e in ipairs(list) do
  local fields = { "id = " .. e.id, "name = " .. string.format("%q", e.name), "q = " .. e.q, "kind = " .. string.format("%q", e.kind) }
  if e.sub ~= "" then fields[#fields + 1] = "sub = " .. string.format("%q", e.sub) end
  if notes[e.id] then fields[#fields + 1] = "note = " .. string.format("%q", notes[e.id]) end
  out[#out + 1] = "  { " .. table.concat(fields, ", ") .. " },"
end
out[#out + 1] = "}"
out[#out + 1] = ""

local f = assert(io.open(OUT, "w"))
f:write(table.concat(out, "\n"))
f:close()
local noted = 0
for _ in pairs(notes) do noted = noted + 1 end
print(string.format("make-top500: wrote %d items (%d with a note) to %s", #list, noted, OUT))
