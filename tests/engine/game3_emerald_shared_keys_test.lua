package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local Itemfinder = require("src.core.game3.itemfinder")
local Flags = require("src.core.game3.scripting.flags")

local rse = { version = "emerald" }
local frlg = { version = "firered" }

eq(Itemfinder.textKey("nothing", rse), "gText_ItemFinderNothing", "Emerald itemfinder nothing key")
eq(Itemfinder.textKey("nearby", rse), "gText_ItemFinderNearby", "Emerald itemfinder nearby key")
eq(Itemfinder.textKey("onTop", rse), "gText_ItemFinderOnTop", "Emerald itemfinder on top key")
eq(Itemfinder.textKey("nothing", frlg), "gText_NopeTheresNoResponse", "FireRed itemfinder nothing key")
eq(Itemfinder.textKey("nearby", frlg), "gText_ItemfinderResponding", "FireRed itemfinder nearby key")
eq(Itemfinder.textKey("onTop", frlg), "gText_ItemfinderShakingWildly", "FireRed itemfinder on top key")

local em = Flags.forVersion("emerald").IDS
eq(em.FLAG_SYS_ENC_UP_ITEM, 2221, "Emerald white flute flag")
eq(em.FLAG_SYS_ENC_DOWN_ITEM, 2222, "Emerald black flute flag")

T.finish("game3_emerald_shared_keys_test")
