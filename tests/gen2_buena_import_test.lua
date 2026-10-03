-- pokecrystal/data/radio/buenas_passwords.asm:1
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness").suite("Crystal Buena ROM metadata #2639")
local Json = require("src.link.Json")
local Rom = require("src.import.Rom")
local Extractor = require("src.import.RomExtractorGen2")
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, v in pairs(value) do out[key] = copy(v) end
  return out
end
local manifest = Json.decode(assert(read("tools/rom_manifest_crystal.json")))
local expected = {
  stationName = "BUENA'S PASSWORD",
  categories = {
    { kind = "mon", width = 10, words = { "CYNDAQUIL", "TOTODILE", "CHIKORITA" } },
    { kind = "item", width = 12, words = { "FRESH_WATER", "SODA_POP", "LEMONADE" } },
    { kind = "item", width = 12, words = { "POTION", "ANTIDOTE", "PARLYZ_HEAL" } },
    { kind = "item", width = 12, words = { "POKE_BALL", "GREAT_BALL", "ULTRA_BALL" } },
    { kind = "mon", width = 10, words = { "PIKACHU", "RATTATA", "GEODUDE" } },
    { kind = "mon", width = 10, words = { "HOOTHOOT", "SPINARAK", "DROWZEE" } },
    { kind = "string", width = 16, words = { "NEW BARK TOWN", "CHERRYGROVE CITY", "AZALEA TOWN" } },
    { kind = "string", width = 6, words = { "FLYING", "BUG", "GRASS" } },
    { kind = "move", width = 12, words = { "TACKLE", "GROWL", "MUD_SLAP" } },
    { kind = "item", width = 12, words = { "X_ATTACK", "X_DEFEND", "X_SPEED" } },
    { kind = "string", width = 13, words = { "POKéMON Talk", "POKéMON Music", "Lucky Channel" } },
  },
}
local symbols = {
  BuenasPasswordTable = { 0x2e, 0x4ff9 },
  BuenasPasswordChannelName = { 0x2e, 0x5171 },
}
for name, location in pairs(symbols) do
  T.same(manifest.symbols[name], location, "required Crystal symbol " .. name)
end
for _, revision in pairs(manifest.symbolRevisions) do
  for name, location in pairs(symbols) do
    T.same(revision[name] or manifest.symbols[name], location,
      "required Crystal 1.1 symbol " .. name)
  end
end
for _, entry in ipairs({
  { path = "../pokecrystal-symbols/pokecrystal.sym", build = "crystal" },
  { path = "../pokecrystal-symbols/pokecrystal11.sym", build = "crystal11" },
}) do
  local body = read(entry.path)
  if body then
    for name, location in pairs(symbols) do
      local bank, address = body:match("(%x+):(%x+) " .. name .. "\n")
      T.eq(tonumber(bank, 16), location[1], entry.build .. " exact bank " .. name)
      T.eq(tonumber(address, 16), location[2], entry.build .. " exact address " .. name)
    end
  else
    print("SKIP exact pret symbol file " .. entry.build)
  end
end
local palettes = {
  BattleTowerInsidePalette = { 18, 21840 }, HousePalette = { 18, 21998 },
  IcePathPalette = { 18, 21919 }, MansionPalette1 = { 18, 22141 },
  MansionPalette2 = { 18, 22270 }, PokeComPalette = { 18, 21761 },
  RadioTowerPalette = { 18, 22077 },
}
for name, location in pairs(palettes) do
  T.same(manifest.symbols[name], location, "prior palette preserved " .. name)
end
for _, name in ipairs({ "_BuenaRadioText1", "_BuenaRadioText4",
    "_BuenaRadioMidnightText10", "_BuenaOffTheAirText", "Music_BuenasPassword" }) do
  T.check(manifest.symbols[name] ~= nil, "existing ROM resource retained " .. name)
end
local real = read("../pokecrystal/pokecrystal.gbc")
if real then
  local e = Extractor.new(real, manifest)
  local eventTables = e:readEventTables()
  T.same(eventTables.buenaPassword, expected, "actual 1.0 events metadata")
  local textAt = manifest.symbols._BuenaRadioText4
  T.eq(e:decodeGen2Text(textAt[1], textAt[2], manifest.charmap),
    "\n{STRBUF}!{DONE}", "actual existing dynamic broadcast text")
else
  print("SKIP actual Crystal 1.0 ROM")
