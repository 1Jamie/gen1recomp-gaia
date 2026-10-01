love = love or require("tests.love_stub")

local SaveConvert = require("src.save_convert.SaveConvert")
local Gen2Save = require("src.save_convert.Gen2Save")
local Gen3Save = require("src.save_convert.Gen3Save")
local Gen3Layout = require("src.save_convert.Gen3Layout")
local Compat = require("src.save_convert.Compat")
local Diff = require("tests.save_compat._diff")
local G2 = require("tests.fixtures.save.gen2_build")

local K = {}

function K.gen1Available()
  return loadfile("data/generated/pokemon.lua") ~= nil
end

local stamped = {}
local supplied = {}
function K.gen1Data(version)
  if not supplied[version] then
    local dir = os.getenv("GEN1_" .. version:upper() .. "_CACHE") or os.getenv(version:upper() .. "_CACHE")
      or (os.getenv("HOME") .. "/Library/Application Support/LOVE/pokemon-love2d/" .. version)
    local generated = SaveConvert.gen1DataFromDir(dir)
    if not generated and version == "red" then generated = SaveConvert.gen1DataFromDir(".") end
    assert(generated, "missing " .. version .. " fixture cache; set " .. version:upper() .. "_CACHE")
    SaveConvert.setGen1DataStub(generated, version)
    supplied[version] = generated
  end
  local data = SaveConvert.loadData(version)
  if not data then
    SaveConvert.setGen1DataStub(supplied[version], version)
    data = assert(SaveConvert.loadData(version))
  end
  if not stamped[data] then
    local stamp = loadfile("tests/fixture_data/map_window.lua")()
    for mapId in pairs(data.maps) do stamp(data, mapId) end
    stamped[data] = true
  end
  return data
end

K.GEN2_MAP = "SAVE_COMPAT_FIXTURE_MAP"
K.gen2Data = {
  items = G2.ITEMS,
  maps = { [K.GEN2_MAP] = { group = 24, map = 7, objectEventsAddr = 0x5A17, width = 2, height = 2,
                            blocks = { 1, 2, 3, 4 }, objects = {} } },
}

function K.gen3Opts(version, template)
  if version == "emerald" then
    return { template = template, version = "emerald", metGame = 3,
      toNational = function() return nil end, itemId = function(id) return tonumber(id) end,
      mapLayoutId = function(g, n) return ({ ["25:40"] = 237 })[g .. ":" .. n] end,
      healWarp = function() return { group = 0, num = 9, warpId = -1, x = 5, y = 8 } end }
  end
  return {
    template = template, version = version,
    metGame = version == "leafgreen" and Gen3Layout.VERSION_LEAF_GREEN or Gen3Layout.VERSION_FIRE_RED,
    toNational = function(sp) return sp >= 1 and sp <= 251 and sp or nil end,
    speciesFromNational = function(n) return n end,
    mapLayoutId = function(g, n) return ({ ["4:1"] = 2 })[g .. ":" .. n] end,
    healWarp = function() return { group = 3, num = 0, warpId = -1, x = 6, y = 8 } end,
  }
end

function K.import(gen, version, bytes)
  if gen == 1 then
    K.gen1Data(version)
    return SaveConvert.importSav(bytes, version, version)
  elseif gen == 2 then
    return Gen2Save.decode(bytes, version, K.gen2Data)
  end
  return SaveConvert.importSav(bytes, version, version)
end

function K.export(gen, version, save, template)
  local ok, out, err
  if gen == 1 then
    K.gen1Data(version)
    if template == false then save.rawImport = nil end
    ok, out, err = pcall(SaveConvert.exportSav, save, version)
  elseif gen == 2 then
    ok, out, err = pcall(Gen2Save.encode, save, version, template or nil, K.gen2Data)
  else
    if template == false and type(save.modData) == "table" then save.modData.cartImage = nil end
    ok, out, err = pcall(Gen3Save.forVersion(version).exportPort, save, K.gen3Opts(version, template or nil))
  end
  if not ok then return nil, "raised: " .. tostring(out) end
  return out, err
end

local function family(version) return version == "emerald" and "emerald" or "frlg" end

local function patch(s, off, src)
  return s:sub(1, off) .. src .. s:sub(off + #src + 1)
end

K.N = {
  { id = "N1", gen = 1, why = "bank 2/3 box checksums are recomputed; derived regions are not diffed" },
  { id = "N3", gen = 3, why = "Gen 3 is compared on reassembled sections; slot, rotation and counter change by design" },
  { id = "N5", gen = 1, why = "party box-level byte is rewritten with the party level (G1-21)" },
  { id = "N6", gen = 2, why = "a primary sum whose low byte is 0 is nudged through the pad byte after GREEN, which OpenHome rejects otherwise" },
}

function K.r1Diff(gen, version, src, out)
  if gen == 1 then
    local count = src:byte(0x2F2C + 1)
    if count <= 6 then
      for i = 0, count - 1 do
        local at = 0x2F2C + 8 + i * 44 + 3
        out = patch(out, at, src:sub(at + 1, at + 1))
      end
    end
    return Diff.diff(src, out, Diff.regionsFor(1, version))
  elseif gen == 2 then
    return Diff.diff(src, out, Diff.regionsFor(2, version))
  end
  local regions = Diff.regionsFor(3, version)
  local fam = family(version)
  local a, b = Compat.gen3Blocks(src, fam), Compat.gen3Blocks(out, fam)
  if not (a and b) then return { { name = "sections", count = 1, first = 0, last = 0, sample = {} } } end
  local entries = {}
  for _, blk in ipairs({ "sb2", "sb1", "storage" }) do
    for _, e in ipairs(Diff.diff(a[blk], b[blk], regions, { block = blk })) do entries[#entries + 1] = e end
  end
  for _, e in ipairs(Diff.diff(src:sub(0x1C001, 0x20000), out:sub(0x1C001, 0x20000), regions,
      { block = "flash", base = 0x1C000 })) do
    entries[#entries + 1] = e
  end
  if #src ~= #out then
    entries[#entries + 1] = { name = "trailer", count = math.abs(#src - #out), first = 0x20000, last = 0x20000,
      sample = { ("%d>%d bytes"):format(#src, #out) } }
  end
  return entries
end

function K.compatKeys(bytes, version)
  local report = Compat.check(bytes, version)
  local keys = {}
  local seen = {}
  for _, e in ipairs(report.errors) do
    if not seen[e.rule] then
      seen[e.rule] = true
      keys[#keys + 1] = { key = "compat:" .. e.rule, detail = e.msg }
    end
  end
  return keys, report
end

return K
