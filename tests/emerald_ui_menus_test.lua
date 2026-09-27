package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_ui_menus_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_ui_menus_test: skipped (" .. ROM_PATH .. " is not Emerald)")
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
local function run(name, opts)
  local M = require(name)
  local o = { cacheRoot = ROOT, game = "emerald" }
  for k, v in pairs(opts or {}) do o[k] = v end
  local ok, man = M.run(rom, cache, o)
  check(ok ~= false, name .. " ran")
  for _, rel in ipairs(M.REQUIRED or {}) do
    check(files[ROOT .. "/" .. rel] ~= nil, name .. " wrote " .. rel)
  end
  if M.ready then check(M.ready(cache, ROOT), name .. " ready after run") end
  return man, M
end

local bag = run("src.import.gba.rse.bag_chrome_extract")
local bw, bh = K.pngSize(files[ROOT .. "/rse/bag/bg.png"])
eq(bw .. "x" .. bh, "240x160", "bag background is one screen")
eq(bag.sprites.male.frames, 6, "six bag sprite frames (item_menu_icons.c:92)")
eq(bag.icons.count, 378, "gItemIconTable holds ITEMS_COUNT + 1 icons")
eq(#files[ROOT .. "/rse/bag/icons.rgba"], 24 * 24 * 4 * 378, "item icon atlas size")
eq(#bag.palettes.male, 32, "two bag palette banks")

local menus = run("src.import.gba.rse.menus_extract")
eq(#menus.option.textPalette, 16, "option text palette")
eq(#menus.option.windows, 2, "option window templates (option_menu.c:95)")
eq(menus.option.windows[2].top, 5, "options window at tile row 5")
eq(#menus.party.cursorOptions, 33, "sCursorOptions rows")
eq(#menus.party.fieldMoves, 14, "Emerald has 14 field moves (party_menu.c:124)")
local C = require("src.core.game3.constants").of("emerald")
eq(menus.party.fieldMoves[1], C:require("moves", "MOVE_CUT"), "first field move is CUT")
eq(menus.party.fieldMoves[7], C:require("moves", "MOVE_DIVE"), "DIVE follows FLY")
eq(menus.party.fieldMoves[11], C:require("moves", "MOVE_SECRET_POWER"), "SECRET POWER is a field move")
eq(menus.party.cursorOptions[33 - 14 + 11], "SECRET POWER", "field move labels line up with sFieldMoves")

local summary = run("src.import.gba.rse.summary_chrome_extract")
eq(summary.moveTypes.count, 23, "18 types + 5 contest categories")
eq(#summary.windows, 20, "sSummaryTemplate label windows (pokemon_summary_screen.c:59)")
eq(summary.pageWindows.moves[2].paletteNum, 8, "PP window uses the PP text palette")
eq(summary.markings.frames, 16, "all marking combos")
check(summary.noFlip[60] == true and summary.noFlip[1] ~= true, "noFlip bit from gSpeciesInfo")
check(summary.tiles.index.dots.start == 0 and summary.tiles.index.exp.count == 9, "summary tile atlas index")

local card = run("src.import.gba.rse.trainer_card_extract")
eq(card.cardType, "emerald", "Hoenn card set")
check(card.layers.front_4 ~= nil and card.layers.back_0 ~= nil, "card layers for every star count")
local cw, ch = K.pngSize(files[ROOT .. "/rse/trainer_card/badges.png"])
eq(cw .. "x" .. ch, "128x16", "eight 16x16 badges")

local Party = require("src.import.gba.party_chrome_extract")
Party.run(rom, cache, { cacheRoot = ROOT, game = "emerald" })
for _, rel in ipairs(Party.REQUIRED) do
  check(files[ROOT .. "/" .. rel] ~= nil, "party chrome wrote " .. rel)
end
eq(#files[ROOT .. "/pokemon/party/bg.rgba"], 240 * 160 * 4, "party background")
eq(#files[ROOT .. "/pokemon/party/slot_main.rgba"], 80 * 56 * 4, "main party slot")

T.finish("emerald_ui_menus")
