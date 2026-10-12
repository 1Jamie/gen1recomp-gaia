local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local Center = require("src.world.gen2.UnionCenter2F")
local Room = require("src.world.gen2.UnionRoomMap")
local Origin = require("src.online.union.Origin")
local Gen2Save = require("src.core.gen2.Save")
local GameVersion = require("src.core.GameVersion")

return function(game)
  local fails = 0
  local version = GameVersion.current
  local shots = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/union-gen2"
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print(((cond and "PASS " or "FAIL ") .. line))
    return cond
  end

  U.wait(60)
  local world = game.world
  if not ok(world and world.map, "world booted") then love.event.quit(1) return end
  local maps = world.maps
  if not ok(maps[Room.ID] ~= nil, "union room map present") then love.event.quit(1) return end
  local base = game.stack:top()
  local save = game.save
  save.party = { Mon.new(game.data, "CYNDAQUIL", 12), Mon.new(game.data, "SENTRET", 6) }
  require("src.online.union.Caps").gameplayMods = function() return false end
  local gate = game.data.gen2Scripts[Center.RECEPTIONIST_KEY][3].event
  world.events:set(gate, true)

  local function settle(limit)
    U.wait(8)
    for _ = 1, limit or 900 do
      if not world:busy() and not world.player.moving and game.stack:top() == base then
        return true
      end
      if game.stack:top() ~= base then U.tap(game, "a") end
      U.wait(2)
    end
    return false
  end

  local function at() return world.map.id, world.player.cellX, world.player.cellY end

  local function step(dir)
    local _, x0, y0 = at()
    local m0 = world.map.id
    for _ = 1, 60 do
      U.hold(game, dir, 2)
      local m, x, y = at()
      if m ~= m0 or x ~= x0 or y ~= y0 then break end
    end
    settle()
  end

  local function walk(dir, n)
    for _ = 1, n do step(dir) end
  end

  local function face(dir)
    world.player.facing = dir
    U.wait(2)
  end

  local function talk(maxPresses)
    U.tap(game, "a")
    U.wait(2)
    local started = world.vm:running()
    local key = world.vm.ctxKey
    local quiet = 0
    for _ = 1, maxPresses or 200 do
      if not world.vm:running() and game.stack:top() == base and not world.mapSetup then
        quiet = quiet + 1
        if quiet >= 6 then break end
      else
        quiet = 0
      end
      if game.stack:top() ~= base then U.tap(game, "a") end
      U.wait(3)
    end
    settle()
    return started, key
  end

  local function place(mapId, x, y, facing)
    world:warpToMapId(mapId, x, y, facing)
    U.wait(20)
    settle()
  end

  local centers = {}
  for id, def in pairs(maps) do
    for i, w in ipairs(def.warps or {}) do
      if w.destMap == Center.MAP_ID and w.destWarp == 1 and id:find("_1F$") then
        centers[#centers + 1] = { id = id, warp = i, x = w.x, y = w.y }
      end
    end
  end
  table.sort(centers, function(a, b) return a.id < b.id end)
  ok(#centers >= 22, ("%d centers lead to the 2F"):format(#centers))

  local function climb(c)
    place(c.id, c.x + 1, c.y, "left")
    if world.map.id ~= c.id or world.player.cellX ~= c.x + 1 or world.player.cellY ~= c.y then
      place(c.id, c.x + 1, c.y, "left")
    end
    walk("left", 1)
    local m = at()
    return m == Center.MAP_ID
  end

  local function descend()
    place(Center.MAP_ID, 1, 7, "left")
    walk("left", 1)
  end

  local matrix = {}
  for _, c in ipairs(centers) do
    local up = climb(c)
    local banked = world.backupWarp and world.backupWarp.map == c.id
    local origin = Origin.get(save)
    local recorded = origin and origin.map == c.id and origin.gen == 2
    step("right")
    walk("left", 1)
    local m, x, y = at()
    local back = m == c.id and x == c.x and y == c.y
    matrix[#matrix + 1] = ("%s up=%s banked=%s origin=%s back=%s"):format(
      c.id, tostring(up), tostring(banked), tostring(recorded), tostring(back))
    ok(up and banked and recorded and back, "stairs round trip " .. c.id)
  end
  for _, line in ipairs(matrix) do print("MATRIX " .. version .. " " .. line) end

  local home = centers[1]
  for _, c in ipairs(centers) do
    if c.id == "CHERRYGROVE_POKECENTER_1F" then home = c end
  end
  local def1f = maps[home.id]
  local nurse
  for _, o in ipairs(def1f.objects) do
    if o.sprite == "SPRITE_NURSE" then nurse = o end
  end
  place(home.id, nurse.x, nurse.y + 2, "up")
  face("up")
  save.party[1].hp = 1
  talk()
  ok(save.party[1].hp == save.party[1].maxHp, "nurse healed the party")
  local pcx, pcy
  local m1 = require("src.world.gen2.Map").new(def1f, world.tilesets[def1f.tileset])
  for y = 0, m1.heightCells - 1 do
    for x = 0, m1.widthCells - 1 do
      if m1:cellCollision(x, y) == 0x93 then pcx, pcy = x, y end
    end
  end
  place(home.id, pcx, pcy + 1, "up")
  face("up")
  U.tap(game, "a")
  U.wait(30)
  local opened = game.stack:top() ~= base
  for _ = 1, 20 do
    if game.stack:top() == base and not world.vm:running() then break end
    U.tap(game, "b")
    U.wait(6)
  end
  settle()
  ok(opened, "1F PC opens")

  ok(climb(home), "up from " .. home.id)
  local banked = { map = world.backupWarp.map, warp = world.backupWarp.warp }
  local def2f = maps[Center.MAP_ID]
  U.still(game, ("%s/%s_on_2f_left.png"):format(shots, version))
  for i = 1, 3 do
    local o = def2f.objects[i]
    place(Center.MAP_ID, o.x, o.y + 1, "up")
    face("up")
    local started, key = talk()
    ok(key == o.scriptKey, ("2F receptionist %d runs %s"):format(i, tostring(o.scriptKey)))
    local m, x, y = at()
    ok(m == Center.MAP_ID and x == o.x and y == o.y + 1, ("receptionist %d leaves the player in place"):format(i))
  end
  local sign = def2f.bgEvents[1]
  place(Center.MAP_ID, sign.x, sign.y + 1, "up")
  face("up")
  local started, key = talk()
  ok(key == sign.scriptKey, "2F sign reads")

  local rcpt
  for _, o in ipairs(def2f.objects) do
    if o.scriptKey == Center.RECEPTIONIST_KEY then rcpt = o end
  end
  ok(rcpt ~= nil, "union receptionist is on the 2F")

  place(Center.MAP_ID, rcpt.x, rcpt.y + 1, "up")
  face("up")
  world.events:set(gate, false)
  talk()
  ok(at() == Center.MAP_ID, "gate closed keeps the player on the 2F")
  world.events:set(gate, true)
  local party = save.party
  save.party = {}
  face("up")
  talk()
  ok(at() == Center.MAP_ID, "empty party keeps the player on the 2F")
  save.party = party

  local leaveScene
  for id, row in pairs(def2f.sceneScripts) do
    if row.scriptKey == Center.LEFT_KEY then leaveScene = id end
  end

  local function enter(tag)
    place(Center.MAP_ID, rcpt.x, rcpt.y + 2, "up")
    step("up")
    local _, px, py = at()
    ok(px == rcpt.x and py == rcpt.y + 1, ("%s: walked to the union desk (%d,%d)"):format(tag, px, py))
    if tag == "first" then U.still(game, ("%s/%s_union_desk.png"):format(shots, version)) end
    face("up")
    save.party[1].hp = 1
    U.tap(game, "a")
    if tag == "first" then
      U.wait(90)
      U.still(game, ("%s/%s_union_receptionist_text.png"):format(shots, version))
    end
    local entered = false
    for _ = 1, 600 do
      if world.map.id == Room.ID then entered = true break end
      if game.stack:top() ~= base then U.tap(game, "a") end
      U.wait(3)
    end
    U.wait(30)
    settle()
    ok(entered, tag .. ": union receptionist walks the player into the room")
    ok(save.party[1].hp == save.party[1].maxHp, tag .. ": union receptionist healed the party")
    local onDisk = Gen2Save.load(version)
    ok(onDisk and onDisk.position and onDisk.position.map == home.id
      and onDisk.position.x == nurse.x and onDisk.position.y == nurse.y + 2
      and onDisk.position.facing == "up",
      tag .. ": desk save is written at the origin nurse front")
    ok(world.mapScenes[Center.MAP_ID] == leaveScene and world.mapScenes[Room.ID] == 1,
      tag .. ": room setup armed the 2F leave scene")
    local _, rx, ry = at()
    ok(rx == Room.EXIT_X and ry == Room.EXIT_Y, ("%s: room entry at (%d,%d)"):format(tag, rx, ry))
    ok(world.backupWarp.map == banked.map and world.backupWarp.warp == banked.warp,
      tag .. ": entering the room leaves backupWarp on " .. banked.map)
  end

  local function leave(tag)
    for _ = 1, 4 do
      if world.map.id ~= Room.ID then break end
      step("down")
    end
    U.wait(30)
    settle()
    local m, x, y = at()
    ok(m == Center.MAP_ID, tag .. ": room exit returns to the 2F")
    ok(x == rcpt.x and y == rcpt.y + 1, ("%s: leave walk ends in front of the desk (%d,%d)"):format(tag, x, y))
    local back
    for _, npc in ipairs(world.npcs) do
      if npc.def and npc.def.scriptKey == Center.RECEPTIONIST_KEY then back = npc end
    end
    ok(back and back.cellX == rcpt.x and back.cellY == rcpt.y, tag .. ": receptionist back at the desk")
    ok((world.mapScenes[Center.MAP_ID] or 0) == 0 and (world.mapScenes[Room.ID] or 0) == 0,
      tag .. ": leave scene disarmed")
    ok(world.backupWarp.map == banked.map and world.backupWarp.warp == banked.warp,
      tag .. ": leaving the room keeps backupWarp on " .. banked.map)
  end

  enter("first")
  U.still(game, ("%s/%s_union_room_entry.png"):format(shots, version))
  local sx, sy = Room.cellFor(1)
  place(Room.ID, sx, sy + 1, "up")
  U.still(game, ("%s/%s_union_room_slot1.png"):format(shots, version))
  place(Room.ID, Room.EXIT_X, Room.EXIT_Y - 1, "down")
  leave("first")
  U.still(game, ("%s/%s_union_left_room.png"):format(shots, version))

  local function reload()
    game:continueGame(Gen2Save.load(version))
    U.wait(30)
    world = game.world
    base = game.stack:top()
    settle()
  end

  local function sealedAt(what, shot)
    local onDisk = Gen2Save.load(version)
    local p = onDisk and onDisk.position
    ok(p and p.map == home.id and p.x == nurse.x and p.y == nurse.y + 2 and p.facing == "up",
      what .. ": written save is at the origin nurse front")
    ok(onDisk and onDisk.backupWarp and onDisk.backupWarp.map == home.id
      and onDisk.backupWarp.warp == home.warp, what .. ": written backupWarp names the 1F stairs")
    ok(onDisk and onDisk.mapScenes and onDisk.mapScenes[Room.ID] == nil
      and (onDisk.mapScenes[Center.MAP_ID] or 0) == 0, what .. ": written save has no union scenes")
    reload()
    local m, x, y = at()
    ok(m == home.id and x == nurse.x and y == nurse.y + 2 and world.player.facing == "up",
      ("%s: reload lands in front of the nurse (%s %d,%d %s)"):format(what, m, x, y, world.player.facing))
    U.still(game, ("%s/%s_%s.png"):format(shots, version, shot))
  end

  enter("second")
  place(Room.ID, 12, 23, "down")
  ok(game:writeSave(), "save inside the room")
  local m, x, y = at()
  ok(m == Room.ID and x == 12 and y == 23, "saving in the room leaves the live player in the room")
  ok(world.mapScenes[Center.MAP_ID] == leaveScene and world.mapScenes[Room.ID] == 1,
    "saving in the room leaves the live scenes armed")
  ok(world.backupWarp.map == banked.map, "saving in the room leaves the live backupWarp")
  leave("after saving in the room")
  sealedAt("room save", "reload_after_room_save")

  ok(climb(home), "climb again after the room reload")
  place(Center.MAP_ID, 18, 5, "down")
  ok(game:writeSave(), "save on the added 2F columns")
  m, x, y = at()
  ok(m == Center.MAP_ID and x == 18 and y == 5, "saving at x>=16 leaves the live player there")
  sealedAt("2F x>=16 save", "reload_after_2f_added_save")

  ok(climb(home), "climb again after the x>=16 reload")
  place(Center.MAP_ID, 14, 4, "down")
  ok(game:writeSave(), "save on a vanilla 2F cell")
  reload()
  m, x, y = at()
  ok(m == Center.MAP_ID and x == 14 and y == 4, ("vanilla 2F save reloads in place (%s %d,%d)"):format(m, x, y))
  descend()
  m, x, y = at()
  ok(m == home.id and x == home.x and y == home.y, ("2F stairs after reload lead to %s"):format(m))

  print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
