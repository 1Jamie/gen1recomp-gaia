package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Json = require("src.link.Json")
local Check = require("src.update.Check")
local Semver = require("src.update.Semver")
local payloadName = "gen1recomp-0.3.47.love"
local payloadRel = "updates/" .. payloadName
local hash = string.rep("a", 64)
local notes = "Windows update regression fixture"
local body = Json.encode({
  tag_name = "v0.3.47", body = notes,
  assets = {
    { name = payloadName, browser_download_url = "fixture:payload", size = 7 },
    { name = "sha256sums.txt", browser_download_url = "fixture:sums" },
    { name = "gen1recomp-0.3.47-windows.zip", browser_download_url = "fixture:full" },
  },
})

-- Execute the real worker command loop with deterministic transport, hashing
-- and archive probes. Both cached and fresh payloads must pass the same gate.
local function runWorker(boot, cached)
  local files, states = {}, {}
  if cached then files[payloadRel] = "payload" end
  local commands = { { cmd = "check", target = { os = "Windows" } } }
  if not cached then commands[#commands + 1] = { cmd = "download" } end
  commands[#commands + 1] = { cmd = "quit" }
  local index = 0
  local modules = {
    ["src/link/Json.lua"] = Json,
    ["src/update/Check.lua"] = Check,
    ["src/update/Semver.lua"] = Semver,
    ["src/core/Version.lua"] = { engine = "0.3.46", shell = 2, payloadHost = "love" },
    ["src/update/Boot.lua"] = boot,
    ["src/core/HostShell.lua"] = {
      canFetch = function() return true end,
      haveCurl = function() return false end,
      httpGet = function(url)
        if url == "fixture:sums" then return hash .. "  " .. payloadName .. "\n" end
        return body
      end,
      httpDownload = function(_, path)
        files[path:gsub("^fixture%-save/", "")] = "payload"
        return true
      end,
    },
  }
  local savedLove, savedRename = _G.love, os.rename
  local savedModules = {}
  local moduleNames = { "love.thread", "love.filesystem", "love.data", "love.timer", "love.system" }
  for _, name in ipairs(moduleNames) do
    savedModules[name] = package.loaded[name]
    package.loaded[name] = true
  end
  _G.love = {
    filesystem = {
      load = function(path) return function() return modules[path] end end,
      getSaveDirectory = function() return "fixture-save" end,
      getInfo = function(path)
        if files[path] then return { type = "file", size = #files[path] } end
      end,
      read = function(path) return files[path] end,
      write = function(path, data) files[path] = data; return true end,
      remove = function(path) files[path] = nil; return true end,
      createDirectory = function() return true end,
    },
    system = { getOS = function() return "Windows" end },
    data = { hash = function() return "digest" end, encode = function() return hash end },
    timer = {},
    thread = { getChannel = function(name)
      if name == "update_check_state" then
        return { push = function(_, state) states[#states + 1] = state end }
      end
      return { demand = function()
        index = index + 1
        assert(commands[index], "worker consumed all fixture commands")
        return commands[index]
      end }
    end },
  }
  os.rename = function() return false end
  local ok, err = pcall(dofile, "src/update/check_worker.lua")
  _G.love, os.rename = savedLove, savedRename
  for _, name in ipairs(moduleNames) do package.loaded[name] = savedModules[name] end
  assert(ok, err)
  return states, files
end

local cases = {
  { name = "missing Boot", reason = "payload_probe_unavailable" },
  { name = "missing probe", boot = {}, reason = "payload_probe_unavailable" },
  { name = "failed mount", boot = { probePayload = function() return nil, "mount failed" end },
    reason = "payload_probe_failed" },
  { name = "throwing probe", boot = { probePayload = function() error("probe failed") end },
    reason = "payload_probe_failed" },
  { name = "invalid probe result", boot = { probePayload = function() return false end },
    reason = "payload_probe_failed" },
  { name = "newer shell", boot = { probePayload = function() return { minShell = 3 } end },
    reason = "min_shell" },
  { name = "different host", boot = { probePayload = function() return { payloadHost = "other" } end },
    reason = "payload_host" },
}
for _, cached in ipairs({ true, false }) do
  local route = cached and "cached" or "downloaded"
  for _, case in ipairs(cases) do
    local label = route .. " " .. case.name
    local states, files = runWorker(case.boot, cached)
    local final = states[#states]
    eq(final.status, "needs_full", label .. " requires a native package")
    eq(final.reason, case.reason, label .. " reports its reason")
    eq(final.notes, notes, label .. " retains release notes")
    for _, state in ipairs(states) do
      check(state.status ~= "ready", label .. " never offers a false restart")
    end
    local record = Json.decode(files["updates/full-update.json"] or "{}")
    eq(record.reason, case.reason, label .. " persists its reason")
    eq(record.full and record.full.url, "fixture:full", label .. " persists the Windows package")
    eq(files[payloadRel], nil, label .. " removes the rejected payload")
    eq(files[payloadRel .. ".part"], nil, label .. " removes the rejected partial payload")
    eq(Json.decode(files["updates/notes_cache.json"])["0.3.47"], notes,
      label .. " caches notes before rejecting the payload")
  end
  local states, files = runWorker({ probePayload = function()
    return { engine = "0.3.47", minShell = 2, payloadHost = "love" }
  end }, cached)
  eq(states[#states].status, "ready", route .. " compatible payload offers a restart")
  eq(files[payloadRel], "payload", route .. " compatible payload is retained")
end

T.finish("update worker probe gate")
