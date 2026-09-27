local F = {}

F.name = "rse"

-- pokeemerald/include/fieldmap.h:4
F.numPrimaryTiles = 512
F.numTilesTotal = 1024
F.numPrimaryMetatiles = 512
F.numMetatilesTotal = 1024
F.numPalsInPrimary = 6
F.numPalsTotal = 13
F.metatileBytes = 16

-- pokeemerald/include/global.fieldmap.h:75
F.layoutSize = 24

-- pokeemerald/include/global.fieldmap.h:64
F.tilesetOffsets = { tiles = 4, palettes = 8, metatiles = 12, attributes = 16, callback = 20 }

F.attrBytes = 2

F.cloneObjects = false

-- pokeemerald/include/constants/event_bg.h:10
F.hiddenItemBgKind = 7
F.secretBaseBgKind = 8

F.encounterSource = "behaviorTable"

F.aliases = false

F.games = {}

-- pokeemerald/include/constants/global.h:149
F.connDirs = { [1] = "south", [2] = "north", [3] = "west", [4] = "east", [5] = "dive", [6] = "emerge" }

-- pokeemerald/include/global.fieldmap.h:39
function F.behaviorOf(w)
  return w % 256
end

function F.layerOf(w)
  return math.floor((tonumber(w) or 0) / 0x1000) % 16
end

function F.encounterOf()
  return nil
end

-- pokeemerald/src/fieldmap.c:51
function F:borderDims()
  return 2, 2
end

-- pokeemerald/include/global.fieldmap.h:185
function F:decodeHeaderFlags(rom, headerOff, out)
  local flags = rom:get(headerOff + 26) or 0
  out.allowCycling = flags % 2
  out.bikingAllowed = out.allowCycling
  out.allowEscaping = math.floor(flags / 2) % 2
  out.allowRunning = math.floor(flags / 4) % 2
  out.showMapName = math.floor(flags / 8) % 32
  out.battleType = rom:get(headerOff + 27)
  return out
end

-- pokeemerald/include/global.fieldmap.h:130
function F:hiddenItem(rom, base)
  return {
    item = rom:u16(base + 8),
    hiddenItemId = rom:u16(base + 10),
  }
end

function F:constants()
  return require("src.core.game3.constants").of(self.game)
end

function F:syms()
  return require("src.import.gba.syms").of(self.game)
end

local groupCache = {}

function F:groups()
  local cached = groupCache[self.game]
  if cached then return cached end
  local mg = self:constants().map_groups
  local out = { group_order = {}, groups = {}, consts = {} }
  for gi, g in ipairs(mg.groups) do
    out.group_order[gi] = g.name
    out.groups[gi - 1] = { name = g.name, maps = {} }
    out.consts[gi - 1] = {}
  end
  for const, row in pairs(mg.byName) do
    local g = out.groups[row.group]
    if g then
      g.maps[row.num + 1] = row.name
      out.consts[row.group][row.num] = const
    end
  end
  groupCache[self.game] = out
  return out
end

function F:mapConstAt(group, num)
  local c = self:groups().consts[tonumber(group) or -1]
  return c and c[tonumber(num) or -1] or nil
end

function F:tilesetName(structOff)
  if not structOff then return nil end
  for _, n in ipairs(self:syms().namesAt(structOff)) do
    local short = n:match("^gTileset_(.+)$")
    if short then
      return (short:gsub("(%l)(%u)", "%1_%2"):gsub("(%d)(%u)", "%1_%2"):lower())
    end
  end
  return nil
end

function F:uncompressedTileBytes(_, tilesOff, _, secondary)
  if not tilesOff then return nil end
  local S = self:syms()
  for _, n in ipairs(S.namesAt(tilesOff)) do
    if n:match("^gTilesetTiles_") then return S.size(n) end
  end
  local tiles = secondary and (self.numTilesTotal - self.numPrimaryTiles) or self.numPrimaryTiles
  return tiles * 32
end

return F
