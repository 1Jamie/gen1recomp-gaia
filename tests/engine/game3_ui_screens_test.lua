package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local Screens = require("src.ui.game3.screens")
local RomText = require("src.core.game3.rom_text")

local prevVersion = GameVersion.get()
Profile.reset()

for _, v in ipairs({ "firered", "leafgreen" }) do
  local s = { version = v }
  for id, path in pairs(Screens.DEFAULT) do
    eq(Screens.path(id, s), path, v .. " resolves " .. id .. " to the FRLG module")
  end
  check(Screens.skin("bag", s) == nil, v .. " has no bag skin")
  check(Screens.skin("summary", s) == nil, v .. " has no summary skin")
  check(Screens.redirect("option", {}, s) == nil, v .. " keeps the FRLG option menu")
end

local em = { version = "emerald" }
eq(Screens.path("option", em), "src.ui.game3.rse.option_menu", "Emerald resolves option to the rse module")
eq(Screens.path("bag", em), "src.ui.game3.bag_menu", "Emerald bag logic stays the shared module")
eq(Screens.path("start_menu", em), "src.ui.game3.start_menu", "Emerald start menu is the shared builder")
check(Screens.skin("bag", em) == require("src.ui.game3.rse.bag_menu"), "Emerald bag skin")
check(Screens.skin("summary", em) == require("src.ui.game3.rse.summary_menu"), "Emerald summary skin")
check(Screens.redirect("option", require("src.ui.game3.option_menu"), em) == require("src.ui.game3.rse.option_menu"),
  "the FRLG option menu redirects to the Emerald one")
local all = table.concat(Screens.all(em), ",")
check(all:find("rse.option_menu", 1, true) ~= nil and all:find("rse.bag_menu", 1, true) ~= nil,
  "Screens.all lists the Emerald modules")

local ui = Profile.of("emerald").ui
eq(ui.startMenu, "src.ui.game3.rse.start_menu_data", "Emerald start menu rows come from rse data")
eq(ui.saveMenu, "rse", "Emerald save dialog layout")
eq(ui.trainerCard.cardType, "emerald", "Emerald trainer card type")
eq(ui.sounds.bagPocket, "SE_SELECT", "Emerald pocket switch plays SE_SELECT")
eq(ui.party.insets.actX, 8, "Emerald party action text inset")
check(Profile.of("firered").ui == nil or Profile.of("firered").ui.startMenu == nil, "FRLG keeps its start menu rows")

local saved, stubbed = {}, {}
local function stub(key, text)
  stubbed[#stubbed + 1] = key
  saved[key] = RomText.overrides[key]
  RomText.overrides[key] = { { t = "text", s = text } }
end
local Data = require("src.ui.game3.rse.start_menu_data")
for id, key in pairs(Data.TEXT) do stub(key, id:upper()) end
for i = 1, 7 do stub("gText_Floor" .. i, "FLOOR " .. i) end
stub("gText_Peak", "PEAK")

local function ctx(o)
  o = o or {}
  local c = {}
  function c.playerLabel() return "MAY" end
  function c.linkActive() return o.link == true end
  function c.inUnionRoom() return o.union == true end
  function c.safariActive() return o.safari == true end
  function c.mapId() return o.map end
  function c.version() return "emerald" end
  function c.flag(name) return (o.flags or {})[name] == true end
  function c.var(name) return (o.vars or {})[name] or 0 end
  function c.safariBalls() return 30 end
  function c.pyramidFloor() return 2 end
  return c
end

local function ids(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.id end
  return table.concat(out, ",")
end

local all3 = { SYS_POKEDEX_GET = true, SYS_POKEMON_GET = true, SYS_POKENAV_GET = true }
local list, kind = Data.build(ctx({ flags = all3 }))
eq(kind, "normal", "normal field menu")
eq(ids(list), "pokedex,pokemon,bag,pokenav,trainer,save,option,exit", "normal rows (start_menu.c:315)")
eq(ids((Data.build(ctx({ flags = {} })))), "bag,trainer,save,option,exit", "fresh game rows")
eq(ids((Data.build(ctx({ flags = { SYS_POKEMON_GET = true } })))), "pokemon,bag,trainer,save,option,exit",
  "POKéMON gated on FLAG_SYS_POKEMON_GET")
eq(ids((Data.build(ctx({ safari = true, flags = all3 })))), "retire,pokedex,pokemon,bag,trainer,option,exit",
  "safari rows (start_menu.c:339)")
eq(ids((Data.build(ctx({ link = true, flags = all3 })))), "pokemon,bag,pokenav,trainer_link,option,exit",
  "link rows (start_menu.c:350)")
eq(ids((Data.build(ctx({ union = true, flags = {} })))), "pokemon,bag,trainer,option,exit",
  "union room rows without POKéNAV (start_menu.c:365)")
eq(ids((Data.build(ctx({ map = "EM_BATTLE_FRONTIER_BATTLE_PIKE_ROOM_NORMAL" })))),
  "pokedex,pokemon,trainer,option,exit", "battle pike rows (start_menu.c:380)")
eq(ids((Data.build(ctx({ map = "EM_BATTLE_FRONTIER_BATTLE_PYRAMID_FLOOR" })))),
  "pokemon,pyramid_bag,trainer,rest_frontier,retire_frontier,option,exit", "battle pyramid rows (start_menu.c:389)")
eq(ids((Data.build(ctx({ map = Data.MULTI_PARTNER_ROOM, vars = { FRONTIER_BATTLE_MODE = 2 } })))),
  "pokemon,trainer,option,exit", "multi partner room rows (start_menu.c:400)")
eq(ids((Data.build(ctx({ map = Data.MULTI_PARTNER_ROOM, vars = { FRONTIER_BATTLE_MODE = 0 } })))),
  "bag,trainer,save,option,exit", "multi partner room outside multis is a normal menu")
local safariWin = Data.extraWindow("safari", ctx())
eq(safariWin.width, 9, "safari balls window is 9 tiles (start_menu.c:143)")
eq(Data.extraWindow("pyramid", ctx()).width, 10, "pyramid floor window")
check(Data.extraWindow("normal", ctx()) == nil, "no side window on the normal menu")
eq(Data.rowPitch, 16, "Emerald start menu rows are 16px apart")
check(Data.exitConfirms == false, "EXIT just closes on Emerald (start_menu.c:747)")

local Fr = require("src.ui.game3.start_menu_frlg")
check(Fr.exitConfirms == true and Fr.rowPitch == nil, "FRLG rows keep the FRLG layout")
eq(Fr.textKey, "sStartMenuActionTable", "FRLG labels from sStartMenuActionTable")

for _, key in ipairs(stubbed) do RomText.overrides[key] = saved[key] end

local OptionMenu = require("src.ui.game3.rse.option_menu")
eq(#OptionMenu.CART, 6, "six Emerald cart option rows (option_menu.c:27)")
eq(OptionMenu.CART[6].id, "frameType", "FRAME is the last cart row")

GameVersion.set(prevVersion)
Profile.reset()
T.finish("game3_ui_screens")
