#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Party = require("src.core.game3.party")

print("[test] 1. battle writeback carries an evolution rename back to the session mon")
do
  local mon = { species = 1, speciesId = 1, name = "BULBASAUR", nickname = "BULBASAUR", level = 16 }
  Party.applyBattleFields(mon, { species = 2, speciesId = 2, name = "IVYSAUR", nickname = "IVYSAUR" })
  eq(mon.name, "IVYSAUR", "name follows the evolution")
  eq(mon.nickname, "IVYSAUR", "nickname follows the evolution")
end

print("[test] 2. a nil nickname leaves the existing nickname alone")
do
  local mon = { name = "BULBASAUR", nickname = "LEAFY" }
  Party.applyBattleFields(mon, { name = "BULBASAUR", nickname = nil })
  eq(mon.nickname, "LEAFY", "custom nickname untouched")
end

finish()
