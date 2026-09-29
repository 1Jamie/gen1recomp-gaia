package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local prevVersion = GameVersion.get()
Profile.reset()
GameVersion.set("emerald")

local session = { version = "emerald", dex = { seen = {}, caught = {}, owned = {} } }
local prevRuntime = package.loaded["src.core.game3.runtime"]
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
local Space = require("src.core.game3.scripting.space")
local prevStore = Space.store
Space.store = { flags = {}, vars = {} }

local prevRomText = package.loaded["src.core.game3.rom_text"]
local romKeys = {
  gText_DelAll = "DEL. ALL", gText_Cancel5 = "CANCEL", gText_Ok2 = "OK",
}
package.loaded["src.core.game3.rom_text"] = {
  has = function(key) return romKeys[key] ~= nil end,
  plain = function(key) return romKeys[key] or key end,
  ir = function(key) return { { t = "text", s = assert(romKeys[key], "ROM text " .. key .. " is not in the script cache") } } end,
}
package.loaded["src.ui.game3.easy_chat"] = nil

local EasyChat = require("src.ui.game3.easy_chat")
local EasyChatText = require("src.core.game3.easy_chat_text")
local Dex = require("src.core.game3.dex")

local ZIGZAGOON, TORCHIC, BULBASAUR = 288, 280, 1
local groups = {}
for gid = 0, 21 do groups[gid] = { id = gid, name = "G" .. gid, numWords = 0, numEnabled = 0, words = {} } end
local function value(gid, v) local g = groups[gid]; g.words[#g.words + 1] = { id = gid * 512 + v, value = v, text = "V" .. v } end
value(0, ZIGZAGOON)
value(0, TORCHIC)
value(21, BULBASAUR)
groups[1].words = {
  { id = 512 + 0, text = "ZED", alphabeticalOrder = 2, enabled = true },
  { id = 512 + 1, text = "HIDDEN", alphabeticalOrder = 0, enabled = false },
  { id = 512 + 2, text = "ALPHA", alphabeticalOrder = 1, enabled = true },
}
EasyChatText.install({ groups = groups })
Dex.setSeen(session.dex, ZIGZAGOON)

-- pokeemerald/src/easy_chat.c:5613
local list = EasyChat.populateGroups(session)
eq(list[1] and list[1].id, 0, "EC_GROUP_POKEMON (0) leads the Emerald group list once a species is seen")
eq(list[1] and #list[1].words, 1, "the Emerald POKEMON group only lists seen species")
eq(list[1] and list[1].words[1] and list[1].words[1].value, ZIGZAGOON, "and the seen species is ZIGZAGOON")
local ids = {}
for _, g in ipairs(list) do ids[g.id] = true end
check(not ids[21], "EC_GROUP_POKEMON_NATIONAL stays locked without the National Dex")
check(not ids[17] and not ids[20], "EVENTS and TRENDY_SAYING stay locked on a fresh save")
eq(list[2] and list[2].id, 1, "TRAINER follows POKEMON")

-- pokeemerald/src/easy_chat.c:5775
local trainer = list[2]
eq(trainer and #trainer.words, 2, "a disabled word is not offered")
eq(trainer and trainer.words[1] and trainer.words[1].text, "ALPHA", "words are listed in alphabeticalOrder")
eq(trainer and trainer.words[2] and trainer.words[2].text, "ZED", "and the last one is ZED")

EasyChat.open({ type = 7, words = { 0xFFFF }, session = session })
local st = EasyChat._state
check(st ~= nil and st.groups[1] and #st.groups[1].words == 1, "the picker opens on a group with a word to pick")
local okDraw, err = pcall(EasyChat.draw)
check(okDraw, "the Emerald easy chat screen draws without FRLG-only ROM text (" .. tostring(err) .. ")")

-- pokeemerald/src/easy_chat.c:1201
local footer, xs = EasyChat.footerLabels()
eq(table.concat(footer, "|"), "DEL. ALL|CANCEL|OK", "the Emerald footer reads gText_DelAll / gText_Cancel5 / gText_Ok2")
eq(32 + xs[1], 24, "DEL. ALL sits at the cart's column")
eq(32 + xs[3], 204, "OK sits at the cart's column")
EasyChat.close(false)

package.loaded["src.core.game3.rom_text"] = prevRomText
package.loaded["src.core.game3.runtime"] = prevRuntime
package.loaded["src.ui.game3.easy_chat"] = nil
Space.store = prevStore
GameVersion.set(prevVersion)
Profile.reset()
T.finish()
