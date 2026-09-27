package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_uc_screens_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
local imports = {
  info = function(_, id) return { id = id, size = #data, md5 = "emerald", file = "memory" } end,
  read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
}
local rom = assert(require("src.import.gba.rom").open(imports, "emerald"))

local store = {}
local cache = {
  write = function(_, rel, bytes) store[rel] = bytes; return true end,
  read = function(_, rel) return store[rel] end,
  exists = function(_, rel) return store[rel] ~= nil end,
}
local ROOT = "data/generated/gba"
local plan = require("src.import.gba.plans.rse.uc")
local Plans = require("src.import.gba.plans.registry")
for _, step in ipairs(plan.tasks[1].steps) do
  local mod = require(Plans.moduleFor(step.name))
  local ok, err = pcall(mod.run, rom, cache, { cacheRoot = ROOT })
  check(ok, step.name .. " runs: " .. tostring(err))
  for _, rel in ipairs(mod.REQUIRED or {}) do
    check(store[ROOT .. "/" .. rel] ~= nil, step.name .. " wrote " .. rel)
  end
end
local function load(rel)
  local src = store[ROOT .. "/" .. rel]
  if not src then return nil end
  return assert(loadstring(src, "@" .. rel))()
end

-- pokeemerald/src/pokemon_storage_system.c:5376
local storage = load("pokemon/storage/manifest.lua")
eq(#storage.wallpaperOrder, 16, "16 regular wallpapers")
eq(storage.wallpaperOrder[13], "polkadot", "wallpaper 13 is POLKA-DOT")
eq(storage.wallpaperOrder[15], "machine", "wallpaper 15 is MACHINE")
check(storage.wallpapers.machine ~= nil, "MACHINE wallpaper baked")
local friends = load("pokemon/storage/wallpapers/friends/manifest.lua")
eq(#friends.patterns + 1, 16, "16 FRIENDS patterns")
eq(#friends.icons + 1, 30, "30 FRIENDS icons")
eq(#friends.patterns[0].palette, 32, "pattern palette has two banks")

-- pokeemerald/src/shop.c:742
eq(#store[ROOT .. "/items/shop/bg.rgba"], 240 * 160 * 4, "shop menu bg 240x160")
eq(#store[ROOT .. "/items/shop/money_label.rgba"], 32 * 16 * 4, "MONEY label 32x16")

-- pokeemerald/src/hall_of_fame.c:151
eq(load("hall_of_fame/manifest.lua").confetti.frames, 17, "17 confetti frames")

-- pokeemerald/src/data/easy_chat/easy_chat_groups.h:26
local ec = load("easy_chat/words.lua")
eq(#ec.groups + 1, 22, "22 easy chat groups")
eq(#ec.templates, 21, "21 easy chat screen templates")
local mailTemplate
for _, t in ipairs(ec.templates) do if t.type == 4 then mailTemplate = t end end
check(mailTemplate and mailTemplate.numColumns == 2 and mailTemplate.numRows == 5 and mailTemplate.frameId == 2,
  "EASY_CHAT_TYPE_MAIL is a 2x5 FRAMEID_MAIL screen")
eq(ec.frames[2].top, 0, "mail frame top 0")
eq(ec.frames[7].left, 5, "quiz question frame left 5")

-- pokeemerald/src/mail.c:118
local mail = load("mail/manifest.lua")
eq(mail.firstMailItem, 121, "ITEM_ORANGE_MAIL is 121")
eq(mail.designs[0].textColor, 0x294A, "orange mail text colour RGB(10,10,10)")
eq(#mail.layouts[0].lines, 5, "tall layout has 5 lines")
eq(mail.layouts[0].lines[5].words, 1, "last mail line holds 1 word")
eq(mail.layouts[10].signatureYPos, 17, "FAB mail signature y 17")

-- pokeemerald/src/data/decoration/header.h:1
local decor = load("decorations/decorations.lua")
eq(decor.count, 121, "121 decorations")
eq(decor.categoryNames[6], "DOLL", "category 6 DOLL")
eq(decor.decorations[1].price, 3000, "SMALL DESK costs 3000")
eq(#store[ROOT .. "/decorations/icons.rgba"], 121 * 24 * 24 * 4, "decoration icon strip")

-- pokeemerald/src/data/credits.h:385
local credits = load("credits_rse/manifest.lua")
eq(credits.pageCount, 57, "57 credits pages")
eq(credits.pages[1][2].text, "POKéMON EMERALD VERSION", "first credits title")
eq(credits.pages[1][2].isTitle, true, "first credits line is a title")
eq(#credits.animsPlayer, 4, "4 player bike anims")
eq(credits.monSpritePos[2][1], 120, "center mon slide x 120")

-- pokeemerald/src/decoration_inventory.c:70
local DecorInv = require("src.core.game3.rse.decoration_inventory")
DecorInv.install(decor)
local sess = {}
local C = require("src.core.game3.constants").of("emerald")
local pichu = C:require("decorations", "DECOR_PICHU_DOLL")
local snorlax = C:require("decorations", "DECOR_SNORLAX_DOLL")
check(DecorInv.checkSpace(pichu, sess), "doll space before any purchase")
check(DecorInv.add(snorlax, sess), "add SNORLAX DOLL")
check(DecorInv.add(pichu, sess), "add PICHU DOLL")
check(DecorInv.has(pichu, sess), "has PICHU DOLL")
eq(DecorInv.countInCategory(6, sess), 2, "two dolls")
eq(DecorInv.remove(snorlax, sess), 1, "remove SNORLAX DOLL")
eq(sess.decorationInventory[6][1], pichu, "condense moves PICHU DOLL to slot 1")
for _ = 1, 39 do DecorInv.add(pichu, sess) end
check(not DecorInv.checkSpace(pichu, sess), "40 dolls fill the DOLL inventory")
check(not DecorInv.add(DecorInv.DECOR_NONE, sess), "DECOR_NONE is never added")
eq(DecorInv.count(sess), 40, "40 decorations owned")

T.finish("emerald_uc_screens_test")
