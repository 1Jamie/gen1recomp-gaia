local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_field_move_anim_2868"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. "hm2868 " .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS " or "FAIL ") .. "hm2868 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local CASES = {
  rse = {
    { move = "CUT", gfx = "CUT_TREE", map = "Route116", frames = 6 },
    { move = "ROCK_SMASH", gfx = "ROCK_SMASH_ROCK", map = "Route111", frames = 8 },
  },
  frlg = {
    { move = "CUT", gfx = "CUT_TREE", map = "Route2", frames = 6 },
    { move = "ROCK_SMASH", gfx = "ROCK_SMASH_ROCK", map = "CeruleanCave_1F", frames = 8 },
  },
}

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.phase == "boot" and game.boot ~= nil, "boot_ready") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "HMS", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local FieldMoves = require("src.core.game3.field_moves")
  local ShowMon = require("src.core.game3.field_move_show_mon")
  local Field = require("src.core.game3.field")
  local Battle = require("src.core.game3.battle")
  local MapCatalog = require("src.import.gba.map_catalog")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field_session_ready") then return finish() end
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end
  Field.tryRockSmashEncounter = function() end

  local version = session.version
  local family = require("src.core.game3.profile").family(session) == "rse" and "rse" or "frlg"
  local C = require("src.core.game3.constants").of(version)
  session.party = {}
  Party.giveMon(session, C:require("species", family == "rse" and "SPECIES_ZIGZAGOON" or "SPECIES_RATTATA"), 50)
  local mon = session.party[1]
  mon.moves = { C:require("moves", "MOVE_CUT"), C:require("moves", "MOVE_ROCK_SMASH"), 0, 0 }
  mon.pp = { 30, 15, 0, 0 }

  local function halt()
    if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
    Field.unlock()
  end

  local function place(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    Player.cellX, Player.cellY, Player.facing = x, y, facing
    Player.px, Player.py = x * 16, y * 16
    U.wait(40)
    halt()
  end

  local function findTarget(gfx)
    for _, lid in ipairs(Objects._order) do
      local eo = Objects._byId[lid]
      if eo and tonumber(eo.graphicsId) == gfx and eo.visible and not eo.hidden and not eo.invisible then
        for dir, d in pairs(DELTA) do
          local sx, sy = eo.cellX - d[1], eo.cellY - d[2]
          if Collision.isWalkable(sx, sy) and not Objects.at(sx, sy) then return eo, sx, sy, dir end
        end
      end
    end
  end

  for _, case in ipairs(CASES[family]) do
    local tag = version .. "_" .. case.move:lower()
    Flags.setFlag(Space.store, nil, FieldMoves.badgeFlag(case.move), true)
    local mapId = MapCatalog.pretToEngine(case.map)
    place(mapId, 5, 5, "down")
    local gfx = FieldMoves.GFX_IDS[case.gfx]
    local eo, sx, sy, dir = findTarget(gfx)
    if check(eo ~= nil, tag .. " target object found on " .. tostring(mapId)) then
      place(mapId, sx, sy, dir)
      eo = Objects.find(eo.localId)
      local lid = eo.localId
      local shownMon, frames, toggles, lastInvisible = 0, {}, 0, false
      local shotMon, shotBreak, shotFlicker = false, false, false
      local removed = false
      for i = 1, 1800 do
        if ShowMon.isActive() then
          shownMon = shownMon + 1
          if shownMon == 64 and not shotMon then
            shotMon = U.still(game, DIR .. "/2868_" .. tag .. "_01_show_mon.png")
          end
        elseif shownMon == 0 and i % 6 == 0 then
          U.tap(game, "a")
        end
        local cur = Objects.find(lid)
        if cur and cur.customFrame ~= nil and frames[#frames] ~= cur.customFrame then
          frames[#frames + 1] = cur.customFrame
          if cur.customFrame == 2 and not shotBreak then
            shotBreak = U.still(game, DIR .. "/2868_" .. tag .. "_02_breaking.png")
          end
        end
        if cur and (cur.invisible == true) ~= lastInvisible then
          toggles = toggles + 1
          lastInvisible = cur.invisible == true
          if toggles == 5 and not shotFlicker then
            shotFlicker = U.still(game, DIR .. "/2868_" .. tag .. "_03_flicker.png")
          end
        end
        if shownMon > 0 and (not cur or cur.hidden or not cur.visible) then removed = true break end
        if Battle.isActive() then break end
        U.wait(1)
      end
      print(("hm2868 %s showMonFrames=%d frames=%s invisibleToggles=%d"):format(tag, shownMon,
        table.concat(frames, ","), toggles))
      check(shownMon > 30, tag .. " field move show-mon cut-in played")
      check(table.concat(frames, ",") == "0,1,2,3", tag .. " obstacle sprite steps frames 0..3")
      check(toggles >= 30, tag .. " obstacle flickers before removal (" .. toggles .. " toggles)")
      check(removed, tag .. " obstacle removed")
      check(shotMon and shotBreak and shotFlicker, tag .. " shots captured")
    end
    U.wait(30)
    halt()
  end
  finish()
end
