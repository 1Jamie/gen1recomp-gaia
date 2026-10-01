package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local H = require("tests.save_compat._gen3_sections")
local G3 = require("tests.fixtures.save.gen3_build")
local B = require("tests.fixtures.save.bytes")
local Tv = require("src.core.game3.rse.tv")

local BASE = 0x27CC
local function sum(w)
  local total = 0
  for i = 0, 255 do total = total + w.sb1[BASE + i] end
  return total % 256
end

local w = G3.base("emerald")
B.fill(w.sb1, BASE, 900, 0)
B.put(w.sb1, BASE, 4, 0)
B.le(w.sb1, BASE + 2, 123, 2)
B.le(w.sb1, BASE + 4, 234, 2)
B.le(w.sb1, BASE + 6, 25, 2)
B.put(w.sb1, BASE + 8, 0xAB)
local bytes = G3.emit(w)
local save = H.import("emerald", bytes)
T.eq(Tv.mixExport(save).tvShowByteSum, sum(w), "an unchanged imported TV packet preserves modeled fields and padding")

save.tvShows[0].species = 26
B.le(w.sb1, BASE + 6, 26, 2)
T.eq(Tv.mixExport(save).tvShowByteSum, sum(w), "record mixing sums changed TV state instead of the import snapshot")

save.tvShows[0].active = true
T.eq(Tv.mixExport(save).tvShowByteSum, sum(w), "the normal-show active byte is excluded before record mixing")
T.eq(save.tvShows[0].active, true, "packet serialization leaves the caller's TV state intact")

save.tvShows[0] = { kind = 0, active = false }
B.fill(w.sb1, BASE, 36, 0)
T.eq(Tv.mixExport(save).tvShowByteSum, sum(w), "a deleted show cannot leave stale bytes in the mail randomizer")

save.tvShows[5] = { kind = 21, active = true, language = 2, language2 = 2, nickname = "ACORN", ball = 4,
  species = 273, nBallsUsed = 3, playerName = "MAY" }
local off = BASE + 5 * 36
B.put(w.sb1, off, 21, 1, 2, 2)
local nick, player = G3.text("ACORN", 11), G3.text("MAY", 8)
for i = 1, 11 do w.sb1[off + 3 + i] = i > 6 and 0 or nick[i] end
for i = 1, 8 do w.sb1[off + 18 + i] = i > 4 and 0 or player[i] end
B.put(w.sb1, off + 15, 4)
B.le(w.sb1, off + 16, 273, 2)
B.put(w.sb1, off + 18, 3)
T.eq(Tv.mixExport(save).tvShowByteSum, sum(w), "new shows contribute their current cartridge bytes")

save.modData.cartImage = nil
save.modData.cartImport.recordMixTvBytes256 = nil
T.eq(Tv.mixExport(save).tvShowByteSum, sum(w), "a native session computes a TV packet sum without an import snapshot")

T.finish()
