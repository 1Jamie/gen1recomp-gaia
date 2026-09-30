package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Plans = require("src.import.gba.plans.registry")
local Extract = require("src.import.gba.move_relearner_rse_extract")
local Rse = require("src.ui.game3.rse.move_relearner")
local ui = require("src.core.game3.profiles.emerald.ui")

local required = {}
for _, p in ipairs(Plans.required(Plans.of("emerald"), "data/generated/gba")) do required[p] = true end
check(required["data/generated/gba/rse/move_relearner/hearts.png"], "emerald plan requires the relearner hearts")
check(required["data/generated/gba/rse/move_relearner/manifest.lua"], "emerald plan requires the relearner manifest")
local frRequired = {}
for _, p in ipairs(Plans.required(Plans.of("firered"), "data/generated/gba")) do frRequired[p] = true end
check(not frRequired["data/generated/gba/rse/move_relearner/hearts.png"], "firered plan does not pull the Emerald relearner")

local aliases = ui.textAliases
eq(aliases.gText_MonIsTryingToLearnMove, "gText_MoveRelearnerPkmnTryingToLearnMove", "trying-to-learn alias")
eq(aliases.gText_WhichMoveShouldBeForgotten, "gText_MoveRelearnerWhichMoveToForget", "which-move alias")
eq(aliases.gText_MonForgotOldMoveAndMonLearnedNewMove, "gText_MoveRelearnerPkmnForgotMoveAndLearnedNew", "forgot alias")

local a, j = Rse.heartCounts({ appeal = 40, jam = 30 })
eq(a, 4, "appeal 40 -> 4 hearts")
eq(j, 3, "jam 30 -> 3 hearts")
a, j = Rse.heartCounts({ appeal = 0xFF, jam = 0xFF })
eq(a, 0, "appeal 0xFF -> 0 hearts")
eq(j, 0, "jam 0xFF -> 0 hearts")
eq(Rse.WIN.list.left, 19, "move list window left")
eq(Rse.WIN.msg.width, 22, "message window width")

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
local data = f and f:read("*a")
if f then f:close() end
if data and data:sub(0xAD, 0xB0) == "BPEE" then
  local GV = require("src.core.GameVersion")
  local Versions = require("src.import.gba.versions")
  local Rom = require("src.import.gba.rom")
  local K = require("src.import.gba.rse.boot_gfx")
  GV.set("emerald")
  Versions.select("emerald")
  local sha = GV.VERSIONS.emerald.sha1
  local rom = assert(Rom.open({
    info = function() return { size = #data, md5 = sha } end,
    read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
  }, GV.forSha1(sha)))
  local files = {}
  local cache = {
    write = function(_, rel, bytes) files[rel] = bytes; return true end,
    read = function(_, rel) return files[rel] end,
  }
  local ok, m = Extract.run(rom, cache, { game = "emerald" })
  check(ok and m and m.hearts, "extractor ran")
  local w, h = K.pngSize(files["data/generated/gba/rse/move_relearner/hearts.png"])
  eq(w, 8, "hearts sheet width")
  eq(h, 32, "hearts sheet height")
  eq(m.hearts.names.jamFull, 3, "jam full frame")
  check(Extract.ready(cache), "extractor ready after run")
else
  print("emerald_move_relearner_test: ROM extract checks skipped (no Emerald ROM at " .. ROM_PATH .. ")")
end

T.finish()
