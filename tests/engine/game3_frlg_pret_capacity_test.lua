package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
require("tests.game3_cache").mountOrSkip("game3_frlg_pret_capacity_test")

local Profile = require("src.core.game3.profile")
local Storage = require("src.core.game3.storage")
local Bag = require("src.core.game3.bag")

local fr = Profile.of("firered")
eq(fr.bag.pcItems, 30, "PC_ITEMS_COUNT (pokefirered/include/constants/global.h:35)")
eq(fr.bag.capacity.ITEMS, 42, "BAG_ITEMS_COUNT")
eq(fr.bag.capacity.KEY_ITEMS, 30, "BAG_KEYITEMS_COUNT")
eq(fr.bag.capacity.POKE_BALLS, 13, "BAG_POKEBALLS_COUNT")
eq(fr.bag.capacity.TM_CASE, 58, "BAG_TMHM_COUNT")
eq(fr.bag.capacity.BERRY_POUCH, 43, "BAG_BERRIES_COUNT")

local s = { version = "firered", bag = Bag.new(), storage = Storage.new() }
s.storage.items = {}
for i = 1, 30 do
  local ok = Storage.addPcItem(s, 100 + i, 1)
  check(ok, "PC slot " .. i .. " accepts a new item")
end
local ok, err = Storage.addPcItem(s, 200, 1)
eq(ok, false, "the 31st unique PC item is refused")
eq(err, "pc_items_full", "with pc_items_full")

local many = {}
for i = 1, 45 do many[i] = { id = 100 + i, qty = 1 } end
eq(#Storage.restore(nil, nil, many).items, 30, "restoring a legacy pcItems list stops at the FRLG capacity")

for b = 1, Storage.TOTAL_BOXES_COUNT do
  eq(Storage.new().boxes[b].wallpaper, ((b - 1) % 4) + 1, "box " .. b .. " default wallpaper")
end
local sparse = Storage.deserialize(Storage.serialize({ currentBox = 1, boxes = Storage.new().boxes, items = {} }))
eq(sparse.boxes[5].wallpaper, 1, "an untouched box round-trips to its default wallpaper")

T.finish()
