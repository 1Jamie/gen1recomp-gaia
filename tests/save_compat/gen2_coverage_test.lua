package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Gen2State = require("src.save_convert.Gen2State")
local Gen2Layout = require("src.save_convert.Gen2Layout")
local Syms = require("src.save_convert.Gen2Syms")

local MODES = { modeled = true, static = true }

local function resolve(spec, S)
  if spec.abs then return spec.abs, spec.abs + spec.len end
  local from = S[spec[1]]
  if from == nil then return nil, "label " .. tostring(spec[1]) .. " is not in the layout" end
  from = from + (spec.plus or 0)
  local to
  if spec.len then
    to = from + spec.len
  elseif spec[2] then
    to = S[spec[2]]
    if to == nil then return nil, "label " .. tostring(spec[2]) .. " is not in the layout" end
  else
    return nil, "a row needs a to label or a len"
  end
  return from, to
end

local modules = Gen2State.modules()
check(#modules >= 1, "the state modules load")

for _, which in ipairs({ { "goldSilver", Gen2Layout.goldSilver, "gs" }, { "crystal", Gen2Layout.crystal, "crystal" } }) do
  local S = Syms[which[1]]
  local L = which[2]
  local rows = {}
  for _, mod in ipairs(modules) do
    for _, row in ipairs(mod.coverage or {}) do
      check(MODES[row.mode], ("%s: coverage row has a mode"):format(which[1]))
      if row.mode == "static" then
        check(type(row.why) == "string" and row.why ~= "", ("%s: static row %s names why"):format(which[1], tostring((row.both or row[which[3]] or {})[1])))
      end
      local spec = row.both or row[which[3]]
      if spec then
        local from, to = resolve(spec, S)
        if not from then
          check(false, ("%s: %s"):format(which[1], tostring(to)))
        else
          rows[#rows + 1] = { from = from, to = to, row = row, name = spec[1] }
        end
      end
    end
  end
  table.sort(rows, function(a, b) if a.from ~= b.from then return a.from < b.from end return a.to < b.to end)
  local at = L.sGameData
  local gaps, overlaps = {}, {}
  for _, r in ipairs(rows) do
    check(r.to > r.from, ("%s: %s has a positive size"):format(which[1], r.name))
    if r.from > at then gaps[#gaps + 1] = ("0x%04X-0x%04X"):format(at, r.from) end
    if r.from < at then overlaps[#overlaps + 1] = ("%s at 0x%04X"):format(r.name, r.from) end
    if r.to > at then at = r.to end
  end
  if at < L.sGameDataEnd then gaps[#gaps + 1] = ("0x%04X-0x%04X"):format(at, L.sGameDataEnd) end
  if at > L.sGameDataEnd then overlaps[#overlaps + 1] = ("past the end 0x%04X"):format(at) end
  eq(#gaps, 0, ("%s: every saved byte is claimed -- gaps %s"):format(which[1], table.concat(gaps, " ")))
  eq(#overlaps, 0, ("%s: no byte is claimed twice -- %s"):format(which[1], table.concat(overlaps, ", ")))
end

T.finish()
