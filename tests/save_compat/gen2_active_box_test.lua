package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local G2 = require("tests.fixtures.save.gen2_build")
local B = require("tests.fixtures.save.bytes")
local Gen2Save = require("src.save_convert.Gen2Save")

local N = Gen2Save.BOX_BYTES

for _, v in ipairs({ "gold", "silver", "crystal" }) do
  local L = Gen2Save.layoutFor(v)
  local function span(s, at) return s:sub(at + 1, at + N) end
  local boxes = { [3] = G2.boxOf(4, 11) }
  local src = G2.build({ version = v, boxes = boxes, currentBox = 2 })
  eq(span(src, L.sBox), span(src, L.boxes[3]), v .. ": the fixture's sBox is box 3")

  -- pokecrystal engine/menus/save.asm:766 LoadBox, :975 LoadBoxAddress
  local b = B.fromString(src)
  local stale = G2.boxOf(2, 90)
  local tmp = B.fromString(G2.build({ version = v, boxes = { [3] = stale }, currentBox = 2 }))
  B.copy(tmp, L.boxes[3], L.sBox, N)
  for i = 0, N - 1 do b[L.sBox + i] = tmp[L.sBox + i] end
  G2.seal(b, v)
  local divergent = B.pack(b)
  check(span(divergent, L.sBox) ~= span(divergent, L.boxes[3]), v .. ": sBox holds mons the archive does not")

  local save = assert(Gen2Save.decode(divergent, v, K.gen2Data))
  eq(#save.boxes[3], 4, v .. ": the archived box is what the cartridge loads over sBox")
  check(save.warnings and save.warnings[1]:find("active box", 1, true) ~= nil, v .. ": and the difference is reported")

  local templated = assert(Gen2Save.encode(save, v, divergent, K.gen2Data))
  eq(templated, divergent, v .. ": an unchanged export keeps the stale sBox bytes exactly")

  -- pokecrystal engine/menus/save.asm:521 SaveBox, :900 SaveBoxAddress
  local fresh = assert(Gen2Save.encode(save, v, nil, K.gen2Data))
  eq(span(fresh, L.sBox), span(fresh, L.boxes[3]), v .. ": a templateless export writes sBox equal to the archive")
  eq(fresh:byte(L.wCurBox + 1), 2, v .. ": with wCurBox naming that box")

  save.boxes[3][1].level = 77
  local edited = assert(Gen2Save.encode(save, v, divergent, K.gen2Data))
  eq(span(edited, L.sBox), span(edited, L.boxes[3]), v .. ": editing the current box rewrites sBox with the archive")
  eq(edited:byte(L.boxes[3] + 0x16 + 0x1F + 1), 77, v .. ": including the edit")

  save.boxes[3][1].level = 5 + 1 % 90
  save.currentBox = 5
  local moved = assert(Gen2Save.encode(save, v, divergent, K.gen2Data))
  eq(moved:byte(L.wCurBox + 1), 4, v .. ": changing the current box writes wCurBox")
  eq(span(moved, L.sBox), span(moved, L.boxes[5]), v .. ": and sBox becomes the new box")
  local back = assert(Gen2Save.decode(moved, v, K.gen2Data))
  eq(back.currentBox, 5, v .. ": and it imports as that box")
  eq(#back.boxes[3], 4, v .. ": leaving the old box intact in the archive")
end

T.finish()
