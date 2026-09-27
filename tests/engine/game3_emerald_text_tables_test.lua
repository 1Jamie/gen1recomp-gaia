package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Text = require("src.import.gba.versions_text_emerald")
local FrText = require("src.import.gba.versions_text")
local Versions = require("src.import.gba.versions")
local Syms = require("src.import.gba.syms")
local S = Syms.of("emerald")

check(#Text.NAMED_TEXTS > 5000, "emerald NAMED_TEXTS has " .. #Text.NAMED_TEXTS .. " names")
check(#Text.NAMED_BATTLE_TEXTS > 300, "emerald NAMED_BATTLE_TEXTS has " .. #Text.NAMED_BATTLE_TEXTS .. " names")
check(#Text.TEXT_TABLES > 200, "emerald TEXT_TABLES has " .. #Text.TEXT_TABLES .. " rows")

local unresolved = 0
for _, list in ipairs({ Text.NAMED_TEXTS, Text.NAMED_BATTLE_TEXTS }) do
  for _, name in ipairs(list) do
    if not S.has(name) then unresolved = unresolved + 1 end
  end
end
for _, t in ipairs(Text.TEXT_TABLES) do
  if not S.has(t.name) then unresolved = unresolved + 1 end
end
eq(unresolved, 0, "every generated emerald text name resolves through Syms")

local V = Versions.forGame("emerald")
eq(V.NAMED_TEXTS.gText_Birch_Welcome, S.off("gText_Birch_Welcome"), "gText_Birch_Welcome offset")
for _, key in ipairs({
  "gText_Birch_Welcome", "gText_Birch_MainSpeech", "gText_Birch_AndYouAre", "gText_Birch_BoyOrGirl",
  "gText_Birch_WhatsYourName", "gText_Birch_AreYouReady", "gText_MainMenuNewGame", "gText_MainMenuContinue",
  "gText_MainMenuOption", "gText_MainMenuMysteryGift", "gText_MainMenuMysteryEvents",
  "gText_ContinueMenuPlayer", "gText_ContinueMenuTime", "gText_ContinueMenuPokedex", "gText_ContinueMenuBadges",
  "gText_BatteryRunDry", "gText_SaveFileErased", "gText_SaveFileCorrupted", "gText_IsThisTheCorrectTime",
  "InsideOfTruck_Text_BoxPrintedWithMonLogo", "gText_ExpandedPlaceholder_Emerald",
}) do
  check(V.NAMED_TEXTS[key] ~= nil, "emerald NAMED_TEXTS has " .. key)
end

local byName = {}
for _, t in ipairs(V.TEXT_TABLES) do byName[t.name] = t end
local bs = byName.gBattleStringsTable
check(bs ~= nil, "gBattleStringsTable is a text table")
eq(bs and bs.count, 369, "gBattleStringsTable has 369 strings")
eq(bs and bs.ids, 12, "gBattleStringsTable starts at STRINGID_TRAINER1LOSETEXT")
eq(bs and bs.battle, true, "gBattleStringsTable decodes battle placeholders")
eq(V.BATTLE_STRING_IDS[0], "STRINGID_INTROMSG", "BATTLE_STRING_IDS[0]")
eq(V.BATTLE_STRING_IDS[12], "STRINGID_TRAINER1LOSETEXT", "BATTLE_STRING_IDS[12]")
eq(V.BATTLE_STRING_IDS[380], "STRINGID_TRAINER2WINTEXT", "BATTLE_STRING_IDS[380]")
eq(V.BATTLE_STRING_IDS[381], nil, "no string id past BATTLESTRINGS_COUNT")
local missingIds = 0
for i = 0, bs.count - 1 do
  if not V.BATTLE_STRING_IDS[i + bs.ids] then missingIds = missingIds + 1 end
end
eq(missingIds, 0, "every gBattleStringsTable slot has a string id")
eq(byName.gTrainerClassNames and byName.gTrainerClassNames.count, 66, "gTrainerClassNames inline count")
eq(byName.gTypeNames and byName.gTypeNames.count, 18, "gTypeNames inline count")
eq(byName.sStartMenuItems and byName.sStartMenuItems.stride, 8, "sStartMenuItems struct table")
eq(byName.gNatureNamePointers and byName.gNatureNamePointers.count, 25, "gNatureNamePointers count")
local badCount = 0
for _, t in ipairs(V.TEXT_TABLES) do
  if not (t.addr and t.count and t.count > 0) then badCount = badCount + 1 end
end
eq(badCount, 0, "every emerald text table has an address and a positive count")

eq(V.TEXT_WINDOW_FRAME_COUNT, 20, "sWindowFrames has 20 user frames")
eq(V.TEXT_WINDOW_PALETTE_COUNT, 5, "sTextWindowPalettes has 5 palettes")
eq(V.MESSAGE_BOX_GFX_BYTES, 0x1C0, "gMessageBox_Gfx is 14 tiles")
eq(V.BRAILLE_GLYPHS, 64, "braille font has 64 glyphs")
for _, face in ipairs({ "normal", "small", "short", "narrow", "small_narrow" }) do
  eq(V.FONT_GLYPH_COUNTS[face], 512, face .. " latin font has 512 glyphs")
end
eq(V.FONTS_JAPANESE.short.count, 512, "short japanese width table")

local Placeholders = require("src.import.gba.text_placeholders_extract")
for name, sym in pairs(Placeholders.SYMBOLS) do
  eq(V.TEXT_PLACEHOLDERS[name], S.off(sym), "placeholder " .. name .. " resolves")
end

local Fr = Versions.forGame("firered")
check(Fr.NAMED_TEXTS == FrText.NAMED_TEXTS, "FireRed NAMED_TEXTS still come from versions_text.lua")
check(Fr.TEXT_TABLES == FrText.TEXT_TABLES, "FireRed TEXT_TABLES still come from versions_text.lua")
eq(Fr.TEXT_WINDOW_FRAMES, nil, "RSE text window keys stay out of the FRLG table")

local Plans = require("src.import.gba.plans.registry")
local plan = Plans.of("emerald")
local found
for _, task in ipairs(plan.tasks) do
  if task.id == "text_chrome" then found = task end
end
check(found ~= nil, "rse plan has the text_chrome task")
local req = {}
for _, p in ipairs(Plans.required(plan, "data/generated/gba")) do req[p] = true end
check(req["data/generated/gba/text/placeholders.lua"], "placeholders.lua is required")
check(req["data/generated/gba/chrome/user_frame_19.rgba"], "user_frame_19.rgba is required")
check(req["data/generated/gba/chrome/fonts/latin_widths.lua"], "latin_widths.lua is required")
check(req["data/generated/gba/chrome/fonts/latin_narrow_fg.rgba"], "latin_narrow_fg.rgba is required")

T.finish("game3_emerald_text_tables_test")
