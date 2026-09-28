local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_warp_arrow"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " warp_arrow failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local DELTA = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
local SIDE = { down = "left", up = "left", left = "up", right = "up" }

return function(game)
  local ok, err = xpcall(function()
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
    U.wait(240)

    local Runtime = require("src.core.game3.runtime")
    local Map = require("src.core.game3.map")
    local Player = require("src.core.game3.player")
    local Collision = require("src.core.game3.collision")
    local WarpArrow = require("src.core.game3.warp_arrow")
    local session = Runtime.getSession()
    if not check(session ~= nil, "new game reached the field") then return end
    local emerald = session.version == "emerald"
    local center = emerald and "EM_OLDALE_TOWN_POKEMON_CENTER_1F" or "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"
    local def = game.data.maps[center]
    if not check(def ~= nil, center .. " exists") then return end
    Map.load(nil, game, center, { x = 7, y = 4, facing = "down" })
    U.wait(30)

    local mat, dir
    for _, w in ipairs(def.warps or {}) do
      local d = Collision.arrowWarpDir(Collision.behavior(w.x, w.y))
      if d then mat, dir = w, d break end
    end
    if not check(mat ~= nil, "arrow warp mat found") then return end
    print("[driver] mat", mat.x, mat.y, dir)

    local d = DELTA[dir]
    local sx, sy = mat.x - d[1], mat.y - d[2]
    Player.moving, Player.progress = false, 0
    Player.cellX, Player.cellY, Player.targetX, Player.targetY = sx, sy, sx, sy
    Player.px, Player.py, Player.facing = sx * 16, sy * 16, dir
    session.x, session.y, session.facing = sx, sy, dir
    U.wait(10)
    check(not WarpArrow._state.visible, "arrow hidden one cell before the mat")

    U.tap(game, dir)
    local shownMid = false
    for _ = 1, 40 do
      if Player.moving and WarpArrow._state.visible then shownMid = true end
      if not Player.moving and Player.cellX == mat.x and Player.cellY == mat.y then break end
      U.wait(1)
    end
    check(Player.cellX == mat.x and Player.cellY == mat.y, "stepped onto the mat")
    check(shownMid, "arrow shows while stepping onto the mat")
    local s = WarpArrow._state
    check(s.visible and s.cx == mat.x + d[1] and s.cy == mat.y + d[2], "arrow sits one cell past the mat")
    local f0 = s.seq and s.seq[s.step][1]
    U.wait(34)
    local f1 = s.seq and s.seq[s.step][1]
    check(f0 ~= nil and f1 ~= nil and f0 ~= f1, "arrow blinks between its two frames")
    U.shot(game, DIR .. "/" .. (emerald and "em" or "fr") .. "_01_arrow_on_mat.png")

    U.tap(game, SIDE[dir])
    U.wait(12)
    check(Player.cellX == mat.x and Player.cellY == mat.y, "turn stayed on the mat")
    check(not WarpArrow._state.visible, "arrow hides when facing away")
    U.shot(game, DIR .. "/" .. (emerald and "em" or "fr") .. "_02_arrow_hidden.png")

    U.tap(game, dir)
    U.wait(12)
    check(WarpArrow._state.visible, "arrow returns when facing the exit again")
  end, debug.traceback)
  if not ok then check(false, "driver error: " .. tostring(err)) end
  finish()
end
