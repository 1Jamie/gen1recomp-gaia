package.path = "./?.lua;./?/init.lua;" .. package.path

require("tests.tier_runner").main({ "tests/save_compat" }, "save_compat")
