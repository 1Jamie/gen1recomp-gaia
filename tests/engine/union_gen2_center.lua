package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Center = require("src.world.gen2.UnionCenter2F")
local Room = require("src.world.gen2.UnionRoomMap")
local Safety = require("src.world.gen2.UnionSafety")
local Origin = require("src.online.union.Origin")
local World = require("src.world.gen2.World")
local Map = require("src.world.gen2.Map")

local ON, OFF = {}, { unionRoom = false }

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function grid(w, h, fill)
  local out = {}
  for i = 1, w * h do out[i] = fill end
  return out
end

local function fixture()
  local pc = { blocks = {}, collision = {} }
  local function pcBlock(id, tile, coll)
    local tiles = {}
    for i = 1, 16 do tiles[i] = tile end
    pc.blocks[id + 1], pc.collision[id + 1] = tiles, coll
  end
  pcBlock(0, 0, { 7, 7, 7, 7 })
  pcBlock(1, 1, { 0, 0, 0, 0 })
  pcBlock(2, 2, { 7, 7, 0, 0 })
  pcBlock(3, 3, { 7, 0x71, 0, 0 })
  pcBlock(4, 4, { 7, 0, 0, 0 })
  pcBlock(5, 5, { 7, 7, 7, 7 })
  pcBlock(6, 6, { 0, 0, 0x72, 0 })
  pcBlock(7, 7, { 0, 0x90, 0, 0 })
  local gate = { blocks = {}, collision = {} }
  local function gateBlock(id, tile, coll)
    local tiles = {}
    for i = 1, 16 do tiles[i] = tile end
    gate.blocks[id + 1], gate.collision[id + 1] = tiles, coll
  end
  gateBlock(0, 0, { 7, 7, 7, 7 })
  gateBlock(1, 10, { 7, 7, 0, 0 })
  gateBlock(2, 11, { 0, 0, 0, 0 })
  gateBlock(3, 12, { 0, 0, 0x70, 0x70 })

  local blocks2f = grid(8, 4, 1)
  for bx = 0, 7 do blocks2f[bx + 1] = 2 end
  blocks2f[2 + 1], blocks2f[4 + 1] = 3, 3
  blocks2f[8 + 2 + 1], blocks2f[8 + 4 + 1], blocks2f[8 + 5 + 1] = 4, 4, 5
  blocks2f[24 + 1] = 6
  local function rcpt(i, x, y, key)
    return { index = i, x = x, y = y, sprite = "SPRITE_LINK_RECEPTIONIST", spriteId = 56,
      palette = 10, movement = 6, eventFlag = 65535, scriptKey = key, type = 0 }
  end
  local maps = {
    POKECENTER_2F = {
      id = "POKECENTER_2F", group = 20, map = 1, width = 8, height = 4,
      tileset = "TILESET_POKECENTER", environment = "INDOOR", blocks = blocks2f,
      warps = {
        { x = 0, y = 7, destMap = "POKECENTER_2F", destWarp = 255 },
        { x = 5, y = 0, destMap = "TRADE_CENTER", destWarp = 1 },
        { x = 9, y = 0, destMap = "COLOSSEUM", destWarp = 1 },
        { x = 13, y = 2, destMap = "TIME_CAPSULE", destWarp = 1 },
      },
      objects = { rcpt(1, 5, 2, "t"), rcpt(2, 9, 2, "b"), rcpt(3, 13, 3, "c"),
        { index = 4, x = 1, y = 1, sprite = "SPRITE_OFFICER", eventFlag = 1809, scriptKey = "o" } },
      bgEvents = { { kind = 0, x = 7, y = 3, scriptKey = "sign" } },
      sceneScripts = { [0] = { sceneId = 0, scriptKey = "s0" }, [1] = { sceneId = 1, scriptKey = "s1" },
        [2] = { sceneId = 2, scriptKey = "s2" }, [3] = { sceneId = 3, scriptKey = "s3" } },
      coordEvents = {}, callbacks = {}, connections = {},
    },
    TRADE_CENTER = {
      id = "TRADE_CENTER", group = 20, map = 2, width = 5, height = 4, music = 38,
      tileset = "TILESET_GATE", environment = "INDOOR", borderBlock = 0,
      blocks = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 2 },
      warps = { { x = 4, y = 7, destMap = "POKECENTER_2F", destWarp = 2 },
        { x = 5, y = 7, destMap = "POKECENTER_2F", destWarp = 2 } },
      objects = {}, callbacks = { {} },
    },
    CHERRYGROVE_POKECENTER_1F = {
      id = "CHERRYGROVE_POKECENTER_1F", group = 11, map = 4, width = 5, height = 4,
      tileset = "TILESET_POKECENTER", environment = "INDOOR",
      blocks = { 2, 2, 2, 2, 2, 1, 7, 1, 1, 1, 1, 1, 1, 1, 1, 6, 1, 1, 1, 1 },
      warps = { { x = 3, y = 7, destMap = "CHERRYGROVE_CITY", destWarp = 3 },
        { x = 4, y = 7, destMap = "CHERRYGROVE_CITY", destWarp = 3 },
        { x = 0, y = 7, destMap = "POKECENTER_2F", destWarp = 1 } },
      objects = { { index = 1, x = 3, y = 1, sprite = "SPRITE_NURSE", eventFlag = 65535, scriptKey = "n" } },
    },
  }
  local data = {
    gen2Maps = maps,
    gen2Tilesets = { TILESET_POKECENTER = pc, TILESET_GATE = gate },
    gen2Scripts = { movements = {}, b = { { op = "checkevent", event = 31 }, { op = "end" } } },
    gen2Constants = { specialOrder = { "WarpToSpawnPoint", "HealParty", "TryQuickSave" } },
    gen2Landmarks = { spawns = { SPAWN_CHERRYGROVE = { map = "CHERRYGROVE_CITY", x = 29, y = 4 } } },
  }
  return data
