-- Launcher save Import/Export glue (src/import/SaveFileIO.lua): the end-to-end
-- importToSlot -> listSlots roundtrip and the exportActiveSlot output-byte
-- sanity check, driven love-free through the same in-memory filesystem stub
-- tests/engine/save_slots.lua uses.  A synthetic 32KB SRAM image is built via
-- GenSave.encode (no real save checked in); a fixture-gated case exercises the
-- real .sav when POKEPORT_SAV_FIXTURE points at one.
--   luajit tests/engine/save_file_io_tests.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GenSave = require("src.save_convert.GenSave")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local SaveFileIO = require("src.import.SaveFileIO")

local realFS = love.filesystem

-- A love.filesystem stub keyed by full path, extended past save_slots' memfs
-- with the export surface SaveFileIO reaches for (createDirectory /
-- getSaveDirectory).  A directory key is implied by any file under it.
local function memfs(files)
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return "/fake/save" end,
  }
end

local function fresh()
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

-- ---- crosswalk data + synthetic 32KB save (built the way the codec tests do)
-- Gen1 encode/decode needs Red species/item indices from data/generated/,
-- which CI never has.  Skip cleanly so the ROM-free T1/T2 tier stays green.
local loadPokemon = loadfile("data/generated/pokemon.lua")
if not loadPokemon then
  print("save_file_io skipped (needs data/generated/ for Gen1 save codec)")
  os.exit(0)
end

GenSave.setCharmap(loadfile("src/save_convert/data/charmap.lua")())
local data = {
  pokemon = loadPokemon(),
  moves = loadfile("data/generated/moves.lua")(),
  items = loadfile("data/generated/items.lua")(),
  maps = loadfile("data/generated/maps.lua")(),
  eventFlags = loadfile("src/save_convert/data/event_flags.lua")(),
}

-- independent checksum re-derivation (complement of the additive byte sum) so
-- the export sanity check does not trust the encoder that wrote it
local bit = require("bit")
local OFF = GenSave.OFFSETS
local function rawChecksum(bytes, from, to)
  local sum = 0
  for i = from, to - 1 do sum = bit.band(sum + bytes:byte(i + 1), 0xFF) end
  return bit.band(bit.bnot(sum), 0xFF)
end
local function mainChecksumValid(bytes)
  return rawChecksum(bytes, OFF.checksumStart, OFF.checksumEnd)
    == bytes:byte(OFF.mainChecksum + 1)
end

local function syntheticSave(name)
  local seed = SaveData.newGame({ playerName = name, rivalName = "BLUE" })
  seed.money = 4321
  seed.inventory = { POTION = 2, POKE_BALL = 7, BOULDERBADGE = 1 }
  seed.bagOrder = { "POTION", "POKE_BALL" }
  seed.party = { {
    species = "SQUIRTLE", level = 6, exp = 200,
    dvs = { hp = 1, attack = 2, defense = 3, speed = 4, special = 5 },
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 22, attack = 12, defense = 13, speed = 11, special = 12 },
    hp = 22, status = nil,
    moves = { { id = "TACKLE", pp = 35, ppUps = 0 } },
    nickname = "SQ", ot = name, otId = seed.player.id, catchRate = 45,
  } }
  return GenSave.encode(seed, data, nil)
end

-- ---------------------------------------------- importToSlot -> listSlots

