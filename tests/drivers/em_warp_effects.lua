local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_warp_effects"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_warp_effects failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Space = require("src.core.game3.scripting.space")
  local Collision = require("src.core.game3.collision")
  local Field = require("src.core.game3.field")
  local MB = require("src.core.game3.mb")
  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end

  local playedSe = {}
  local origPlaySe = Audio.playSe
  Audio.playSe = function(id, ...)
    playedSe[#playedSe + 1] = SE.resolve(id)
    return origPlaySe(id, ...)
  end
  local function sawSe(name)
    for _, v in ipairs(playedSe) do if v == SE[name] then return true end end
    return false
  end

  local function mapNow() local s = Runtime.getSession(); return s and s.map end

  local function idle()
    return not Warp.isBusy() and not Field.locked and not (Space.vm and Space.vm:isRunning())
      and not (Message.isOpen and Message.isOpen())
  end

  local function settle(frames)
    for _ = 1, frames or 900 do
      if idle() then return true end
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      U.wait(1)
    end
    return idle()
  end

  local function place(mapId, x, y, facing)
    settle()
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    local s = Runtime.getSession()
    s.x, s.y, s.facing = x, y, facing or "down"
    Field.unlock()
    U.wait(20)
    settle()
  end

  local DIRS = { { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" } }

  local function warpWithBehavior(mapId, behName)
    place(mapId, 1, 1)
    local def = Map.currentDef()
    for _, w in ipairs(def and def.warps or {}) do
      local x, y = tonumber(w.x), tonumber(w.y)
      if Collision.behavior(x, y) == MB.id(behName) then
        for _, d in ipairs(DIRS) do
          local ax, ay = x + d[1], y + d[2]
          if Collision.isWalkable(ax, ay) and Collision.behavior(ax, ay) ~= MB.id(behName) then
            return x, y, ax, ay, d[3]
          end
        end
      end
    end
    return nil
  end

  local function stepOnto(mapId, behName, label)
    local wx, wy, ax, ay, dir = warpWithBehavior(mapId, behName)
    if not check(wx ~= nil, label .. ": warp cell with " .. behName) then return nil end
    place(mapId, ax, ay, dir)
    playedSe = {}
    local fromMap = mapNow()
    U.hold(game, dir, 16)
    local sawInvisible, sawOffset, sawPan = false, false, false
    for _ = 1, 1200 do
      if not Player.isVisible() then sawInvisible = true end
      if (Player.spriteYOffset or 0) ~= 0 then sawOffset = true end
      local FieldView = package.loaded["src.core.game3.field_view"]
      if FieldView and (FieldView.cameraPanY or 0) ~= 0 then sawPan = true end
      if idle() and (mapNow() ~= fromMap or not Warp.isBusy()) and U.frame() then
        if mapNow() ~= fromMap or (Player.cellX ~= ax or Player.cellY ~= ay) then break end
      end
      U.wait(1)
    end
    settle()
    return { from = fromMap, to = mapNow(), x = Player.cellX, y = Player.cellY, invisible = sawInvisible,
      offset = sawOffset, pan = sawPan, wx = wx, wy = wy }
  end

  local r = stepOnto("EM_LAVARIDGE_TOWN_GYM_1F", "LAVARIDGE_GYM_1F_WARP", "Lavaridge 1F")
  if r then
    check(r.to == "EM_LAVARIDGE_TOWN_GYM_B1F", "Lavaridge 1F warp sinks to B1F (" .. tostring(r.to) .. ")")
    check(sawSe("SE_LAVARIDGE_FALL_WARP"), "SE_LAVARIDGE_FALL_WARP plays while sinking")
    check(r.invisible, "the player disappears into the ash")
    check(r.offset, "B1F arrival drops the player in from above (FieldCB_FallWarpExit)")
    U.shot(game, DIR .. "/01_lavaridge_b1f_arrival.png")
  end

  r = stepOnto("EM_LAVARIDGE_TOWN_GYM_B1F", "LAVARIDGE_GYM_B1F_WARP", "Lavaridge B1F")
  if r then
    check(r.to == "EM_LAVARIDGE_TOWN_GYM_1F", "Lavaridge B1F warp launches to 1F (" .. tostring(r.to) .. ")")
    check(sawSe("SE_M_EXPLOSION") and sawSe("SE_M_DIG"), "SE_M_EXPLOSION on launch, SE_M_DIG on pop-out")
    check(r.pan, "camera shakes during the launch")
    check(r.offset, "the player rises off screen")
    U.shot(game, DIR .. "/02_lavaridge_1f_popout.png")
  end

  r = stepOnto("EM_MOSSDEEP_CITY_GYM", "MOSSDEEP_GYM_WARP", "Mossdeep Gym")
  if r then
    check(r.to == "EM_MOSSDEEP_CITY_GYM" and (r.x ~= r.wx or r.y ~= r.wy), string.format(
      "Mossdeep gym pad warps within the gym (%s %d,%d)", tostring(r.to), r.x, r.y))
    check(sawSe("SE_WARP_IN") and sawSe("SE_WARP_OUT"), "SE_WARP_IN / SE_WARP_OUT")
    U.shot(game, DIR .. "/03_mossdeep_gym_pad.png")
  end

  local aqua = nil
  for _, id in ipairs({ "EM_AQUA_HIDEOUT_B1F", "EM_AQUA_HIDEOUT_B2F" }) do
    if not aqua and warpWithBehavior(id, "AQUA_HIDEOUT_WARP") then aqua = id end
  end
  r = aqua and stepOnto(aqua, "AQUA_HIDEOUT_WARP", "Aqua Hideout")
  check(aqua ~= nil, "an Aqua Hideout map has AQUA_HIDEOUT_WARP pads")
  if r then
    check(r.to ~= nil and (r.to ~= r.from or r.x ~= r.wx or r.y ~= r.wy), "Aqua Hideout pad teleports (" .. tostring(r.to) .. ")")
    check(sawSe("SE_WARP_IN") and sawSe("SE_WARP_OUT"), "teleport tile plays SE_WARP_IN then SE_WARP_OUT")
    check(r.offset, "arrival spins in from above (DoPlayerSpinEntrance)")
    U.shot(game, DIR .. "/04_aqua_hideout_pad.png")
  end

  local pyre = nil
  for _, id in ipairs({ "EM_MT_PYRE_2F", "EM_MT_PYRE_3F", "EM_MT_PYRE_4F", "EM_MT_PYRE_5F", "EM_MT_PYRE_6F" }) do
    if not pyre and warpWithBehavior(id, "MT_PYRE_HOLE") then pyre = id end
  end
  check(pyre ~= nil, "a Mt. Pyre floor has MT_PYRE_HOLE")
  r = pyre and stepOnto(pyre, "MT_PYRE_HOLE", "Mt. Pyre")
  if r then
    check(r.to ~= r.from, "Mt. Pyre hole drops to the floor below (" .. tostring(r.from) .. " -> " .. tostring(r.to) .. ")")
    check(sawSe("SE_FALL"), "SE_FALL plays")
    check(r.invisible and r.offset, "player vanishes then falls in from above")
    U.shot(game, DIR .. "/05_mt_pyre_hole.png")
  end

  Audio.playSe = origPlaySe
  finish()
end
