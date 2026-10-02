package.path = "./?.lua;./?/init.lua;" .. package.path

local Runner = require("tests.tier_runner")
local Groups = require("tests.save_compat._groups")
if not arg[1] then
  Runner.main({ "tests/save_compat" }, "save_compat")
elseif arg[1] == "--group" and Groups.valid[arg[2]] and not arg[3] then
  local group = arg[2]
  Runner.main({ "tests/save_compat" }, "save_compat/" .. group,
    function(path) return Groups.of(path) == group end)
else
  io.stderr:write("usage: tests/run_save_compat.lua [--group codecs|records|world]\n")
  os.exit(2)
end
