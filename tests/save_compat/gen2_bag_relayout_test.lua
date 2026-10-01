package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local G2 = require("tests.fixtures.save.gen2_build")
local Gen2Save = require("src.save_convert.Gen2Save")

local DATA = {
  items = K.gen2Data.items, maps = K.gen2Data.maps,
  pokemon = { CYNDAQUIL = { index = 155, dex = 155, name = "CYNDAQUIL", genderRatio = 0x1F },
              UNOWN = { index = 201, dex = 201, name = "UNOWN", genderRatio = 0xFF },
              PIKACHU = { index = 25, dex = 25, name = "PIKACHU", genderRatio = 0x7F } },
  moves = { TACKLE = { index = 33, pp = 35 }, GROWL = { index = 43, pp = 40 }, EMBER = { index = 52, pp = 25 } },
}

local function decode(bytes, v) return assert(Gen2Save.decode(bytes, v, DATA)) end
local function fresh(save, v) return Gen2Save.encode(save, v, nil, DATA) end

local P, R, A, M = G2.ITEMS.POTION.index, G2.ITEMS.REPEL.index, G2.ITEMS.ANTIDOTE.index, G2.ITEMS.MAX_POTION.index
local NAME = { [P] = "POTION", [R] = "REPEL", [A] = "ANTIDOTE", [M] = "MAX_POTION" }

local function pocket(bytes, L, countKey, listKey)
  local n = bytes:byte(L[countKey] + 1)
  local out = {}
  for i = 0, n - 1 do
    out[#out + 1] = bytes:byte(L[listKey] + i * 2 + 1) .. "x" .. bytes:byte(L[listKey] + i * 2 + 2)
  end
  return table.concat(out, ",")
end

local function items(bytes, L) return pocket(bytes, L, "wNumItems", "wItems") end
local function slots(...)
  local out = {}
  for _, s in ipairs({ ... }) do out[#out + 1] = s[1] .. "x" .. s[2] end
  return table.concat(out, ",")
end

for _, v in ipairs({ "gold", "silver", "crystal" }) do
  local L = Gen2Save.layoutFor(v)
  local function base(list)
    return decode(G2.build({ version = v, items = list }), v)
  end

  local src = base({ { P, 99 }, { R, 4 }, { P, 5 } })
  check(src.cartBag ~= nil, v .. ": a split POTION stack is carried")
  src.inventory[NAME[P]] = 105
  eq(items(fresh(src, v), L), slots({ P, 99 }, { R, 4 }, { P, 6 }),
    v .. ": adding 1 POTION tops up the first slot with room, keeping the gap and the order")

  src = base({ { P, 99 }, { R, 4 }, { P, 5 } })
  src.inventory[NAME[P]] = 250
  eq(items(fresh(src, v), L), slots({ P, 99 }, { R, 4 }, { P, 99 }, { P, 52 }),
    v .. ": overflow opens a new slot on the end")

  src = base({ { P, 99 }, { R, 4 }, { P, 5 } })
  src.inventory[NAME[P]] = 90
  eq(items(fresh(src, v), L), slots({ P, 85 }, { R, 4 }, { P, 5 }),
    v .. ": removing takes from the first POTION slot (RemoveItemFromPocket)")

  src = base({ { P, 99 }, { R, 4 }, { P, 5 } })
  src.inventory[NAME[P]] = 5
  eq(items(fresh(src, v), L), slots({ R, 4 }, { P, 5 }),
    v .. ": an emptied slot is dropped and the survivors keep their order")

  src = base({ { P, 99 }, { R, 4 }, { P, 5 } })
  src.inventory[NAME[R]] = nil
  eq(items(fresh(src, v), L), slots({ P, 99 }, { P, 5 }), v .. ": a used-up item leaves the others where they were")

  src = base({ { P, 99 }, { R, 4 }, { P, 5 } })
  src.inventory[NAME[A]] = 2
  src.bagOrder[#src.bagOrder + 1] = NAME[A]
  eq(items(fresh(src, v), L), slots({ P, 99 }, { R, 4 }, { P, 5 }, { A, 2 }),
    v .. ": a new item goes on the end")

  src = base({ { P, 99 }, { R, 4 }, { P, 5 } })
  src.bagOrder = { NAME[R], NAME[P] }
  eq(items(fresh(src, v), L), slots({ R, 4 }, { P, 99 }, { P, 5 }),
    v .. ": a reordered bag is laid out in the new order, the stacks still split")

  local out = fresh(base({ { P, 99 }, { R, 4 }, { P, 5 } }), v)
  eq(items(out, L), slots({ P, 99 }, { R, 4 }, { P, 5 }), v .. ": an unchanged bag stays exact")
end

T.finish()
