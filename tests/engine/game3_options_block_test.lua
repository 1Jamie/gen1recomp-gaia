-- T1.1 handoff (docs/game3/rse-seams.md section 4, finding J2): the engine
-- options block key comes from the game profile, not the `"firered"` literal.
--
-- Regression: Options.BLOCK was a hardcoded "firered" and every read/write went
-- through it, so a second Gen 3 game would share FireRed's options block.
-- FireRed resolves to "firered" in every path, so existing files are unchanged.
--   luajit tests/engine/game3_options_block_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Options = require("src.core.game3.options")
local Profile = require("src.core.game3.profile")

-- 1. Compatibility field stays, sourced from the profile.
eq(Options.BLOCK, Profile.FALLBACK_ID, "Options.BLOCK is the profile fallback id")
eq(Profile.active().optionsBlock, "firered", "the active profile resolves to firered headless")

-- 2. Defaults still fill, and the block lands under the profile's key.
local engine = {}
local o = Options.block(engine)
eq(o.textSpeed, 1, "defaults are filled")
check(type(engine.firered) == "table", "the block is created under the profile's block id")

-- 3. An explicit block id is honoured (the seam RSE callers use).
local engine2 = {}
Options.block(engine2, "other")
check(type(engine2.other) == "table", "an explicit block id creates that block")
check(engine2.firered == nil, "no firered block is created when an explicit id is given")

-- 4. bind() keys off the session's stored game (T0.2 version field).
local session = { version = "firered" }
local engine3 = { firered = { textSpeed = 2, buttonMode = 2 } }
local bound = Options.bind(session, engine3)
eq(bound.textSpeed, 2, "bind reads the stored game's block")
eq(bound.text_speed, 2, "the text_speed alias is set")
eq(bound.l_equals_a, true, "the l_equals_a alias is set")

-- 5. ensure() reads a nested engine options table by the session's block id.
local nestedOpts = { firered = { textSpeed = 0 } }
local nested = { version = "firered", options = nestedOpts }
eq(Options.ensure(nested).textSpeed, 0, "ensure reads the stored game's nested block")
eq(nested.engineOptions, nestedOpts, "ensure records the engine options table")

-- 6. Unknown ids fail closed to the active profile without raising.
eq(Options.blockId({ version = "not-a-real-game" }), Profile.active().optionsBlock,
  "an unknown game id fails closed to the active block")
eq(Options.blockId({}), Profile.active().optionsBlock, "no version means the active block")

-- 7. The legacy root-level migration still runs when a block is created.
local legacy = { battleStyle = 1 }
local migrated = Options.block(legacy)
eq(migrated.battleStyle, 1, "legacy root keys migrate into the block")
eq(legacy.battleStyle, nil, "the legacy root key is removed")

T.finish("game3_options_block_test")
