package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local G2 = require("tests.fixtures.save.gen2_build")
local B = require("tests.fixtures.save.bytes")
local K = require("tests.save_compat._codec")
local Codec = require("src.save_convert.Gen2Save")
local Events = require("src.world.gen2.Events")

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local image = G2.build({ version = version, patch = function(bytes, layout)
    B.put(bytes, layout.wEventFlags + 100, 8)
  end })
  local save = assert(Codec.decode(image, version, K.gen2Data))
  local events = Events.new():restore(save.events)
  events:set(803, false)
  save.events = events:serialize()
  T.eq(save.events[100], nil, version .. " engine drops cleared event bytes")
  local out = assert(Codec.encode(save, version, image, K.gen2Data))
  T.eq(out:byte(G2.layout(version).wEventFlags + 101), 0, version .. " export clears omitted event bytes")
  local decoded = assert(Codec.decode(out, version, K.gen2Data))
  T.eq(decoded.events[100], 0, version .. " cleared events survive reimport")
end

T.finish()