end
T.check(type(Extractor.readBuenaPasswordData) == "function", "strict ROM reader available")
if type(Extractor.readBuenaPasswordData) ~= "function" then T.finish();return end

local function put(body, bank, address, bytes)
  local offset = Rom.offset(bank, address)
  return body:sub(1, offset) .. bytes .. body:sub(offset + #bytes + 1)
end
local glyphs = {}
for byte, text in pairs(manifest.charmap) do
  if tonumber(byte) ~= 0x50 and text ~= "" then
    glyphs[#glyphs + 1] = { text = text, byte = tonumber(byte) }
  end
end
table.sort(glyphs, function(a, b) return #a.text > #b.text end)
local function encode(text)
  local out, index = {}, 1
  while index <= #text do
    local found
    for _, glyph in ipairs(glyphs) do
      if text:sub(index, index + #glyph.text - 1) == glyph.text then
        out[#out + 1] = string.char(glyph.byte)
        index = index + #glyph.text
        found = true
        break
      end
    end
    assert(found, "fixture character missing")
  end
  return table.concat(out) .. string.char(0x50)
end
local fixtureManifest = copy(manifest)
fixtureManifest.symbols.BuenasPasswordTable = { 1, 0x4000 }
fixtureManifest.symbols.BuenasPasswordChannelName = { 1, 0x4400 }
local fixture, rows = string.rep("\0", 0x8000), {}
local address = 0x4100
local kinds = { mon = 0, item = 1, move = 2, string = 3 }
local orders = { mon = manifest.constants.speciesOrder,
  item = manifest.constants.itemOrder, move = manifest.constants.moveOrder }
for i, category in ipairs(expected.categories) do
  rows[i] = address
  fixture = put(fixture, 1, 0x4000 + (i - 1) * 2,
    string.char(address % 256, math.floor(address / 256)))
  local bytes = { string.char(kinds[category.kind], category.width) }
  for _, word in ipairs(category.words) do
    if category.kind == "string" then
      bytes[#bytes + 1] = encode(word)
    else
      local id
      for index, name in ipairs(orders[category.kind]) do if name == word then id = index;break end end
      assert(id, "fixture identifier missing")
      bytes[#bytes + 1] = string.char(id)
    end
  end
  local body = table.concat(bytes)
  fixture = put(fixture, 1, address, body)
  address = address + #body
end
fixture = put(fixture, 1, 0x4400, encode(expected.stationName))
local function extract(body, m, sha1)
  return Extractor.new(body or fixture, m or fixtureManifest, nil, sha1):readBuenaPasswordData()
end
T.same(extract(), expected, "synthetic ROM encodes all category types")
for sha1 in pairs(manifest.symbolRevisions) do
  local revisionFixture = copy(fixtureManifest)
  revisionFixture.symbols.BuenasPasswordTable = { 1, 0x4600 }
  revisionFixture.symbols.BuenasPasswordChannelName = { 1, 0x4700 }
  revisionFixture.symbolRevisions[sha1].BuenasPasswordTable = { 1, 0x4000 }
  revisionFixture.symbolRevisions[sha1].BuenasPasswordChannelName = { 1, 0x4400 }
  T.same(extract(fixture, revisionFixture, sha1), expected,
    "synthetic revision relocation reads resolved symbols")
  if real then
    T.same(Extractor.new(real, manifest, nil, sha1):readBuenaPasswordData(), expected,
      "1.1-symbol fixture uses unchanged Buena bytes from actual 1.0 ROM")
  end
end
local real11Path = os.getenv("POKEPORT_TEST_CRYSTAL11_ROM")
if real11Path then
  local bytes = assert(read(real11Path))
  for sha1 in pairs(manifest.symbolRevisions) do
    T.same(Extractor.new(bytes, manifest, nil, sha1):readBuenaPasswordData(), expected,
      "actual explicitly supplied Crystal 1.1 ROM")
  end
else
  print("SKIP actual Crystal 1.1 ROM; revision fixture and both sym files verified separately")
end
for _, version in ipairs({ "gold", "silver" }) do
  local m = Json.decode(assert(read("tools/rom_manifest_" .. version .. ".json")))
  local e = Extractor.new("", m)
  e.rom = setmetatable({}, { __index = function() error("Gold/Silver must not read Buena ROM") end })
  e.symbol = function() error("Gold/Silver must not request Buena symbols") end
  T.eq(e:readBuenaPasswordData(), nil, version .. " emits no Buena data or ROM reads")
end
local renamed = put(fixture, 1, 0x4400, encode("ALPHA STATION"))
T.eq(extract(renamed).stationName, "ALPHA STATION", "station name comes from changed ROM bytes")
local firstMon = put(fixture, 1, rows[1] + 2, string.char(1))
T.eq(extract(firstMon).categories[1].words[1], "BULBASAUR", "category identifier comes from changed ROM byte")
local rawWord = put(fixture, 1, rows[8] + 2, encode("GROUND"))
T.eq(extract(rawWord).categories[8].words[1], "GROUND", "raw category string comes from changed ROM bytes")
for _, symbol in ipairs({ "BuenasPasswordTable", "BuenasPasswordChannelName" }) do
  local m = copy(fixtureManifest);m.symbols[symbol] = nil
  T.raises(function() extract(fixture, m) end, "required symbol is missing", "missing " .. symbol .. " fails")
end
for _, value in ipairs({ -1, 1.5, 128, math.huge }) do
  local m = copy(fixtureManifest);m.symbols.BuenasPasswordChannelName[1] = value
  T.raises(function() extract(fixture, m) end, "invalid Buena ROM bank", "invalid bank " .. value)
end
for _, value in ipairs({ 0x3fff, 0x8000, 0x4400 + 0.5, math.huge }) do
  local m = copy(fixtureManifest);m.symbols.BuenasPasswordChannelName[2] = value
  T.raises(function() extract(fixture, m) end, "invalid Buena ROM pointer", "invalid station pointer " .. value)
end
for _, pointer in ipairs({ 0, 0x3fff, 0x7fff, 0x8000 }) do
  local body = put(fixture, 1, 0x4000, string.char(pointer % 256, math.floor(pointer / 256)))
  T.raises(function() extract(body) end, "invalid Buena ROM pointer", "invalid category pointer " .. pointer)
end
local m = copy(fixtureManifest);m.symbols.BuenasPasswordTable[2] = 0x7ff0
T.raises(function() extract(fixture, m) end, "invalid Buena ROM pointer", "table cannot cross ROM bank")
T.raises(function() extract(put(fixture, 1, rows[1], string.char(4))) end,
  "invalid Buena password type", "unsupported function type fails")
for _, width in ipairs({ 0, 19, 255 }) do
  T.raises(function() extract(put(fixture, 1, rows[1] + 1, string.char(width))) end,
    "invalid Buena password width", "invalid menu width " .. width)
end
for _, category in ipairs({ 1, 2, 9 }) do
  T.raises(function() extract(put(fixture, 1, rows[category] + 2, string.char(0))) end,
    "invalid Buena password identifier", "zero identifier type " .. category)
end
local missingOrder = copy(fixtureManifest);missingOrder.constants.moveOrder = {}
T.raises(function() extract(fixture, missingOrder) end, "invalid Buena password identifier",
  "unknown identifier has no invented name")
local unused = copy(fixtureManifest);unused.constants.speciesOrder[155] = "UNUSED_MON"
T.raises(function() extract(fixture, unused) end, "invalid Buena password identifier", "unused identifier fails")
T.raises(function() extract(put(fixture, 1, 0x4400, string.rep(string.char(0x80), 32))) end,
  "unterminated Buena ROM string", "station terminator required")
T.raises(function() extract(put(fixture, 1, rows[8] + 2, string.rep(string.char(0x80), 32))) end,
  "unterminated Buena ROM string", "category terminator required")
T.raises(function() extract(put(fixture, 1, 0x4400, string.char(0x50))) end,
  "empty Buena ROM string", "station cannot be empty")
T.raises(function() extract(put(fixture, 1, rows[8] + 2, string.char(0x50))) end,
  "empty Buena ROM string", "category word cannot be empty")
local unknown
for byte = 0, 255 do if manifest.charmap[tostring(byte)] == nil then unknown = byte;break end end
assert(unknown)
T.raises(function() extract(put(fixture, 1, rows[8] + 2, string.char(unknown))) end,
  "invalid Buena ROM character", "unmapped string byte has no fallback")
T.raises(function() extract(fixture:sub(1, Rom.offset(1, 0x4400))) end,
  "ROM read past end", "truncated ROM fails")
T.finish()
