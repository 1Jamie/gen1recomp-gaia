local Caps = require("src.online.union.Caps")
local Strings = require("src.core.Strings")
local Setting = require("src.online.union.Setting")
local Origin = require("src.online.union.Origin")
local RoomMap = require("src.world.gen2.UnionRoomMap")

local M = {}

M.MAP_ID = "POKECENTER_2F"
M.ROOM_ID = RoomMap.ID
M.RECEPTIONIST_KEY = "union:2f_receptionist"
M.LEFT_KEY = "union:2f_left_room"

local KEY = {
  closed = "union:2f_closed",
  needTwo = "union:2f_need_two",
  mods = "union:2f_mods",
  decline = "union:2f_decline",
}

local MOVE = {
  aside = "union:mv_receptionist_aside",
  playerIn = "union:mv_player_in",
  makeWay = "union:mv_receptionist_make_way",
  playerOut = "union:mv_player_out",
  back = "union:mv_receptionist_back",
}

local TEXT = {
  closed = Strings.source("I'm sorry, the\nUNION ROOM isn't\vopen to you yet."),
  -- pokefirered/data/scripts/cable_club.inc:1492
  needTwo = Strings.source("To enter the UNION\nROOM, you must\vhave at least two\vPOKéMON."),
  intro = Strings.source(
    "Welcome to the\nUNION ROOM.\fTrainers from\nevery generation\vgather here.\f"
    .. "Would you like\nto go in?"),
  save = Strings.source("Your game will be\nsaved before you\vgo in. OK?"),
  decline = Strings.source("Please come\nback anytime."),
  comeIn = Strings.source("Your POKéMON are\nall rested.\fRight this way."),
}
M.TEXT = TEXT

-- macros/scripts/movement.asm:6
local TURN_HEAD = 0x00
-- macros/scripts/movement.asm:16
local SLOW_STEP = 0x08
-- macros/scripts/movement.asm:21
local STEP = 0x0c
-- macros/scripts/movement.asm:122
local STEP_END = 0x47
-- constants/ram_constants.asm:82
local DOWN, UP, LEFT, RIGHT = 0, 1, 2, 3
M.VAR_PARTY_NON_EGGS = "PARTY_NON_EGGS"
M.VAR_LINK_MODS = "LINK_MODS"