end

local function suite(label, makeData)
  local pristine = makeData()
  local off = makeData()
  eq(Center.apply(off, OFF), false, label .. ": OFF apply reports nothing applied")
  check(deepEq(off, pristine), label .. ": OFF leaves maps, tilesets and scripts deep-equal to the cache")
  for _ = 1, 3 do Center.apply(off, OFF) end
  check(deepEq(off, pristine), label .. ": repeated OFF reloads never accumulate")

  local data = makeData()
  eq(Center.apply(data, ON), true, label .. ": ON applies")
  local once = copy(data)
  eq(Center.apply(data, ON), true, label .. ": second apply is a no-op success")
  check(deepEq(data, once), label .. ": patch is idempotent")
  local again = makeData()
  Center.apply(again, ON)
  check(deepEq(again, once), label .. ": a fresh reload patches to the same tables")

  local maps, tilesets = data.gen2Maps, data.gen2Tilesets
  local vanilla = pristine.gen2Maps.POKECENTER_2F
  local def = maps.POKECENTER_2F
  local room = maps[Room.ID]
  check(room ~= nil, label .. ": union room map added")
  eq(def.width, vanilla.width + 2, label .. ": 2F gains two block columns")
  eq(#def.blocks, def.width * def.height, label .. ": 2F block grid is complete")
  for by = 0, vanilla.height - 1 do
    for bx = 0, vanilla.width - 1 do
      if def.blocks[by * def.width + bx + 1] ~= vanilla.blocks[by * vanilla.width + bx + 1] then
        check(false, ("%s: original 2F block (%d,%d) changed"):format(label, bx, by))
      end
    end
  end
  for i, w in ipairs(vanilla.warps) do
    check(deepEq(def.warps[i], w), ("%s: original 2F warp %d unchanged"):format(label, i))
  end
  for i, o in ipairs(vanilla.objects) do
    check(deepEq(def.objects[i], o), ("%s: original 2F object %d unchanged"):format(label, i))
  end
  check(deepEq(def.bgEvents, vanilla.bgEvents), label .. ": 2F sign unchanged")
  for id, row in pairs(vanilla.sceneScripts) do
    check(deepEq(def.sceneScripts[id], row), label .. ": 2F scene " .. tostring(id) .. " unchanged")
  end
  eq(def.warps[1].destWarp, 0xff, label .. ": the 2F stairs keep the -1 destination")
  local doorIndex = #vanilla.warps + 1
  local door = def.warps[doorIndex]
  eq(door and door.destMap, Room.ID, label .. ": new 2F warp leads to the union room")
  for _, w in ipairs(room.warps) do
    eq(w.destMap, "POKECENTER_2F", label .. ": room exit leads to the 2F")
    eq(w.destWarp, doorIndex, label .. ": room exit lands on the union door")
  end
  local rcpt = def.objects[#def.objects]
  eq(rcpt.scriptKey, Center.RECEPTIONIST_KEY, label .. ": union receptionist added")
  eq(rcpt.x, door.x, label .. ": receptionist stands in the door column")
  local map2f = Map.new(def, tilesets[def.tileset])
  eq(map2f:cellCollision(door.x, door.y), 0x71, label .. ": the union door cell is a door")
  check(map2f:isWalkable(rcpt.x, rcpt.y + 1), label .. ": the desk front is floor")
  check(map2f:isWalkable(rcpt.x, rcpt.y - 1) and map2f:isWalkable(rcpt.x - 1, rcpt.y - 1),
    label .. ": the receptionist has room to step aside")
  for _, key in ipairs({ Center.RECEPTIONIST_KEY, Center.LEFT_KEY, Room.SETUP_KEY }) do
    check(type(data.gen2Scripts[key]) == "table", label .. ": script " .. key .. " registered")
  end
  local gateCmd = data.gen2Scripts[Center.RECEPTIONIST_KEY][3]
  eq(gateCmd.op, "checkevent", label .. ": receptionist gates on an event")
  eq(gateCmd.event, data.gen2Scripts[vanilla.objects[2].scriptKey][1].event,
    label .. ": the gate is the cable club's own event")
  local function talk(party, mods)
    local shown = {}
    local function run(key)
      local var = 0
      for _, c in ipairs(data.gen2Scripts[key]) do
        if c.op == "checkevent" or c.op == "yesorno" then var = 1
        elseif c.op == "readvar" and c.var == World.VAR_LINK_MODS then var = mods and 1 or 0
        elseif c.op == "readvar" then var = party
        elseif c.op == "iftrue" and var ~= 0 then return run(c.script)
        elseif c.op == "rawtext" then shown[#shown + 1] = c.text
        elseif c.op == "iffalse" and var == 0 then return run(c.script)
        elseif c.op == "ifless" and var < c.value then return run(c.script)
        elseif c.op == "sjump" then return run(c.script)
        elseif c.op == "special" then return end
      end
    end
    run(Center.RECEPTIONIST_KEY)
    return shown
  end
  local one, two = talk(1), talk(2)
  check(one[1] == Center.TEXT.intro and one[2] == Center.TEXT.needTwo and one[3] == Center.TEXT.decline,
    label .. ": one POKEMON gets the welcome, then the need-two refusal")
  eq(#one, 3, label .. ": the one-POKEMON refusal ends there")
  check(two[1] == Center.TEXT.intro and two[2] == Center.TEXT.save,
    label .. ": two POKEMON go on to the save prompt")
  local countVar
  for _, c in ipairs(data.gen2Scripts[Center.RECEPTIONIST_KEY]) do
    if c.op == "readvar" then countVar = c.var end
  end
  eq(countVar, World.VAR_PARTY_NON_EGGS, label .. ": the party check counts non-egg POKEMON")
  local modded = talk(2, true)
  check(modded[1] == require("src.online.union.Caps").MODS_TEXT and modded[2] == Center.TEXT.decline,
    label .. ": link-play mods are refused at the desk before the welcome")
  eq(#modded, 2, label .. ": the mods refusal ends there")

  local roomMap = Map.new(room, tilesets[room.tileset])
  eq(room.width * 2, Room.WIDTH, label .. ": room width")
  local seen = {}
  for slot = 1, Room.CAP do
    local x, y = Room.cellFor(slot)
    check(x ~= nil, label .. ": slot " .. slot .. " has a cell")
    local key = y * 64 + x
    check(not seen[key], label .. ": slot " .. slot .. " does not overlap")
    seen[key] = true
    check(roomMap:isWalkable(x, y) and roomMap:isWalkable(x, y - 1),
      label .. ": slot " .. slot .. " and its badge cell are floor")
    eq(Room.slotAt(x, y), slot, label .. ": slotAt inverts cellFor for " .. slot)
    check(not roomMap:warpAt(x, y), label .. ": slot " .. slot .. " is not an exit")
  end
  eq(Room.cellFor(Room.CAP + 1), nil, label .. ": no 41st slot")
  eq(roomMap:cellCollision(Room.EXIT_X, Room.EXIT_Y), 0x70, label .. ": room exit is a warp mat")

  local function world(mapId, x, y)
    local game = { data = { audio = { sfxOrder = {} } }, save = { player = {}, version = "gold" } }
    local w = World.new(game)
    w.maps, w.tilesets = maps, tilesets
    w.map = Map.new(maps[mapId], tilesets[maps[mapId].tileset])
    w.player = { cellX = x, cellY = y, facing = "left", moving = false }
    w.setMap = function(self, id, cx, cy, facing)
      self.loaded = { id = id, x = cx, y = cy, facing = facing }
      self.map = Map.new(maps[id], tilesets[maps[id].tileset])
      self.player = { cellX = cx, cellY = cy, facing = facing or "down", moving = false }
      return true
    end
    return w
  end
  local function pump(w)
    for _ = 1, 64 do
      if not w.mapSetup then return end
      w:updateMapSetup()
    end
  end
  local oneF = "CHERRYGROVE_POKECENTER_1F"
  local w = world(oneF, 0, 7)
  local stairsIndex = 3
  local stairs = maps[oneF].warps[stairsIndex]
  check(w:takeWarp(stairs), label .. ": up the 1F stairs")
  pump(w)
  eq(w.loaded.id, "POKECENTER_2F", label .. ": arrived on the 2F")
  eq(w.backupWarp and w.backupWarp.map, oneF, label .. ": backupWarp banks the 1F")
  local origin = Origin.get(w.game.save)
  eq(origin and origin.map, oneF, label .. ": origin records the 1F center")
  eq(origin and origin.gen, 2, label .. ": origin is gen 2")
  eq(origin and origin.x, stairs.x, label .. ": origin x is the 1F stairs")
  w.game.save.unionOrigin = nil
  w.player = { cellX = door.x, cellY = door.y, facing = "up", moving = false }
  check(w:takeWarp(door), label .. ": through the union door")
  pump(w)
  eq(w.loaded.id, Room.ID, label .. ": in the union room")
  eq(w.backupWarp.map, oneF, label .. ": entering the room keeps backupWarp")
  eq(Origin.get(w.game.save), nil, label .. ": the room door does not rewrite the origin")
  check(w:takeWarp(room.warps[1]), label .. ": out of the room")
  pump(w)
  eq(w.loaded.id, "POKECENTER_2F", label .. ": back on the 2F")
  eq(w.loaded.x, door.x, label .. ": at the union door x")
  eq(w.loaded.y, door.y, label .. ": at the union door y")
  eq(w.backupWarp.map, oneF, label .. ": leaving the room keeps backupWarp")
  w.player = { cellX = 0, cellY = 7, facing = "left", moving = false }
  check(w:takeWarp(def.warps[1]), label .. ": down the 2F stairs")
  pump(w)
  eq(w.loaded.id, oneF, label .. ": the stairs still return to the same center")

  local offData = makeData()
  local fx, fy, ff = Safety.nurseFront(data, oneF)
  check(fx ~= nil, label .. ": " .. oneF .. " has a nurse front")
  eq(ff, "up", label .. ": nurse front faces up")
  local function stranded(pos, backup, withOrigin)
    local save = { position = pos, backupWarp = backup, spawn = "SPAWN_CHERRYGROVE",
      mapScenes = { POKECENTER_2F = 99, [Room.ID] = 1 } }
    if withOrigin ~= false then
      Origin.record(save, { gen = 2, version = "gold", map = oneF, warp = 3, x = 0, y = 7, facing = "left" })
    end
    return save
  end
  local function atNurse(save, what)
    eq(save.position and save.position.map, oneF, label .. ": " .. what .. " lands in the origin 1F")
    eq(save.position and save.position.x, fx, label .. ": " .. what .. " at the nurse front x")
    eq(save.position and save.position.y, fy, label .. ": " .. what .. " at the nurse front y")
    eq(save.position and save.position.facing, "up", label .. ": " .. what .. " faces the nurse")
    eq(save.backupWarp and save.backupWarp.map, oneF, label .. ": " .. what .. " banks the 1F stairs")
    eq(save.backupWarp and save.backupWarp.warp, stairsIndex, label .. ": " .. what .. " banks the stairs warp")
  end
  local s1 = stranded({ map = Room.ID, x = 12, y = 23, facing = "down" }, { map = oneF, warp = 3 })
  eq(Safety.settle(s1, offData), oneF, label .. ": OFF room save relocates to the 1F")
  atNurse(s1, "OFF room load")
  eq(Origin.get(s1), nil, label .. ": load relocation clears the origin")
  eq(s1.mapScenes.POKECENTER_2F, 0, label .. ": load relocation resets a union 2F scene")
  eq(s1.mapScenes[Room.ID], nil, label .. ": load relocation drops the room scene")
  local s2 = stranded({ map = Room.ID, x = 12, y = 23 }, { map = "NOWHERE", warp = 1 }, false)
  eq(Safety.settle(s2, offData), oneF, label .. ": unknown origin falls back to the heal-point center")
  atNurse(s2, "heal-point fallback")
  local s3 = stranded({ map = "POKECENTER_2F", x = door.x, y = door.y + 3 }, { map = oneF, warp = 3 })
  eq(Safety.settle(s3, offData), oneF, label .. ": OFF save on a removed 2F cell relocates")
  atNurse(s3, "OFF removed 2F cell")
  local s4 = stranded({ map = "POKECENTER_2F", x = 0, y = 7 }, { map = oneF, warp = 3 })
  eq(Safety.settle(s4, offData), nil, label .. ": OFF save on a vanilla 2F cell stays")
  check(Origin.get(s4) ~= nil, label .. ": and keeps its origin")
  local s5 = stranded({ map = Room.ID, x = 12, y = 23 }, { map = oneF, warp = 3 })
  eq(Safety.settle(s5, data), oneF, label .. ": ON load also moves a room save to the 1F")
  atNurse(s5, "ON room load")
  local s6 = stranded({ map = "POKECENTER_2F", x = 14, y = 4 }, { map = oneF, warp = 3 })
  eq(Safety.settle(s6, data), nil, label .. ": ON save on a vanilla 2F cell stays")

  check(Safety.isAdded(data, { map = Room.ID, x = 1, y = 1 }), label .. ": the room is added")
  check(Safety.isAdded(data, { map = "POKECENTER_2F", x = 16, y = 4 }), label .. ": 2F x=16 is added")
  check(not Safety.isAdded(data, { map = "POKECENTER_2F", x = 15, y = 4 }), label .. ": 2F x=15 is vanilla")
  check(not Safety.isAdded(data, { map = oneF, x = 3, y = 3 }), label .. ": a 1F cell is vanilla")
  local leaveId
  for id, row in pairs(def.sceneScripts) do
    if row.scriptKey == Center.LEFT_KEY then leaveId = id end
  end
  local liveScenes = { POKECENTER_2F = leaveId, [Room.ID] = 1 }
  local liveBackup = { map = oneF, warp = 3 }
  for _, pos in ipairs({ { map = Room.ID, x = 12, y = 23, facing = "down" },
      { map = "POKECENTER_2F", x = door.x, y = door.y + 3, facing = "up" } }) do
    local live = { position = pos, backupWarp = liveBackup, mapScenes = liveScenes, spawn = "SPAWN_CHERRYGROVE" }
    Origin.record(live, { gen = 2, version = "gold", map = oneF, warp = 3, x = 0, y = 7 })
    eq(Safety.seal(live, data), oneF, label .. ": save-time seal moves " .. pos.map .. " to the 1F")
    atNurse(live, "sealed " .. pos.map)
    check(live.backupWarp ~= liveBackup and liveBackup.map == oneF and liveBackup.warp == 3,
      label .. ": seal never mutates the live backupWarp")
    check(live.mapScenes ~= liveScenes and liveScenes.POKECENTER_2F == leaveId and liveScenes[Room.ID] == 1,
      label .. ": seal never mutates the live scene table")
    eq(live.mapScenes[Room.ID], nil, label .. ": sealed save drops the room scene")
    eq(live.mapScenes.POKECENTER_2F, 0, label .. ": sealed save resets the 2F leave scene")
    check(Origin.get(live) ~= nil, label .. ": seal keeps the live origin")
  end
  local plain = { position = { map = "POKECENTER_2F", x = 0, y = 7 }, backupWarp = liveBackup }
  eq(Safety.seal(plain, data), nil, label .. ": seal leaves a vanilla 2F save alone")
  eq(plain.backupWarp, liveBackup, label .. ": and its backupWarp")
  return data
end

suite("fixture", fixture)

do
  local w = World.new({ data = { audio = { sfxOrder = {} } },
    save = { player = {}, version = "gold", party = { { species = "PIDGEY" }, { species = "TOGEPI", isEgg = true } } } })
  eq(w:readVar(World.VAR_PARTY_NON_EGGS), 1, "a POKEMON and an EGG count as one for the union room")
  eq(w:readVar(0x01), 2, "VAR_PARTYCOUNT still counts the EGG")
  eq(w:readVar(World.VAR_LINK_MODS), 0, "no mod loader reads as no link-play mods")
  local Caps = require("src.online.union.Caps")
  local saved = Caps.gameplayMods
  Caps.gameplayMods = function(g) return g == w.game end
  eq(w:readVar(World.VAR_LINK_MODS), 1, "the desk reads the same link-play mods predicate as FireRed")
  Caps.gameplayMods = saved
end

local ok, Plaza = pcall(require, "src.core.game3.link.union_plaza_map")
if ok and Plaza and Plaza.cellFor then
  for slot = 1, Room.CAP do
    local gx, gy = Plaza.cellFor(slot)
    local x, y = Room.cellFor(slot)
    if gx ~= x or gy ~= y then
      check(false, ("slot %d: gen 2 (%s,%s) vs gen 3 (%s,%s)"):format(slot, tostring(x), tostring(y), tostring(gx), tostring(gy)))
    end
  end
  check(true, "slot geometry matches the Gen 3 plaza")
else
  print("[skip] gen 3 plaza module not loadable: " .. tostring(Plaza))
end

local home = (os.getenv("HOME") or "") .. "/Library/Application Support/LOVE/"
for _, v in ipairs({ "gold", "silver", "crystal" }) do
  local dir = os.getenv(v:upper() .. "_CACHE") or (home .. "g1r-" .. v .. "/" .. v)
  local probe = io.open(dir .. "/data/generated/maps.lua", "r")
  if not probe then
    print("[skip] no " .. v .. " cache at " .. dir)
  else
    probe:close()
    local raw = {}
    for _, f in ipairs({ "maps", "tilesets", "scripts", "constants", "landmarks" }) do
      raw[f] = assert(loadfile(dir .. "/data/generated/" .. f .. ".lua"))()
    end
    local function makeData()
      return { gen2Maps = copy(raw.maps), gen2Tilesets = copy(raw.tilesets),
        gen2Scripts = copy(raw.scripts), gen2Constants = copy(raw.constants),
        gen2Landmarks = copy(raw.landmarks) }
    end
    local data = suite(v, makeData)
    local centers = 0
    for id, cdef in pairs(data.gen2Maps) do
      local leads = false
      for _, wp in ipairs(cdef.warps or {}) do
        if wp.destMap == "POKECENTER_2F" and id ~= "POKECENTER_2F" and wp.destWarp == 1 then leads = true end
      end
      if leads then
        centers = centers + 1
        local nx, ny, nf = Safety.nurseFront(data, id)
        check(nx ~= nil and nf == "up", ("%s: %s has a nurse front cell"):format(v, id))
      end
    end
    eq(centers, 22, v .. ": 22 centers lead to the 2F")
    local def = data.gen2Maps.POKECENTER_2F
    local map = Map.new(def, data.gen2Tilesets[def.tileset])
    local blocked = {}
    for _, o in ipairs(def.objects) do blocked[o.y * 64 + o.x] = true end
    local seen, queue = { [7 * 64] = true }, { { 0, 7 } }
    local head = 1
    while queue[head] do
      local cx, cy = queue[head][1], queue[head][2]
      head = head + 1
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = cx + d[1], cy + d[2]
        local k = ny * 64 + nx
        if not seen[k] and not blocked[k] and map:isWalkable(nx, ny) then
          seen[k] = true
          queue[#queue + 1] = { nx, ny }
        end
      end
    end
    local function reachable(x, y)
      for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
        if seen[(y + d[2]) * 64 + x + d[1]] then return true end
        local cx, cy = x + d[1], y + d[2]
        if map:inBounds(cx, cy) and require("src.world.gen2.Permissions").isCounter(map:cellCollision(cx, cy))
            and seen[(y + 2 * d[2]) * 64 + x + 2 * d[1]] then
          return true
        end
      end
      return false
    end
    for i, o in ipairs(def.objects) do
      check(reachable(o.x, o.y), ("%s: 2F object %d (%s) can be talked to"):format(v, i, tostring(o.sprite)))
    end
    for _, ev in ipairs(def.bgEvents) do
      check(reachable(ev.x, ev.y), ("%s: 2F sign at (%d,%d) can be read"):format(v, ev.x, ev.y))
    end
    for i, wp in ipairs(def.warps) do
      if map:isWalkable(wp.x, wp.y) or i == 1 then
        local behind
        for _, o in ipairs(def.objects) do
          if o.x == wp.x and o.y > wp.y and o.y <= wp.y + 3 then behind = o end
        end
        check(behind ~= nil or seen[wp.y * 64 + wp.x] or i == 1,
          ("%s: 2F warp %d to %s is reachable or guarded by its receptionist"):format(v, i, wp.destMap))
      end
    end
  end
end

T.finish("union gen2 center")
