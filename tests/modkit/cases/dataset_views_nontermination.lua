-- A generated chunk that would loop if executed must be rejected as syntax.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = require("tests.modkit.dataset_view_fixture")

local files = {}
Fixture.cache(files, "red", {
  pokemon = "while true do end; return {}",
})
local modPath = Fixture.addMod(files, "nontermination_probe", [[
local mod = ...
local view, reason = mod.datasets:open("red")
mod.exports.result = { view ~= nil, reason }
]])
local run = T.sdk.loadMods({ modPath }, {
  fs = T.sdk.memfs(files), data = { pokemon = {} }, generation = 1,
})
T.same(run.loader.exports.nontermination_probe.result,
  { false, "invalid_cache" }, "generated code is never executed")
run.release()
T.finish("dataset_views_nontermination")
