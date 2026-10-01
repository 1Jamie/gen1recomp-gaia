return function(game)
  local U = require("tests.drivers.util")
  local GameVersion = require("src.core.GameVersion")
  local SaveData = require("src.core.SaveData")
  local CacheFs = require("src.import.CacheFs")
  local Contract = require("src.import.CacheContract")
  local Importer = require("src.import.RomImporter")
  local Writer = require("src.import.LuaWriter")
  local Gen2Save = require("src.save_convert.Gen2Save")
  local Compat = require("src.save_convert.Compat")
  local MapContext = require("src.save_convert.Gen2MapContext")
  local identity = love.filesystem.getIdentity()
  assert(type(identity) == "string" and identity:match("^bsa1001%-"), "scratch bsa1001 identity required")
  assert(not SaveData.isPortable(), "scratch save-directory cache required")
  assert(GameVersion.get() == "crystal", "Crystal runtime required")
  assert(game.world and game.world.map, "normal Crystal world required")

  local path = os.getenv("POKEPORT_EXPORT_CACHE_REFRESH_ROM")
  if not path then
    local f = assert(io.open("tools/reimport.local", "rb"))
    for line in f:lines() do
      local version, candidate = line:match("^%s*([^#=]+)%s*=%s*(.-)%s*$")
      if version and version:match("^%s*crystal%s*$") then path = candidate break end
    end
    f:close()
  end
  assert(type(path) == "string" and path:sub(1, 1) == "/", "absolute Crystal ROM path required")
  local f = assert(io.open(path, "rb"))
  f:close()
  local prefix = GameVersion.cachePrefix("crystal")
  local function cacheRead(rel)
    local previous = CacheFs.prefix
    CacheFs.prefix = prefix
    local bytes, err = CacheFs.read(rel)
    CacheFs.prefix = previous
    return assert(bytes, err)
  end
  local function cacheWrite(rel, bytes)
    local previous = CacheFs.prefix
    CacheFs.prefix = prefix
    local ok, err = CacheFs.write(rel, bytes)
    CacheFs.prefix = previous
    assert(ok, err)
  end
  local function tableRead(name)
    return assert(loadstring(cacheRead("data/generated/" .. name .. ".lua")))()
  end
  local imp = Importer.new(nil, { launcher = true })
  imp._inputBlocked = true
  assert(imp.ready.crystal, "fresh Crystal cache must be ready before reproduction")
  local constants = tableRead("constants")
  assert(constants.spriteContext and constants.spriteContext.edition == "crystal", "fresh ROM metadata required")
  constants.spriteContext = nil
  cacheWrite("data/generated/constants.lua", Writer.encode(constants))
  cacheWrite(Contract.MARKER_PATH, "rom-cache-v12-crystal4:" .. GameVersion.info("crystal").sha1)
  assert(not Importer.isReady("crystal"), "old cache must fail the current contract")

  local slot = assert(SaveData.createSlot("crystal"))
  assert(SaveData.writeSlot("crystal", slot, {
    version = "crystal", generation = 2, engine = "crystal",
    player = { name = "CHRIS", id = 12345, gender = "male", money = 3000,
      badges = { ZEPHYRBADGE = true, HIVEBADGE = true } },
    position = { map = "CHERRYGROVE_CITY", mapGroup = 26, mapNumber = 3,
      x = 28, y = 11, facing = "down" },
    playerState = "normal", party = {}, events = {}, playTime = { hours = 0, minutes = 52 },
  }))
  assert(SaveData.setActiveSlot("crystal", slot))
  imp:exportSave("crystal")
  local notice = assert(imp.saveNotice.crystal)
  assert(not notice.ok and notice.text:find(
    "this save cannot be exported onto map 26/3: Gen 2 sprite metadata is missing (re-import the ROM)", 1, true),
    "missing metadata did not reproduce the reported export refusal: " .. tostring(notice.text))
  local output = "exports/crystal/gen1recomp-crystal-" .. slot .. ".sav"
  assert(not love.filesystem.getInfo(output), "refused export must not write a cartridge image")
  U.log("PASS old-cache launcher export reproduces map 26/3 missing sprite metadata")

  local previousUpdate, previousDraw = rawget(game, "update"), rawget(game, "draw")
  game.update, game.draw = function() end, function() end
  imp:reimport("crystal")
  assert(not imp.ready.crystal and imp.chooseVersion == "crystal", "public reimport action did not select Crystal")
  imp:startPath(path)
  local deadline = love.timer.getTime() + 24
  for _ = 1, 100000 do
    if imp.workState ~= "working" or love.timer.getTime() >= deadline then break end
    imp:update(1 / 60)
    U.wait(1)
  end
  assert(imp.workState == "complete" and imp.completeVersion == "crystal",
    "actual ROM reimport did not complete: " .. tostring(imp.status) .. " " .. tostring(imp.detail))
  assert(Importer.isReady("crystal"), "regenerated cache does not satisfy the current contract")
  assert(cacheRead(Contract.MARKER_PATH) == Contract.markerFor("crystal", imp.romSha1), "regenerated marker has wrong provenance")
  local regenerated = tableRead("constants")
  assert(regenerated.spriteContext and regenerated.spriteContext.edition == "crystal", "reimport did not generate Crystal sprite metadata")
  U.log("PASS actual SHA-verified ROM extraction regenerated current Crystal metadata")

  imp:exportSave("crystal")
  notice = assert(imp.saveNotice.crystal)
  assert(notice.ok, "same-session export after reimport failed: " .. tostring(notice.text))
  local bytes = assert(love.filesystem.read(output))
  assert(#bytes == Gen2Save.SAVE_SIZE, "export size is not a complete SRAM image")
  assert(Gen2Save.checksumValid(bytes, Gen2Save.layoutFor("crystal")), "export checksum failed")
  assert(#Compat.check(bytes, "crystal").errors == 0, "export failed the cartridge reader gate")
  local data = {}
  for _, name in ipairs({ "pokemon", "moves", "items", "maps", "scripts", "sprites", "constants" }) do
    data[name] = tableRead(name)
  end
  local decoded = assert(Gen2Save.decode(bytes, "crystal", data))
  assert(decoded.position.mapGroup == 26 and decoded.position.mapNumber == 3, "export changed the destination map")
  assert(decoded.player.name == "CHRIS", "export changed the player")
  local teacher
  for id, name in ipairs(regenerated.spriteOrder) do
    if name == "SPRITE_TEACHER" then teacher = id break end
  end
  assert(teacher, "regenerated ROM constants have no teacher sprite")
  local found = false
  local O = MapContext.offsetsFor("crystal")
  for index = 1, 12 do
    if bytes:byte(O.objectStructs + index * MapContext.OBJECT_LENGTH + 1) == teacher then found = true end
  end
  assert(found, "export did not reconstruct the nearby Cherrygrove teacher")
  game.update, game.draw = previousUpdate, previousDraw
  U.log("PASS same-session launcher export after real ROM reimport; SRAM size, checksum, reader, map, player and NPC verified")
  U.log("PASS gen2_export_cache_refresh", identity, notice.text)
  love.event.quit(0)
end
