-- Extract FRLG trainer tables + player back pics into data/generated/gba/trainers/.

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")
local Lz77 = require("src.import.gba.lz77")

local TrainerExtract = {}

TrainerExtract.FORMAT_VERSION = 4
TrainerExtract.CACHE_SUB = "trainers"

-- Party mon strides (ARM EABI sizes used by FRLG gTrainers parties).
local PARTY_STRIDE = {
  [0] = 8,  -- NoItemDefaultMoves
  [1] = 16, -- NoItemCustomMoves
  [2] = 8,  -- ItemDefaultMoves
  [3] = 16, -- ItemCustomMoves
}

local function read_last_level(rom, partyFlags, partySize, partyPtr)
  partyFlags = tonumber(partyFlags) or 0
  partySize = tonumber(partySize) or 0
  if partySize < 1 or not partyPtr or partyPtr < 0x08000000 then return nil end
  local stride = PARTY_STRIDE[partyFlags % 4] or 8
  local off = (partyPtr - 0x08000000) + (partySize - 1) * stride
  local lvl = rom:get(off + 2)
  if type(lvl) ~= "number" or lvl < 1 or lvl > 100 then return nil end
  return lvl
end

local function read_items(rom, off)
  local items = {}
  for i = 0, 3 do
    items[i + 1] = rom:u16(off + 0x10 + i * 2) or 0
  end
  return items
end

local function items_lua(items)
  return string.format("{%d,%d,%d,%d}",
    items[1] or 0, items[2] or 0, items[3] or 0, items[4] or 0)
end

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

