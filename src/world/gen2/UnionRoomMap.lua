local UnionRoomMap = {}

UnionRoomMap.ID = "UNION_ROOM"
UnionRoomMap.TEMPLATE = "TRADE_CENTER"
UnionRoomMap.CAP = 40
UnionRoomMap.WIDTH_BLOCKS = 13
UnionRoomMap.HEIGHT_BLOCKS = 13
UnionRoomMap.WIDTH = UnionRoomMap.WIDTH_BLOCKS * 2
UnionRoomMap.HEIGHT = UnionRoomMap.HEIGHT_BLOCKS * 2
UnionRoomMap.EXIT_X, UnionRoomMap.EXIT_Y = 12, 25
UnionRoomMap.EXITS = { { x = 12, y = 25 }, { x = 13, y = 25 } }
UnionRoomMap.SETUP_KEY = "union:room_setup"
UnionRoomMap.ATTENDANT = { x = 3, y = 2 }
UnionRoomMap.BOARD = { x = 2, y = 1 }
UnionRoomMap.ATTENDANT_INDEX = 1

local CELL_XS = { 3, 6, 9, 12, 15, 18, 21 }
local CELL_YS = { 5, 8, 11, 14, 17, 20 }
local DOOR_X, DOOR_Y = 12, 23

local cells, bySlot, byKey = {}, {}, {}
for _, y in ipairs(CELL_YS) do
  for _, x in ipairs(CELL_XS) do
    if not (x == DOOR_X and y == 20) then
      cells[#cells + 1] = { x = x, y = y }
    end
  end
end
table.sort(cells, function(p, q)
  local dp = math.abs(p.x - DOOR_X) + math.abs(p.y - DOOR_Y)
  local dq = math.abs(q.x - DOOR_X) + math.abs(q.y - DOOR_Y)
  if dp ~= dq then return dp < dq end
  local ap, aq = math.abs(p.x - DOOR_X), math.abs(q.x - DOOR_X)
  if ap ~= aq then return ap < aq end
  if p.x ~= q.x then return p.x < q.x end
  return p.y > q.y
end)
for i, c in ipairs(cells) do
  if i <= UnionRoomMap.CAP then
    bySlot[i] = c
    byKey[c.y * 64 + c.x] = i
  end
end
UnionRoomMap.CELLS = cells

function UnionRoomMap.cellFor(slot)
  local c = bySlot[tonumber(slot) or -1]
  if not c then return nil end
  return c.x, c.y, "down"
end

function UnionRoomMap.slotAt(x, y)
  x, y = tonumber(x), tonumber(y)
  if not (x and y) then return nil end
  return byKey[y * 64 + x]
end

function UnionRoomMap.entry()
  return UnionRoomMap.EXIT_X, UnionRoomMap.EXIT_Y, "up"
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

function UnionRoomMap.block(tileset, tiles, coll)
  for id = 1, #tileset.blocks do
    if same(tileset.blocks[id], tiles) and tileset.collision[id]
        and same(tileset.collision[id], coll) then
      return id - 1
    end
  end
  local id = #tileset.blocks + 1
  tileset.blocks[id] = tiles
  tileset.collision[id] = coll
  return id - 1
end

function UnionRoomMap.compose(tileset, top, bottom)
  local tt, bt = tileset.blocks[top + 1], tileset.blocks[bottom + 1]
  local tc, bc = tileset.collision[top + 1], tileset.collision[bottom + 1]
  local tiles = {}
  for i = 1, 8 do tiles[i] = tt[i] end
  for i = 9, 16 do tiles[i] = bt[i] end
  return UnionRoomMap.block(tileset, tiles, { tc[1], tc[2], bc[3], bc[4] })
end

function UnionRoomMap.talkAttendant(world)
  return require("src.world.gen2.UnionRoomPresence").talkBoard(world, "attendant")
end

function UnionRoomMap.talkBoard(world)
  return require("src.world.gen2.UnionRoomPresence").talkBoard(world, "check")
end

local function nurseTemplate(maps)
  local ids = {}
  for id in pairs(maps) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    for _, o in ipairs(type(maps[id]) == "table" and maps[id].objects or {}) do
      if o.sprite == "SPRITE_NURSE" then return o end
    end
  end
  error("gen2 cache has no SPRITE_NURSE object")
end

local function blockAt(def, bx, by)
  return def.blocks[by * def.width + bx + 1]
end

local function nextMapNumber(maps, group)
  local top = 0
  for _, def in pairs(maps) do
    if type(def) == "table" and def.group == group and (def.map or 0) > top then
      top = def.map
    end
  end
  return top + 1
end

local COPIED = {
  "borderBlock", "environment", "environmentId", "fishGroup", "generation",
  "group", "landmark", "music", "palette", "phoneService", "tileset",
  "tilesetId",
}

function UnionRoomMap.build(maps, tilesets, link)
  local src = assert(maps[UnionRoomMap.TEMPLATE], "gen2 cache has no TRADE_CENTER")
  local tileset = assert(tilesets[src.tileset], "gen2 cache has no " .. tostring(src.tileset))
  local wall = blockAt(src, 0, 0)
  local floor = blockAt(src, 0, 1)
  local exit = src.warps[1]
  local mat = blockAt(src, math.floor(exit.x / 2), math.floor(exit.y / 2))
  local exitBlock = (exit.y % 2 == 1) and UnionRoomMap.compose(tileset, floor, mat)
    or UnionRoomMap.compose(tileset, mat, floor)
  local w, h = UnionRoomMap.WIDTH_BLOCKS, UnionRoomMap.HEIGHT_BLOCKS
  local blocks = {}
  for by = 0, h - 1 do
    for bx = 0, w - 1 do
      blocks[by * w + bx + 1] = (by == 0) and wall or floor
    end
  end
  blocks[math.floor(UnionRoomMap.EXIT_Y / 2) * w
    + math.floor(UnionRoomMap.EXIT_X / 2) + 1] = exitBlock
  local def = {}
  for _, key in ipairs(COPIED) do def[key] = src[key] end
  def.id = UnionRoomMap.ID
  def.map = nextMapNumber(maps, src.group)
  def.source = "union"
  def.width, def.height = w, h
  def.blocks = blocks
  def.warps = {}
  for _, cell in ipairs(UnionRoomMap.EXITS) do
    def.warps[#def.warps + 1] = {
      x = cell.x, y = cell.y, destMap = link.map, destWarp = link.warp,
      destGroup = link.group, destMapNum = link.mapNum,
    }
  end
  local nurse = {}
  for k, v in pairs(nurseTemplate(maps)) do nurse[k] = v end
  nurse.index = UnionRoomMap.ATTENDANT_INDEX
  nurse.x, nurse.y = UnionRoomMap.ATTENDANT.x, UnionRoomMap.ATTENDANT.y
  nurse.scriptKey, nurse.script = nil, nil
  nurse.eventFlag = 65535
  nurse.onTalk = UnionRoomMap.talkAttendant
  def.objects = { nurse }
  def.bgEvents = { { kind = 0, x = UnionRoomMap.BOARD.x, y = UnionRoomMap.BOARD.y,
                     onTalk = UnionRoomMap.talkBoard } }
  def.coordEvents = {}
  def.callbacks = {}
  def.connections = {}
  def.sceneScripts = {
    [0] = { sceneId = 0, scriptKey = UnionRoomMap.SETUP_KEY },
    [1] = { sceneId = 1 },
  }
  return def
end

return UnionRoomMap
