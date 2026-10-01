package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
local K = require("tests.save_compat._codec")

if not K.gen1Available() then
  print("gen1_crosswalk_asm skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

local GenSave = require("src.save_convert.GenSave")
local P = require("tests.save_compat._pret_asm")

local function run(version)
  local root = P.root(version)
  if not root then
    print("gen1_crosswalk_asm: pret checkout missing for " .. version .. ", skipped")
    return
  end
  local tag = version .. ": "
  local data = K.gen1Data(version)
  local cw = GenSave.crosswalks(data)

  local species, speciesAt = P.constants(root .. "/constants/pokemon_constants.asm")
  local count = 0
  for id, idx in pairs(cw.pokemonIndex) do
    count = count + 1
    eq(species[id], idx, tag .. "species " .. id .. " is index " .. tostring(species[id]) .. " in pokemon_constants.asm")
  end
  eq(count, 151, tag .. "151 species in the crosswalk")

  local moves = P.constants(root .. "/constants/move_constants.asm")
  count = 0
  for id, idx in pairs(cw.movesIndex) do
    count = count + 1
    eq(moves[id], idx, tag .. "move " .. id .. " index")
  end
  eq(count, 165, tag .. "165 moves in the crosswalk")

  local items = P.constants(root .. "/constants/item_constants.asm")
  local machines = P.machines(root .. "/constants/item_constants.asm")
  count = 0
  for id, idx in pairs(cw.itemsIndex) do
    count = count + 1
    local want = items[id] or machines[id]
    eq(want, idx, tag .. "item " .. id .. " index")
  end
  check(count >= 80, tag .. "the item crosswalk is populated (" .. count .. ")")

  local maps = P.mapIndexes(root)
  count = 0
  for id, idx in pairs(cw.mapsIndex) do
    if maps[id] then
      count = count + 1
      eq(maps[id], idx, tag .. "map " .. id .. " index")
    end
  end
  check(count >= 200, tag .. "the map crosswalk matches map_constants.asm (" .. count .. ")")

  local asmCharmap = P.charmap(root)
  local charmap = dofile("src/save_convert/data/charmap.lua")
  local compared = 0
  for token, byte in pairs(charmap.byToken) do
    if asmCharmap[token] then
      compared = compared + 1
      eq(asmCharmap[token], byte, tag .. "charmap " .. token)
    end
  end
  check(compared >= 100, tag .. "the charmap agrees with charmap.asm (" .. compared .. " glyphs)")
  for _, letter in ipairs({ "A", "Z", "a", "z", "0", "9", " ", "!", "?", "-", "." }) do
    eq(charmap.byToken[letter], asmCharmap[letter], tag .. "charmap " .. letter .. " is present and exact")
  end

  local dexIndex = P.constants(root .. "/constants/pokedex_constants.asm")
  local order = P.dexOrder(root)
  eq(#order, 190, tag .. "PokedexOrder has one row per internal species index")
  for i, dexName in ipairs(order) do
    local sp = speciesAt[i]
    if dexName and sp and cw.pokemonDex[sp] then
      eq(cw.pokemonDex[sp], dexIndex["DEX_" .. dexName], tag .. sp .. " dex number")
    end
  end
end

run("red")
run("yellow")

T.finish()
