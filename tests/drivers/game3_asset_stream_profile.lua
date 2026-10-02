local U = require("tests.drivers.util")
local function stats(v)
  table.sort(v)
  return string.format("n=%d p99=%.3f max=%.3f", #v, v[math.max(1, math.ceil(#v * .99))] or 0, v[#v] or 0)
end
return function(game)
  for _ = 1, 900 do if game.boot then break end U.wait(1) end
  local Native = require("src.core.game3.tileset_native")
  local Ow = require("src.core.game3.ow_sprites")
  local Map = require("src.core.game3.map")
  local family = require("src.core.GameVersion").get()
  local records = {}
  for _, spec in ipairs({ { Native, "get", "pair" }, { Ow, "get", "sprite" }, { Map, "load", "map" } }) do
    local owner, key, label = unpack(spec)
    local fn = owner[key]
    owner[key] = function(...)
      local args = { ... }
      local t = love.timer.getTime()
      local a, b = fn(...)
      local ms = (love.timer.getTime() - t) * 1000
      if ms > 1 then print(string.format("ASSET_STALL %s id=%s ms=%.3f", label, tostring(args[label == "map" and 3 or 1]), ms)) end
      records[label] = records[label] or {}; records[label][#records[label] + 1] = ms
      return a, b
    end
  end
  game:_handleBootAction({ action = "new_game", name = "STREAM", gender = 0 })
  U.wait(60)
  local map = family == "emerald" and "EM_ROUTE111" or "FR_CELADON_CITY"
  Map.load(nil, game, map, { x = 10, y = 10 })
  U.wait(120)
  local pairsToTest = {}
  for pair in pairs(Native._pairs) do pairsToTest[#pairsToTest + 1] = pair end
  table.sort(pairsToTest)
  local spritesToTest = {}
  for gid in pairs(Ow._loaded) do spritesToTest[#spritesToTest + 1] = gid end
  table.sort(spritesToTest)
  local base = Native._cache
  local cold = { read = function(_, rel) if rel:find("/atlas_", 1, true) then return nil end return base:read(rel) end,
    write = function() return true end, exists = function(_, rel) return base:exists(rel) end }
  local savedUpdate, savedDraw = game.update, game.draw
  game.update, game.draw = function() end, function() end
  if os.getenv("ASSET_COLD_WORKER") == "1" and Native.prefetch then
    assert(love.filesystem.getIdentity() == os.getenv("POKEPORT_IDENTITY"), "use a disposable driver identity")
    Native.install(base)
    local Stream = require("src.core.game3.asset_stream")
    for _, pair in ipairs(pairsToTest) do
      local root = require("src.import.gba.extract_island1").NATIVE_ROOT
      local spec = assert(base:assetWorkerSpec(root, "pair", pair))
      assert(not spec.directory, "cold worker benchmark requires a disposable save-dir cache")
      local dir = spec.prefix .. root .. "/" .. pair
      for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
        if file:match("^atlas_.*%.rgba$") then assert(love.filesystem.remove(dir .. "/" .. file)) end
      end
      Native.prefetch(pair)
      local deadline = love.timer.getTime() + 20
      while not Native._stream:decoded(pair) and love.timer.getTime() < deadline do Stream.poll(); U.wait(1) end
      assert(Native._stream:decoded(pair), pair)
      local data = Native._stream.pending[pair].data
      local reference = assert(require("src.core.game3.asset_decode").pair(base, root, pair))
      for i, layer in ipairs(data.layers) do
        assert(layer.data:getString() == reference.layers[i].data:getString(), "worker RGBA mismatch " .. pair)
      end
      print("PASS worker cold RGBA parity " .. pair)
      while not Native._pairs[pair] do Stream.frameComplete(); Stream.update(); U.wait(1) end
    end
  end
  for _, mode in ipairs({ "cold_rgba_cache", "disk_rgba_cache", "decoded", "gpu_warm" }) do
    local v = {}
    if mode ~= "gpu_warm" then Native.install(mode == "cold_rgba_cache" and cold or base) end
    for _, pair in ipairs(pairsToTest) do
      if mode == "decoded" and Native.prefetch then
        Native.prefetch(pair)
        local Stream = require("src.core.game3.asset_stream")
        local deadline = love.timer.getTime() + 20
        while not Native._stream:decoded(pair) and love.timer.getTime() < deadline do Stream.poll(); U.wait(1) end
        assert(Native._stream:decoded(pair), "worker failed to prepare " .. pair)
      end
      local t = love.timer.getTime(); assert(Native.get(pair), pair)
      local ms = (love.timer.getTime() - t) * 1000
      v[#v + 1] = ms
      print(string.format("ASSET_PAIR mode=%s id=%s ms=%.3f", mode, pair, ms))
    end
    print("ASSET_PROFILE " .. mode .. " " .. stats(v))
  end
  local spriteCache = Ow._cache
  for _, mode in ipairs({ "disk_rgba_cache", "decoded", "gpu_warm" }) do
    if mode ~= "gpu_warm" then Ow.install(spriteCache) end
    local v = {}
    for _, gid in ipairs(spritesToTest) do
      if mode == "decoded" and Ow.prefetch then
        Ow.prefetch(gid)
        local Stream = require("src.core.game3.asset_stream")
        local deadline = love.timer.getTime() + 20
        while not Ow._stream:decoded(gid) and love.timer.getTime() < deadline do Stream.poll(); U.wait(1) end
        assert(Ow._stream:decoded(gid), "worker failed to prepare sprite " .. gid)
      end
      local t = love.timer.getTime(); assert(Ow.get(gid), gid)
      local ms = (love.timer.getTime() - t) * 1000
      v[#v + 1] = ms
      print(string.format("ASSET_SPRITE mode=%s id=%s ms=%.3f", mode, gid, ms))
    end
    print("ASSET_PROFILE sprite_" .. mode .. " " .. stats(v))
  end
  game.update, game.draw = savedUpdate, savedDraw
  for label, v in pairs(records) do print("ASSET_PROFILE " .. label .. " " .. stats(v)) end
  print("PASS game3_asset_stream_profile")
  love.event.quit(0)
end
