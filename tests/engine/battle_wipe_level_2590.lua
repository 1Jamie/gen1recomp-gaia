-- engine/battle/read_trainer_party.asm:69-80
-- engine/battle/battle_transitions.asm:11-46,96-121
-- scripts/RocketHideoutB4F.asm:99-121

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, value)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then
      debug.setupvalue(fn, i, value)
      return true
    end
    i = i + 1
  end
end

local captured
local realBT = package.loaded["src.render.BattleTransition"]
package.loaded["src.render.BattleTransition"] = {
  new = function(_, onDone, opts)
    captured = { opts = opts, onDone = onDone }
    return captured
  end,
}

local pushed = {}
local fakeGame = {
  save = { party = {} },
  stack = { push = function(_, s) table.insert(pushed, s) end },
}
check(setUpvalue(OW.pushBattle, "Game", fakeGame),
      "pushBattle reads Game through an upvalue")

local ow = setmetatable({ player = {} }, { __index = OW })
ow.isDungeonTransitionMap = function() return false end

local function lead(level)
  fakeGame.save.party = { { hp = 0, level = 99 }, { hp = 20, level = level } }
end
local function trainerBattle(levels)
  local party = {}
  for i, l in ipairs(levels) do party[i] = { level = l } end
  return { kind = "trainer", enemyParty = party, enemy = { mon = party[1] } }
end

lead(24)
ow:pushBattle(trainerBattle({ 25, 24, 29 }))
eq(captured.opts.trainer, true, "a trainer battle sets the trainer bit")
eq(captured.opts.stronger, true,
   "GiovanniData L25/24/29 vs a L24 lead: wCurEnemyLevel is the last mon (29), outward spiral")

lead(25)
ow:pushBattle(trainerBattle({ 25, 24, 29 }))
eq(captured.opts.stronger, true, "L29 last mon vs a L25 lead is still >= lead+3")

lead(27)
ow:pushBattle(trainerBattle({ 25, 24, 29 }))
eq(captured.opts.stronger, false, "a L27 lead gets the inward spiral")

lead(10)
ow:pushBattle(trainerBattle({ 15, 9 }))
eq(captured.opts.stronger, false,
   "a strong lead mon does not count when the last mon is weaker")

lead(10)
ow:pushBattle({ kind = "wild", enemy = { mon = { level = 13 } } })
eq(captured.opts.trainer, false, "a wild battle clears the trainer bit")
eq(captured.opts.stronger, true, "a wild battle still compares the wild mon's level")
lead(11)
ow:pushBattle({ kind = "wild", enemy = { mon = { level = 13 } } })
eq(captured.opts.stronger, false, "wild L13 vs L11 lead stays inward")

local giovanni, other = { id = "giovanni" }, { id = "rocket" }
ow:pushBattle(trainerBattle({ 25, 24, 29 }), giovanni)
eq(ow.battleOamKeep, giovanni, "the talked-to trainer keeps his OAM through the wipe")
check(not ow:oamCulled(giovanni), "Giovanni is not culled")
check(ow:oamCulled(other), "other sprites are culled")
check(not ow:oamCulled(ow.player), "the player is not culled")
captured.onDone()
eq(ow.battleOamKeep, nil, "the keep clears once the battle is pushed")

package.loaded["src.render.BattleTransition"] = realBT

local realTextBox = package.loaded["src.render.TextBox"]
local realBattleState = package.loaded["src.battle.BattleState"]
local boxes = {}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, cb, opts)
    local box = { text = text, cb = cb, opts = opts }
    table.insert(boxes, box)
    return box
  end,
  substitute = function(_, text) return text end,
  soundOpts = require("src.render.TextBox").soundOpts,
}
package.loaded["src.battle.BattleState"] = {
  newTrainer = function(_, class, index)
    return { kind = "trainer", trainerClass = class, partyIndex = index }
  end,
}
local scripts = dofile("data/scripts/story3.lua")
local handler = scripts.ROCKET_HIDEOUT_B4F.talk.TEXT_ROCKETHIDEOUTB4F_GIOVANNI

local events = {}
local sow = {
  trainerDefeated = function() return false end,
  playTrainerMusic = function(_, cls) table.insert(events, { "music", cls }) end,
  pushBattle = function(_, b, npc) table.insert(events, { "battle", b, npc }) end,
  afterBattle = function() end,
}
local game = {
  data = { text = {} },
  save = { defeatedTrainers = {}, flags = {}, player = { name = "RED" } },
  stack = { push = function() end },
}
local npc = { id = "giovanni", facing = "left", origFacing = "down" }
handler(game, sow, npc, function() end)
eq(#boxes, 1, "the impressed line opens the scene")
eq(#events, 0, "nothing plays or starts while the box types")
local auto = boxes[1].opts and boxes[1].opts.auto
check(type(auto) == "table" and type(auto.sound) == "function",
      "the sting is armed on the box itself (RocketHideoutB4F.asm:113 before AfterDisplayingTextID)")
eq(auto and auto.wait, true, "the box still waits for A after the sting starts")
eq(auto and auto.sound(), nil, "the sting does not hold the box")
eq(events[1] and events[1][1], "music", "the typed box plays the trainer music")
eq(events[1] and events[1][2], "OPP_GIOVANNI", "for OPP_GIOVANNI (EvilTrainerList)")
eq(#events, 1, "the battle waits for the box to close")
eq(sow.emote, nil, "no world hold after the close (home/overworld.asm:127-130)")
boxes[1].cb()
eq(events[2] and events[2][1], "battle", "closing the box pushes the battle straight away")
eq(events[2] and events[2][3], npc, "with the talked-to Giovanni kept on screen")
eq(npc.facing, "down", "CloseTextDisplay restores his pre-talk facing (text_script.asm:112-120)")

package.loaded["src.render.TextBox"] = realTextBox
package.loaded["src.battle.BattleState"] = realBattleState

local faced = { facing = "down", facePlayer = function(self) self.facing = "left" end }
OW.makeNpcFacePlayer({ player = {} }, faced)
eq(faced.facing, "left", "talking turns the NPC to the player")
eq(faced.origFacing, "down", "and remembers the facing he had (display_text_id_init.asm:42-51)")

local Music = require("src.core.Music")
local realPlay = Music.play
local played
Music.play = function(_, song) played = song end
check(setUpvalue(OW.playTrainerMusic, "Game", { data = {} }),
      "playTrainerMusic reads Game through an upvalue")
OW.playTrainerMusic(ow, "OPP_GIOVANNI")
eq(played, "Music_MeetEvilTrainer", "OPP_GIOVANNI gets the evil-trainer sting")
played = nil
OW.playTrainerMusic(ow, "OPP_RIVAL2")
eq(played, nil, "rivals get no sting")
OW.playTrainerMusic(ow, "OPP_LASS")
eq(played, "Music_MeetFemaleTrainer", "female classes get the female sting")
Music.play = realPlay

T.finish("battle_wipe_level_2590")
