package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local Battle = require("src.core.game3.battle.init")

Battle._leveledUp = {}
local first = Battle._mergeLeveledSet({ [1] = true })
local second = Battle._mergeLeveledSet({ [2] = true })
T.check(first == second, "level-up marker keeps one battle-wide table")
T.eq(second[1], true, "level-up from the first trainer foe is retained")
T.eq(second[2], true, "level-up from the later trainer foe is retained")

Battle._mergeLeveledSet({ [1] = false, [2] = false })
T.eq(Battle._leveledUp[1], true, "a later award cannot erase the earlier marker")
T.eq(Battle._leveledUp[2], true, "a later empty award cannot erase a marker")

T.finish("game3 battle evolution marker #2503")
