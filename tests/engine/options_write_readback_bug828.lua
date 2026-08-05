-- #828: launcher settings "reset" on Android and Steam Deck, with nothing in
-- the log.  Every options write is a WHOLE-FILE rewrite out of the caller's
-- table (src/core/SaveData.lua saveOptions), so a filesystem that reports a
-- successful write without the bytes surviving -- an external-storage volume
-- that went away mid-session (conf.lua sets t.externalstorage on Android), a
-- read-only or full save dir -- is indistinguishable from "the launcher never
-- saved at all".  saveOptions therefore reads the file back and fails loudly.
--
-- This suite pins that contract against injected filesystem stubs, the same
-- { getInfo, read, write, remove } shape tests/engine/save_slots.lua and
-- tests/engine/save_file_io_tests.lua use.  It is ROM-free (T2 engine tier).
--
-- What it does NOT do: prove #828 is fixed.  The launcher -> options.lua ->
-- bootGame chain already round-trips correctly on desktop, so the readback is
-- instrumentation for the two platforms that report the loss, and the real
-- verification is a platform run (see the issue).  What is testable here is
-- that a silent no-op write is now reported instead of swallowed.
--   luajit tests/engine/options_write_readback_bug828.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Logger = require("src.core.Logger")
local SaveData = require("src.core.SaveData")

local OPTIONS = "options.lua"

-- An in-memory love.filesystem stub.  `mode` decides what write() does with
-- the bytes AFTER reporting success, which is the whole point of the suite:
--   "honest"    -- stores them (a working save dir)
--   "drop"      -- reports true, stores nothing (the volume vanished)
--   "truncate"  -- reports true, stores a short prefix (a full save dir)
--   "fail"      -- reports false plus an error string (the pre-existing path)
local function memfs(mode)
  local files = {}
  return {
    files = files,
    write = function(path, content)
      if mode == "fail" then return false, "no space left on device" end
      if mode == "drop" then return true end
      if mode == "truncate" then
        files[path] = tostring(content):sub(1, 16)
        return true
      end
      files[path] = content
      return true
    end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] ~= nil then return { type = "file" } end
      return nil
    end,
  }
end

-- SaveData.persistFs hands an injected fs straight back only when it differs
-- from love.filesystem, so the suite never touches the real save directory.
local function logged(pattern)
  for i = #Logger.history, 1, -1 do
    if Logger.history[i]:find(pattern, 1, true) then return Logger.history[i] end
  end
  return nil
end

-- ---- the write that lands: unchanged success contract

local fs = memfs("honest")
local saved = SaveData.saveOptions({ battleLayout = "wide" }, fs)
check(saved ~= nil, "a write that lands returns the merged options table")
eq(saved and saved.battleLayout, "wide", "the caller's key survives the merge")
eq(saved and saved.textSpeed ~= nil, true, "defaults are filled in around it")
check(fs.files[OPTIONS] ~= nil, "options.lua is written to the injected fs")

local loaded = SaveData.loadOptions(fs)
eq(loaded and loaded.battleLayout, "wide",
  "loadOptions reads back what saveOptions wrote (the launcher -> game hop)")

-- ---- the write that silently does not land: the #828 failure mode

local dropMark = #Logger.history
local dropped = SaveData.saveOptions({ battleLayout = "wide" }, memfs("drop"))
eq(dropped, nil, "a write that reports success but stores nothing returns nil")
check(logged("options save did not land"),
  "the vanished write is logged, so the next Android report can carry it")
check(#Logger.history > dropMark, "a log line was actually emitted")

-- ---- a partial write is just as lost, and just as loud

local truncated = SaveData.saveOptions({ battleLayout = "wide" }, memfs("truncate"))
eq(truncated, nil, "a truncated write is treated as a failed write")
check(logged("options save did not land"), "the truncated write is logged too")

-- ---- the pre-existing honest failure still behaves exactly as before

local failMark = #Logger.history
local failed = SaveData.saveOptions({ battleLayout = "wide" }, memfs("fail"))
eq(failed, nil, "a write that returns false still returns nil")
check(logged("options save failed"),
  "the false-return path keeps its own distinct log line")
check(#Logger.history > failMark, "the false-return path still logs")

-- A dropped write must not be reported through the false-return message:
-- the two are different diagnoses and the platform reports need to tell
-- them apart.
local last = Logger.history[#Logger.history]
check(last and last:find("options save failed", 1, true) ~= nil,
  "the last failure logged is the false-return one, not the readback one")

T.finish("options_write_readback_bug828")