local function decode_name(rom, off, length)
  length = length or 12
  local chars = {}
  local i = 0
  while i < length do
    local b = rom:get(off + i)
    if b == 0xFF then break end
    if b == 0x53 and i + 1 < length and rom:get(off + i + 1) == 0x54 then
      chars[#chars + 1] = "POKéMON"
      i = i + 2
    else
      local ch = TextIR.CHARMAP[b]
      if ch and ch ~= "" then
        chars[#chars + 1] = ch
      elseif b >= 0xBB and b <= 0xD4 then
        chars[#chars + 1] = string.char(string.byte("A") + (b - 0xBB))
      elseif b >= 0xD5 and b <= 0xEE then
        chars[#chars + 1] = string.char(string.byte("a") + (b - 0xD5))
      elseif b == 0x00 then
        chars[#chars + 1] = " "
      end
      i = i + 1
    end
  end
  return table.concat(chars):gsub("%s+$", "")
end

local function lua_quote(s)
  return string.format("%q", tostring(s or ""))
end

local function pack_to_lua(pack)
  local lines = {
    "-- Auto-generated FRLG gTrainers / gTrainerClassNames.",
    "return {",
    string.format("  version = %d,", pack.version or 1),
    string.format("  trainerCount = %d,", pack.trainerCount or 0),
    string.format("  classCount = %d,", pack.classCount or 0),
    "  classNames = {",
  }
  for id = 0, (pack.classCount or 0) - 1 do
    lines[#lines + 1] = string.format("    [%d] = %s,", id, lua_quote(pack.classNames[id] or ""))
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  trainers = {"
  for id = 0, (pack.trainerCount or 0) - 1 do
    local t = pack.trainers[id]
    if t then
      lines[#lines + 1] = string.format(
        "    [%d] = { class=%d, pic=%d, name=%s, partySize=%d, lastLevel=%d, aiFlags=%d, items=%s },",
        id, t.class or 0, t.pic or 0, lua_quote(t.name), t.partySize or 0,
        t.lastLevel or 1, t.aiFlags or 0, items_lua(t.items or {}))
    end
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function decode_sheet_rgba(tiles, palBytes, frames)
  frames = math.max(1, tonumber(frames) or 1)
  local pal = {}
  for c = 0, 15 do
    local lo = palBytes[c * 2 + 1] or 0
    local hi = palBytes[c * 2 + 2] or 0
    pal[c] = lo + hi * 256
  end
  local rgb = {}
  for c = 0, 15 do
    local r, g, b = bgr555_to_rgb8(pal[c] or 0)
    rgb[c] = { r, g, b }
  end
  local w, h = 64, 64 * frames
  local chunks = {}
  local ti = 0
  local tilesH = 8 * frames
  for ty = 0, tilesH - 1 do
    for tx = 0, 7 do
      local tileOff = ti * 32
      for row = 0, 7 do
        for bx = 0, 3 do
          local bi = tileOff + row * 4 + bx + 1
          local byte = tiles[bi] or 0
          local p0 = byte % 16
          local p1 = math.floor(byte / 16) % 16
          local x0 = tx * 8 + bx * 2
          local y0 = ty * 8 + row
          local function put(x, y, idx)
            local i = y * w + x + 1
            if idx == 0 then
              chunks[i] = string.char(0, 0, 0, 0)
            else
              local c = rgb[idx] or rgb[0]
              chunks[i] = string.char(c[1], c[2], c[3], 255)
            end
          end
          put(x0, y0, p0)
          put(x0 + 1, y0, p1)
        end
      end
      ti = ti + 1
    end
  end
  return table.concat(chunks), w, h
end

local function bake_back_pic(rom, gender)
  gender = tonumber(gender) or 0
  local picTable = Versions.TRAINER_BACK_PIC_TABLE or 0x239FA4
  local palTable = Versions.TRAINER_BACK_PIC_PAL_TABLE or 0x239FD4
  local sheetOff = picTable + gender * 8
  local palOff = palTable + gender * 8
  local function get(i) return rom:get(i) end
  local function u32(off)
    if rom.u32 then return rom:u32(off) end
    return rom:get(off)
      + rom:get(off + 1) * 256
      + rom:get(off + 2) * 65536
      + rom:get(off + 3) * 16777216
  end
  local tilePtr = u32(sheetOff)
  local palPtr = u32(palOff)
  local tileFile = Versions.gbaToFile(tilePtr)
  local palFile = Versions.gbaToFile(palPtr)
  if not tileFile or not palFile then return nil end
  -- size field at sheetOff+4: 0x2800 → 5 frames. Back pics are raw 4bpp
  -- (pret INCBIN .4bpp), not LZ — unlike front pics.
  local sizeLo = rom:get(sheetOff + 4) or 0
  local sizeHi = rom:get(sheetOff + 5) or 0
  local size = sizeLo + sizeHi * 256
  if size < 0x800 then size = 0x2800 end
  local frames = math.max(1, math.floor(size / 0x800))
  local tiles = {}
  for i = 0, size - 1 do
    tiles[i + 1] = rom:get(tileFile + i) or 0
  end
  local okP, palBytes = pcall(Lz77.decompress, get, palFile)
  if not okP or type(palBytes) ~= "table" then return nil end
  return decode_sheet_rgba(tiles, palBytes, frames)
end

--- Opponent front pics are LZ77; bake so LOVE never needs the ROM at battle time.
local function bake_front_pic(rom, picId)
  picId = tonumber(picId)
  if not picId or picId < 0 then return nil end
  local picTable = Versions.TRAINER_FRONT_PIC_TABLE or 0x23957C
  local palTable = Versions.TRAINER_FRONT_PIC_PAL_TABLE or 0x239A1C
  local sheetOff = picTable + picId * 8
  local palOff = palTable + picId * 8
  local function get(i) return rom:get(i) end
  local function u32(off)
    if rom.u32 then return rom:u32(off) end
    return rom:get(off)
      + rom:get(off + 1) * 256
      + rom:get(off + 2) * 65536
      + rom:get(off + 3) * 16777216
  end
  local tilePtr = u32(sheetOff)
  local palPtr = u32(palOff)
  local tileFile = Versions.gbaToFile(tilePtr)
  local palFile = Versions.gbaToFile(palPtr)
  if not tileFile or not palFile then return nil end
  local sizeLo = rom:get(sheetOff + 4) or 0
  local sizeHi = rom:get(sheetOff + 5) or 0
  local size = sizeLo + sizeHi * 256
  local okT, tiles = pcall(Lz77.decompress, get, tileFile)
  if not okT or type(tiles) ~= "table" then return nil end
  -- Multi-frame front sheets (size 0x1000): first 64×64 only.
  if size >= 0x1000 and #tiles > 2048 then
    local trimmed = {}
    for i = 1, 2048 do trimmed[i] = tiles[i] end
    tiles = trimmed
  end
  local okP, palBytes = pcall(Lz77.decompress, get, palFile)
  if not okP or type(palBytes) ~= "table" then return nil end
  return decode_sheet_rgba(tiles, palBytes, 1)
end

function TrainerExtract.extract(rom, opts)
  opts = opts or {}
  local classBase = Versions.TRAINER_CLASS_NAMES or 0x23E558
  local classStride = Versions.TRAINER_CLASS_NAME_STRIDE or 13
  local classCount = Versions.TRAINER_CLASS_COUNT or 107
  local trainersBase = Versions.TRAINERS_TABLE or 0x23EAC8
  local stride = Versions.TRAINER_STRIDE or 0x28
  local trainerCount = Versions.TRAINERS_COUNT or 743

  local classNames = {}
  for id = 0, classCount - 1 do
    classNames[id] = decode_name(rom, classBase + id * classStride, classStride)
  end

  local trainers = {}
  for id = 0, trainerCount - 1 do
    local off = trainersBase + id * stride
    local partyFlags = rom:get(off) or 0
    local class = rom:get(off + 1) or 0
    local pic = rom:get(off + 3) or 0
    local name = decode_name(rom, off + 4, 12)
    -- pret: partySize is u8 at +0x20; party pointer at +0x24.
    local partySize = rom:get(off + 0x20) or 0
    local partyPtr = rom:u32(off + 0x24)
    local lastLevel = read_last_level(rom, partyFlags, partySize, partyPtr)
    local aiFlags = rom:u32(off + 0x1C) or 0
    local items = read_items(rom, off)
    trainers[id] = {
      class = class,
      pic = pic,
      name = name,
      partySize = partySize,
      partyFlags = partyFlags,
      lastLevel = lastLevel or 1,
      aiFlags = aiFlags,
      items = items,
    }
  end

  return {
    version = TrainerExtract.FORMAT_VERSION,
    classCount = classCount,
    trainerCount = trainerCount,
    classNames = classNames,
    trainers = trainers,
  }
end

function TrainerExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. TrainerExtract.CACHE_SUB
  local pack = TrainerExtract.extract(rom, opts)
  cache:write(cacheRoot .. "/trainers.lua", pack_to_lua(pack))
  cache:write(root .. "/manifest.lua", string.format(
    "return { version = %d, trainerCount = %d, classCount = %d }\n",
    pack.version, pack.trainerCount, pack.classCount))

  for gender = 0, 1 do
    local rgba = bake_back_pic(rom, gender)
    if rgba then
      cache:write(root .. "/back_" .. gender .. ".rgba", rgba)
    end
  end

  -- Eager-bake every front pic so battle intro never depends on ROM-in-cwd.
  local picCount = Versions.TRAINER_PIC_COUNT or 148
  local baked = 0
  for picId = 0, picCount - 1 do
    local rgba = bake_front_pic(rom, picId)
    if rgba then
      cache:write(root .. "/front/" .. picId .. ".rgba", rgba)
      baked = baked + 1
    end
  end

  return { pack = pack, root = root, frontPics = baked }
end

function TrainerExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root())
  if cache and cache.exists and cache:exists(root .. "/trainers.lua") then
    return true
  end
  if cache and cache.read and cache:read(root .. "/trainers.lua") then
    return true
  end
  return false
end

return TrainerExtract
