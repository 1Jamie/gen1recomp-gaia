package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
local K = require("tests.save_compat._codec")

if not K.gen1Available() then
  print("gen1_mutation skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

local GenSave = require("src.save_convert.GenSave")
local SaveConvert = require("src.save_convert.SaveConvert")
local G1 = require("tests.fixtures.save.gen1_build")
local Diff = require("tests.save_compat._diff")
local Regions = require("src.save_convert.regions.gen1")

local O = GenSave.OFFSETS
local MUTATIONS = tonumber(os.getenv("GEN1_MUTATIONS")) or 1500

local function lcg(seed)
  local state = seed
  return function(n)
    state = (state * 1664525 + 1013904223) % 4294967296
    return math.floor(state / 4294967296 * n)
  end
end

local function reseal(bytes)
  local sum = 0
  for i = O.checksumStart + 1, O.checksumEnd do sum = (sum + bytes:byte(i)) % 256 end
  bytes = bytes:sub(1, O.mainChecksum) .. string.char(255 - sum) .. bytes:sub(O.mainChecksum + 2)
  return bytes
end

local regions = Regions.layouts.default
local idx = Diff.index(regions)
local base
do
  local cases = G1.cases()
  for _, c in ipairs(cases) do
    if c.id == "g1.red.full_boxes" then base = c.bytes end
  end
end
assert(base)

local darkMapIndexes = {}
do
  local data = K.gen1Data("red")
  local cw = GenSave.crosswalks(data)
  for _, id in ipairs(data.field.darkMaps.maps) do darkMapIndexes[#darkMapIndexes + 1] = cw.mapsIndex[id] end
end

local function invalidInput(bytes)
  local function listBad(countAt, rowsAt, cap)
    local n = 0
    while n < cap and bytes:byte(rowsAt + n * 2 + 1) ~= 0xFF do n = n + 1 end
    return bytes:byte(countAt + 1) ~= n
  end
  if listBad(0x25C9, 0x25CA, 20) or listBad(0x27E6, 0x27E7, 50) then return true end
  if bytes:byte(0x2F2C + 1) > 6 or bytes:byte(0x30C0 + 1) > 20 then return true end
  for b = 0, 11 do
    local base = b < 6 and (0x4000 + b * 0x462) or (0x6000 + (b - 6) * 0x462)
    if bytes:byte(base + 1) > 20 then return true end
  end
  for _, at in ipairs({ 0x25F3, 0x25F4, 0x25F5, 0x2850, 0x2851 }) do
    local b = bytes:byte(at + 1)
    if b % 16 > 9 or math.floor(b / 16) > 9 then return true end
  end
  local darkMap = false
  for _, id in ipairs(darkMapIndexes) do if bytes:byte(0x260A + 1) == id then darkMap = true end end
  if not darkMap and bytes:byte(0x2609 + 1) ~= 0 then return true end
  for _, at in ipairs({ 0x2CEF, 0x2CF0, 0x2CF1 }) do
    if bytes:byte(at + 1) > 59 then return true end
  end
  return false
end

local rand = lcg(20260930)
local raised, nilResult, identical, differing, normalized = 0, 0, 0, 0, 0
local byRegion = {}
for n = 1, MUTATIONS do
  local at = rand(0x7A53)
  local region = idx[at]
  if region and not region.derived and at ~= O.mainChecksum then
    local mutated = base:sub(1, at) .. string.char((base:byte(at + 1) + 1 + rand(255)) % 256) .. base:sub(at + 2)
    mutated = reseal(mutated)
    local ok, save, err = pcall(SaveConvert.importSav, mutated, "red", "red")
    if not ok then
      raised = raised + 1
      check(false, ("mutation at 0x%X (%s): import raised %s"):format(at, region.name, tostring(save)))
    elseif not save then
      nilResult = nilResult + 1
    else
      local ok2, out, xerr = pcall(SaveConvert.exportSav, save, "red")
      if not ok2 then
        raised = raised + 1
        check(false, ("mutation at 0x%X (%s): export raised %s"):format(at, region.name, tostring(out)))
      elseif not out then
        nilResult = nilResult + 1
      else
        local diff = Diff.diff(mutated, out, regions)
        local meaningful = {}
        local terminators = {}
        terminators[O.partyData + 1 + math.min(mutated:byte(O.partyData + 1), 6)] = true
        terminators[O.curBoxData + 1 + math.min(mutated:byte(O.curBoxData + 1), 20)] = true
        for b = 0, 11 do
          local base = b < 6 and (0x4000 + b * 0x462) or (0x6000 + (b - 6) * 0x462)
          terminators[base + 1 + math.min(mutated:byte(base + 1), 20)] = true
        end
        for _, e in ipairs(diff) do
          local atTerminator = e.name:match("%.species$") and e.count == 1 and terminators[e.first]
          if e.name ~= "identityTag" and not atTerminator then
            meaningful[#meaningful + 1] = e
          end
        end
        if #meaningful > 0 and invalidInput(mutated) then
          normalized = normalized + 1
          meaningful = {}
        end
        if #meaningful == 0 then
          identical = identical + 1
        else
          differing = differing + 1
          byRegion[region.name] = byRegion[region.name] or { count = 0, sample = Diff.format(meaningful, 2) }
          byRegion[region.name].count = byRegion[region.name].count + 1
        end
      end
    end
  end
end

local names = {}
for name in pairs(byRegion) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  print(("  mutation sink %s x%d: %s"):format(name, byRegion[name].count, byRegion[name].sample))
end
print(("gen1_mutation: %d identical, %d normalized invalid inputs, %d differing, %d refused, %d raised"):format(
  identical, normalized, differing, nilResult, raised))
eq(raised, 0, "no mutation makes the importer or exporter raise")
eq(differing, 0, "every accepted single-byte mutation reproduces byte for byte")

T.finish()
