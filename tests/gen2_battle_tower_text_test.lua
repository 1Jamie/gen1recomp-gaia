-- The Battle Tower trainer quotes: engine/events/battle_tower/trainer_text.asm
-- BattleTowerText, the `battletowertext` script command and the two lines the
-- battle prints (engine/battle/core.asm:2401-2407, :2943-2952).
--
--   luajit tests/gen2_battle_tower_text_test.lua
--
-- ROM-free.  The extractor half runs against a synthetic cartridge laid out
-- the way trainer_text.asm assembles, the rest against that read.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle tower text")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local BattleTowerText = require("src.script.gen2.BattleTowerText")
local Events = require("src.world.gen2.Events")
local RomExtractorGen2 = require("src.import.RomExtractorGen2")
local Save = require("src.core.gen2.Save")
local Specials = require("src.script.gen2.Specials")
local Vm = require("src.script.gen2.Vm")

local NAME_LENGTH = 11

-- ---------------------------------------------------------------- cartridge

local CODE_AT, GENDERS_AT = 0x4000, 0x4100
local MALE_AT, FEMALE_AT = 0x4300, 0x4400
local STRUCTS_AT, TEXT_AT = 0x4500, 0x4800
local CLASS_WRAM, NAME_WRAM = 0xd10a, 0xd100

local charmap = {}
local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
for index = 1, #letters do
  charmap[tostring(0x80 + index - 1)] = letters:sub(index, index)
end
charmap[tostring(0x7f)] = " "

local function encode(text)
  local out = {}
  for index = 1, #text do
    local c = text:sub(index, index)
    out[index] = (c == " ") and 0x7f or (0x80 + c:byte() - 65)
  end
  return out
end

