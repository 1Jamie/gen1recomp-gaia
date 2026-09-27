package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local VersionsGame = require("src.import.gba.versions_game")
local Versions = require("src.import.gba.versions")
local Frlg = require("src.import.gba.versions_frlg")

local prevVersion = GameVersion.get()

VersionsGame.reset()
GameVersion.set("firered")

check(VersionsGame.game("firered") == Frlg,
  "firered resolves the FRLG table")
check(VersionsGame.game("leafgreen") == Frlg,
  "leafgreen shares the FireRed tables")
check(VersionsGame.game(nil) == Frlg,
  "nil resolves the active game's table")
check(VersionsGame.game("") == Frlg, "an empty id resolves the active game")
check(not pcall(VersionsGame.game, "ruby"),
  "an unregistered id raises instead of reading FireRed offsets")

VersionsGame.reset()
GameVersion.set("red")
check(VersionsGame.game(nil) == Frlg,
  "a non-Gen3 process resolves nil to FireRed's table")

VersionsGame.reset()
GameVersion.set("firered")
local tables = VersionsGame.game("firered")
check(type(tables.MAPS) == "table", "MAPS is a table")
check(type(tables.WARPS) == "table", "WARPS is a table")
check(type(tables.TILESETS) == "table", "TILESETS is a table")
check(type(tables.PAIR_TILESET) == "table", "PAIR_TILESET is a table")
check(type(tables.NUM_SPECIES) == "number", "NUM_SPECIES is a number")
check(type(tables.CACHE_VERSION) == "number", "CACHE_VERSION is a number")
eq(tables.NUM_SPECIES, 412,
  "NUM_SPECIES is 412 (pret: pokefirered/include/constants/species.h:421-423)")

local probe = { MAPS = {}, NUM_SPECIES = 1 }
package.loaded["tests.versions_game_probe"] = probe
check(VersionsGame.register("testgame", "tests.versions_game_probe") == true,
  "register accepts an id + module path")
check(VersionsGame.game("testgame") == probe, "a registered row resolves its module")
check(VersionsGame.register("", "tests.versions_game_probe") == false,
  "register rejects an empty id")
check(VersionsGame.register("testgame", 7) == false, "register rejects a non-string path")

check(VersionsGame.register("busted", "no.such.module") == true, "register a broken row")
check(not pcall(VersionsGame.game, "busted"), "a broken row raises")

VersionsGame.reset()
check(VersionsGame.game("testgame") == probe, "registrations survive reset")
check(VersionsGame.game("firered") == Frlg, "resolutions re-resolve after reset")
check(Versions.forGame("firered") == Frlg, "the facade hands out the FRLG table")
check(Versions.active() == "firered", "the facade defaults to firered")
check(Versions.NUM_SPECIES == Frlg.NUM_SPECIES, "the facade forwards reads")
check(not pcall(Versions.select, "0000000000000000000000000000000000000000"),
  "an unknown sha1 raises")
check(not pcall(Versions.select, "red"), "a non gen 3 id raises")
eq(Versions.active(), "firered", "a failed select leaves the active game")

VersionsGame.GAMES["testgame"] = nil
VersionsGame.GAMES["busted"] = nil
package.loaded["tests.versions_game_probe"] = nil
VersionsGame.reset()

GameVersion.set(prevVersion)
T.finish("game3_versions_game_test")
