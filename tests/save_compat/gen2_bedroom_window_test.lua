package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local Ctx = require("src.save_convert.Gen2MapContext")
local Codec = require("src.save_convert.Gen2Save")
local G2 = require("tests.fixtures.save.gen2_build")

local ROM_BLOCKS = { 4, 1, 3, 2, 5, 6, 5, 5, 5, 5, 7, 5 }

local function mapsFor(id)
  return { maps = { [id] = { group = 24, map = 7, width = 4, height = 3, blocks = ROM_BLOCKS, objects = {},
                             objectEventsAddr = 0x4000 } } }
end

local function window(version, id, save)
  local ctx = assert(Ctx.build(mapsFor(id), version, 24, 7, 3, 3, save))
  return table.concat(ctx.writes[Ctx.OFFSETS[version == "crystal" and "crystal" or "goldSilver"].screenSave], ",")
end

local function rows(a)
  return table.concat(a, ",")
end

local FULL = rows({ 0, 0, 0, 0, 0, 0, 0, 11, 1, 3, 36, 0, 0, 12, 13, 12, 5, 0, 0, 30, 5, 7, 32, 0, 0, 0, 0, 0, 0, 0 })
local DEFAULT = rows({ 0, 0, 0, 0, 0, 0, 0, 4, 1, 3, 31, 0, 0, 5, 6, 5, 5, 0, 0, 27, 5, 7, 5, 0, 0, 0, 0, 0, 0, 0 })
local BARE = rows({ 0, 0, 0, 0, 0, 0, 0, 4, 1, 3, 2, 0, 0, 5, 6, 5, 5, 0, 0, 5, 5, 7, 5, 0, 0, 0, 0, 0, 0, 0 })

for _, v in ipairs({ "gold", "silver", "crystal" }) do
  local deco = { decorations = { bed = 5, carpet = 8, plant = 12, poster = 18 } }
  eq(window(v, "PLAYERS_HOUSE_2F", deco), FULL, v .. ": a furnished bedroom's first screen carries the blocks the TILES callback lays (mGBA measured)")
  eq(window(v, "PLAYERS_HOUSE_2F", {}), DEFAULT, v .. ": a new game's bedroom has the feathery bed and the town map (mGBA measured)")
  eq(window(v, "PLAYERS_HOUSE_2F", { decorations = {} }), BARE, v .. ": an emptied room is the bare ROM blocks")
  eq(window(v, "SOME_OTHER_ROOM", deco), BARE, v .. ": no other map gets decorations")
  local moved = assert(Ctx.reposition(mapsFor("PLAYERS_HOUSE_2F"), v, 24, 7, 3, 3, deco))
  eq(table.concat(moved.writes[Ctx.OFFSETS[v == "crystal" and "crystal" or "goldSilver"].screenSave], ","), FULL,
    v .. ": a repositioned save gets the same window")
  local data = mapsFor("PLAYERS_HOUSE_2F")
  data.items = G2.ITEMS
  local model = assert(Codec.decode(G2.build({ version = v }), v, data))
  model.rawImport = nil
  model.position.x, model.position.y = 3, 3
  model.decorations = nil
  local image = assert(Codec.encode(model, v, nil, data))
  model = assert(Codec.decode(image, v, data))
  eq(assert(Codec.encode(model, v, image, data)), image, v .. ": unchanged bedroom is byte exact")
  model.decorations = deco.decorations
  local furnished = assert(Codec.encode(model, v, image, data))
  local off = Ctx.offsetsFor(v).screenSave
  eq(rows({ furnished:byte(off + 1, off + 30) }), FULL,
    v .. ": decorating an imported bedroom refreshes the window without moving")
end

T.finish()