local function moves(...)
  local out = {}
  for i, b in ipairs({ ... }) do out[i] = b end
  out[#out + 1] = STEP_END
  return out
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function blockAt(def, bx, by)
  return def.blocks[by * def.width + bx + 1]
end

local function warpTo(def, dest)
  for i, w in ipairs(def.warps or {}) do
    if w.destMap == dest then return i, w end
  end
  return nil
end

function M.layout(def)
  local _, door = warpTo(def, "COLOSSEUM")
  assert(door, "POKECENTER_2F has no COLOSSEUM warp")
  local col = math.floor(door.x / 2)
  local lx = door.x % 2
  local receptionist
  for _, obj in ipairs(def.objects or {}) do
    if obj.x == door.x and obj.y > door.y and obj.scriptKey then
      if not receptionist or obj.y < receptionist.y then receptionist = obj end
    end
  end
  assert(receptionist, "POKECENTER_2F has no COLOSSEUM receptionist")
  local x = def.width * 2 + (door.x - col * 2)
  return {
    col = col, lx = lx, source = door, receptionist = receptionist,
    width = def.width + 2,
    doorX = x, doorY = door.y,
    deskX = x, deskY = receptionist.y,
    frontX = x, frontY = receptionist.y + 1,
  }
end

local function composeDoor(def, tileset, plan)
  local src = blockAt(def, plan.col, 0)
  local wall = tileset.blocks[blockAt(def, 0, 0) + 1]
  local tiles = copy(tileset.blocks[src + 1])
  local ex = (1 - plan.lx) * 2
  for _, i in ipairs({ ex + 1, ex + 2, ex + 5, ex + 6 }) do
    tiles[i] = wall[i - ex]
  end
  return RoomMap.block(tileset, tiles, copy(tileset.collision[src + 1]))
end

local function widen(def, tileset, plan)
  local w, h = def.width, def.height
  local nw = plan.width
  local door = composeDoor(def, tileset, plan)
  local floor = blockAt(def, plan.col, 2)
  local out = {}
  for by = 0, h - 1 do
    for bx = 0, w - 1 do out[by * nw + bx + 1] = blockAt(def, bx, by) end
    local a, b
    if by == 0 then
      a, b = door, blockAt(def, plan.col + 1, 0)
    elseif by == 1 then
      a, b = blockAt(def, plan.col, 1), blockAt(def, plan.col + 1, 1)
    else
      a, b = floor, floor
    end
    out[by * nw + w + 1] = a
    out[by * nw + w + 2] = b
  end
  def.blocks = out
  def.width = nw
end

local function specialId(constants, name)
  for i, n in ipairs(constants and constants.specialOrder or {}) do
    if n == name then return i - 1 end
  end
  error("gen2 cache special order has no " .. name)
end

local function gateEvent(scripts, receptionist)
  for _, cmd in ipairs(scripts[receptionist.scriptKey] or {}) do
    if cmd.op == "checkevent" then return cmd.event end
  end
  error("gen2 cable club receptionist has no gate event")
end

local function says(text, ...)
  local list = { { op = "rawtext", text = text }, { op = "waitbutton" },
    { op = "closetext" } }
  for _, cmd in ipairs({ ... }) do list[#list + 1] = cmd end
  list[#list + 1] = { op = "end" }
  return list
end

local function addScripts(data, def, room, plan, rcptConst, leaveScene)
  local scripts = data.gen2Scripts
  scripts.movements = scripts.movements or {}
  local mv = scripts.movements
  mv[MOVE.aside] = moves(SLOW_STEP + UP, SLOW_STEP + LEFT, TURN_HEAD + DOWN)
  mv[MOVE.playerIn] = moves(STEP + UP, STEP + UP, STEP + UP)
  mv[MOVE.makeWay] = moves(SLOW_STEP + UP, SLOW_STEP + LEFT, TURN_HEAD + RIGHT)
  mv[MOVE.playerOut] = moves(STEP + DOWN, STEP + DOWN, STEP + DOWN)
  mv[MOVE.back] = moves(SLOW_STEP + RIGHT, SLOW_STEP + DOWN)
  scripts[KEY.closed] = says(TEXT.closed)
  scripts[KEY.decline] = says(TEXT.decline)
  scripts[KEY.mods] = {
    { op = "rawtext", text = Caps.MODS_TEXT }, { op = "waitbutton" },
    { op = "sjump", script = KEY.decline },
  }
  scripts[KEY.needTwo] = {
    { op = "rawtext", text = TEXT.needTwo }, { op = "waitbutton" },
    { op = "sjump", script = KEY.decline },
  }
  scripts[M.RECEPTIONIST_KEY] = {
    { op = "faceplayer" },
    { op = "opentext" },
    { op = "checkevent", event = gateEvent(scripts, plan.receptionist) },
    { op = "iffalse", script = KEY.closed },
    -- pokefirered/data/scripts/cable_club.inc:747
    { op = "readvar", var = M.VAR_LINK_MODS },
    { op = "iftrue", script = KEY.mods },
    { op = "rawtext", text = TEXT.intro },
    { op = "yesorno" },
    { op = "iffalse", script = KEY.decline },
    -- pokefirered/data/scripts/cable_club.inc:804
    { op = "readvar", var = M.VAR_PARTY_NON_EGGS },
    { op = "ifless", value = 2, script = KEY.needTwo },
    { op = "rawtext", text = TEXT.save },
    { op = "yesorno" },
    { op = "iffalse", script = KEY.decline },
    { op = "special", id = specialId(data.gen2Constants, "TryQuickSave") },
    { op = "iffalse", script = KEY.decline },
    { op = "special", id = specialId(data.gen2Constants, "HealParty") },
    { op = "rawtext", text = TEXT.comeIn },
    { op = "waitbutton" },
    { op = "closetext" },
    { op = "applymovementlasttalked", movement = MOVE.aside },
    { op = "applymovement", object = 0, movement = MOVE.playerIn },
    { op = "warpcheck" },
    { op = "end" },
  }
  scripts[M.LEFT_KEY] = {
    { op = "applymovement", object = rcptConst, movement = MOVE.makeWay },
    { op = "applymovement", object = 0, movement = MOVE.playerOut },
    { op = "applymovement", object = rcptConst, movement = MOVE.back },
    { op = "setscene", scene = 0 },
    { op = "setmapscene", group = room.group, map = room.map, scene = 0 },
    { op = "end" },
  }
  scripts[RoomMap.SETUP_KEY] = {
    { op = "setscene", scene = 1 },
    { op = "setmapscene", group = def.group, map = def.map, scene = leaveScene },
    { op = "end" },
  }
end

local applied = setmetatable({}, { __mode = "k" })

function M.isApplied(maps)
  return maps ~= nil and applied[maps] == true
end

function M.apply(data, opts)
  if not Setting.patchesOn(2, opts) then return false end
  local maps, tilesets = data.gen2Maps, data.gen2Tilesets
  local def = maps and maps[M.MAP_ID]
  if not (def and tilesets and data.gen2Scripts) then return false end
  if applied[maps] or maps[M.ROOM_ID] then
    applied[maps] = true
    return true
  end
  local tileset = assert(tilesets[def.tileset], "gen2 cache has no " .. tostring(def.tileset))
  local plan = M.layout(def)
  widen(def, tileset, plan)
  local index = 0
  for _, obj in ipairs(def.objects) do
    if (obj.index or 0) > index then index = obj.index end
  end
  local rcpt = copy(plan.receptionist)
  rcpt.index = index + 1
  rcpt.x, rcpt.y = plan.deskX, plan.deskY
  rcpt.script = nil
  rcpt.scriptKey = M.RECEPTIONIST_KEY
  rcpt.eventFlag = 65535
  def.objects[#def.objects + 1] = rcpt
  local warpIndex = #def.warps + 1
  local room = RoomMap.build(maps, tilesets, {
    map = M.MAP_ID, warp = warpIndex, group = def.group, mapNum = def.map,
  })
  def.warps[warpIndex] = {
    x = plan.doorX, y = plan.doorY, destMap = room.id, destWarp = 1,
    destGroup = room.group, destMapNum = room.map,
  }
  local leaveScene = 0
  for id, row in pairs(def.sceneScripts or {}) do
    local sid = type(row) == "table" and row.sceneId or id
    if type(sid) == "number" and sid >= leaveScene then leaveScene = sid + 1 end
  end
  def.sceneScripts = def.sceneScripts or {}
  def.sceneScripts[leaveScene] = { sceneId = leaveScene, scriptKey = M.LEFT_KEY }
  maps[room.id] = room
  addScripts(data, def, room, plan, rcpt.index + 1, leaveScene)
  applied[maps] = true
  return true
end

function M.noteWarp(world, prevMapId, prevWarpIndex, warpDef, destMapId, arrival)
  if destMapId ~= M.MAP_ID or not (arrival and arrival.destWarp == 0xff) then return end
  local maps = world and world.maps
  if not (maps and maps[M.ROOM_ID]) or prevMapId == M.MAP_ID then return end
  local game = world.game
  local save = game and game.save
  if not (save and warpDef) then return end
  Origin.record(save, {
    gen = 2, version = save.version or require("src.core.GameVersion").current,
    map = prevMapId, warp = prevWarpIndex, x = warpDef.x, y = warpDef.y,
    facing = world.player and world.player.facing,
  })
end

return M
