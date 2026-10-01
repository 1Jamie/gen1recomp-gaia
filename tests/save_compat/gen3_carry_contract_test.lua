package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local K = require("tests.save_compat._codec")
local H = require("tests.save_compat._gen3_sections")
local Diff = require("tests.save_compat._diff")
local Regions = require("src.save_convert.regions.gen3")

local FAMILIES = { frlg = "firered", emerald = "emerald" }
local SB_SIZE = { frlg = { sb1 = 0x3D68, sb2 = 0xF24 }, emerald = { sb1 = 0x3D88, sb2 = 0xF2C } }
local KINDS = { padding = true, absent = true, capability = true, runtime = true, contract = true }
local MAP_RESET = {
  ["sb2.mapView"] = true, ["sb1.mapView"] = true, ["sb1.objectEvents"] = true, ["sb1.questLog"] = true,
}

local function files()
  local list = {}
  local p = io.popen("find src -name '*.lua' -not -path 'src/save_convert/*' -not -path 'src/import/*' -not -path 'src/mods/*'")
  for line in p:lines() do list[#list + 1] = line end
  p:close()
  return list
end

local ENGINE = {}
for _, path in ipairs(files()) do
  local f = io.open(path, "rb")
  if f then
    ENGINE[path] = f:read("*a")
    f:close()
  end
end

local function hits(pattern)
  local out = {}
  for path, text in pairs(ENGINE) do
    if text:find(pattern) then out[#out + 1] = path end
  end
  table.sort(out)
  return out
end

local function readText(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local Capabilities = require("src.core.game3.capabilities")
local Profile = require("src.core.game3.profile")

for fam, version in pairs(FAMILIES) do
  local regions = Regions[fam]
  for _, block in ipairs({ "sb1", "sb2" }) do
    local idx = Diff.index(regions, block)
    local uncovered = {}
    for o = 0, SB_SIZE[fam][block] - 1 do
      local r = idx[o]
      if not r or r.name == block then uncovered[#uncovered + 1] = o end
    end
    check(#uncovered == 0, ("%s %s: every byte has a named region (%d unnamed, first 0x%X)"):format(fam, block, #uncovered,
      uncovered[1] or 0))
  end
end

local carried = {}
for fam in pairs(FAMILIES) do
  for _, r in ipairs(Regions[fam]) do
    if (r.block == "sb1" or r.block == "sb2") and r.tier == "T2" and r.name ~= r.block then
      carried[#carried + 1] = { fam = fam, region = r }
    end
  end
end
check(#carried > 40, "the carried (T2) region list is not empty (" .. #carried .. " rows)")

for _, row in ipairs(carried) do
  local r, fam = row.region, row.fam
  local label = ("%s %s"):format(fam, r.name)
  local proof = r.proof
  check(type(proof) == "table" and KINDS[proof.kind], label .. ": a carried region names its proof")
  if type(proof) == "table" then
    if proof.kind == "absent" then
      check(type(proof.patterns) == "table" and #proof.patterns > 0, label .. ": absence proof lists patterns")
      for _, pat in ipairs(proof.patterns or {}) do
        local found = hits(pat)
        check(#found == 0, ("%s: no engine file matches %q (%s)"):format(label, pat, table.concat(found, ", ")))
      end
    elseif proof.kind == "capability" then
      local set = Capabilities[proof.set]
      check(type(set) == "table" and Capabilities.NAMES[proof.name], label .. ": " .. proof.name .. " is a known capability")
      check(set and set[proof.name] ~= true, ("%s: the %s profile has no %s capability"):format(label, proof.set, proof.name))
    elseif proof.kind == "runtime" then
      local schema = readText("src/core/game3/save_schema_firered.lua")
      for _, pat in ipairs(proof.patterns or {}) do
        check(not schema:find(pat), ("%s: %q is not in the persisted save table"):format(label, pat))
      end
      local sections = Profile.of(version).save.sections or {}
      local listed = false
      for _, entry in ipairs(sections) do
        local name = type(entry) == "table" and entry.name or entry
        for _, pat in ipairs(proof.patterns or {}) do
          if tostring(name):lower():find(pat:lower(), 1, true) then listed = true end
        end
      end
      check(not listed, label .. ": no persisted save section carries it")
    elseif proof.kind == "contract" then
      check(readText(proof.test) ~= nil, label .. ": the contract test " .. proof.test .. " exists")
    end
  end
end

local function region(bytes, v, r)
  return H.blocks(bytes, v)[r.block]:sub(r.offset + 1, r.offset + r.size)
end

for fam, version in pairs(FAMILIES) do
  local versions = fam == "frlg" and { "firered", "leafgreen" } or { "emerald" }
  for _, v in ipairs(versions) do
    local list = {}
    for _, row in ipairs(carried) do
      if row.fam == fam and row.region.proof.kind ~= "contract" then list[#list + 1] = row.region end
    end
    for seed = 1, 12 do
      local rng = H.rng(seed * 101)
      local cart = H.cart(v, function(w)
        for _, r in ipairs(list) do H.randomize(w, r.block, r.offset, r.size, rng) end
      end)
      local save = H.import(v, cart)
      local out = H.withTemplate(v, save, cart)
      local kept = true
      local lost = {}
      for _, r in ipairs(list) do
        if region(out, v, r) ~= region(cart, v, r) then
          kept = false
          lost[#lost + 1] = r.name
        end
      end
      check(kept, ("%s seed %d: every carried region survives the template round trip (%s)"):format(v, seed,
        table.concat(lost, ",")))
    end
    local fresh = H.fresh(v, H.import(v, H.cart(v)))
    local nonzero = {}
    for _, r in ipairs(list) do
      if region(fresh, v, r) ~= string.rep("\0", r.size) then nonzero[#nonzero + 1] = r.name end
    end
    check(#nonzero == 0, ("%s: a templateless export writes zeros into every carried region (%s)"):format(v,
      table.concat(nonzero, ",")))
  end
end

T.finish()
