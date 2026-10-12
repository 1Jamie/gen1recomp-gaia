local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("game3_lavaridge_ash_warp_2876")

local DIRS = { { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" } }

return function(game)
  if not F.boot(game) then return F.finish() end
  F.givePartyAndRepel()
  local Runtime = require("src.core.game3.runtime")
  local version = Runtime.getSession().version
  local prefix = ({ emerald = "EM", ruby = "RU", sapphire = "SA" })[version]
  if not F.check(prefix ~= nil, "ashwarp2876 RSE version") then return F.finish() end
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Collision = require("src.core.game3.collision")
  local MB = require("src.core.game3.mb")
  local FxRse = require("src.core.game3.field_effects_rse")
  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")

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

  local function warpWithBehavior(mapId, behName)
    F.goTo(game, mapId, 1, 1, "down")
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

  local function waitFor(pred, frames)
    for _ = 1, frames or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end

  local function settle()
    waitFor(function() return not Warp.isBusy() and not Player.moving end, 900)
    F.settle(game)
  end

  local function stepOnto(tag, mapId, behName, effectName, expectTo)
    local label = "ashwarp2876 " .. version .. " " .. tag
    local wx, wy, ax, ay, dir = warpWithBehavior(mapId, behName)
    if not F.check(wx ~= nil, label .. " warp_cell_" .. behName) then return end
    F.goTo(game, mapId, ax, ay, dir, { wait = 20 })
    playedSe = {}
    local fromMap = mapNow()
    U.hold(game, dir, 16)
    local started = waitFor(function() return FxRse.isActive(effectName) end, 300)
    F.check(started, label .. " " .. effectName .. "_spawned")
    local sheet
    for _, e in ipairs(FxRse._list) do if e.effectName == effectName then sheet = e.name end end
    print("[driver] " .. label .. " sheet=" .. tostring(sheet))
    F.check(sheet ~= nil and FxRse.objectNameAt(effectName == "FLDEFF_ASH_LAUNCH" and 33 or 32, "") == sheet,
      label .. " sheet_from_slot (" .. tostring(sheet) .. ")")
    U.wait(6)
    F.check(F.shot(game, "2876_" .. version .. "_" .. tag .. "_effect.png", true), label .. " effect_capture")
    local arrived = waitFor(function() return mapNow() == expectTo end, 1200)
    F.check(arrived, label .. " arrives_" .. expectTo .. " (" .. tostring(mapNow()) .. ")")
    if arrived and tag == "b1f_launch" then
      local popped = waitFor(function() return FxRse.isActive("FLDEFF_ASH_PUFF") end, 600)
      F.check(popped, label .. " exit_pop_out_of_ash")
      waitFor(function() return Player.isVisible() end, 60)
      U.wait(2)
      F.check(F.shot(game, "2876_" .. version .. "_" .. tag .. "_exit_popout.png", true), label .. " exit_capture")
    end
    settle()
    return fromMap
  end

  stepOnto("1f_sink", prefix .. "_LAVARIDGE_TOWN_GYM_1F", "LAVARIDGE_GYM_1F_WARP", "FLDEFF_ASH_PUFF",
    prefix .. "_LAVARIDGE_TOWN_GYM_B1F")
  F.check(sawSe("SE_LAVARIDGE_FALL_WARP"), "ashwarp2876 " .. version .. " 1f_sink SE_LAVARIDGE_FALL_WARP")
  stepOnto("b1f_launch", prefix .. "_LAVARIDGE_TOWN_GYM_B1F", "LAVARIDGE_GYM_B1F_WARP", "FLDEFF_ASH_LAUNCH",
    prefix .. "_LAVARIDGE_TOWN_GYM_1F")
  F.check(sawSe("SE_M_EXPLOSION") and sawSe("SE_M_DIG"), "ashwarp2876 " .. version .. " b1f_launch SE_M_EXPLOSION_and_SE_M_DIG")
  F.finish()
end
