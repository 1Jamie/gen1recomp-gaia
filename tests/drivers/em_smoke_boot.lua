local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_smoke"

return function(game)
  local ok = true
  local function check(c, label) print((c and "PASS " or "FAIL ") .. label) if not c then ok = false end end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  U.wait(120)
  print("[driver] boot phase " .. tostring(game.boot and game.boot.phase))
  U.shot(game, DIR .. "/em_smoke_01_boot.png")
  local okNew, err = pcall(function() game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 }) end)
  check(okNew, "new_game action " .. tostring(err))
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  check(session ~= nil, "field session exists")
  if session then print("[driver] map " .. tostring(session.mapId) .. " at " .. tostring(session.x) .. "," .. tostring(session.y)) end
  U.shot(game, DIR .. "/em_smoke_02_field.png")
  local okL, errL = pcall(function()
    local Map = require("src.core.game3.map")
    Map.load(nil, game, "EM_LITTLEROOT_TOWN", { x = 10, y = 10, facing = "down" })
  end)
  check(okL, "load Littleroot " .. tostring(errL))
  U.wait(60)
  U.shot(game, DIR .. "/em_smoke_03_littleroot.png")
  love.event.quit(ok and 0 or 1)
end
