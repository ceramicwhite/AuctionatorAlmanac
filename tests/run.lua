-- Usage: lua tests/run.lua [name-filter]
local here = (arg[0]:match("^(.*)/[^/]*$")) or "."
package.path = here .. "/?.lua;" .. package.path

local H = require("harness")
local filter = arg[1]

local p = io.popen('ls "' .. here .. '"/test_*.lua 2>/dev/null')
local files = {}
for line in p:lines() do files[#files + 1] = line end
p:close()
table.sort(files)

local ran = 0
for _, path in ipairs(files) do
  local name = path:match("([^/]+)%.lua$")
  if not filter or name:find(filter, 1, true) then
    ran = ran + 1
    local ok, err = pcall(dofile, path)
    if not ok then
      H.failures[#H.failures + 1] = { name = name .. " (load)", err = tostring(err) }
    end
  end
end

for _, f in ipairs(H.failures) do
  print("FAIL: " .. f.name .. "\n  " .. f.err:gsub("\n", "\n  "))
end
print(string.format("%d files, %d passed, %d failed", ran, H.passes, #H.failures))
os.exit(#H.failures == 0 and 0 or 1)
