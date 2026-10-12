local Plaza = require("src.core.game3.link.union_plaza_map")

local UnionRoomMap = {}

UnionRoomMap.MAP_ID = "UNION_ROOM"
UnionRoomMap.LABEL = "UnionRoom"
UnionRoomMap.TILESET = "CLUB"
UnionRoomMap.WIDTH = 13
UnionRoomMap.HEIGHT = 13
UnionRoomMap.CAP = Plaza.CAP
UnionRoomMap.EXIT_X, UnionRoomMap.EXIT_Y = 12, 25
UnionRoomMap.EXITS = { { x = 12, y = 25 }, { x = 13, y = 25 } }
UnionRoomMap.TEXT_ATTENDANT = "TEXT_UNION_ROOM_ATTENDANT"
UnionRoomMap.TEXT_BOARD = "TEXT_UNION_ROOM_TRADING_BOARD"
UnionRoomMap.ATTENDANT = { x = 3, y = 2 }
UnionRoomMap.BOARD = { x = 2, y = 1 }

local WALL_LEFT, WALL, POSTER, WALL_RIGHT = 27, 3, 19, 23
local FLOOR, CARPET = 10, 1

function UnionRoomMap.cellFor(slot)
  return Plaza.cellFor(slot)
end

function UnionRoomMap.slotAt(x, y)
  return Plaza.slotAt(x, y)
end

function UnionRoomMap.entry()
  return UnionRoomMap.EXIT_X, UnionRoomMap.EXIT_Y, "up"
end

function UnionRoomMap.blocks()
  local w, h = UnionRoomMap.WIDTH, UnionRoomMap.HEIGHT
  local out = {}
  for by = 0, h - 1 do
    for bx = 0, w - 1 do
      local b = FLOOR
      if by == 0 then
        b = (bx == 0 and WALL_LEFT) or (bx == w - 1 and WALL_RIGHT)
            or ((bx == 6 or bx == math.floor(UnionRoomMap.BOARD.x / 2)) and POSTER) or WALL
      elseif by == h - 1 and bx == 6 then
        b = CARPET
      end
      out[by * w + bx + 1] = b
    end
  end
  return out
end

function UnionRoomMap.build(borderBlock, floor2Id, floor2DoorWarp)
  local warps = {}
  for i, e in ipairs(UnionRoomMap.EXITS) do
    warps[i] = { x = e.x, y = e.y, destMap = floor2Id, destWarp = floor2DoorWarp }
  end
  return {
    id = UnionRoomMap.MAP_ID, label = UnionRoomMap.LABEL,
    tileset = UnionRoomMap.TILESET,
    width = UnionRoomMap.WIDTH, height = UnionRoomMap.HEIGHT,
    borderBlock = borderBlock,
    blocks = UnionRoomMap.blocks(),
    warps = warps,
    objects = {
      { index = 1, movement = "STAY", range = "DOWN", sprite = "SPRITE_NURSE",
        x = UnionRoomMap.ATTENDANT.x, y = UnionRoomMap.ATTENDANT.y,
        name = "UNION_ROOM_ATTENDANT", text = UnionRoomMap.TEXT_ATTENDANT },
    },
    signs = { { x = UnionRoomMap.BOARD.x, y = UnionRoomMap.BOARD.y, text = UnionRoomMap.TEXT_BOARD } },
    connections = {},
  }
end

return UnionRoomMap