do
  fresh()
  local bytes = syntheticSave("IMP")
  eq(#bytes, GenSave.SAVE_SIZE, "the synthetic save is 32768 bytes")

  local ok, slotId = SaveFileIO.importToSlot(bytes, "red")
  eq(ok, true, "importToSlot succeeds on a valid 32KB save")
  eq(slotId, "slot1", "the first import registers slot1")

  local slots = SaveData.listSlots("red")
  eq(#slots, 1, "the imported save shows up as exactly one slot")
  eq(slots[1].id, "slot1", "the listed slot is slot1")
  eq(slots[1].exists, true, "the imported slot reports a save present")
  eq(slots[1].name, "IMP", "the imported slot surfaces the decoded player name")
  eq(SaveData.activeSlot("red"), "slot1", "the imported slot is made active")

  -- the slot loads cleanly (meta re-stamped from gen1_import to the numeric
  -- format, so runMigrations does not choke)
  local loaded = SaveData.load("red")
  check(loaded ~= nil, "the imported slot loads back")
  eq(loaded and loaded.player.name, "IMP", "loaded save keeps the player name")
  eq(loaded and loaded.money, 4321, "loaded save keeps the money")
  eq(loaded and #loaded.party, 1, "loaded save keeps the party")

  -- a second import allocates a fresh slot and makes it active
  local ok2, slot2 = SaveFileIO.importToSlot(syntheticSave("TWO"), "red")
  eq(ok2, true, "a second import succeeds")
  eq(slot2, "slot2", "the second import allocates slot2")
  eq(#SaveData.listSlots("red"), 2, "both imported slots are listed")
  eq(SaveData.activeSlot("red"), "slot2", "the newest import becomes active")
end

-- ---------------------------------------------- exportActiveSlot byte sanity

do
  local files = fresh()
  SaveFileIO.importToSlot(syntheticSave("EXP"), "red")

  local ok, path = SaveFileIO.exportActiveSlot("red")
  eq(ok, true, "exportActiveSlot succeeds for an active slot with a save")
  eq(path, "/fake/save/exports/gen1recomp-red-slot1.sav",
    "the export path is absolute and names the version + slot")

  local outBytes = files["exports/gen1recomp-red-slot1.sav"]
  check(outBytes ~= nil, "the export file lands in the save-dir exports/ folder")
  eq(outBytes and #outBytes, GenSave.SAVE_SIZE, "the export is exactly 32768 bytes")
  check(outBytes and mainChecksumValid(outBytes),
    "the export carries a valid main-data checksum")

  -- the export re-imports to an equivalent save
  local re = SaveConvert.importSav(outBytes, "red")
  check(re ~= nil, "the export re-imports through SaveConvert")
  eq(re and re.player and re.player.name, "EXP", "the export round-trips the player name")
  eq(re and re.party[1] and re.party[1].species, "SQUIRTLE",
    "the export round-trips the party")
  eq(re and re.inventory and re.inventory.BOULDERBADGE, 1,
    "the export round-trips a badge")
end

-- ---------------------------------------------- failure UX (never raises)

do
  fresh()
  -- wrong size via a DroppedFile-shaped source (100 bytes)
  local shortFile = {
    _bytes = string.rep("\0", 100),
    open = function() return true end,
    getSize = function(self) return #self._bytes end,
    read = function(self) return self._bytes end,
    close = function() return true end,
  }
  local ok, err = SaveFileIO.importToSlot(shortFile, "red")
  eq(ok, false, "a wrong-size save is rejected, not imported")
  check(type(err) == "string" and err:find("32", 1, true) ~= nil,
    "the wrong-size error names the required size")
  eq(#SaveData.listSlots("red"), 0, "a rejected import creates no slot")

  -- bad checksum: flip a modeled byte in an otherwise valid image
  local good = syntheticSave("BAD")
  local corrupt = good:sub(1, OFF.money)
    .. string.char((good:byte(OFF.money + 1) + 1) % 256)
    .. good:sub(OFF.money + 2)
  local okc, errc = SaveFileIO.importToSlot(corrupt, "red")
  eq(okc, false, "a bad-checksum save is rejected")
  check(type(errc) == "string" and errc:find("checksum", 1, true) ~= nil,
    "the bad-checksum error mentions the checksum")
  eq(#SaveData.listSlots("red"), 0, "a rejected checksum creates no slot")

  -- export with nothing to export
  local oke, erre = SaveFileIO.exportActiveSlot("red")
  eq(oke, false, "exportActiveSlot fails cleanly when there is no save")
  check(type(erre) == "string", "the empty-export failure carries a message")
end

-- ---------------------------------------------- fixture-gated real save

do
  local fixturePath = os.getenv("POKEPORT_SAV_FIXTURE")
  local fixtureBytes
  if fixturePath then
    local ff = io.open(fixturePath, "rb")
    if ff then
      fixtureBytes = ff:read("*a")
      ff:close()
      if #fixtureBytes ~= GenSave.SAVE_SIZE then fixtureBytes = nil end
    end
  end
  if not fixtureBytes then
    print("save_file_io fixture case skipped (set POKEPORT_SAV_FIXTURE to a 32KB .sav)")
  else
    local files = fresh()
    local ok, slotId = SaveFileIO.importToSlot(fixtureBytes, "red")
    eq(ok, true, "fixture: a real .sav imports to a slot")
    check(slotId ~= nil, "fixture: the import returns a slot id")

    local slots = SaveData.listSlots("red")
    eq(#slots, 1, "fixture: the real save shows as one slot")
    check(slots[1].exists and type(slots[1].name) == "string" and #slots[1].name > 0,
      "fixture: the imported slot has a non-empty player name")

    local loaded = SaveData.load("red")
    check(loaded ~= nil and #loaded.party >= 1 and #loaded.party <= 6,
      "fixture: the imported slot loads with a 1..6 party")

    local eok, path = SaveFileIO.exportActiveSlot("red")
    eq(eok, true, "fixture: the imported real save exports")
    local rel = path:gsub("^/fake/save/", "")
    local outBytes = files[rel]
    eq(outBytes and #outBytes, GenSave.SAVE_SIZE, "fixture: the export is 32768 bytes")
    check(outBytes and mainChecksumValid(outBytes),
      "fixture: the export has a valid main-data checksum")
  end
end

love.filesystem = realFS

T.finish("save_file_io")
