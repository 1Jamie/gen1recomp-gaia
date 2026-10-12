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
package.loaded["src.ui.Menu"] = {
  new = function(_, items, opts) return { kind = "menu", items = items, opts = opts } end,
}
package.loaded["src.ui.PartyMenu"] = {
  new = function(_, opts) return { kind = "party", opts = opts } end,
}
package.loaded["src.ui.ListMenu"] = {
  new = function(_, title, items, opts)
    local l = { kind = "list", title = title, items = items, opts = opts }
    function l:close() for i = #pushed, 1, -1 do if pushed[i] == self then table.remove(pushed, i) end end end
    return l
  end,
}
local invited
package.loaded["src.ui.union.gen1.Talk"] = {
  invite = function(_, _, p, activity, done) invited = { p = p, activity = activity, done = done } end,
}

local Board = require("src.online.union.Board")
local UI = require("src.ui.union.gen1.Board")
local UnionRoomMap = require("src.world.gen1.UnionRoomMap")

local def = UnionRoomMap.build(0, "UNION_FLOOR", 2)
local nurse = def.objects[1]
check(nurse and nurse.sprite == "SPRITE_NURSE", "the union room has a nurse attendant")
eq(nurse and (nurse.x .. "," .. nurse.y), "3,2", "the attendant stands where FRLG puts her")
eq(nurse and nurse.text, UnionRoomMap.TEXT_ATTENDANT, "the attendant talks through the board text id")
local sign = def.signs[1]
eq(sign and (sign.x .. "," .. sign.y .. ":" .. sign.text), "2,1:" .. UnionRoomMap.TEXT_BOARD,
  "the trading board reads at FRLG's board cell")
for slot = 1, UnionRoomMap.CAP do
  local x, y = UnionRoomMap.cellFor(slot)
  check(not (x == nurse.x and y == nurse.y), "no member slot lands on the attendant " .. slot)
end
local talk = require("data.scripts.pokecenter_upstairs")[UnionRoomMap.MAP_ID].talk
check(type(talk[UnionRoomMap.TEXT_ATTENDANT]) == "function", "the attendant has a talk handler")
check(type(talk[UnionRoomMap.TEXT_BOARD]) == "function", "the board has a talk handler")

eq(Board.entry(25, 12, "ELECTRIC").wantType, 13, "board types go out as the GBA type ids")
eq(Board.entry(25, 12, "BIRD"), nil, "an unknown type cannot be registered")

local data = {
  pokemon = {
    PIKACHU = { dex = 25, name = "PIKACHU", types = { "ELECTRIC" } },
    ODDISH = { dex = 43, name = "ODDISH", types = { "GRASS", "POISON" } },
    SQUIRTLE = { dex = 7, name = "SQUIRTLE", types = { "WATER" } },
  },
  type_chart = { types = { ELECTRIC = { name = "ELECTRIC" }, WATER = { name = "WATER" },
    GRASS = { name = "GRASS" }, POISON = { name = "POISON" }, PSYCHIC_TYPE = { name = "PSYCHIC" } } },
}
local pika = { species = "PIKACHU", level = 12 }
local oddish = { species = "ODDISH", level = 9 }
local members = {
  { id = "a", slot = 1, name = "AMY", gen = 3, status = "idle", board = { species = 7, level = 5, wantType = 13 } },
  { id = "b", slot = 2, name = "BOB", gen = 3, board = { species = 277, level = 5, wantType = 0 } },
  { id = "c", slot = 3, name = "CAL", gen = 2, board = { species = 43, level = 7, wantType = 10 } },
  { id = "d", slot = 4, name = "DEE", gen = 1 },
}
local sent = {}
local room = {
  members = function() return members end,
  member = function(_, id) for _, m in ipairs(members) do if m.id == id then return m end end end,
  setBoard = function(_, b) sent[#sent + 1] = b return true end,
  setStatus = function() return true end,
}
local busy = {}
local presence = { state = "joined", room = room, setBusy = function(_, on) busy[#busy + 1] = on end }
local game = { data = data, stack = stack, save = { party = { pika, oddish }, player = { name = "RED" } } }

local offers = Board.offers(room, UI.DEX_MAX)
eq(#offers, 2, "gen 1 lists only the offers it can hold")
eq(offers[1].p.name, "AMY", "a FireRed SQUIRTLE is listed")
eq(offers[2].typeName, "FIRE", "the wanted type decodes from the GBA id")

local done = 0
UI.attendant(game, presence, function() done = done + 1 end)
local welcome = top()
check(welcome.kind == "text" and tostring(welcome.text):find("TRADING BOARD", 1, true), "the attendant welcomes to the board")
welcome.opts.stay.onShown()
local menu = top()
eq(menu.kind, "menu", "the attendant offers REGISTER / INFO / EXIT")
eq(#menu.items, 3, "three choices")
menu.items[1].onSelect()
local which = top()
check(tostring(which.text):find("offer", 1, true), "register asks which POKEMON to offer")
which.after()
local party = top()
eq(party.kind, "party", "the party menu opens")
party.opts.onSwitch(pika)
top().after()
local types = top()
eq(types.kind, "list", "a type list follows")
local water
for _, it in ipairs(types.items) do if it.value == "WATER" then water = it end end
types.opts.onChoose(water)
local reg = sent[#sent]
check(reg and reg.species == 25 and reg.level == 12 and reg.wantType == 11, "PIKACHU is posted wanting WATER")
check(presence.boardEntry and presence.boardEntry.mon == pika, "the registration is kept")
top().after()
eq(done, 1, "registration finishes the talk")

UI.attendant(game, presence, function() done = done + 1 end)
local cancelAsk = top()
check(tostring(cancelAsk.text):find("PIKACHU", 1, true), "talking again offers to cancel the PIKACHU")
cancelAsk.opts.choice(true)
eq(sent[#sent], false, "cancel clears the board")
eq(presence.boardEntry, nil, "and the registration")
top().after()
eq(done, 2, "cancel finishes the talk")

presence.boardEntry = { mon = { species = "PIKACHU", level = 3 }, board = { species = 25, level = 3 } }
UI.settle(game, presence)
eq(presence.boardEntry, nil, "a registered POKEMON that left the party is unposted")

UI.check(game, presence, function() done = done + 1 end)
local checked = top()
check(tostring(checked.text):find("RED checked", 1, true), "checking the board names the player")
checked.after()
local list = top()
eq(list.kind, "list", "the board lists the offers")
eq(#list.items, 3, "two offers and CANCEL")
list.opts.onChoose(list.items[2])
local refuse = top()
check(tostring(refuse.text):find("FIRE-type", 1, true), "no FIRE POKEMON in the party refuses CAL")
refuse.after()
list = top()
eq(list.kind, "list", "the refusal returns to the board")
list.opts.onChoose(list.items[1])
local ask = top()
check(tostring(ask.text):find("AMY", 1, true), "AMY wants ELECTRIC and PIKACHU fits, so the trade is asked")
ask.opts.choice(true)
check(invited and invited.p.id == "a" and invited.activity == "xg_trade", "the board sends AMY a cross-gen trade invite")

local off = { state = "offline", offlineCode = "offline", room = room }
pushed = {}
UI.attendant(game, off, function() end)
check(top() and top().kind == "text", "offline the attendant only explains")

T.finish("union_gen1_trading_board")
