package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local Scripts = dofile("data/scripts/story6.lua")

local played
package.loaded["src.core.Sound"] = {
  play = function(_, id) played = id end,
}

local blocks = {}
local game = {
  data = { text = {
    _PokemonMansion1FSwitchText = "A secret switch!",
    _PokemonMansion1FSwitchPressedText = "Who wouldn't?",
  } },
  save = { flags = {} },
  stack = {
    push = function(self, box) self.box = box end,
  },
}
local ow = {
  map = { id = "POKEMON_MANSION_1F" },
  player = { facing = "up" },
  replaceBlock = function(_, x, y, block)
    blocks[#blocks + 1] = { x, y, block }
  end,
}

local interacted = Scripts.POKEMON_MANSION_1F.onInteract(game, ow, 2, 5)
T.check(interacted, "Mansion switch accepts interaction")
local question = game.stack.box
T.check(question and question.choice, "Mansion switch opens its yes/no prompt")
question.choice(true)
local pressed = game.stack.box
T.check(pressed and pressed ~= question, "yes opens the pressed message")
T.eq(game.save.flags.EVENT_MANSION_SWITCH_ON, nil,
  "door flag waits while pressed message is open")
T.eq(#blocks, 0, "door blocks wait while pressed message is open")

pressed.onDone()
T.eq(game.save.flags.EVENT_MANSION_SWITCH_ON, true,
  "door flag toggles after pressed message closes")
T.eq(#blocks, 4, "door blocks replace after pressed message closes")
T.eq(played, "Go_Inside", "switch jingle plays with the delayed update")

T.finish("mansion switch timing #2496")
