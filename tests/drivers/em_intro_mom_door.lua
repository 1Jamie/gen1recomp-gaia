local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_intro_mom_door", "/tmp/em_intro_mom_door")
  local check = d.check
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return d.finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(30)
  local Doors = require("src.core.game3.doors")
  local Audio = require("src.core.game3.audio")
  local opens, ses = {}, {}
  local origOpen, origSe = Doors.open, Audio.playSe
  Doors.open = function(mapId, x, y, ...)
    opens[#opens + 1] = string.format("%s(%s,%s)", tostring(mapId), tostring(x), tostring(y))
    return origOpen(mapId, x, y, ...)
  end
  Audio.playSe = function(se, ...)
    ses[#ses + 1] = tostring(se)
    return origSe(se, ...)
  end
  local shots = 0
  for _ = 1, 3000 do
    if S.mapNow() == "EM_LITTLEROOT_TOWN" and #opens > 0 and shots < 3 then
      shots = shots + 1
      U.wait(4)
      d.shot(game, "door_" .. shots)
    end
    if require("src.ui.game3.message").isOpen() then break end
    if S.mapNow() == "EM_INSIDE_OF_TRUCK" then U.hold(game, "right", 8) else U.wait(1) end
  end
  print("DOOR opens: " .. table.concat(opens, " "))
  print("DOOR se: " .. table.concat(ses, " "))
  check(#opens > 0 and opens[1]:find("%(1?%d,%d+%)") ~= nil, "mom door opened at real map coords")
  return d.finish()
end
