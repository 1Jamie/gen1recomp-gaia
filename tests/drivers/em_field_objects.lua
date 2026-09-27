local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_field_objects"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_field_objects failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  try("new_game", function()
    game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  end)
  U.wait(30)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Objects = require("src.core.game3.objects")
  local OwSprites = require("src.core.game3.ow_sprites")
  local FieldEffects = require("src.core.game3.field_effects")
  local Doors = require("src.core.game3.doors")
  local Collision = require("src.core.game3.collision")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Field = require("src.core.game3.field")
  local Encounters = require("src.core.game3.encounters")
  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  local C = require("src.core.game3.constants").of("emerald")
  local T = Flags.forVersion("emerald")

  local session = Runtime.getSession()
  if not check(session ~= nil and session.version == "emerald", "Emerald session is live") then return finish() end
  Encounters.onStep = function() return nil end

  local played = {}
  local playSe = Audio.playSe
  Audio.playSe = function(id, ...)
    played[#played + 1] = id
    return playSe(id, ...)
  end

  local function mapNow()
    local s = Runtime.getSession()
    return s and s.map
  end

  local function settle(frames)
    for _ = 1, frames or 600 do
      local busy = Warp.isBusy() or (Message.isOpen and Message.isOpen())
      if not busy then break end
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      U.wait(1)
    end
  end

  local function goTo(mapId, x, y, facing)
    settle()
    local ok = try("Map.load " .. mapId, function()
      Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    end)
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.reset(x, y, facing)
    U.wait(40)
    return ok
  end

  local VARS = T.VAR_IDS
  Flags.setVar(Space.store, nil, VARS.VAR_LITTLEROOT_TOWN_STATE, 4)
  Flags.setVar(Space.store, nil, VARS.VAR_ROUTE101_STATE, 3)
  Flags.setFlag(Space.store, nil, T.IDS.FLAG_RESCUED_BIRCH, true)

  goTo("EM_LITTLEROOT_TOWN", 14, 12, "up")
  check(mapNow() == "EM_LITTLEROOT_TOWN", "Littleroot Town loads")
  local avatars = OwSprites.avatars()
  check(avatars ~= nil and OwSprites.playerGraphicsId(game) == OwSprites.avatarGraphicsId("NORMAL", false),
    "player draws Brendan from sPlayerAvatarGfxIds (gfx " .. tostring(OwSprites.playerGraphicsId(game)) .. ")")
  local kid = Objects.find(1)
  check(kid ~= nil and kid.movement == "WALK", "Littleroot kid (localId 1) wanders (" .. tostring(kid and kid.movement) .. ")")
  check(kid ~= nil and OwSprites.get(kid.graphicsId) ~= nil,
    "kid sprite is Emerald gfx " .. tostring(kid and kid.graphicsId))
  local momFlag = Objects._byId[4] and Objects._byId[4].flag or 752
  Flags.setFlag(Space.store, nil, momFlag, false)
  Objects.syncFlagVisibility(momFlag, false)
  U.wait(4)
  local mom = Objects.find(4)
  check(mom ~= nil and mom.visible and not mom.hidden, "Mom (localId 4) shows once her flag clears")
  local seen, start = {}, kid and (kid.cellX .. "," .. kid.cellY .. kid.facing)
  local changed = false
  for _ = 1, 420 do
    U.wait(1)
    if kid then
      local key = kid.cellX .. "," .. kid.cellY .. kid.facing
      if key ~= start then changed = true end
      if kid.moving and not seen.moving then
        seen.moving = true
        U.still(game, DIR .. "/01_littleroot_kid_walking.png")
      end
    end
  end
  check(changed, "Littleroot kid wandered (" .. tostring(start) .. " -> " .. tostring(kid and (kid.cellX .. "," .. kid.cellY .. kid.facing)) .. ")")
  U.still(game, DIR .. "/02_littleroot_mom_kid.png")
  Flags.setFlag(Space.store, nil, momFlag, true)
  Objects.syncFlagVisibility(momFlag, true, true)

  goTo("EM_LITTLEROOT_TOWN", 5, 9, "up")
  local entry = Doors.getDoorEntryAt("EM_LITTLEROOT_TOWN", 5, 8)
  check(entry and entry.tile == "littleroot" and entry.file == "littleroot__petalburg.rgba",
    "door manifest resolves the Littleroot door by tileset pair (" .. tostring(entry and entry.file) .. ")")
  for i = #played, 1, -1 do played[i] = nil end
  local shots = {}
  U.hold(game, "up", 1)
  for _ = 1, 120 do
    local a = Doors._activeAnim
    if a and a.tile and not shots[a.frame] and (a.frame == 1 or a.frame == 2) then
      shots[a.frame] = true
      U.still(game, DIR .. string.format("/03_door_open_frame%d.png", a.frame))
    end
    if mapNow() ~= "EM_LITTLEROOT_TOWN" then break end
    U.wait(1)
  end
  local sheet = Doors._sheets["littleroot__petalburg.rgba"]
  check(type(sheet) == "table" and sheet.frames == 3, "Littleroot door sheet loaded (3 frames)")
  check(shots[1] and shots[2], "door animated through frames 1 and 2")
  local door = false
  for _, id in ipairs(played) do if id == C:song("SE_DOOR") then door = true end end
  check(door, "door open played SE_DOOR by name (" .. tostring(C:song("SE_DOOR")) .. ")")
  settle()
  U.wait(30)
  check(mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F", "door warp lands in Brendan's house (" .. tostring(mapNow()) .. ")")

  goTo("EM_OLDALE_TOWN", 10, 10, "up")
  local n, drawn = 0, 0
  for _, eo in ipairs(Objects.forDraw()) do
    n = n + 1
    if OwSprites.get(eo.graphicsId) then drawn = drawn + 1 end
  end
  check(n >= 3 and drawn == n, string.format("Oldale NPCs draw Emerald sprites (%d/%d)", drawn, n))
  U.wait(60)
  U.still(game, DIR .. "/04_oldale_npcs.png")

  goTo("EM_ROUTE102", 15, 10, "left")
  local gx, gy
  local L = Collision._mapDef and Collision._mapDef.midLayout
  for y = 1, (L and L.height or 20) - 2 do
    for x = 1, (L and L.width or 20) - 2 do
      if not gx and Collision.isGrass(x, y) and not Collision.isGrass(x, y + 1)
          and Collision.canEnter(game, x, y + 1, {}) and not Objects.at(x, y + 1) and not Objects.at(x, y) then
        gx, gy = x, y
      end
    end
  end
  check(gx ~= nil, "found a tall grass cell on Route 102 (" .. tostring(gx) .. "," .. tostring(gy) .. ")")
  if gx then
    goTo("EM_ROUTE102", gx, gy + 1, "up")
    U.hold(game, "up", 1)
    U.wait(7)
    local fx = FieldEffects._fx
    check(fx and fx.cx == gx and fx.cy == gy, "stepping into grass starts the tall grass effect")
    check(type(FieldEffects._sheets.tall_grass) == "table", "tall grass sheet loaded from field_effects/objects.lua")
    U.still(game, DIR .. "/05_route102_tall_grass_rustle.png")
    U.wait(30)
    U.still(game, DIR .. "/06_route102_in_grass.png")
  end

  Flags.setFlag(Space.store, nil, T.IDS.FLAG_SYS_B_DASH, true)
  goTo("EM_ROUTE101", 10, 10, "up")
  local zig = Objects.find(4)
  local zx, zy, stepped = zig and zig.cellX, zig and zig.cellY, 0
  for _ = 1, 40 do
    U.wait(1)
    if zig and zig.moving then stepped = stepped + 1 end
  end
  check(zig and zig.movement == "IN_PLACE" and zig.facing == "left" and stepped > 20
    and zig.cellX == zx and zig.cellY == zy,
    string.format("Route 101 Zigzagoon jogs in place left (%s %s, %d moving frames)",
      tostring(zig and zig.movement), tostring(zig and zig.facing), stepped))
  check(Player.canDash(), "B-dash allowed on Route 101 with FLAG_SYS_B_DASH")
  game.input.state.b = true
  U.hold(game, "up", 5)
  local runFrame = Player.runPose and Player.runPose()
  local sprite = OwSprites.get(OwSprites.playerGraphicsId(game))
  local frame = sprite and OwSprites.pose(sprite, Player.facing, 1, Player.stepFlip, { running = runFrame })
  check(Player.running and Player.stepFrames == 8, "running step is 8 frames")
  check(frame == 14 or frame == 15 or frame == 10, "Emerald run north frame (" .. tostring(frame) .. ")")
  U.still(game, DIR .. "/07_route101_running.png")
  game.input.state.b = false
  U.wait(20)

  session.party = {}
  local Party = require("src.core.game3.party")
  Party.giveMon(session, C:id("species", "SPECIES_TREECKO"), 5)
  local trainerKey
  goTo("EM_ROUTE102", 25, 13, "down")
  local spotted, approached, started
  for _ = 1, 400 do
    U.wait(1)
    local t = Objects.find(3)
    for _, a in ipairs(FieldEffects._anims) do
      if a.kind == "emote" and a.rse and not spotted and a.timer >= 12 then
        spotted = true
        U.still(game, DIR .. "/08_route102_trainer_exclamation.png")
      end
    end
    if t and t.moving and spotted and not approached then
      approached = true
      U.still(game, DIR .. "/09_route102_trainer_approach.png")
    end
    trainerKey = trainerKey or (Space.vm and Space.vm:isRunning() and Space.vm._scriptKey)
    if trainerKey and not started then
      started = true
      U.wait(30)
      U.still(game, DIR .. "/10_route102_trainer_intro.png")
      break
    end
  end
  local tr = Objects.find(3)
  check(spotted, "Route 102 trainer (localId 3) shows the Emerald ! icon")
  check(approached, "trainer walks toward the player")
  check(tr and tr.cellY == 14, "trainer stops next to the player (" .. tostring(tr and tr.cellY) .. ")")
  check(trainerKey == tr.scriptKey, "trainer script starts (" .. tostring(trainerKey) .. " want " .. tostring(tr and tr.scriptKey) .. ")")
  if Space.vm and Space.vm:isRunning() then
    Space.vm:halt(true)
    Field.unlock()
  end

  finish()
end
