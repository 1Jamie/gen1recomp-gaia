package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local function glyphs(text)
  local out = {}
  for chunk in (text .. "\n"):gmatch("([^\n\v]*)[\n\v]") do
    out[#out + 1] = table.concat(Font.encode(chunk), ",")
  end
  return out
end

local function shownStrings(battle)
  local out = {}
  for i, line in ipairs(battle.shown) do out[i] = table.concat(line, ",") end
  return out
end

local function setup()
  local save = SaveData.newGame()
  local mon = Pokemon.new(Data, "FIXMON_A", 20, function(_, b) return b end)
  local moveIds = { "FIX_TACKLE", "FIX_SCRATCH", "FIX_EMBERISH", "FIX_CUT", "FIX_NEW" }
  local copy = {}
  for k, v in pairs(Data.moves.FIX_CUT) do copy[k] = v end
  copy.id, copy.name = "FIX_NEW", "FIX NEW"
  Data.moves.FIX_NEW = copy
  mon.moves = {}
  for i = 1, 4 do mon.moves[i] = { id = moveIds[i], pp = 5 } end
  save.party = { mon }
  local game = { data = Data, save = save,
               stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 10)
  battle.queue, battle.nextInsert = {}, 0
  local newMove = moveIds[5]
  local captured
  battle.buildScreen = function(_, _, _, _, onDone) captured = onDone return {} end
  battle:learnMove(mon, newMove)
  battle.queue[1].ui()
  return battle, mon, Data.moves[newMove], captured
end

do
  local battle, mon, mdef, onDone = setup()
  T.check(type(onDone) == "function", "the learn menu is handed an onDone")
  local grew = glyphs("GREW\nTO LEVEL 20!")
  battle.shown = {}
  for i, g in ipairs(grew) do battle.shown[i] = { g } end
  battle.msgHold = true
  onDone(true)
  local name = mon.nickname or Data.pokemon[mon.species].name
  local want = glyphs(name .. " learned\n" .. mdef.name .. "!")
  local got = shownStrings(battle)
  T.eq(got[1], want[1], "the held page is the learned line 1")
  T.eq(got[2], want[2], "the held page is the learned line 2")
  T.eq(battle.msgHold, true, "the page stays held")
  T.eq(battle.current, nil, "with no message pending")
end

do
  local battle, mon, mdef, onDone = setup()
  battle.shown = { { 1, 2, 3 } }
  onDone(false)
  local name = mon.nickname or Data.pokemon[mon.species].name
  local want = glyphs(name .. "\ndid not learn\v" .. mdef.name .. "!")
  local got = shownStrings(battle)
  T.eq(#got, 2, "the did-not-learn hold is two lines")
  T.eq(got[1], want[2], "line 1 is the did-not-learn line")
  T.eq(got[2], want[3], "line 2 is the move name")
end

T.finish("battle_learn_move_page_bug2540")
