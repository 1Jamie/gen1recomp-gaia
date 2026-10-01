package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local K = require("tests.save_compat._codec")

if not K.gen1Available() then
  print("r1_gen1 skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

require("tests.save_compat._r1").run(T, 1, require("tests.fixtures.save.gen1_build").cases())
T.finish()
