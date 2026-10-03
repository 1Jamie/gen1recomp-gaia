package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
love = { system = { getOS = function() return "Linux" end } }
local Extractor = require("src.import.RomExtractorGen3")
local Importer = require("src.import.RomImporter")
local CacheFs = require("src.import.CacheFs")
local getenv = os.getenv
os.getenv = function(key)
  if key == "POKEPORT_EXTRACT_WORKERS" then return "2" end
  if key == "POKEPORT_NO_THREAD" or key == "POKEPORT_IMPORT_ONLY" then return nil end
  return getenv(key)
end

local plan = { tasks = {{ id = "a" }, { id = "b" }, { id = "c" }}, sequential = { "gba" } }
local function nested(mode)
  local threads, queue, writes = {}, {}, {}
  local created, sleeps, clears, fallbackLive, fallback, peak = 0, 0, 0, nil, 0, 0
  local function live()
    local count = 0
    for _, th in ipairs(threads) do if th.live then count = count + 1 end end
    return count
  end
  local channel = {
    pop = function()
      if mode == "channel" then error("fixture channel failure") end
      return table.remove(queue, 1)
    end,
    clear = function()
      if mode == "clear" then error("fixture clear failure") end
      clears = clears + 1; queue = {}
    end,
  }
  CacheFs.exists = function() return false end
  CacheFs.write = function(path)
    writes[#writes + 1] = { path = path, live = live() }
    return true
  end
  love = {
    system = { getOS = function() return "Linux" end, getProcessorCount = function() return 8 end },
    timer = { getTime = function() return 10 end, sleep = function()
      sleeps = sleeps + 1
      if sleeps > 6 then error("fixture watchdog") end
    end },
    thread = { getChannel = function() return channel end, newThread = function()
      created = created + 1
      local index = created
      if (mode == "create" and index == 2) or (mode == "refill" and index == 3) then
        error("fixture create failure")
      end
      local th = { joins = 0 }
      function th:start(task, prefix, rom, sha1)
        T.eq(prefix, CacheFs.prefix, mode .. " transfers prefix")
        T.eq(rom, "fixture ROM", mode .. " transfers ROM")
        T.eq(sha1, "fixture SHA", mode .. " transfers SHA")
        if mode == "start" and index == 2 then error("fixture start failure") end
        if mode == "false" and index == 2 then return false end
        self.live = true
        peak = math.max(peak, live())
        if mode == "sideeffect" and index == 2 then error("fixture post-start failure") end
        if mode == "report" then
          queue[#queue + 1] = { type = "progress", task = task, fraction = .1 }
        elseif mode == "error" then
          self.live = false
          self.err = "fixture worker error"
        else
          queue[#queue + 1] = { type = "done", task = task, ok = mode ~= "doneerror", error = "fixture task failure" }
        end
        return true
      end
      function th:getError() return self.err end
      function th:wait()
        self.joins = self.joins + 1
        if mode == "join" and index == 1 then error("fixture join failure") end
        self.live = false
        queue[#queue + 1] = { type = "progress", task = "late", fraction = 1 }
      end
      threads[#threads + 1] = th
      return th
    end },
  }
  local ex = setmetatable({ romData = "fixture ROM", plan = plan }, Extractor)
  ex.ensureSha1 = function() return "fixture SHA" end
  ex.writeRequiredMarkers = function() end
  ex.report = function(self, fraction)
    if mode == "report" and fraction > .03 and not self.reportFailed then
      self.reportFailed = true
      error("fixture report failure")
    end
  end
  ex.runGbaExtract = function()
    fallback = fallback + 1
    fallbackLive = live()
    return true
  end
  local ok, result = pcall(ex.run, ex)
  if mode == "join" or mode == "clear" then
    T.eq(ok, false, mode .. " cleanup failure aborts import")
    T.eq(fallback, 0, mode .. " cleanup failure cannot enter sequential fallback")
    T.check(tostring(result):find("fixture " .. mode .. " failure", 1, true), mode .. " cleanup error retains cause")
    T.eq(#writes, 0, mode .. " cleanup failure publishes no successful pool output")
    local published = false
    local imp = setmetatable({ workState = "working", _extract = {
      version = "firered", prefix = "fixture/", thread = {},
      progress = { pop = function() return nil end },
      result = { pop = function() return { ok = ok, error = result } end },
    } }, Importer)
    imp._completeImport = function() published = true end
    imp:_pumpExtract()
    T.eq(published, false, mode .. " worker result prevents readiness publication")
    T.eq(imp.workState, "error", mode .. " worker result exposes import failure")
  else
    T.check(ok and result.extractOk, mode .. " import succeeds after completed pool or safe fallback")
    T.eq(live(), 0, mode .. " no writer survives return")
    T.eq(clears, 1, mode .. " clears private channel after joins")
    T.eq(#queue, 0, mode .. " drains late messages")
    if mode == "success" then
      T.eq(fallback, 0, "success uses parallel output")
    else
      T.eq(fallback, 1, mode .. " uses existing sequential fallback")
      T.eq(fallbackLive, 0, mode .. " joins before sequential write")
    end
    if mode == "false" then T.eq(sleeps, 0, "false start rejected before dead polling") end
    for _, write in ipairs(writes) do T.eq(write.live, 0, mode .. " final output occurs after joins") end
  end
  T.check(peak <= 2, mode .. " promptly joins completed workers within the resource limit")
  for index, th in ipairs(threads) do T.eq(th.joins, 1, mode .. " joins owned thread " .. index) end
end
for _, mode in ipairs({ "create", "refill", "start", "sideeffect", "false", "report", "channel", "error", "doneerror", "success", "join", "clear" }) do
  nested(mode)
end

for _, version in ipairs({ "red", "gold", "firered" }) do
  for _, mode in ipairs({ "false", "throw", "true", "nil", "create" }) do
    local channels = {}
    local thread = {
      start = function()
        if mode == "throw" then error("fixture outer start failure") end
        if mode == "false" then return false end
        if mode == "true" then return true end
      end,
      getError = function() return nil end,
    }
    love = { thread = {
      newThread = function() if mode == "create" then error("fixture outer create failure") end; return thread end,
      getChannel = function(name)
        channels[name] = channels[name] or { clear = function() end, pop = function() return nil end }
        return channels[name]
      end,
    } }
    local imp = setmetatable({ romSha1 = "fixture SHA", romData = "fixture ROM", workState = "working" }, Importer)
    local success = mode == "true" or mode == "nil"
    local started = imp:_startExtractThread(version, "fixture/", "fixture ROM", "fixture")
    T.eq(started, success, version .. " " .. mode .. " outer startup result")
    T.eq(imp._extract ~= nil, success, version .. " " .. mode .. " tracks only started workers")
    T.eq(imp.romData, not success and "fixture ROM" or nil, version .. " " .. mode .. " retains fallback ROM")
    if not success then
      local published = false
      imp._completeImport = function() published = true end
      imp:_pumpExtract()
      T.eq(published, false, version .. " " .. mode .. " cannot publish readiness")
    end
  end
end
os.getenv = getenv
T.finish("importer_worker_failure_cleanup")
