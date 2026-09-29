package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

local session
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }

local Space = require("src.core.game3.scripting.space")
Space.store = { flags = {}, vars = {} }
local Flags = require("src.core.game3.scripting.flags")
local EM = Flags.forVersion("emerald")
local function flag(name) return Flags.getFlag(Space.store, nil, assert(EM.IDS[name], name)) == true end

local Types = require("src.core.game3.rse.easy_chat_types")
local okN, NativesDewford = pcall(require, "src.core.game3.scripting.natives_dewford")
local Player = require("src.core.game3.rse.easy_chat_player")
local SaveSections = require("src.core.game3.save_sections")

local VAR_0x8004, VAR_RESULT = 0x8004, 0x800D
local E = 0xFFFF

local section
for _, sec in ipairs(SaveSections.of("emerald")) do
  if sec.name == "easyChat" then section = sec.def end
end
assert(section, "the Emerald save profile lists the easyChat section")

local function newSession()
  local s = { version = "emerald", name = "MAY" }
  section.newGame(s)
  return s
end

local opened
local function show(typeId, reply)
  local ctx = { specialVars = { [VAR_0x8004] = typeId } }
  opened = nil
  local adapters = {
    openEasyChat = function(st, cb)
      opened = st
      if reply == false then cb(false) else cb(true, reply(st.words)) end
    end,
  }
  local handler = okN and NativesDewford.BY_NAME.ShowEasyChatScreen or Types.handler()
  handler(ctx, adapters)
  return ctx.specialVars[VAR_RESULT] or 0, ctx.specialVars[VAR_0x8004] or 0
end

print("[test] easy chat save section (pokeemerald/src/easy_chat.c:5562)")
session = newSession()
eq(session.easyChatBattleStart[1], 8 * 512 + 15, "battle start defaults to ARE YOU READY? HERE I COME!")
eq(session.easyChatBattleWon[5], 3 * 512 + 7, "battle won default carries WON")
eq(session.easyChatBattleLost[6], 6 * 512 + 4, "battle lost default ends in an ellipsis")
local out = {}
section.export(session, out)
eq(#out.easyChatBattleStart, 6, "battle start words exported")
local back = {}
section.restore({}, back)
eq(back.easyChatBattleWon and back.easyChatBattleWon[1], 6 * 512 + 58, "an old save without the words restores the defaults")

print("[test] EASY_CHAT_TYPE_PROFILE (pokeemerald/src/easy_chat.c:1464)")
check(Types.get(Types.ID.PROFILE) ~= nil, "profile type registered")
local profile = { 5 * 512 + 1, 8 * 512 + 2, 1 * 512 + 3, 5 * 512 + 4 }
local r = show(Types.ID.PROFILE, function(words)
  eq(words[1], Player.DEFAULT_PROFILE[1], "profile screen opens on I AM A POKEMON FRIEND")
  return profile
end)
eq(opened and opened.type, Types.ID.PROFILE, "easy chat screen opened as PROFILE")
eq(r, 1, "a changed profile answers VAR_RESULT 1")
eq(session.easyChatProfile[3], profile[3], "session.easyChatProfile keeps the new words for the trainer card")
check(flag("FLAG_SYS_CHAT_USED"), "FLAG_SYS_CHAT_USED set")
r = show(Types.ID.PROFILE, function(words) return words end)
eq(r, 0, "an unchanged profile answers VAR_RESULT 0 (DidPhraseChange)")
r = show(Types.ID.PROFILE, false)
eq(r, 0, "cancel answers 0")
eq(session.easyChatProfile[1], profile[1], "cancel keeps the profile")

print("[test] EASY_CHAT_TYPE_BATTLE_START/WON/LOST (pokeemerald/src/easy_chat.c:1467)")
for id, field in pairs({ [Types.ID.BATTLE_START] = "easyChatBattleStart", [Types.ID.BATTLE_WON] = "easyChatBattleWon",
  [Types.ID.BATTLE_LOST] = "easyChatBattleLost" }) do
  local before = session[field][1]
  local newWords = { 1, 2, 3, 4, 5, id }
  r = show(id, function(words)
    eq(words[1], before, field .. " screen opens on the saved words")
    eq(#words, 6, field .. " edits six words")
    return newWords
  end)
  eq(r, 1, field .. " change answers VAR_RESULT 1")
  eq(session[field][6], id, field .. " stored in the session")
end
out = {}
section.export(session, out)
eq(out.easyChatBattleLost[6], Types.ID.BATTLE_LOST, "edited words exported")

print("[test] EASY_CHAT_TYPE_GOOD_SAYING (pokeemerald/src/easy_chat.c:2982)")
local P = Player.BERRY_MASTER_WIFE_PHRASES
for i = 1, 5 do
  local res, v = show(Types.ID.GOOD_SAYING, function(words)
    eq(words[1], E, "good saying screen starts empty")
    return { P[i][1], P[i][2] }
  end)
  eq(res, 1, "phrase " .. i .. " answers VAR_RESULT TRUE")
  eq(v, i, "phrase " .. i .. " answers VAR_0x8004 = " .. i)
end
eq(P[1][1], 9 * 512 + 64, "GREAT is EC_GROUP_FEELINGS 64")
eq(P[3][2], 407, "LATIAS is EC_POKEMON(LATIAS)")
local res, v = show(Types.ID.GOOD_SAYING, function() return { P[1][2], P[1][1] } end)
eq(res, 1, "any full phrase answers TRUE")
eq(v, 0, "a normal phrase answers NOT_SPECIAL_PHRASE")
res = show(Types.ID.GOOD_SAYING, function() return { P[1][1], E } end)
eq(res, 0, "a half phrase is not accepted")
res = show(Types.ID.GOOD_SAYING, false)
eq(res, 0, "cancel answers FALSE")

T.finish()