-- Builds one cartridge whose BattleTowerText reads the gender from
-- `source` (wBT_OTTrainerClass on 1.1, wBT_OTName + 5 on 1.0).
local function cartridge(source)
  local bytes = {}
  local function put(offset, list)
    for index, value in ipairs(list) do bytes[offset + index] = value end
  end
  local function lo(v) return v % 256 end
  local function hi(v) return math.floor(v / 256) end
  -- trainer_text.asm:6-9 then `ld hl, nn`, then the two `and / cp / jr c`.
  put(CODE_AT, { 0xf0, 0x70, 0xf5, 0x3e, 0x03, 0xe0, 0x70,
    0x21, lo(source), hi(source),
    0x7e, 0x3d, 0x5f, 0x16, 0x00, 0x21, lo(GENDERS_AT), hi(GENDERS_AT),
    0x19, 0x7e, 0xa7, 0x20, 0x0a,
    0xf0, 0xe1, 0xe6, 0x03, 0xfe, 0x03, 0x38, 0x02, 0xd6, 0x03,
    0x21, lo(MALE_AT), hi(MALE_AT), 0x18, 0x0a,
    0xf0, 0xe1, 0xe6, 0x01, 0xfe, 0x02, 0x38, 0x02, 0xd6, 0x02,
    0x21, lo(FEMALE_AT), hi(FEMALE_AT) })
  -- BTTrainerClassGenders: class 1 male, 2 female, 3 male; the byte a 1.0
  -- name-character index lands on is nonzero.
  local genders = {}
  for index = 1, 256 do genders[index] = 1 end
  genders[1], genders[2], genders[3] = 0, 1, 0
  put(GENDERS_AT, genders)
  -- Three structs per text; the strings themselves.
  local strings = {
    "HI M ONE", "HI M TWO", "HI M THREE",
    "LOST M ONE", "LOST M TWO", "LOST M THREE",
    "WON M ONE", "WON M TWO", "WON M THREE",
    "HI F ONE", "HI F TWO",
    "LOST F ONE", "LOST F TWO",
    "WON F ONE", "WON F TWO",
  }
  local structAt, textAt = {}, TEXT_AT
  for index, text in ipairs(strings) do
    local raw = encode(text)
    put(textAt, { 0x00 })
    put(textAt + 1, raw)
    put(textAt + 1 + #raw, { 0x57 })
    local struct = STRUCTS_AT + (index - 1) * 5
    put(struct, { 0x16, lo(textAt), hi(textAt), 0x01, 0x50 })
    structAt[index] = struct
    textAt = textAt + #raw + 2
  end
  local function pointerTables(at, first, count)
    local lists = at + 6
    local words = {}
    for list = 0, 2 do
      local listAt = lists + list * count * 2
      put(at + list * 2, { lo(listAt), hi(listAt) })
      for n = 0, count - 1 do
        local struct = structAt[first + list * count + n]
        words[#words + 1] = lo(struct)
        words[#words + 1] = hi(struct)
      end
    end
    put(lists, words)
  end
  pointerTables(MALE_AT, 1, 3)
  pointerTables(FEMALE_AT, 10, 2)

  local rom = {}
  for index = 1, 0x8000 do rom[index] = string.char(bytes[index] or 0) end
  local manifest = {
    romSha1 = "",
    charmap = charmap,
    constants = {},
    symbols = {
      BattleTowerText = { 1, CODE_AT },
      BTTrainerClassGenders = { 1, GENDERS_AT },
      BTMaleTrainerTexts = { 1, MALE_AT },
      BTFemaleTrainerTexts = { 1, FEMALE_AT },
      wBT_OTTrainerClass = { 3, CLASS_WRAM },
    },
  }
  return RomExtractorGen2.new(table.concat(rom), manifest, nil)
end

-- home/text.asm:566 DoneText, the marker every one of these ends on.
local function plain(text)
  return type(text) == "string" and (text:gsub("\012?{DONE}$", "")) or text
end

local function trainer(name, class)
  local raw = {}
  for index = 1, NAME_LENGTH - 1 do
    raw[index] = (index <= #name) and (0x80 + name:byte(index) - 65) or 0x50
  end
  return { index = 0, name = name, class = class, nameRaw = raw }
end

-- ================================================ the extractor's text read
local text11 = cartridge(CLASS_WRAM):readBattleTowerText(charmap)
do
  check(text11 ~= nil, "the text block reads out of the cartridge")
  eq(text11.genderByName, false,
    "`ld hl, wBT_OTTrainerClass` keys the gender on the class")
  eq(text11.male.mask, 3, "the male roll mask comes off `and`")
  eq(text11.male.count, 3, "and its fold off `cp`")
  eq(text11.female.mask, 1, "the female roll mask")
  eq(text11.female.count, 2, "and its fold")
  eq(#text11.male.intro, 3, "three male greetings")
  eq(#text11.male.playerLost, 3, "three male player-lost lines")
  eq(#text11.male.playerWon, 3, "three male player-won lines")
  eq(#text11.female.intro, 2, "two female greetings")
  eq(#text11.female.playerWon, 2, "two female player-won lines")
  eq(plain(text11.male.intro[2]), "HI M TWO", "the pointer chain lands on the text")
  eq(plain(text11.male.playerWon[3]), "WON M THREE", "and the third list too")
  eq(plain(text11.female.playerLost[1]), "LOST F ONE", "female lists are their own")
  eq(#text11.classGenders, 256, "the gender table carries a full index range")
  eq(text11.classGenders[2], 1, "class 2 is female")
  eq(text11.classGenders[3], 0, "class 3 is male")
end

local text10 = cartridge(NAME_WRAM + 5):readBattleTowerText(charmap)
do
  eq(text10.genderByName, true,
    "`ld hl, wBT_OTName + 5` keys the gender on the sixth name character")
end

-- ============================================ gender and the stored index
do
  eq(BattleTowerText.gender(text11, trainer("ABLE", 1)), "male",
    "1.1: class 1 reads BTTrainerClassGenders[0]")
  eq(BattleTowerText.gender(text11, trainer("ABLE", 2)), "female",
    "1.1: class 2 reads BTTrainerClassGenders[1]")
  eq(BattleTowerText.gender(text10, trainer("ABLE", 1)), "female",
    "1.0: the name's sixth byte indexes past the table and lands on nonzero")
  eq(BattleTowerText.gender(text10, trainer("ABCDEFG", 3)), "female",
    "1.0: a seven-letter name's sixth letter does the same")

  local rolls = {}
  for value = 1, 4 do
    rolls[#rolls + 1] = BattleTowerText.roll(text11.male, function() return value end)
  end
  eq(table.concat(rolls, ","), "0,1,2,0",
    "the roll folds values at or past the count back down")
  rolls = {}
  for value = 1, 2 do
    rolls[#rolls + 1] = BattleTowerText.roll(text11.female, function() return value end)
  end
  eq(table.concat(rolls, ","), "0,1", "a female roll stays inside its mask")

  local roster = { trainers = { trainer("ABLE", 1), trainer("BAKER", 2) },
    text = text11 }
  eq(plain(BattleTowerText.pick(roster, 0, BattleTowerText.INTRO, 1)), "HI M TWO",
    "INTRO on a male trainer is .Greetings[index]")
  eq(plain(BattleTowerText.pick(roster, 0, BattleTowerText.WIN, 1)), "LOST M TWO",
    "BATTLETOWERTEXT_WIN_TEXT is .PlayerLost[index]")
  eq(plain(BattleTowerText.pick(roster, 0, BattleTowerText.LOSS, 2)), "WON M THREE",
    "BATTLETOWERTEXT_LOSS_TEXT is .PlayerWon[index]")
  eq(plain(BattleTowerText.pick(roster, 1, BattleTowerText.INTRO, 0)), "HI F ONE",
    "a female trainer reads the female tables")
  eq(BattleTowerText.pick(roster, 5, BattleTowerText.INTRO, 0), nil,
    "an unknown trainer row has no line")
end

-- ========================================= the script command and the battle
do
  local roster = { trainers = { trainer("ABLE", 1), trainer("BAKER", 2) },
    text = text11, groups = { {} }, levelGroups = 1 }
  local DATA = { trainers = { battleTower = roster, classes = {} } }
  local pages = {}
  local vm = Vm.new({
    s = {
      { op = "battletowertext", args = { BattleTowerText.INTRO } },
      { op = "promptbutton" },
      { op = "end" },
    },
  }, {}, Events.new(), {
    specials = { data = function() return DATA end },
    showText = function(text, resume) pages[#pages + 1] = text; resume() end,
  })
  vm.btOpponent = { index = 1, name = "BAKER", class = 2, rows = {} }
  local savedRandom = Specials.random
  Specials.random = function() return 2 end
  check(vm:start("s"), "the room script's battletowertext runs")
  Specials.random = savedRandom
  eq(plain(pages[1]), "HI F TWO", "INTRO prints the rolled greeting")
  eq(vm.btTextIndex, 1, "and stores the roll in wBT_TrainerTextIndex")
  eq(next(vm.unknownOps), nil, "battletowertext is no longer an unknown op")

  eq(plain(BattleTowerText.forVm(vm, BattleTowerText.WIN)), "LOST F TWO",
    "WIN_TEXT reuses the stored index")
  eq(plain(BattleTowerText.forVm(vm, BattleTowerText.LOSS)), "WON F TWO",
    "and so does LOSS_TEXT")

  local save = Save.normalize({ version = "crystal", generation = 2 })
  save.battleTower.levelGroup = 1
  save.party = {}
  local spec
  vm.specials.save = function() return save end
  vm.specials.party = function() return save.party end
  vm.specials.healParty = function() end
  vm.specials.startTowerBattle = function(record, done)
    spec = record
    done("win")
    return true
  end
  Specials.ALL.BattleTowerBattle(vm)
  check(spec ~= nil, "BattleTowerBattle started the battle")
  eq(plain(spec and spec.winText), "WON F TWO",
    "the trainer record's winText is .PlayerWon (core.asm:2406)")
  eq(plain(spec and spec.lossText), "LOST F TWO",
    "and its lossText is .PlayerLost (core.asm:2951)")
end

S.finish()
