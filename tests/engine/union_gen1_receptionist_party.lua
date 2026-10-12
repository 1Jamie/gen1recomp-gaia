package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.render.TextBox"] = {
  new = function(_, text, after, opts) return { text = text, after = after, opts = opts } end,
}

local UnionCenters = require("src.world.gen1.UnionCenters")
local talk = require("data.scripts.pokecenter_upstairs")[UnionCenters.FLOOR_2F].talk[UnionCenters.TEXT_UNION]

local function game(party)
  local pushed = {}
  return {
    pushed = pushed,
    data = { text = { _CableClubNPCMakingPreparationsText = "PREP",
      _CableClubNPCPleaseComeAgainText = "COME AGAIN", _WouldYouLikeToSaveText = "SAVE?" } },
    save = { flags = { EVENT_GOT_POKEDEX = true }, party = party },
    stack = { push = function(_, box) pushed[#pushed + 1] = box end },
  }
end

local g1 = game({ "a" })
local done1 = false
talk(g1, {}, {}, function() done1 = true end)
local welcome = g1.pushed[1]
check(welcome and welcome.opts and welcome.opts.choice, "welcome asks yes/no")
welcome.opts.choice(true)
local refusal = g1.pushed[2]
check(refusal and tostring(refusal.text):find("at least two", 1, true) ~= nil,
  "one POKEMON gets the need-two text after YES")
check(refusal and refusal.text ~= "SAVE?", "one POKEMON is never offered the save")
refusal.after()
eq(g1.pushed[3] and g1.pushed[3].text, "COME AGAIN", "the refusal closes with please come again")
g1.pushed[3].after()
check(done1, "the refusal finishes the talk")

local g2 = game({ "a", "b" })
talk(g2, {}, {}, function() end)
g2.pushed[1].opts.choice(true)
eq(g2.pushed[2] and g2.pushed[2].text, "SAVE?", "two POKEMON go on to the save prompt")

local g0 = game({ "a" })
g0.save.flags.EVENT_GOT_POKEDEX = nil
talk(g0, {}, {}, function() end)
eq(g0.pushed[1] and g0.pushed[1].text, "PREP", "before the POKEDEX the attendant is still preparing")

local Caps = require("src.online.union.Caps")
local saved = Caps.gameplayMods
local gm = game({ "a", "b" })
Caps.gameplayMods = function() return true end
talk(gm, {}, {}, function() end)
eq(gm.pushed[1] and gm.pushed[1].text, Caps.MODS_TEXT, "link-play mods are refused at the desk, before the welcome")
gm.pushed[1].after()
eq(gm.pushed[2] and gm.pushed[2].text, "COME AGAIN", "then please come again")
local gp = game({ "a" })
gp.save.flags.EVENT_GOT_POKEDEX = nil
talk(gp, {}, {}, function() end)
eq(gp.pushed[1] and gp.pushed[1].text, "PREP", "the POKEDEX gate still comes first")
Caps.gameplayMods = saved

T.finish("union_gen1_receptionist_party")
