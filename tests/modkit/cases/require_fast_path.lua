-- T4: the require shim's fast path (already-loaded, undeniable, unserved
-- module, no owner) is outcome-identical to the slow path.
--
-- The shim is a security backstop (Sandbox.moduleDenial, the cross-generation
-- denial, the Gen 2/3 compat facades, scanRequire's warnings), and the fast
-- path skips all of it, so every cell of name x caller x owner x generation x
-- dev is run twice -- forced slow, then fast -- and the returned value, the
-- error text and every log line must match.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")
local Logger = require("src.core.Logger")

local function manifest(id, permissions)
  return ('{"id":"%s","name":"%s","version":"1.0.0","entry":"main.lua",'
    .. '"api":2,"games":["all"]%s}'):format(id, id, permissions or "")
end

local FILES = {
  ["mods/fp_plain/manifest.json"] = manifest("fp_plain"),
  ["mods/fp_plain/main.lua"] = "local mod = ...",
  ["mods/fp_net/manifest.json"] =
    manifest("fp_net", ',"permissions":["network","engine_internals"]'),
  ["mods/fp_net/main.lua"] = "local mod = ...",
}

-- a chunk whose name is inside / outside the engine tree, the only thing the
-- shim's callerIsMod looks at
local source = debug.getinfo(Loader._installDevShim, "S").source
local engineName = source:gsub("mods[/\\]Loader%.lua$", "fp_engine_probe.lua")
local modName = "@mods/fp_mod/main.lua"
local CODE = "local name = ...; local r = require(name); return r"
local engineChunk = assert(loadstring(CODE, engineName))
local modChunk = assert(loadstring(CODE, modName))

-- deterministic stand-ins so no case depends on what happens to be loaded
local STUBS = {
  ["src.core.Logger"] = false, -- real, already loaded
  ["src.core.Game"] = {}, -- Gen 1-only; served by the Gen 2/3 compat arms
  ["src.battle.gen2.Mon"] = {}, -- cross-generation
  ["src.fp.Plain"] = {}, -- an ordinary engine module
  ["socket"] = {}, -- network permission
  ["fp.Throws"] = false, -- preloaded below; its loader throws
  ["jit.util"] = {}, -- denied prefix
  ["love.filesystem"] = {}, -- denied prefix
}
local saved = {}
for name, stub in pairs(STUBS) do
  saved[name] = package.loaded[name]
  if stub then package.loaded[name] = stub end
end

local NAMES = {
  "src.core.Logger", "src.core.Game", "src.battle.gen2.Mon", "src.fp.Plain",
  "socket", "jit.util", "love.filesystem", "io", "os", "debug", "package",
  "ffi", "src.fp.NeverLoaded", "fp.Throws", 42,
}

-- a loader that throws: LuaJIT leaves a non-module placeholder in
-- package.loaded, and the next require must error, not hand it back
local function armThrower()
  package.loaded["fp.Throws"] = nil
  package.preload["fp.Throws"] = function() error("fp.Throws loader failed", 0) end
end
pcall(require, "fp.Throws")

local function capture()
  local log = {}
  local real = { warn = Logger.warn, info = Logger.info, error = Logger.error }
  for level in pairs(real) do
    Logger[level] = function(fmt, ...)
      log[#log + 1] = level .. ":" .. tostring(fmt):format(...)
    end
  end
  return log, function()
    for level, fn in pairs(real) do Logger[level] = fn end
  end
end

local function outcome(chunk, name, owner)
  Loader._resetShimWarned()
  local previousCurrent, previousRequire = Runtime.currentMod, Runtime.modRequire
  if owner.current ~= nil then Runtime.currentMod = owner.current end
  if owner.require ~= nil then Runtime.modRequire = owner.require end
  local log, restore = capture()
  local ok, value = pcall(chunk, name)
  restore()
  Runtime.currentMod, Runtime.modRequire = previousCurrent, previousRequire
  return { ok = ok, value = value, log = table.concat(log, "\n") }
end

local OWNERS = {
  { label = "no owner" },
  { label = "currentMod plain", current = "fp_plain" },
  { label = "currentMod net", current = "fp_net" },
  { label = "modRequire plain", require = "fp_plain" },
  { label = "modRequire true", require = true },
}
local CALLERS = {
  { label = "engine chunk", chunk = engineChunk },
  { label = "mod chunk", chunk = modChunk },
}

local cells, fastTaken = 0, 0
local hitCount = 0
local function onHit() hitCount = hitCount + 1 end
for _, generation in ipairs({ 1, 2, 3 }) do
  for _, dev in ipairs({ false, true }) do
    local run = T.sdk.loadMods({ "mods/fp_plain", "mods/fp_net" },
      { fs = T.sdk.memfs(FILES), generation = generation, dev = dev,
        data = generation == 3 and T.sdk.gen3Data() or {} })
    for _, owner in ipairs(OWNERS) do
      for _, caller in ipairs(CALLERS) do
        for _, name in ipairs(NAMES) do
          local label = ("gen%d dev=%s %s / %s / %s"):format(generation,
            tostring(dev), caller.label, owner.label, tostring(name))
          local thrower = name == "fp.Throws"
          if thrower then armThrower(); pcall(require, name) end
          Loader._setFastRequire(false)
          local slow = outcome(caller.chunk, name, owner)
          if thrower then armThrower(); pcall(require, name) end
          Loader._setFastRequire(true, onHit)
          local hitsBefore = hitCount
          local fast = outcome(caller.chunk, name, owner)
          Loader._setFastRequire(true)
          if hitCount > hitsBefore then
            fastTaken = fastTaken + 1
            T.check(not owner.current and not owner.require and fast.ok,
              label .. ": fast return only for a clean no-owner success")
            T.eq(fast.value, package.loaded[name], label .. ": fast value is the loaded one")
          end
          if thrower then
            T.check(not fast.ok, label .. ": a failed-load placeholder is never returned")
          end
          cells = cells + 1
          T.eq(fast.ok, slow.ok, label .. ": ok")
          T.eq(fast.value, slow.value, label .. ": value / error text")
          T.eq(fast.log, slow.log, label .. ": log lines")
        end
      end
    end
    run.release()
  end
end
T.check(cells > 500, "the matrix ran (" .. cells .. " cells)")
T.check(fastTaken > 20, "and the fast return actually ran (" .. fastTaken .. ")")

-- ------- the cases that must stay denied / served on the fast path

local run = T.sdk.loadMods({ "mods/fp_plain", "mods/fp_net" },
  { fs = T.sdk.memfs(FILES), data = {}, generation = 2 })
Loader._setFastRequire(true)
T.check(not outcome(modChunk, "io", {}).ok, "io stays denied to a mod chunk")
T.check(outcome(engineChunk, "io", {}).ok, "and stays available to the engine")
T.check(not outcome(modChunk, "socket", {}).ok,
  "socket stays denied to a mod with no network permission")
T.check(outcome(modChunk, "src.fp.Plain", {}).value == STUBS["src.fp.Plain"],
  "an ordinary loaded module is returned as-is")
local gameForMod = outcome(modChunk, "src.core.Game", {}).value
T.check(gameForMod ~= STUBS["src.core.Game"],
  "a Gen 1 module under Gen 2 is answered by the compat adapter for a mod")
T.eq(outcome(engineChunk, "src.core.Game", {}).value, STUBS["src.core.Game"],
  "while the engine keeps the real module")

-- ------- memo behaviour

Loader._setFastRequire(true)
T.eq(next(Loader._fastRequireMemo() or {}), nil, "forcing the toggle clears the memo")
outcome(engineChunk, "src.fp.Plain", {})
T.eq(Loader._fastRequireMemo()["src.fp.Plain"], true, "an undeniable name is memoized")
outcome(engineChunk, "io", {})
T.eq(Loader._fastRequireMemo()["io"], false, "a denied name is memoized as ineligible")
outcome(engineChunk, "src.core.Game", {})
T.eq(Loader._fastRequireMemo()["src.core.Game"], false,
  "a compat-served name is ineligible under Gen 2")

-- re-installing (a second loader) drops the memo
local run2 = T.sdk.loadMods({ "mods/fp_plain" },
  { fs = T.sdk.memfs(FILES), data = {}, generation = 2 })
T.eq(next(Loader._fastRequireMemo() or {}), nil, "a fresh load drops the memo")
run2.release()

-- the memo is per generation: Game is served under 2, plain under 1
outcome(engineChunk, "src.core.Game", {})
local run3 = T.sdk.loadMods({ "mods/fp_plain" },
  { fs = T.sdk.memfs(FILES), data = {}, generation = 1 })
outcome(engineChunk, "src.core.Game", {})
T.eq(Loader._fastRequireMemo()["src.core.Game"], true,
  "src.core.Game is eligible on a Gen 1 game")
run3.release()

-- endSession drops it too
Loader.endSession()
T.eq(next(Loader._fastRequireMemo() or {}), nil, "endSession drops the memo")

-- unloading is live: the memo never caches the loaded value itself
local run4 = T.sdk.loadMods({ "mods/fp_plain" },
  { fs = T.sdk.memfs(FILES), data = {}, generation = 1 })
package.loaded["src.fp.Plain"] = { replaced = true }
T.eq(outcome(engineChunk, "src.fp.Plain", {}).value, package.loaded["src.fp.Plain"],
  "a replaced package.loaded entry is returned, not a stale one")
package.loaded["src.fp.Plain"] = nil
T.check(not outcome(engineChunk, "src.fp.Plain", {}).ok,
  "an unloaded module takes the slow path and fails like require does")
run4.release()

Loader._setFastRequire(true)
for name, was in pairs(saved) do package.loaded[name] = was end
package.loaded["src.fp.Plain"] = nil
package.loaded["fp.Throws"], package.preload["fp.Throws"] = nil, nil

T.finish("require fast path")
