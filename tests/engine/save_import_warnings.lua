package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

local K = require("tests.save_compat._codec")
local SaveConvert = require("src.save_convert.SaveConvert")

SaveConvert.setGen2DataStub(K.gen2Data)

local noted, quiet = {}, 0
for _, gen in ipairs({ 1, 2, 3 }) do
  if gen == 1 and not K.gen1Available() then
    print("[skip] gen1 fixtures need data/generated/")
  else
    for _, c in ipairs(require("tests.fixtures.save.gen" .. gen .. "_build").cases()) do
      if not c.refuse then
        if gen == 1 then K.gen1Data(c.version) end
        local save, err, note = SaveConvert.importSav(c.bytes, c.version, c.version)
        if save then
          check(note == nil or type(note) == "string" and note ~= "", c.id .. ": the note is a non-empty string or nil")
          check(save.warnings == nil, c.id .. ": warnings never ride into the slot")
          if note then noted[c.id] = note else quiet = quiet + 1 end
        else
          check(type(err) == "string", c.id .. ": a refusal carries a message")
        end
      end
    end
  end
end

check(noted["g2.crystal.corrupt_primary"] ~= nil
  and noted["g2.crystal.corrupt_primary"]:find("backup", 1, true) ~= nil,
  "the Crystal backup copy being used is reported")

local B = require("tests.fixtures.save.bytes")
local G2 = require("tests.fixtures.save.gen2_build")
for _, v in ipairs({ "gold", "silver", "crystal" }) do
  local L = G2.layout(v)
  local base = G2.build({ version = v, boxes = { [1] = G2.boxOf(5, 3) }, currentBox = 0 })
  local _, _, healthy = SaveConvert.importSav(base, v, v)
  check(healthy == nil, v .. ": a healthy cart has no note")

  local b = B.fromString(base)
  b[L.sGameData + 20] = (b[L.sGameData + 20] + 1) % 256
  local save, err, note = SaveConvert.importSav(B.pack(b), v, v)
  check(save ~= nil and note ~= nil and note:find("backup", 1, true) ~= nil,
    v .. ": a corrupt primary imports from the backup and says so -- " .. tostring(err or note))

  b = B.fromString(base)
  b[L.sBox + 40] = (b[L.sBox + 40] + 1) % 256
  G2.seal(b, v)
  save, err, note = SaveConvert.importSav(B.pack(b), v, v)
  check(save ~= nil and note ~= nil and note:find("active box", 1, true) ~= nil,
    v .. ": a stale active box is reported -- " .. tostring(err or note))
end

for id, note in pairs(noted) do
  check(note:find("[%.!?]$") ~= nil, id .. ": the note is a finished sentence -- " .. note)
end
check(quiet > 0, "healthy fixtures import without a note")

SaveConvert.setGen2DataStub(nil)
T.finish()
