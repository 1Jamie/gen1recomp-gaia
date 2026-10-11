package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Versions = require("src.import.gba.versions")
local Pokemon = require("src.core.game3.pokemon")

local reads = {}
Pokemon._cache = { read = function(_, rel) reads[#reads + 1] = rel return nil end }

local function reset()
  reads = {}
  Pokemon._front, Pokemon._back, Pokemon._icons = {}, {}, {}
end

local function lastRead(pattern)
  for i = #reads, 1, -1 do
    if reads[i]:find(pattern) then return reads[i] end
  end
  return nil
end

for _, version in ipairs({ "firered", "leafgreen", "emerald" }) do
  Versions.select(version)
  check(Versions.MON_PIC_DUPLICATE_DEOXYS == true, version .. " duplicates the Deoxys form frame")
  eq(Versions.MON_ICON_DEOXYS_OFFSET, 0x400, version .. " Deoxys form icon offset")

  reset()
  Pokemon.frontPic(410, nil, false, 0)
  check(lastRead("/front/410_handled%.rgba$") ~= nil, version .. " front pic loads the game's Deoxys form")
  Pokemon.backPic(410, nil, false)
  check(lastRead("/back/410_handled%.rgba$") ~= nil, version .. " back pic loads the game's Deoxys form")
  Pokemon.frontPic(410, nil, true, 0)
  check(lastRead("/front_shiny/410_handled%.rgba$") ~= nil, version .. " shiny front pic loads the form")
  Pokemon.icon(410)
  check(lastRead("/icons/410_handled%.rgba$") ~= nil, version .. " party icon loads the form")
  Pokemon.monIcon({ species = 410, personality = 0 })
  check(lastRead("/icons/410_handled%.rgba$") ~= nil, version .. " mon icon loads the form")

  reset()
  Pokemon.frontPicDontHandleDeoxys(410, nil, false, 0)
  check(lastRead("/front/410%.rgba$") ~= nil and lastRead("_handled") == nil,
    version .. " DontHandleDeoxys front pic is Normal Forme")
  Pokemon.backPicDontHandleDeoxys(410, nil, false)
  check(lastRead("/back/410%.rgba$") ~= nil and lastRead("_handled") == nil,
    version .. " DontHandleDeoxys back pic is Normal Forme")
  Pokemon.iconDontHandleDeoxys(410)
  check(lastRead("/icons/410%.rgba$") ~= nil and lastRead("_handled") == nil,
    version .. " trainer card icon is Normal Forme")

  reset()
  Pokemon.frontPic(150, nil, false, 0)
  Pokemon.icon(150)
  check(lastRead("_handled") == nil, version .. " other species never load a form file")
end

Versions.select("ruby")
reset()
Pokemon.frontPic(410, nil, false, 0)
Pokemon.icon(410)
check(lastRead("/front/410%.rgba$") ~= nil and lastRead("_handled") == nil,
  "Ruby has no Deoxys form frame")

Versions.select("firered")
local okUi, Ui = pcall(require, "src.core.game3.battle.ui")
if okUi and Ui.ignoreDeoxysForm then
  Ui._st = { multi = false }
  check(Ui.ignoreDeoxysForm("enemy", nil, false) == true, "opponent front pic ignores the form")
  check(Ui.ignoreDeoxysForm("player", nil, false) == false, "player back pic shows the form")
  check(Ui.ignoreDeoxysForm("player", nil, true) == true, "a transformed battler shows Normal Forme")
  Ui._st = { multi = true, linkOwn = 0 }
  check(Ui.ignoreDeoxysForm("player", 0, false) == false, "own multi battler shows the form")
  check(Ui.ignoreDeoxysForm("player", 2, false) == true, "multi partner battler ignores the form")
  Ui._st = nil
else
  check(false, "battle ui exposes ignoreDeoxysForm")
end

T.finish("game3_deoxys_form_bug2859")
