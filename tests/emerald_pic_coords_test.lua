package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local FR_ROOT = os.getenv("POKEFIRERED") or "../pokefirered"
local EM_ROM = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local GV = require("src.core.GameVersion")
local Rom = require("src.import.gba.rom")
local Versions = require("src.import.gba.versions")
local PicCoords = require("src.import.gba.pic_coords_extract")

local function openRom(path, sha)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return assert(Rom.open({
    info = function() return { size = #data, md5 = sha } end,
    read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
  }, GV.forSha1(sha)))
end

local function elfSymbols(elf, wanted)
  for _, tool in ipairs({ "arm-none-eabi-readelf", "readelf" }) do
    local p = io.popen(tool .. " -sW " .. elf .. " 2>/dev/null")
    if p then
      local out = {}
      for line in p:lines() do
        local addr, size, name = line:match("^%s*%d+:%s+(%x+)%s+(%d+)%s+OBJECT%s+%S+%s+%S+%s+%S+%s+(%S+)$")
        if name and wanted[name] then out[name] = { off = tonumber(addr, 16) - 0x08000000, size = tonumber(size) } end
      end
      p:close()
      if next(out) then return out end
    end
  end
  return nil
end

local ran = false

local fr = openRom(FR_ROOT .. "/pokefirered.gba", GV.VERSIONS.firered.sha1)
local syms = fr and elfSymbols(FR_ROOT .. "/pokefirered.elf",
  { gMonFrontPicCoords = true, gMonBackPicCoords = true, gEnemyMonElevation = true })
if fr and syms and syms.gMonFrontPicCoords and syms.gMonBackPicCoords and syms.gEnemyMonElevation then
  ran = true
  local pack = PicCoords.extract(fr, {
    front = syms.gMonFrontPicCoords.off,
    back = syms.gMonBackPicCoords.off,
    elevation = syms.gEnemyMonElevation.off,
    stride = 4,
    count = syms.gMonFrontPicCoords.size / 4,
    elevationCount = syms.gEnemyMonElevation.size,
  })
  local Hand = dofile("src/core/game3/battle/pic_coords.lua")
  eq(pack.count, 440, "FR pic coord rows")
  local frontBad, backBad, rows = 0, 0, 0
  for sp, y in pairs(Hand.front) do
    rows = rows + 1
    if pack.front[sp].y ~= y then frontBad = frontBad + 1 end
  end
  for sp, y in pairs(Hand.back) do
    if pack.back[sp].y ~= y then backBad = backBad + 1 end
  end
  eq(rows, 413, "hand table front rows")
  eq(frontBad, 0, "FR-extracted front y_offset equals the hand table for every row")
  eq(backBad, 0, "FR-extracted back y_offset equals the hand table for every row")
  local elevBad = 0
  for sp = 0, pack.elevationCount - 1 do
    if (Hand.elev[sp] or 0) ~= pack.elevation[sp] then elevBad = elevBad + 1 end
  end
  for sp in pairs(Hand.elev) do
    if pack.elevation[sp] == nil then elevBad = elevBad + 1 end
  end
  eq(pack.elevationCount, 412, "FR elevation rows")
  eq(elevBad, 0, "FR-extracted gEnemyMonElevation equals the hand table for every row")
  local back = assert(load(PicCoords.toLua(pack)))()
  eq(back.front[1].y, pack.front[1].y, "pack round-trips through Lua")
else
  print("emerald_pic_coords_test: FR half skipped (pokefirered ROM/ELF or readelf missing)")
end

local em = openRom(EM_ROM, GV.VERSIONS.emerald.sha1)
if em then
  ran = true
  eq(Versions.active(), "emerald", "Emerald key table selected")
  local pack = PicCoords.extract(em)
  eq(pack.count, 440, "Emerald pic coord rows")
  eq(pack.front[1].size, 0x45, "Emerald Bulbasaur size MON_COORDS_SIZE(32, 40)")
  eq(pack.front[1].width, 32, "Emerald Bulbasaur drawn width")
  eq(pack.front[1].height, 40, "Emerald Bulbasaur drawn height")
  eq(pack.front[1].y, 14, "Emerald Bulbasaur y_offset (front_pic_coordinates.h:7)")
  local Hand = dofile("src/core/game3/battle/pic_coords.lua")
  local differ = 0
  for sp, y in pairs(Hand.front) do
    if pack.front[sp].y ~= y then differ = differ + 1 end
  end
  check(differ > 0, "Emerald coords differ from the FRLG hand table (" .. differ .. " rows)")
  eq(pack.elevationCount, 412, "Emerald elevation rows")
else
  print("emerald_pic_coords_test: Emerald half skipped (no ROM at " .. EM_ROM .. ")")
end

if not ran then
  print("emerald_pic_coords_test: skipped")
  os.exit(0)
end
T.finish("emerald_pic_coords_test")
