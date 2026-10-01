package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local cache = { prefix = "sentinel/", bytes = {} }
function cache.read(path)
  local bytes = cache.bytes[cache.prefix .. path]
  if bytes == false then error("unreadable cache") end
  return bytes
end
package.loaded["src.import.CacheFs"] = cache
local SaveConvert = require("src.save_convert.SaveConvert")

for _, version in ipairs({ "red", "blue", "yellow" }) do
  local data, why = SaveConvert.loadData(version)
  eq(data, nil, version .. ": a missing edition cache is refused")
  check(type(why) == "string" and why:lower():find(version, 1, true), version .. ": refusal names the edition")
  eq(cache.prefix, "sentinel/", version .. ": cache prefix is restored")
end

if SaveConvert.setGen1DataStub then
  local stub = { pokemon = {}, moves = {}, items = {}, maps = {}, encounters = {} }
  SaveConvert.setGen1DataStub(stub, "yellow")
  local data = assert(SaveConvert.loadData("yellow"))
  eq(data.maps, stub.maps, "an explicitly selected headless cache supplies its own maps")
  eq(data.gameVersion, "yellow", "the selected cache keeps its edition")
  eq(data.eventFlags, require("src.save_convert.data.event_flags_yellow"), "Yellow uses its own static crosswalk")
  eq(SaveConvert.loadData("blue"), nil, "a Yellow stub cannot satisfy Blue")
  SaveConvert.setGen1DataStub(nil)
  eq(SaveConvert.loadData("yellow"), nil, "clearing the stub clears cached data")
  eq(SaveConvert.gen1DataFromDir("/nonexistent"), nil, "a missing headless directory is refused")
else
  check(false, "headless edition caches can be supplied explicitly")
end

for _, version in ipairs({ "red", "blue", "yellow" }) do
  cache.bytes[version .. "/data/generated/pokemon.lua"] = false
  local ok, data, why = pcall(SaveConvert.loadData, version)
  check(ok and data == nil and type(why) == "string", version .. ": unreadable cache returns a message")
  eq(cache.prefix, "sentinel/", version .. ": failing read restores prefix")
end

do
  local load = loadfile
  local stub = { pokemon = {}, moves = {}, items = {}, maps = {}, encounters = {} }
  loadfile = function(path)
    local name = path:match("/data/generated/(.+)%.lua$")
    if name then return function() return stub[name] end end
    return load(path)
  end
  local K = require("tests.save_compat._codec")
  local first = K.gen1Data("blue")
  SaveConvert.setGen1DataStub(nil)
  local ok, second = pcall(K.gen1Data, "blue")
  check(ok and second.maps == first.maps, "the fixture helper restores its explicit cache after a stub reset")
  loadfile = load
end

T.finish()
