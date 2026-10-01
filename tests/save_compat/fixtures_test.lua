package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Compat = require("src.save_convert.Compat")

local INVALID_ON_PURPOSE = {
  ["g1.red.box_index_invalid"] = { "gen1.currentBoxIndex" },
  ["g2.crystal.corrupt_primary"] = { "gen2.checksum", "gen2.openhomeChecksum" },
}

local seen = {}
for _, gen in ipairs({ 1, 2, 3 }) do
  local mod = require("tests.fixtures.save.gen" .. gen .. "_build")
  local first, second = mod.cases(), mod.cases()
  eq(#first, #second, ("gen%d: builders return the same case list twice"):format(gen))
  for i, c in ipairs(first) do
    check(not seen[c.id], c.id .. " is a unique case id")
    seen[c.id] = true
    eq(c.gen, gen, c.id .. " is tagged with its generation")
    check(c.bytes == second[i].bytes, c.id .. " builds byte-identically every time")
    local size = gen == 3 and 0x20000 or 0x8000
    check(#c.bytes >= size, ("%s is at least %d bytes"):format(c.id, size))
    local report = Compat.check(c.bytes, c.version)
    if c.refuse then
      eq(report.ok, false, c.id .. " (a blank cart) is not a valid save")
    elseif INVALID_ON_PURPOSE[c.id] then
      local want = INVALID_ON_PURPOSE[c.id]
      eq(#report.errors, #want, c.id .. " fails only the rules it is built for -- " .. Compat.describe(report))
      for k, rule in ipairs(want) do
        eq(report.errors[k] and report.errors[k].rule, rule, c.id .. " fails " .. rule)
      end
    else
      eq(#report.errors, 0, c.id .. " is a cart every reader accepts -- " .. Compat.describe(report))
    end
  end
end

T.finish()
