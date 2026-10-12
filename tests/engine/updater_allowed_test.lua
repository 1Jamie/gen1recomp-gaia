-- Tests for RomImporter's updaterAllowed gate across AppImage, Flatpak, and handhelds.
--   luajit tests/engine/updater_allowed_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local love_stub = require("tests.love_stub")
_G.love = love_stub

local Platform = require("src.core.Platform")
local RomImporter = require("src.import.RomImporter")

local updaterAllowed = RomImporter._updaterAllowed
check(type(updaterAllowed) == "function", "RomImporter._updaterAllowed is exported for tests")

local VERSION_KEY = "src.core.Version"

local function withVersion(engine, isDev, fn)
  local saved = package.loaded[VERSION_KEY]
  package.loaded[VERSION_KEY] = {
    engine = engine,
    isDev = function() return isDev end,
  }
  local ok, err = pcall(fn)
  package.loaded[VERSION_KEY] = saved
  if not ok then error(err, 0) end
end

local function withFused(isFused, fn)
  local oldFused = love.filesystem.isFused
  love.filesystem.isFused = function() return isFused end
  local ok, err = pcall(fn)
  love.filesystem.isFused = oldFused
  if not ok then error(err, 0) end
end

local function withEnv(key, val, fn)
  local old = os.getenv(key)
  -- luajit os.getenv does not reflect changes via os.setenv unless mocked or env wrapper used
  -- Test harness uses an env override table or temporarily hooks os.getenv
  local realGetenv = os.getenv
  os.getenv = function(k)
    if k == key then return val end
    return realGetenv(k)
  end
  local ok, err = pcall(fn)
  os.getenv = realGetenv
  if not ok then error(err, 0) end
end

-- 1. Fused packaged release (AppImage): allowed
withFused(true, function()
  withVersion("0.3.82", false, function()
    eq(updaterAllowed(), true, "fused release (AppImage) enables updater")
  end)
end)

-- 2. Unfused packaged release (Flatpak): allowed via Boot.canUpdateInPlace()
withFused(false, function()
  withVersion("0.3.82", false, function()
    eq(updaterAllowed(), true, "unfused release (Flatpak) enables updater via Boot.canUpdateInPlace()")
  end)
end)

-- 3. Dev checkout (0.0.0-dev) unfused: rejected
withFused(false, function()
  withVersion("0.0.0-dev", true, function()
    eq(updaterAllowed(), false, "unfused dev checkout disables updater")
  end)
end)

-- 4. Handheld environment marker: allowed even if unfused
withFused(false, function()
  withVersion("0.0.0-dev", true, function()
    withEnv("POKEPORT_HANDHELD", "1", function()
      eq(updaterAllowed(), true, "handheld port enables updater")
    end)
  end)
end)

-- 5. Autopilot override: disabled
withFused(true, function()
  withVersion("0.3.82", false, function()
    withEnv("POKEPORT_AUTOPILOT", "1", function()
      eq(updaterAllowed(), false, "autopilot suppresses updater")
    end)
  end)
end)

-- 6. Import only override: disabled
withFused(true, function()
  withVersion("0.3.82", false, function()
    withEnv("POKEPORT_IMPORT_ONLY", "1", function()
      eq(updaterAllowed(), false, "import-only suppresses updater")
    end)
  end)
end)

-- 7. Network not validated (e.g. Switch): disabled
withFused(true, function()
  withVersion("0.3.82", false, function()
    local oldNet = Platform.networkValidated
    Platform.networkValidated = function() return false end
    eq(updaterAllowed(), false, "invalidated network suppresses updater")
    Platform.networkValidated = oldNet
  end)
end)

T.finish("updater_allowed_test")
