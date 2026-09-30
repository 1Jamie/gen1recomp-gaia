package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

local NativePack = require("src.import.gba.native_pack")
local Palette = require("src.core.game3.palette")

do
  local pixels = {}
  for i = 1, 512 do pixels[i] = (i * 7) % 256 end
  local blob = NativePack.encodeIdx({
    midCount = 2, atlasCols = 16, atlasRows = 1, midIds = { 0, 5 }, pixels = pixels,
  })
  local t = NativePack.decodeIdx(blob)
  check(rawget(t, "pixels") == nil, "decodeIdx leaves pixels undecoded")
  check(t.midCount == 2 and t.midIds[2] == 5, "header and midIds decode eagerly")
  local px = t.pixels
  check(#px == 512 and px[1] == pixels[1] and px[512] == pixels[512], "pixels decode on first access")
  check(rawget(t, "pixels") == px and t.pixels == px, "pixels decode once")
  local rgb = {}
  for p = 0, 15 do
    rgb[p] = {}
    for c = 0, 15 do rgb[p][c] = { p * 10, c * 10, 3 } end
  end
  local rgba, w, h = NativePack.bakeRgba(NativePack.decodeIdx(blob), rgb, {})
  check(#rgba == w * h * 4, "bakeRgba works on a lazy table")
end

do
  check(Palette._md5hex("") == "d41d8cd98f00b204e9800998ecf8427e", "md5 empty vector")
  check(Palette._md5hex("The quick brown fox jumps over the lazy dog") == "9e107d9d372bb6826bd81d3542a419d6",
    "md5 fox vector")
  local bgr = {}
  for p = 0, 15 do
    bgr[p] = {}
    for c = 0, 15 do bgr[p][c] = (p * 977 + c * 31) % 32768 end
  end
  local chunks = {}
  for i = 1, 4099 do chunks[i] = string.char((i * 13 + i % 7) % 256) end
  local extra = table.concat(chunks)
  local key = Palette.hash(bgr, extra)
  check(key:match("^%x+$") and #key == 16, "Palette.hash is 16 hex chars")
  check(Palette.hash(bgr, extra) == key, "Palette.hash is deterministic")
  local tweaked = extra:sub(1, 2000) .. "\255" .. extra:sub(2002)
  check(Palette.hash(bgr, tweaked) ~= key, "one byte of extra changes the key")
  bgr[3][4] = (bgr[3][4] + 1) % 32768
  check(Palette.hash(bgr, extra) ~= key, "one palette color changes the key")
  bgr[3][4] = (bgr[3][4] - 1) % 32768
  check(Palette.hash(bgr, extra) == key, "restoring the color restores the key")
  local savedLove = love
  love = { data = {
    hash = function(_, s) return (Palette._md5hex(s):gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)) end,
    encode = function(_, _, s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end,
  } }
  check(Palette.hash(bgr, extra) == key, "love.data path yields the same key as the fallback")
  love = savedLove
end

do
  local loads = {}
  local Native = { _pairs = {} }
  function Native.ready() return true end
  function Native.get(pair) loads[#loads + 1] = pair; Native._pairs[pair] = {}; return {} end
  package.loaded["src.core.game3.tileset_native"] = Native
  package.loaded["src.core.game3.player"] = { cellX = 10, cellY = 10 }
  local Map = require("src.core.game3.map")
  local function def(pair, w, h) return { pair = pair, midLayout = { pair = pair, width = w, height = h } } end
  Map.computeWorld = function()
    return {
      { id = "NEAR", def = def("pnear", 20, 20), ox = 20, oy = 0 },
      { id = "FAR", def = def("pfar", 20, 20), ox = 400, oy = 400 },
    }
  end
  Map.ensureMidLayout = function() end
  Map._warmPairs = nil
  Map._worldRoot = nil
  Map.refreshWorld({ data = { maps = {} } }, 10, 10, "ROOT")
  check(#Map._warmQueue == 2, "both pairs queued")
  Map.stepWarm()
  check(#loads == 1 and loads[1] == "pnear", "near pair loads first")
  Map.stepWarm()
  check(#loads == 1 and Map._warmQueue and #Map._warmQueue == 1, "far pair is not loaded")
  package.loaded["src.core.game3.player"].cellX = 400
  package.loaded["src.core.game3.player"].cellY = 400
  Map.stepWarm()
  check(#loads == 2 and loads[2] == "pfar" and Map._warmQueue == nil, "far pair loads once in range")

  Native._pairs = {}
  loads = {}
  package.loaded["src.core.game3.player"].cellX = 10
  package.loaded["src.core.game3.player"].cellY = 10
  Map._warmPairs = true
  Map._worldRoot = nil
  Map.refreshWorld({ data = { maps = {} } }, 10, 10, "ROOT")
  check(#loads == 1 and loads[1] == "pnear" and Map._warmQueue and #Map._warmQueue == 1,
    "warp preload only loads near pairs synchronously")

  love = { timer = { getDelta = function() return 0.2 end } }
  Map._warmDefer = 0
  loads = {}
  Native._pairs = {}
  Map._warmQueue = { "pnear" }
  Map._warmEntries = {}
  Map.stepWarm()
  check(#loads == 0, "slow frame defers the load")
  Map.stepWarm()
  Map.stepWarm()
  Map.stepWarm()
  check(#loads == 1, "deferral is bounded")
  love = nil
  package.loaded["src.core.game3.tileset_native"] = nil
  package.loaded["src.core.game3.player"] = nil
end

print(failures == 0 and "PASS game3_seam_warm_budget_test"
  or ("FAIL game3_seam_warm_budget_test failures=" .. failures))
os.exit(failures == 0 and 0 or 1)
