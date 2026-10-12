package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local pushed = {}
local function top() return pushed[#pushed] end
local stack = {
  push = function(_, s) pushed[#pushed + 1] = s end,
  pop = function() return table.remove(pushed) end,
  top = function() return pushed[#pushed] end,
}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, after, opts) return { kind = "text", text = text, after = after, opts = opts } end,
}
package.loaded["src.ui.gen2.ScriptMenu"] = {
  new = function(_, opts) return { kind = "menu", opts = opts } end,
}
package.loaded["src.ui.gen2.PartyMenu"] = {
  new = function(_, opts) return { kind = "party", opts = opts } end,
}
package.loaded["src.ui.gen2.union.List"] = {
  new = function(_, title, items, onDone)
    return { kind = "list", title = title, items = items,
             choose = function(self, it) if top() == self then table.remove(pushed) end onDone(it) end }
  end,
}
local invited
package.loaded["src.ui.gen2.union.Talk"] = {
  invite = function(_, p, activity) invited = { p = p, activity = activity } end,
}

local UI = require("src.ui.gen2.union.Board")
local RoomMap = require("src.world.gen2.UnionRoomMap")

local maps = {
  TRADE_CENTER = {
    id = "TRADE_CENTER", group = 20, map = 2, width = 5, height = 4, tileset = "TILESET_GATE",
    blocks = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 2 },
    warps = { { x = 4, y = 7, destMap = "POKECENTER_2F", destWarp = 2 } }, objects = {},
  },
  GOLDENROD_POKECENTER_1F = { objects = { { index = 1, x = 3, y = 1, sprite = "SPRITE_NURSE", spriteId = 9,
    palette = 0, movement = 6, eventFlag = 65535, scriptKey = "nurse" } } },
}
local tile = {}
for i = 1, 16 do tile[i] = 0 end
local tilesets = { TILESET_GATE = { blocks = { tile, tile, tile, tile }, collision = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 },
  { 0, 0, 0, 0 }, { 0, 0, 0x70, 0x70 } } } }
local room = RoomMap.build(maps, tilesets, { map = "POKECENTER_2F", warp = 5, group = 20, mapNum = 1 })
local nurse = room.objects[1]
check(nurse and nurse.sprite == "SPRITE_NURSE", "the Gen 2 union room has a nurse")
eq(nurse and (nurse.x .. "," .. nurse.y), "3,2", "standing at FRLG's attendant cell")
eq(nurse and nurse.onTalk, RoomMap.talkAttendant, "talking to her opens the board attendant")
eq(nurse and nurse.scriptKey, nil, "she runs no cart script")
local sign = room.bgEvents[1]
eq(sign and (sign.x .. "," .. sign.y), "2,1", "the board reads at FRLG's board cell")
eq(sign and sign.onTalk, RoomMap.talkBoard, "reading it checks the board")
for slot = 1, RoomMap.CAP do
  local x, y = RoomMap.cellFor(slot)
  check(not (x == 3 and y == 2), "no member slot lands on the nurse " .. slot)
end

local data = {
  pokemon = {
    PIKACHU = { dex = 25, name = "PIKACHU", types = { "ELECTRIC" } },
    TOGEPI = { dex = 175, name = "TOGEPI", types = { "NORMAL" } },
    MAREEP = { dex = 179, name = "MAREEP", types = { "ELECTRIC" } },
  },
  type_chart = { types = { ELECTRIC = { name = "ELECTRIC" }, NORMAL = { name = "NORMAL" }, STEEL = { name = "STEEL" } } },
}
local pika = { species = "PIKACHU", level = 12 }
local egg = { species = "TOGEPI", level = 5, isEgg = true }
local members = {
  { id = "a", slot = 1, name = "AMY", gen = 3, status = "idle", board = { species = 179, level = 5, wantType = 13 } },
  { id = "b", slot = 2, name = "BOB", gen = 3, status = "idle", board = { species = 252, level = 5, wantType = 0 } },
  { id = "c", slot = 3, name = "CAL", gen = 1, status = "idle", board = { species = 25, level = 7, wantType = 0 } },
}
local sent = {}
local uiLog = {}
local session = {
  state = "joined", game = { data = data, stack = stack, save = { party = { egg, pika }, player = { name = "GOLD" } } },
  room = {
    members = function() return members end,
    member = function(_, id) for _, m in ipairs(members) do if m.id == id then return m end end end,
    setBoard = function(_, b) sent[#sent + 1] = b return true end,
  },
  uiOpen = function(_, k) uiLog[#uiLog + 1] = "open:" .. tostring(k) end,
  uiDone = function() uiLog[#uiLog + 1] = "done" end,
}

eq(#require("src.online.union.Board").offers(session.room, UI.DEX_MAX), 2, "Gen 2 lists offers up to dex 251")

UI.attendant(session)
local welcome = top()
check(tostring(welcome.text):find("TRADING BOARD", 1, true), "the nurse welcomes to the board")
welcome.opts.stay.onShown()
local menu = top()
eq(#menu.opts.header.items, 3, "REGISTER / INFO / EXIT")
menu.opts.onChoose(1)
top().after()
local party = top()
eq(party.kind, "party", "the party menu opens")
party.opts.onChoose(1, egg)
check(top() == party, "an EGG cannot be registered")
party.opts.onChoose(2, pika)
top().after()
local types = top()
eq(types.kind, "list", "the type list opens")
local steel
for _, it in ipairs(types.items) do if it.value == "STEEL" then steel = it end end
check(steel ~= nil, "Gen 2 can ask for STEEL")
types:choose(steel)
local reg = sent[#sent]
check(reg and reg.species == 25 and reg.wantType == 8, "PIKACHU is posted wanting STEEL")
top().after()
eq(uiLog[#uiLog], "done", "registration finishes the talk")

UI.attendant(session)
local cancelAsk = top()
check(tostring(cancelAsk.text):find("PIKACHU", 1, true), "talking again offers to cancel")
cancelAsk.opts.choice(true)
eq(sent[#sent], false, "cancel clears the board")
top().after()

UI.check(session)
top().after()
local list = top()
eq(#list.items, 3, "two offers and CANCEL")
list:choose(list.items[2])
check(tostring(top().text):find("NORMAL-type", 1, true), "the EGG does not count as a NORMAL POKEMON")
top().after()
list = top()
list:choose(list.items[1])
local ask = top()
check(tostring(ask.text):find("AMY", 1, true), "PIKACHU fits AMY's ELECTRIC request")
ask.opts.choice(true)
check(invited and invited.p.id == "a" and invited.activity == "xg_trade", "the board sends AMY a cross-gen trade invite")

T.finish("union_gen2_trading_board")
