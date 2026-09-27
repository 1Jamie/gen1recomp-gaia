package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local PRET = os.getenv("POKEEMERALD") or "../pokeemerald"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_pokemon_pack_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()

local SHA = "f3ae088181bf583e55daf962a92bb46f4f1d07b7"
local rom = assert(require("src.import.gba.rom").open({
  info = function() return { size = #data, md5 = SHA } end,
  read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
}, "emerald"))
local Versions = require("src.import.gba.versions")
eq(Versions.active(), "emerald", "the ROM selects the Emerald key table")

local files = {}
local cache = {
  write = function(_, rel, b) files[rel] = b; return true end,
  read = function(_, rel) return files[rel] end,
  exists = function(_, rel) return files[rel] ~= nil end,
}
local ROOT = "R"
local function pack(rel) return assert(load(assert(files[ROOT .. "/pokemon/" .. rel], rel)))() end
local function file(rel) return files[ROOT .. "/pokemon/" .. rel] end

local PE = require("src.import.gba.pokemon_extract")
local plan = require("src.import.gba.plans.rse.pokemon_gfx")
for _, task in ipairs(plan.tasks) do
  for _, step in ipairs(task.steps) do
    local opts = { cacheRoot = ROOT }
    for k, v in pairs(step.opts or {}) do opts[k] = v end
    require("src.import.gba." .. step.name).run(rom, cache, opts)
  end
end

local names, stats, meta = pack("names.lua"), pack("stats.lua"), pack("meta.lua")
eq(names[277], "TREECKO", "species 277 is TREECKO")
eq(names[410], "DEOXYS", "species 410 is DEOXYS")
local d = stats[410]
eq(table.concat({ d.hp, d.atk, d.def, d.spe, d.spa, d.spd }, "/"), "50/95/90/180/95/90",
  "Deoxys in-game stats are the Emerald Speed forme")
eq(table.concat(meta[410].linkStats, "/"), "50/150/50/150/150/50", "Deoxys link stats are the normal forme")

local moves = require("src.import.gba.battle_moves_extract").extract(rom).moves
eq(moves[267].accuracy, 95, "move 267 Nature Power accuracy 95")
eq(moves[289].flags, 0x10, "move 289 Snatch flags 0x10")
eq(pack("move_names.lua")[1], "POUND", "move 1 POUND")

local hoenn, regional = pack("hoenn.lua"), pack("regional_dex.lua")
eq(hoenn.toHoenn[277], 1, "Treecko is Hoenn #1")
eq(hoenn.toSpecies[1], 277, "Hoenn #1 is species 277")
eq(regional.count, 202, "Hoenn dex count 202")
eq(regional.order[1], 252, "Hoenn #1 is national 252")
eq(pack("national.lua").toNational[277], 252, "Treecko is national 252")
eq(pack("type_names.lua")[13], "ELECTR", "type 13 ELECTR")
eq(pack("exp_table.lua")[0][100], 1000000, "medium fast level 100 exp")
eq(#pack("learnsets.lua")[277] > 0, true, "Treecko has a level-up learnset")
eq(pack("dex.lua")[252].category, "WOOD GECKO", "national 252 category")

local PIC = 64 * 64 * 4
local anim = file("front_anim/277.rgba")
eq(anim and #anim, 64 * 128 * 4, "front_anim/277 is a 64x128 RGBA sheet")
check(anim and anim:sub(1, PIC) ~= anim:sub(PIC + 1), "Treecko frame 1 differs from frame 0")
eq(file("front/277.rgba"), anim and anim:sub(1, PIC), "front/277 is frame 0 of the sheet")
check(file("front_anim_shiny/277.rgba") ~= anim, "shiny sheet differs from the normal sheet")
eq(#(file("front_still/277.rgba") or ""), PIC, "still front pic")
eq(#(file("back/277.rgba") or ""), PIC, "back pic")

local deoxysAnim = file("front_anim/410.rgba")
eq(file("front/410_handled.rgba"), deoxysAnim and deoxysAnim:sub(PIC + 1),
  "DuplicateDeoxysTiles: the handled front is frame 1")
local handled = file("front_anim/410_handled.rgba") or ""
eq(handled:sub(1, PIC), handled:sub(PIC + 1), "handled Deoxys sheet repeats frame 1")
eq(#(file("back/410_handled.rgba") or ""), PIC, "handled Deoxys back pic")
check(file("icons/410_handled.rgba") ~= file("icons/410.rgba"), "the handled Deoxys icon is the second icon")

for form = 1, 3 do
  check(file("front/385_" .. form .. ".rgba") ~= nil, "Castform front form " .. form)
  check(file("back/385_" .. form .. ".rgba") ~= nil, "Castform back form " .. form)
end
check(file("front_anim/385.rgba") == nil, "Castform has no 2-frame sheet")
check(file("front_anim/439.rgba") ~= nil, "Unown ? has a 2-frame sheet")

local icons = 0
for rel in pairs(files) do
  if rel:match("^R/pokemon/icons/%d+%.rgba$") then icons = icons + 1 end
end
eq(icons, Versions.MON_ICON_COUNT, "one icon per gMonIconTable entry")
eq(pack("icons.lua").count, 440, "icon palette index count")
local footprints = 0
for rel in pairs(files) do
  if rel:match("^R/pokemon/footprints/%d+%.rgba$") then footprints = footprints + 1 end
end
eq(footprints, Versions.MON_FOOTPRINT_COUNT, "one footprint per gMonFootprintTable entry")

local coords = pack("pic_coords.lua")
eq(coords.count, 440, "pic coords rows")
eq(coords.front[1].size, 0x45, "Bulbasaur front coords size (Emerald)")
eq(coords.front[1].y, 14, "Bulbasaur front y_offset (Emerald)")

local anims = pack("front_anims.lua")
local tl = anims.lists[anims.species[277][2]]
eq(tl.name, "sAnim_Treecko_1", "Treecko anim list")
local seq = {}
for _, c in ipairs(tl.cmds) do seq[#seq + 1] = c.op or (c.frame .. ":" .. c.duration) end
eq(table.concat(seq, " "), "0:6 1:15 0:6 1:15 0:3 end", "Treecko anim cmds (front_pic_anims.h:2920)")
local delays, maxId = 0, 0
for sp, v in pairs(anims.animDelays) do delays = delays + 1 end
for _, v in pairs(anims.animIds) do if v > maxId then maxId = v end end
eq(delays, 411, "animation delay table covers every species")
check(maxId < #anims.functions + 1, "anim ids index sMonAnimFunctions")
eq(#pack("back_anims.lua").natureMods + 1, 25, "back anim nature mods")

eq(#(files[ROOT .. "/pokemon/egg/hatch.rgba"] or ""), 32 * 128 * 4, "egg hatch sheet")
eq(#(file("front/412.rgba") or ""), PIC, "egg front pic")

for _, rel in ipairs(PE.REQUIRED) do
  check(files[ROOT .. "/" .. rel] ~= nil, "REQUIRED " .. rel)
end
check(PE.ready(cache, ROOT), "pokemon pack ready")

local function pngIndices(path)
  local p = io.popen("python3 -c \"import sys;from PIL import Image;im=Image.open(sys.argv[1]);"
    .. "sys.stdout.write(' '.join(map(str,im.getdata())))\" " .. path .. " 2>/dev/null")
  if not p then return nil end
  local out = p:read("*a")
  p:close()
  if out == "" then return nil end
  local t = {}
  for n in out:gmatch("%d+") do t[#t + 1] = tonumber(n) end
  return t
end

local function palette(path)
  local h = io.open(path, "r")
  if not h then return nil end
  local lines = {}
  for line in h:lines() do lines[#lines + 1] = line end
  h:close()
  local pal = {}
  for i = 0, 15 do
    local r, g, b = lines[4 + i]:match("(%d+)%s+(%d+)%s+(%d+)")
    local function c8(v) return math.floor(math.floor(tonumber(v) / 8) * 255 / 31 + 0.5) end
    pal[i] = { c8(r), c8(g), c8(b) }
  end
  return pal
end

local function pixelExact(png, pal, rgba, limit)
  local idx, colors = pngIndices(png), palette(pal)
  if not (idx and colors) then return nil end
  local bad = 0
  for i, p in ipairs(idx) do
    if limit and i > limit then break end
    local a, b, c, al = rgba:byte((i - 1) * 4 + 1, (i - 1) * 4 + 4)
    if p == 0 then
      if al ~= 0 then bad = bad + 1 end
    else
      local e = colors[p]
      if not (a == e[1] and b == e[2] and c == e[3] and al == 255) then bad = bad + 1 end
    end
  end
  return bad, #idx
end

local bad, n = pixelExact(PRET .. "/graphics/pokemon/treecko/anim_front.png",
  PRET .. "/graphics/pokemon/treecko/normal.pal", anim or "")
if bad then
  eq(n, 64 * 128, "pret Treecko anim_front.png is 64x128")
  eq(bad, 0, "Treecko front_anim is pixel-exact vs pret anim_front.png + normal.pal")
  local sbad = pixelExact(PRET .. "/graphics/pokemon/treecko/anim_front.png",
    PRET .. "/graphics/pokemon/treecko/shiny.pal", file("front_anim_shiny/277.rgba") or "")
  eq(sbad, 0, "Treecko shiny sheet is pixel-exact vs shiny.pal")
  local bbad = pixelExact(PRET .. "/graphics/pokemon/treecko/back.png",
    PRET .. "/graphics/pokemon/treecko/normal.pal", file("back/277.rgba") or "")
  eq(bbad, 0, "Treecko back is pixel-exact vs back.png")
  local dbad = pixelExact(PRET .. "/graphics/pokemon/deoxys/anim_front.png",
    PRET .. "/graphics/pokemon/deoxys/normal.pal", deoxysAnim or "")
  eq(dbad, 0, "Deoxys sheet is pixel-exact vs anim_front.png")
  local ebad = pixelExact(PRET .. "/graphics/pokemon/egg/anim_front.png",
    PRET .. "/graphics/pokemon/egg/normal.pal", file("front/412.rgba") or "", 64 * 64)
  eq(ebad, 0, "egg front pic is frame 0 of pret egg anim_front.png")
else
  print("emerald_pokemon_pack_test: pixel checks skipped (python3 + PIL or pret graphics missing)")
end

T.finish("emerald_pokemon_pack_test")
