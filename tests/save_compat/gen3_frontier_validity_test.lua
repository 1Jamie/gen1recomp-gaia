package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local H = require("tests.save_compat._gen3_sections")
local G3 = require("tests.fixtures.save.gen3_build")
local B = require("tests.fixtures.save.bytes")
local D = require("src.core.game3.rse.frontier.trainers")
local Rse = require("src.core.game3.rse.init")
local Tower = require("src.core.game3.rse.frontier.tower")

local manifest, random, enemyLevel, var = D.manifest, D.rng, D.enemyLevel, Rse.var
D.manifest = function()
  return { towerPartySizes = { 3, 4, 2, 2 }, apprenticeChallengeThreshold = { 0 } }
end
D.rng = function() return { Random = function() return 0 end } end
D.enemyLevel = function() return 50 end
Rse.var = function(name) return name == "VAR_FRONTIER_FACILITY" and D.FACILITY.TOWER or D.MODE.SINGLES end

local function seal(w, off, size, damaged)
  local sum = 0
  for i = 0, size - 5, 4 do sum = (sum + B.getLE(w.sb2, off + i, 4)) % 4294967296 end
  B.le(w.sb2, off + size - 4, (sum + (damaged and 1 or 0)) % 4294967296, 4)
end

local function cart(damaged, apprentice, emptyName)
  local w = G3.base("emerald")
  B.fill(w.sb2, 0x64C + 236, 5 * 236, 0)
  B.fill(w.sb2, 0xDC, 4 * 68, 0)
  if apprentice then
    local off = 0xDC
    B.put(w.sb2, off, 32, 0)
    local name = G3.text(emptyName and "" or "MAY", 7)
    for i = 1, 7 do w.sb2[off + 55 + i] = name[i] end
    seal(w, off, 68, damaged)
  else
    local off = 0x64C + 236
    local name = G3.text("FRIEND", 8)
    for i = 1, 8 do w.sb2[off + 3 + i] = name[i] end
    for i = 0, 2 do B.le(w.sb2, off + 52 + i * 44, 1, 2); B.put(w.sb2, off + 64 + i * 44, 50) end
    seal(w, off, 236, damaged)
  end
  return H.import("emerald", G3.emit(w))
end

local good = cart(false)
T.check(Tower.chooseSpecialTrainer(good), "a checksum-valid imported Tower record is eligible")
T.eq(good.frontierOpponentA, D.TRAINER_RECORD_MIXING_FRIEND, "the valid record selects its original slot")

local bad = cart(true)
T.eq(bad.frontier.towerRecords[1].checksumValid, false, "the importer reports a damaged Tower record")
T.eq(Tower.chooseSpecialTrainer(bad), false, "the engine excludes an imported damaged Tower record")

for _, emptyName in ipairs({ false, true }) do
  local goodApp = cart(false, true, emptyName)
  T.check(Tower.chooseSpecialTrainer(goodApp), "a checksum-valid imported apprentice is eligible")
  T.eq(goodApp.frontierOpponentA, D.TRAINER_RECORD_MIXING_APPRENTICE, "the valid apprentice selects its original slot")
  local badApp = cart(true, true, emptyName)
  T.eq(badApp.apprentices[1].checksumValid, false, "the importer reports a damaged active apprentice")
  T.eq(Tower.chooseSpecialTrainer(badApp), false, "the engine excludes an imported damaged apprentice")
  T.eq(badApp.apprentices[1].lvlMode, 0, "the engine clears the damaged apprentice before selection")
  T.eq(badApp.apprentices[1].id, 16, "the cleared apprentice restores the original empty ID")
end

D.manifest, D.rng, D.enemyLevel, Rse.var = manifest, random, enemyLevel, var
T.finish()
