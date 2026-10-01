package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local K = require("tests.save_compat._codec")

require("tests.save_compat._r1").run(T, 3, require("tests.fixtures.save.gen3_build").cases())
T.finish()
