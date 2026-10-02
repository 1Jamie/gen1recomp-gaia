package.path = "./?.lua;./?/init.lua;" .. package.path
if package.config:sub(1, 1) == "\\" then
  print("[skip] Ubuntu CI runner requires a POSIX shell")
  os.exit(0)
end
local T = require("tests.harness")
local Runner = require("tests.tier_runner")
local Groups = require("tests.save_compat._groups")

local function capture(command)
  local pipe = assert(io.popen(command))
  local text = pipe:read("*a")
  pipe:close()
  return text
end

local names = {}
for name in capture("bash scripts/test.sh --list-groups"):gmatch("[^\r\n]+") do
  names[#names + 1] = name
end
T.eq(#names, 8, "eight named ROM-free groups")
local workflow = assert(io.open(".github/workflows/ci.yml", "rb"))
local text = workflow:read("*a")
workflow:close()
local aggregate = assert(text:match("  headless:\n(.-)  headless%-groups:"))
T.check(aggregate:find("name: headless suites (no ROM)", 1, true), "required branch check keeps its name")
T.check(aggregate:find("needs: headless-groups", 1, true), "required check waits for every matrix child")
T.check(aggregate:find("if: ${{ always() }}", 1, true), "required check runs after failed or skipped groups")
T.check(aggregate:find("HEADLESS_RESULT: ${{ needs.headless-groups.result }}", 1, true),
  "required check reads the combined matrix result")
local gate = assert(aggregate:match("        run: |\n(.*)")):gsub("\n          ", "\n"):gsub("^          ", "")
local gatePath = os.tmpname()
local gateFile = assert(io.open(gatePath, "wb"))
gateFile:write(gate)
gateFile:close()
for _, status in ipairs({ "success", "failure", "cancelled", "skipped" }) do
  local result = os.execute("HEADLESS_RESULT=" .. status .. " bash " .. gatePath .. " >/dev/null 2>&1")
  T.eq(result == 0 or result == true, status == "success", "required check handles " .. status)
end
os.remove(gatePath)
local headless = assert(text:match("  headless%-groups:\n(.-)  fixture%-dataset:"))
local configured = {}
for name in headless:gmatch("%- group: ([%w%-]+)") do
  T.check(not configured[name], "CI group occurs once: " .. name)
  configured[name] = true
end
T.check(headless:find('run: ./scripts/test.sh --group "${{ matrix.group }}"', 1, true),
  "CI executes the selected group")
T.check(headless:find("fail-fast: false", 1, true), "one failing group does not cancel the others")

local prefix = "POKEPORT_TEST_CACHES=/tmp/no-headless-group-cache POKEPORT_IDENTITY=ci-group-plan "
  .. "RED_CACHE= BLUE_CACHE= YELLOW_CACHE= GOLD_CACHE= SILVER_CACHE= CRYSTAL_CACHE= "
local function plan(group)
  local result = {}
  local output = capture(prefix .. "bash scripts/test.sh --quick --list --group " .. group)
  T.check(output:find("tests were not run", 1, true), "listing does not execute tests: " .. group)
  for label in output:gmatch("%[tier%] ([^\r\n]+)") do
    T.check(not result[label], "tier occurs once in " .. group .. ": " .. label)
    result[label] = true
  end
  return result
end
local all, assigned = plan("all"), {}
for _, name in ipairs(names) do
  T.check(configured[name], "CI includes " .. name)
  configured[name] = nil
  local selected = plan(name)
  T.check(next(selected) ~= nil, "group is not empty: " .. name)
  for label in pairs(selected) do
    T.check(all[label], "group tier belongs to the full suite: " .. label)
    T.check(not assigned[label], "tier belongs to exactly one CI group: " .. label)
    assigned[label] = name
  end
end
T.check(next(configured) == nil, "CI has no unknown groups")
for label in pairs(all) do
  T.check(assigned[label], "full ROM-free tier is covered in CI: " .. label)
end

local counts, seen = {}, {}
for _, path in ipairs(Runner.suites("tests/save_compat")) do
  local group = Groups.of(path)
  T.check(Groups.valid[group], "every save suite has a group: " .. path)
  counts[group] = (counts[group] or 0) + 1
  seen[path:match("([^/]+)%.lua$")] = true
end
for name in pairs(Groups.named) do
  T.check(seen[name], "named save suite exists: " .. name)
end
for group in pairs(Groups.valid) do
  T.check((counts[group] or 0) > 0, "save group is not empty: " .. group)
end
T.eq(Groups.of("tests/save_compat/future_codec_test.lua"), "codecs", "new save tests remain covered")
local invalid = os.execute("bash scripts/test.sh --group nonexistent >/dev/null 2>&1")
T.check(invalid ~= 0 and invalid ~= true, "unknown group fails instead of running the full suite")
invalid = os.execute("luajit tests/run_save_compat.lua --group nonexistent >/dev/null 2>&1")
T.check(invalid ~= 0 and invalid ~= true, "unknown save group fails")

-- Exercise real child-process success, failure and an empty filter.
local dir = os.tmpname()
os.remove(dir)
assert(os.execute("mkdir -p " .. dir) == 0)
for name, exitCode in pairs({ pass = 0, fail = 7 }) do
  local file = assert(io.open(dir .. "/" .. name .. ".lua", "wb"))
  file:write("exit " .. exitCode .. "\n")
  file:close()
end
local oldInterpreter, oldPrint = arg[-1], print
arg[-1], print = "sh", function() end
local passed, passedTotal = Runner.run({ dir }, "filtered pass", function(p) return p:match("/pass%.lua$") end)
local failed, failedTotal = Runner.run({ dir }, "filtered fail", function(p) return p:match("/fail%.lua$") end)
local empty = Runner.run({ dir }, "empty", function() return false end)
arg[-1], print = oldInterpreter, oldPrint
T.eq(passed, 0, "successful selected child passes")
T.eq(passedTotal, 1, "unselected failing child is not run")
T.eq(failed, 1, "selected child failure propagates")
T.eq(failedTotal, 1, "failure reports the selected count")
T.eq(empty, 1, "empty group cannot pass vacuously")
os.remove(dir .. "/pass.lua")
os.remove(dir .. "/fail.lua")
os.execute("rmdir " .. dir)
T.finish("headless CI groups")
