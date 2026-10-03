package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Extractor = require("src.import.RomExtractorGen3")
local CacheFs = require("src.import.CacheFs")
local plans = {
  frlg = require("src.import.gba.plans.frlg"),
  rse = require("src.import.gba.plans.rse"),
}
local getenv = os.getenv
local flags = { "HANDHELD", "POKEPORT_HANDHELD", "PORTMASTER" }
local cases = {
  { "Linux desktop", "Linux", 8, {}, 6 },
  { "Linux four cores", "Linux", 4, {}, 3 },
  { "single core", "Linux", 1, {}, 1 },
  { "two cores", "Linux", 2, {}, 1 },
  { "unknown OS", "", 8, {}, 6 },
  { "Android", "Android", 8, {}, 2 },
  { "iOS", "iOS", 8, {}, 2 },
  { "NX", "NX", 8, {}, 2 },
  { "disabled flags", "Linux", 8, { HANDHELD = "0", POKEPORT_HANDHELD = "0", PORTMASTER = "0" }, 6 },
  { "override two", "Linux", 8, { HANDHELD = "1", POKEPORT_EXTRACT_WORKERS = "2" }, 2 },
  { "override one", "Linux", 8, { PORTMASTER = "1", POKEPORT_EXTRACT_WORKERS = "1" }, 1 },
  { "override floor", "Linux", 8, { POKEPORT_HANDHELD = "1", POKEPORT_EXTRACT_WORKERS = "2.9" }, 2 },
  { "override cap", "Linux", 8, { PORTMASTER = "1", POKEPORT_EXTRACT_WORKERS = "100" }, 100 },
  { "invalid override", "Linux", 8, { PORTMASTER = "1", POKEPORT_EXTRACT_WORKERS = "bad" }, 1 },
  { "zero override", "Linux", 8, { PORTMASTER = "1", POKEPORT_EXTRACT_WORKERS = "0" }, 1 },
}
for _, flag in ipairs(flags) do
  for _, platform in ipairs({ "Linux", "OS X" }) do
    cases[#cases + 1] = { platform .. " " .. flag, platform, 8, { [flag] = "1" }, 1 }
  end
end

local function run(plan, case, failure)
  local live, maximum, starts, completions, pending, writes = 0, 0, {}, {}, {}, {}
  local env = case[4]
  os.getenv = function(key)
    if key == "POKEPORT_NO_THREAD" or key == "POKEPORT_EXTRACT_WORKERS" then return env[key] end
    for _, flag in ipairs(flags) do if key == flag then return env[key] end end
    return getenv(key)
  end
  CacheFs.exists = function() return false end
  CacheFs.write = function(path, bytes) writes[path] = bytes; return true end
  _G.love = {
    system = { getOS = function() return case[2] end, getProcessorCount = function() return case[3] end },
    timer = { getTime = function() return 10 end, sleep = function() end },
    thread = {
      getChannel = function()
        return { pop = function()
          local task = table.remove(pending, 1)
          if not task then return nil end
          live = live - 1
          completions[task] = (completions[task] or 0) + 1
          return { type = "done", task = task, ok = task ~= failure, error = task == failure and "fixture failure" or nil }
        end }
      end,
      newThread = function()
        return {
          start = function(_, task, _, rom, sha1)
            T.eq(rom, "ROM fixture", "scheduler transfers unchanged ROM")
            T.eq(sha1, "fixture sha1", "scheduler transfers SHA")
            live = live + 1
            maximum = math.max(maximum, live)
            starts[task] = (starts[task] or 0) + 1
            pending[#pending + 1] = task
          end,
          getError = function() return nil end,
        }
      end,
    },
  }
  local ex = setmetatable({ romData = "ROM fixture", plan = plan }, Extractor)
  local ok, err = ex:runParallel("fixture sha1")
  local label = case[1] .. " " .. plan.id
  T.eq(ok, failure == nil, label .. " scheduler result")
  T.eq(maximum, math.min(#plan.tasks, case[5]), label .. " maximum concurrent nested workers")
  T.eq(live, 0, label .. " completes all workers")
  for _, task in ipairs(plan.tasks) do
    T.eq(starts[task.id], 1, label .. " starts " .. task.id .. " exactly once")
    T.eq(completions[task.id], 1, label .. " completes " .. task.id .. " exactly once")
  end
  if failure then
    T.check(tostring(err):find("fixture failure", 1, true) ~= nil, label .. " propagates worker failure")
    T.eq(next(writes), nil, label .. " failed tasks cannot publish success output")
  else
    T.check(next(writes) ~= nil, label .. " successful pool publishes maps inventory")
  end
end
for _, plan in pairs(plans) do
  for _, case in ipairs(cases) do run(plan, case) end
  run(plan, { "failed handheld task", "Linux", 8, { PORTMASTER = "1" }, 1 }, plan.tasks[1].id)
end
os.getenv = getenv
T.finish("game3_import_worker_policy_2636")
