package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local K = require("src.import.gba.rse.boot_gfx")

eq(select(1, K.objDims(0, 3)), 64, "square size 3 is 64 wide")
eq(select(2, K.objDims(1, 3)), 32, "wide size 3 is 32 tall")
eq(select(1, K.objDims(2, 2)), 16, "tall size 2 is 16 wide")
check(not pcall(K.objDims, 3, 0), "shape 3 is invalid")

local r, g, b = K.rgb8(0x7FFF)
eq(r + g + b, 765, "white BGR555")
r, g, b = K.rgb8(0x001F)
eq(r, 255, "red channel") eq(g, 0, "no green") eq(b, 0, "no blue")

local function tile4(fill)
  return string.rep(string.char(fill * 17), 32)
end

local gfx = tile4(0) .. tile4(3)
local map = string.char(1, 0x20) .. string.rep("\0", 2046)
local idx, W, H = K.bakeText(gfx, map, 32, 32)
eq(W, 256, "text layer width") eq(H, 256, "text layer height")
eq(idx[1], 2 * 16 + 3, "bank 2 colour 3 packs to 35")
eq(idx[9], 0, "tile 0 colour 0 is transparent")

local asym = string.char(0x21) .. string.rep("\0", 31)
local flipMap = string.char(0, 0x04) .. string.rep("\0", 2046)
idx = K.bakeText(asym, flipMap, 32, 32)
eq(idx[1], 0, "hflip moves the pixel off column 0")
eq(idx[8], 1, "hflip puts column 0 at column 7")

local tall = K.bakeText(gfx, string.rep("\0", 2048) .. string.char(1, 0), 32, 64)
eq(#tall, 256 * 512, "256x512 layer size")
eq(tall[256 * 256 + 1], 3, "second screen block starts at row 32")

local wide = K.bakeText(gfx, string.rep("\0", 2048) .. string.char(1, 0), 64, 32)
eq(wide[257], 3, "second screen block of a 512-wide map starts at column 32")

local g8 = string.rep("\0", 64) .. string.rep(string.char(200), 64)
local aff, AW = K.bakeAffine(g8, string.char(1) .. string.rep("\0", 1023), 32)
eq(AW, 256, "affine 256") eq(aff[1], 200, "8bpp affine keeps the full index") eq(aff[9], 0, "tile 0 index 0")

local spr = K.bakeSprite(string.rep("\0", 64) .. string.rep(string.char(7), 64), 8, 8, 2, 8)
eq(spr[1], 7, "8bpp sprite tile offsets count 32-byte units")
local s4 = K.bakeSprite(tile4(0) .. tile4(5), 16, 8, 0, 4)
eq(s4[1], 0, "1D mapping left tile") eq(s4[9], 5, "1D mapping right tile")

local stacked, SW, SH = K.stack({ { 1, 2 }, { 3, 4 } }, 2, 1)
eq(SW, 2, "stack width") eq(SH, 2, "stack height") eq(stacked[3], 3, "second frame below the first")

local png = K.encodeIndexed(3, 2, { 0, 1, 2, 2, 1, 0 }, { [0] = 0, 0x7FFF, 0x001F }, true)
local pw, ph = K.pngSize(png)
eq(pw, 3, "png width") eq(ph, 2, "png height")
check(png:find("PLTE", 1, true) ~= nil, "indexed png has PLTE")
check(png:find("tRNS", 1, true) ~= nil, "transparent png has tRNS")
check(K.encodeIndexed(1, 1, { 0 }, { [0] = 0 }, false):find("tRNS", 1, true) == nil, "opaque png has no tRNS")
eq(select(1, K.pngSize(K.encodeGray(4, 5, K.blank(4, 5)))), 4, "gray png width")

local stored = K.zlibStored(string.rep("a", 70000))
eq(stored:byte(1), 0x78, "zlib header")
eq(#stored, 2 + 70000 + 5 * 2 + 4, "two stored blocks plus adler")

local mods = {
  "extract_intro_emerald", "intro_credits_gfx_extract", "extract_title_rse",
  "extract_birch_rse", "extract_naming_rse", "extract_wallclock_rse",
}
local seen, all = {}, {}
for _, name in ipairs(mods) do
  local M = require("src.import.gba.rse." .. name)
  check(type(M.run) == "function" and type(M.ready) == "function", name .. " exposes run/ready")
  check(#M.REQUIRED > 1, name .. " exports REQUIRED")
  eq(M.REQUIRED[1], M.SUB .. "/manifest.lua", name .. " manifest is first")
  for _, rel in ipairs(M.REQUIRED) do
    check(not seen[rel], "unique required path " .. rel)
    seen[rel] = true
    all[#all + 1] = rel
  end
end

local plan = require("src.import.gba.plans.rse.boot")
local Plans = require("src.import.gba.plans.registry")
local stepMods = {}
for _, t in ipairs(plan.tasks) do
  eq(t.run, "steps", t.id .. " is a steps task")
  check(t.id:match("^em_boot_") ~= nil, t.id .. " is namespaced")
  for _, s in ipairs(t.steps) do
    local modName = Plans.moduleFor(s.name)
    check(pcall(require, modName), modName .. " resolves")
    stepMods[modName] = true
  end
end
for _, name in ipairs(mods) do
  check(stepMods["src.import.gba.rse." .. name], name .. " is in the boot plan")
end

local okCC, CacheContract = pcall(require, "src.import.CacheContract")
if okCC and CacheContract.planFilesFor then
  local files = {}
  for _, f in ipairs(CacheContract.planFilesFor("emerald")) do files[f] = true end
  local missing = 0
  for _, rel in ipairs(all) do
    if not files["data/generated/gba/" .. rel] then missing = missing + 1 end
  end
  eq(missing, 0, "every boot REQUIRED path is in the emerald cache contract")
end

local V = require("src.import.gba.games.emerald")
check(type(V.NAMING) == "table" and V.NAMING.menu_gfx ~= nil, "emerald NAMING keys")
eq(V.NAMING.rival_gfx, nil, "no FRLG rival naming art on emerald")
eq(V.BOOT_RSE_FORMAT, K.FORMAT, "boot format stamp")

local memo = {}
local fakeCache = { read = function(_, rel) return memo[rel] end }
check(not K.ready("title", fakeCache, "data/generated/gba"), "not ready without a manifest")
memo["data/generated/gba/title/manifest.lua"] = "return {\n  format = " .. K.FORMAT .. ",\n}\n"
check(K.ready("title", fakeCache, "data/generated/gba"), "ready with a current manifest")
memo["data/generated/gba/title/manifest.lua"] = "return {\n  format = 0,\n}\n"
check(not K.ready("title", fakeCache, "data/generated/gba"), "stale format is not ready")

T.finish("game3_emerald_boot_assets_test")
