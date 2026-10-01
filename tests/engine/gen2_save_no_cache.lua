package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local SaveConvert = require("src.save_convert.SaveConvert")
local G2 = require("tests.fixtures.save.gen2_build")

local stub = {
  pokemon = {}, moves = {}, items = G2.ITEMS,
  maps = { PLAYERS_HOUSE_2F = { group = 24, map = 7, objectEventsAddr = 0x5CF0, width = 2, height = 2,
                                blocks = { 1, 2, 3, 4 }, objects = {} } },
}

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local cart = G2.build({ version = version })
  SaveConvert.setGen2DataStub(nil)
  local save, why = SaveConvert.importSav(cart, version, version)
  eq(save, nil, version .. ": import without a Gen 2 cache is refused")
  check(type(why) == "string" and why:find("data cache is missing", 1, true) ~= nil,
    version .. ": and the refusal names the missing cache -- " .. tostring(why))
  local out, xwhy = SaveConvert.exportSav({ meta = {}, position = { map = "PLAYERS_HOUSE_2F", x = 1, y = 1 } }, version)
  eq(out, nil, version .. ": export without a Gen 2 cache is refused")
  check(type(xwhy) == "string" and xwhy:find("data cache is missing", 1, true) ~= nil,
    version .. ": and says why -- " .. tostring(xwhy))

  SaveConvert.setGen2DataStub(stub)
  local imported = SaveConvert.importSav(cart, version, version)
  check(imported ~= nil, version .. ": an injected stub is the only fallback")
  SaveConvert.setGen2DataStub(nil)
end

local envCaches = { gold = "GOLD_CACHE", silver = "SILVER_CACHE", crystal = "CRYSTAL_CACHE" }
for version, env in pairs(envCaches) do
  local dir = os.getenv(env)
  if dir and dir ~= "" then
    local data = SaveConvert.gen2DataFromDir(dir)
    check(data ~= nil and data.maps ~= nil, version .. ": " .. env .. " loads the four Gen 2 tables")
    SaveConvert.setGen2DataStub(data)
    local imported = SaveConvert.importSav(G2.build({ version = version }), version, version)
    check(imported ~= nil, version .. ": a real cache imports a synthetic cart")
    SaveConvert.setGen2DataStub(nil)
  else
    print(("[skip] %s not set"):format(env))
  end
end
check(SaveConvert.gen2DataFromDir("/nonexistent") == nil, "a missing cache directory loads nothing")

T.finish()
