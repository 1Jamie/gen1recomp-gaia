package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local Json = require("src.link.Json")
local Context = require("src.save_convert.Gen2SpriteContext")
local Extractor = require("src.import.RomExtractorGen2")
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local bytes = f:read("*a")
  f:close()
  return bytes
end
local fixture = assert(Json.decode(assert(read("tests/fixtures/save/gen2_sprite_context.json"))))
local dataByEdition = {}

for _, build in ipairs(fixture.builds) do
  local edition = build.edition
  local manifest = assert(Json.decode(assert(read("tools/rom_manifest_" .. edition .. ".json"))))
  local constants = manifest.constants
  constants.spriteContext = build.metadata
  local sprites = {}
  for _, name in ipairs(constants.spriteOrder) do sprites[name] = {} end
  local data = { constants = constants, sprites = sprites }
  dataByEdition[edition] = data
  local stem = edition == "crystal" and "pokecrystal/pokecrystal" or "pokegold/poke" .. edition
  local rom = read(os.getenv("GEN2_" .. edition:upper() .. "_ROM") or "../" .. stem .. ".gbc")
  if rom then
    local extractor = Extractor.new(rom, manifest)
    extractor.write = function() end
    local extracted = extractor:extractConstants().spriteContext
    T.same(extracted, build.metadata, edition .. " cached sprite metadata matches every original ROM row")
    data.constants = extractor:extractConstants()
  end
  for index, case in ipairs(build.cases) do
    local objects = {}
    for _, id in ipairs(case.rawIds) do objects[#objects + 1] = { spriteId = id } end
    local state = { playerState = case.playerState,
      player = { gender = case.female and "female" or "male" }, variableSprites = case.variables,
      dayCare = { man = { mon = { species = "PIKACHU" } } } }
    local result, why = Context.build(data, edition, { group = case.group,
      environment = case.outdoor and "TOWN" or "INDOOR", objects = objects }, state)
    T.check(result ~= nil, edition .. " native sprite case " .. index .. " builds: " .. tostring(why))
    for raw, expected in pairs(case.expected) do
      local actual = result and result[tonumber(raw)]
      T.eq(actual and actual.tile, expected.tile, edition .. " case " .. index .. " original tile for " .. raw)
      T.eq(actual and actual.palette, expected.palette, edition .. " case " .. index .. " original palette for " .. raw)
    end
  end
end

local data = dataByEdition.crystal
local map = { group = 26, environment = "TOWN", objects = { { spriteId = 47 } } }
local metadata = data.constants.spriteContext
data.constants.spriteContext = nil
local result, why = Context.build(data, "crystal", map, {})
T.eq(result, nil, "old caches refuse NPC reconstruction")
T.check(why and why:find("re-import the ROM", 1, true), "missing metadata names the cache repair")
data.constants.spriteContext = metadata
result, why = Context.build(data, "gold", map, {})
T.eq(result, nil, "cross-edition sprite metadata is refused")
T.check(why and why:find("different edition", 1, true), "edition refusal is named")
local group = metadata.outdoorGroups[26]
metadata.outdoorGroups[26] = nil
result, why = Context.build(data, "crystal", map, {})
T.eq(result, nil, "missing outdoor list is refused")
metadata.outdoorGroups[26] = group
result, why = Context.build(data, "crystal", { environment = "INDOOR",
  objects = { { spriteId = 0xF0 } } }, { variableSprites = { [0] = 0xF1, [1] = 0xF0 } })
T.eq(result, nil, "cyclic variable sprites are refused")
T.check(why and why:find("cycle", 1, true), "variable sprite cycle is named")

T.finish()
