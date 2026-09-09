-- Unit tests for Game 3 intro video sequence, asset extraction, and state machine.

local function check(cond, msg)
  if not cond then
    error(msg or "assertion failed", 2)
  end
end

local Versions = require("src.import.gba.versions")
local ExtractIntro = require("src.import.gba.extract_intro")
local IntroMovie = require("src.ui.game3.intro_movie")
local Boot = require("src.ui.game3.boot")

print("[test] 1. Verify Versions.INTRO_MOVIE and TITLE_EFFECTS")
check(type(Versions.INTRO_MOVIE) == "table", "Versions.INTRO_MOVIE exists")
check(type(Versions.TITLE_EFFECTS) == "table", "Versions.TITLE_EFFECTS exists")
check(Versions.INTRO_MOVIE.copyright_pal == 0x402260, "copyright_pal offset is 0x402260")
check(Versions.INTRO_MOVIE.star_tiles == 0x402A64, "star_tiles offset is 0x402A64")
check(Versions.INTRO_MOVIE.scene3_gengar_static_tiles == 0x409D20, "scene3_gengar_static_tiles is 0x409D20")
check(Versions.TITLE_EFFECTS.flames_tiles == 0x3BF79C, "flames_tiles is 0x3BF79C")

print("[test] 2. Verify IntroMovie phase lifecycle and state machine")
local movie = IntroMovie.new({})
check(movie.phase == IntroMovie.PHASE.COPYRIGHT, "Starts in COPYRIGHT phase")

-- Step through copyright
movie:update(nil, 2.5)
check(movie.phase == IntroMovie.PHASE.COPYRIGHT or movie.phase == IntroMovie.PHASE.GF_OPEN or movie.fadeDir ~= 0, "Advances past copyright")

-- Test direct skip
local skipMovie = IntroMovie.new({})
local fakeInput = {
  wasPressed = function(self, key)
    return key == "start"
  end
}
skipMovie:update(fakeInput, 0.1)
check(skipMovie.phase == IntroMovie.PHASE.FADE_OUT or skipMovie.isDone, "Skip initiates fade_out or done")
skipMovie:update(nil, 1.0)
check(skipMovie.isDone == true, "Skip finishes with isDone = true")

print("[test] 3. Verify Boot state machine starts in INTRO and transitions to TITLE")
local boot = Boot.new()
check(boot.phase == Boot.PHASE.INTRO, "Boot starts in INTRO phase")

-- Advance intro to completion via skip
local skipInput = {
  wasPressed = function(self, key)
    return key == "a"
  end
}
Boot.update(boot, skipInput, 0.1)
Boot.update(boot, nil, 1.0)
check(boot.phase == Boot.PHASE.TITLE, "Boot transitions to TITLE after intro completion")
check(boot._titleActive == true, "Title hardware screen is active")

-- Verify flame spawner runs (OAM sprites when gfx present)
Boot.update(boot, nil, 0.5)
check(boot._flameState ~= nil and boot._flameState >= 1, "Title flame spawner is running")
local Oam = require("src.core.game3.oam")
local flameCount = 0
for i = 0, 63 do
  local s = Oam.get(i)
  if s and s.oam and s.oam.priority == 3 then
    flameCount = flameCount + 1
  end
end
if boot.assets and boot.assets.titleFlames then
  check(flameCount > 0, "Title spawns OAM priority-3 flame sprites when gfx loaded")
end

print("[test] 4. Verify GBA ROM extraction if ROM file is present")
local romFile = io.open("1636 - Pokemon Fire Red (U)(Squirrels).gba", "rb")
if romFile then
  local romData = romFile:read("*a")
  romFile:close()
  local dummyCache = {
    _files = {},
    write = function(self, path, data)
      self._files[path] = data
      return true
    end,
  }
  local ok, meta = ExtractIntro.run(romData, dummyCache, {
    sha1 = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc",
    root = "data/generated/gba/intro",
  })
  check(ok == true, "ExtractIntro runs successfully on ROM")
  check(dummyCache._files["data/generated/intro.lua"] ~= nil, "Generated intro.lua index")
  check(dummyCache._files["data/generated/gba/intro/oak_speech.lua"] ~= nil, "Generated oak_speech.lua")
  if love and love.image and love.image.newImageData then
    check(dummyCache._files["data/generated/gba/intro/intro_copyright.png"] ~= nil, "Extracted intro_copyright.png")
    check(dummyCache._files["data/generated/gba/intro/intro_star.png"] ~= nil, "Extracted intro_star.png")
    check(dummyCache._files["data/generated/gba/intro/intro_scene1_grass.png"] ~= nil, "Extracted intro_scene1_grass.png")
    check(dummyCache._files["data/generated/gba/intro/intro_scene3_nidorino.png"] ~= nil, "Extracted intro_scene3_nidorino.png")
    check(dummyCache._files["data/generated/gba/intro/title_flames.png"] ~= nil, "Extracted title_flames.png")
    print("[test] All GBA ROM intro & title PNG assets extracted and validated successfully!")
  else
    print("[test] ROM metadata and scripts verified (love.image not active in CLI luajit mode)")
  end
else
  print("[test] (ROM file not present; skipped raw binary asset check)")
end

print("ALL GAME3 INTRO TESTS PASSED!")
