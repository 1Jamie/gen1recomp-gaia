local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_shoal_tide"

return function(game)
  local ok = true
  local function check(c, label)
    print((c and "PASS " or "FAIL ") .. label)
    if not c then ok = false end
  end
  local function finish()
    love.event.quit(ok and 0 or 1)
    U.wait(10)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  if not game.boot then return finish() end
  game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  check(session ~= nil, "field session")
  if not session then return finish() end

  local Map = require("src.core.game3.map")
  local Rtc = require("src.core.game3.rtc")
  local Rse = require("src.core.game3.rse")
  local Dataset = require("src.core.game3.dataset")
  local NativePack = require("src.import.gba.native_pack")
  local Extract = require("src.import.gba.extract_island1")
  local root = Extract.NATIVE_ROOT or ((Extract.CACHE_ROOT or "data/generated/gba") .. "/native")
  local P = game.data.maps.EM_ROUTE125 and "EM_" or "RU_"
  local ROOM = P .. "SHOAL_CAVE_LOW_TIDE_ENTRANCE_ROOM"

  local function layoutFile(name)
    local blob = Dataset.cache():read(root .. "/layouts/" .. name .. ".mid")
    return blob and NativePack.decodeMidLayout(blob)
  end
  local high = layoutFile(P .. "SHOAL_CAVE_HIGH_TIDE_ENTRANCE_ROOM")
  local low = layoutFile(ROOM)
  check(high ~= nil and low ~= nil, "both tide layouts are in the cache")
  if not (high and low) then return finish() end

  local function matches(ref)
    local def = game.data.maps[ROOM]
    local layout = def and def.midLayout
    if not layout then return -1 end
    local n = 0
    for y = 0, ref.trueHeight - 1 do
      for x = 0, ref.trueWidth - 1 do
        if layout:cellAt(x, y).mid == ref.cells[y * ref.width + x + 1].mid then n = n + 1 end
      end
    end
    return n
  end

  local function enterAt(hour, shot)
    Map.load(nil, game, P .. "ROUTE125", { x = 22, y = 20, facing = "up" })
    U.wait(20)
    Rtc.calcLocalTimeOffset(session, Rtc.calcLocalTime(session).days, hour, 0, 0)
    check(Rtc.calcLocalTime(session).hours == hour, ("local clock reads %02d:00"):format(hour))
    Map.load(nil, game, ROOM, { x = 20, y = 30, facing = "up" })
    for _ = 1, 60 do U.wait(1) end
    U.still(game, DIR .. "/" .. shot)
    return Rse.flag("FLAG_SYS_SHOAL_TIDE", session), matches(high), matches(low)
  end

  local cells = high.trueWidth * high.trueHeight
  local flag, hi, lo = enterAt(22, "01_shoal_entrance_2200_high_tide.png")
  print(("[driver] 22:00 flag=%s high=%d/%d low=%d/%d"):format(tostring(flag), hi, cells, lo, cells))
  check(flag == true, "22:00 sets FLAG_SYS_SHOAL_TIDE")
  check(hi == cells and lo < cells, "22:00 entrance room shows the high tide layout")

  flag, hi, lo = enterAt(4, "02_shoal_entrance_0400_low_tide.png")
  print(("[driver] 04:00 flag=%s high=%d/%d low=%d/%d"):format(tostring(flag), hi, cells, lo, cells))
  check(flag == false, "04:00 clears FLAG_SYS_SHOAL_TIDE")
  check(lo == cells and hi < cells, "04:00 entrance room shows the low tide layout")

  return finish()
end
