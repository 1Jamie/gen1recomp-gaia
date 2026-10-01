package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Diff = require("tests.save_compat._diff")

local TIERS = { T1 = true, T2 = true, T3 = true }
local BLOCK_SIZE = {
  frlg = { sb2 = 0xF24, sb1 = 0x3D68, storage = 0x83D0, flash = 0x20000 },
  emerald = { sb2 = 0xF2C, sb1 = 0x3D88, storage = 0x83D0, flash = 0x20000 },
}

local function verify(label, regions, limitFor)
  local names = {}
  for _, r in ipairs(regions) do
    check(TIERS[r.tier] ~= nil, ("%s %s: tier %s"):format(label, r.name, tostring(r.tier)))
    check(r.size > 0 and r.offset >= 0, ("%s %s: positive size"):format(label, r.name))
    check(r.offset + r.size <= limitFor(r), ("%s %s: 0x%X+0x%X inside its block"):format(label, r.name, r.offset, r.size))
    for id in tostring(r.ids or ""):gmatch("%S+") do
      check(id:match("^G[123]%-%d%d$") or id:match("^X%-%d%d$"), ("%s %s: id %s is an audit id"):format(label, r.name, id))
    end
    local key = (r.block or "") .. ":" .. r.name
    check(not names[key], ("%s: region name %s is unique"):format(label, key))
    names[key] = true
  end
  local bad = 0
  for i = 1, #regions do
    local a = regions[i]
    for j = i + 1, #regions do
      local b = regions[j]
      if a.block == b.block then
        local a1, a2, b1, b2 = a.offset, a.offset + a.size, b.offset, b.offset + b.size
        local disjoint = a2 <= b1 or b2 <= a1
        local nested = (a1 <= b1 and b2 <= a2) or (b1 <= a1 and a2 <= b2)
        if not (disjoint or nested) then
          bad = bad + 1
          if bad <= 5 then check(false, ("%s: %s and %s overlap without nesting"):format(label, a.name, b.name)) end
        end
      end
    end
  end
  eq(bad, 0, label .. ": regions nest or are disjoint")
end

local g1 = require("src.save_convert.regions.gen1")
verify("gen1", g1.regions, function() return 0x8000 end)
local idx = Diff.index(g1.regions)
local holes = 0
for o = 0, 0x7FFF do if not idx[o] then holes = holes + 1 end end
eq(holes, 0, "gen1: every SRAM byte has a named region")
eq(Diff.regionAt(g1.regions, 0x2F2C + 8 + 44).name, "party.mon2", "gen1: the second party struct")
eq(Diff.regionAt(g1.regions, 0x3523).derived, true, "gen1: the main checksum is derived")

local g2 = require("src.save_convert.regions.gen2")
for _, which in ipairs({ "gs", "crystal" }) do
  verify("gen2 " .. which, g2[which], function() return 0x8030 end)
  local i2 = Diff.index(g2[which])
  local n = 0
  for o = 0x2009, (which == "gs" and 0x2D68 or 0x2B82) do if not i2[o] then n = n + 1 end end
  eq(n, 0, "gen2 " .. which .. ": every sGameData byte has a named region")
end
eq(Diff.regionAt(g2.gs, 0x2D69).name, "checksum", "gold: primary checksum")
eq(Diff.regionAt(g2.crystal, 0x2D0D).name, "checksum", "crystal: primary checksum")
eq(Diff.regionAt(g2.gs, 0x4000 + 0x16).name, "box01.mon1", "gold: first box struct")

local g3 = require("src.save_convert.regions.gen3")
for _, fam in ipairs({ "frlg", "emerald" }) do
  verify("gen3 " .. fam, g3[fam], function(r) return BLOCK_SIZE[fam][r.block] end)
end
eq(Diff.regionAt(g3.frlg, 0xF20, "sb2").name, "sb2.encryptionKey", "frlg: key at SB2 0xF20")
eq(Diff.regionAt(g3.emerald, 0xAC, "sb2").name, "sb2.encryptionKey", "emerald: key at SB2 0xAC")
eq(Diff.regionAt(g3.frlg, 0x38, "sb1").name, "sb1.party1", "frlg: party at SB1 0x38")
eq(Diff.regionAt(g3.emerald, 0x238, "sb1").name, "sb1.party1", "emerald: party at SB1 0x238")

T.finish()
