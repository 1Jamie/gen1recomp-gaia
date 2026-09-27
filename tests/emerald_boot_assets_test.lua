package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_boot_assets_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_boot_assets_test: skipped (" .. ROM_PATH .. " is not Emerald)")
  os.exit(0)
end

local rom = { id = "emerald", size = #data }
function rom.get(_, o) return data:byte(o + 1) end
function rom.u16(_, o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
function rom.u32(_, o)
  local a, b, c, d = data:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
function rom.readString(_, o, n) return data:sub(o + 1, o + n) end

local files = {}
local cache = {
  write = function(_, rel, bytes) files[rel] = bytes; return true end,
  read = function(_, rel) return files[rel] end,
  exists = function(_, rel) return files[rel] ~= nil end,
}

local K = require("src.import.gba.rse.boot_gfx")
local ROOT = "data/generated/gba"
local MODS = {
  "intro_credits_gfx_extract", "extract_intro_emerald", "extract_title_rse",
  "extract_birch_rse", "extract_naming_rse", "extract_wallclock_rse",
}

local required = {}
for _, name in ipairs(MODS) do
  local M = require("src.import.gba.rse." .. name)
  check(not M.ready(cache, ROOT), name .. " not ready before run")
  local ok, man = M.run(rom, cache, { cacheRoot = ROOT })
  eq(ok, true, name .. " ran")
  check(M.ready(cache, ROOT), name .. " ready after run")
  eq(man.format, K.FORMAT, name .. " manifest format")
  local body = files[ROOT .. "/" .. M.SUB .. "/manifest.lua"]
  local chunk = body and loadstring(body)
  check(chunk ~= nil, name .. " manifest parses")
  if chunk then
    local loaded = chunk()
    eq(#loaded.files, #M.REQUIRED - 1, name .. " manifest lists every image")
  end
  for _, rel in ipairs(M.REQUIRED) do required[ROOT .. "/" .. rel] = true end
end

local produced, dims = {}, {}
for rel, bytes in pairs(files) do
  produced[#produced + 1] = rel
  if rel:match("%.png$") then
    local w, h = K.pngSize(bytes)
    dims[rel] = { w, h }
    check(w and h and w > 0 and h > 0, rel .. " is a png")
  end
end
table.sort(produced)
print(string.format("emerald_boot_assets_test: %d files", #produced))
for _, rel in ipairs(produced) do
  local d = dims[rel]
  print(string.format("  %-62s %s", rel, d and (d[1] .. "x" .. d[2]) or (#files[rel] .. " bytes")))
  check(required[rel], rel .. " is declared in REQUIRED")
end
for rel in pairs(required) do check(files[rel] ~= nil, rel .. " was produced") end

local function dim(rel, w, h)
  local d = dims[ROOT .. "/" .. rel]
  check(d ~= nil, rel .. " exists")
  if d then eq(d[1] .. "x" .. d[2], w .. "x" .. h, rel .. " size") end
end
dim("intro/rse/copyright.png", 256, 256)
dim("intro/rse/scene1_bg3.png", 256, 512)
dim("intro/rse/scene3_pokeball.png", 256, 256)
dim("intro/rse/scene3_groudon.png", 512, 512)
dim("intro/rse/scene3_kyogre.png", 512, 512)
dim("intro/rse/scene3_clouds_left.png", 512, 256)
dim("intro/rse/manectric.png", 64, 256)
dim("intro/rse/scenery/trees_bg3_sunset.png", 256, 256)
dim("intro/rse/scenery/grass_night.png", 256, 256)
dim("intro/rse/scenery/brendan.png", 64, 256)
dim("intro/rse/scenery/bicycle.png", 64, 128)
dim("title/logo.png", 256, 256)
dim("title/version_banner_left.png", 64, 32)
dim("title/press_start.png", 32, 80)
dim("birch/bg_8.png", 256, 160)
dim("birch/lotad.png", 64, 128)
dim("naming/bg.png", 240, 160)
dim("naming/kb_upper.png", 176, 80)
dim("naming/cursor.png", 48, 16)
dim("wallclock/start_female.png", 256, 160)
dim("wallclock/minute_hand_male.png", 64, 64)

local function manifest(sub)
  return loadstring(files[ROOT .. "/" .. sub .. "/manifest.lua"])()
end
local title = manifest("title")
eq(#title.alphaBlend, 64, "gTitleScreenAlphaBlend has 64 rows")
eq(title.alphaBlend[1][1] .. "," .. title.alphaBlend[1][2], "16,0", "first title blend step")
eq(title.sprites.press_start.frames, 10, "press start + copyright frames")
local birch = manifest("birch")
eq(#birch.presetNames.male, 20, "20 male preset names")
eq(birch.presetNames.male[1], "STU", "first male preset name")
eq(birch.presetNames.female[20], "HALIE", "last female preset name")
eq(birch.layers.bg.initialState, 8, "Birch gradient starts at state 8")
local naming = manifest("naming")
eq(#naming.templates, 5, "five naming templates")
eq(naming.templates[5].title, "Tell him the words.", "Walda template title")
eq(naming.keyboard.text[2][1], "ABCDEF .", "upper keyboard row")
local wall = manifest("wallclock")
eq(#wall.handCoords, 360, "360 hand coords")
eq(wall.handCoords[1][2], -24, "hand coord 0 y")
local intro = manifest("intro/rse")
eq(#intro.tables.sparkleCoords, 11, "11 sparkle coords")
eq(#intro.tables.gameFreakLetters, 9, "9 Game Freak letters")
eq(#intro.tables.groudonRocks, 6, "6 Groudon rocks")
eq(#intro.tables.kyogreBubbles, 12, "12 Kyogre bubbles")
eq(intro.sprites.torchic.anims[3][3].frame, 5, "Torchic trip anim third frame")
local scenery = manifest("intro/rse/scenery")
eq(#scenery.scenery.moving_clouds.sprites, 9, "9 cloud sprites")
eq(#scenery.scenery.moving_trees.sprites, 12, "12 tree sprites")

T.finish("emerald_boot_assets_test")
