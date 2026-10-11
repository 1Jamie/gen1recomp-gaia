package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Syms = require("src.import.gba.syms")
local Builds = require("src.import.gba.rs_builds")
local Rs = require("src.import.gba.games.rs")

local REVISED_TEXT = {
  -- pokeruby/src/strings.c:324
  gOtherText_CantUseOnPoke = true,
  -- pokeruby/data/text/tv.inc:908
  gTVSmartShopperText1 = true,
  -- pokeruby/src/data/pokedex_entries_en.h:523
  DexDescription_Paras_1 = true, DexDescription_Paras_2 = true,
  -- pokeruby/src/data/pokedex_entries_en.h:3813
  DexDescription_Mawile_1 = true, DexDescription_Mawile_2 = true,
  -- pokeruby/src/decoration.c:413
  DecorDesc_TOGEPI_DOLL = true,
  -- pokeruby/data/event_scripts.s:1674
  Text_1C6C62 = true,
}

local used, restore = {}, {}
local function record(build)
  local S = Syms.of(build)
  local names = {}
  used[build] = names
  for _, fn in ipairs({ "off", "count", "size" }) do
    local orig = S[fn]
    restore[#restore + 1] = function() S[fn] = orig end
    S[fn] = function(name, ...)
      names[name] = true
      return orig(name, ...)
    end
  end
end

for _, game in ipairs({ "ruby", "sapphire" }) do
  local facade = Rs.new(game)
  for _, revision in ipairs(Builds[game]) do
    record(revision.build)
    facade.select(revision.sha1)
  end
end
for _, fn in ipairs(restore) do fn() end

local function sorted(set)
  local out = {}
  for name in pairs(set) do out[#out + 1] = name end
  table.sort(out)
  return out
end

local function sizeMismatches(names, A, B)
  local out = {}
  for _, name in ipairs(names) do
    if not REVISED_TEXT[name] then
      local a, b = A.size(name), B.size(name)
      if a ~= b then out[#out + 1] = string.format("%s %d~=%d", name, a, b) end
    end
  end
  return out
end

for _, game in ipairs({ "ruby", "sapphire" }) do
  local base = Builds[game][1].build
  local names = sorted(used[base])
  T.check(#names >= 150, game .. " extractors resolve " .. #names .. " symbols on " .. base)
  for _, revision in ipairs(Builds[game]) do
    local build = revision.build
    T.same(sorted(used[build]), names, build .. " resolves the same symbol set as " .. base)
    local bad = sizeMismatches(names, Syms.of(base), Syms.of(build))
    T.same(bad, {}, build .. " symbol sizes match " .. base .. " " .. table.concat(bad, ", "))
    for name in pairs(REVISED_TEXT) do
      T.check(Syms.of(build).size(name) > 0, build .. " revised text " .. name .. " resolves")
    end
  end
end

-- pokeruby/fonts.mk:22
for _, build in ipairs({ "ruby11", "ruby12", "sapphire11", "sapphire12" }) do
  local S = Syms.of(build)
  T.eq(S.size("gFont3LatinGlyphs"), 16256, build .. " font3 latin glyph bytes")
  T.eq(S.size("gFont4LatinGlyphs"), 7040, build .. " font4 latin glyph bytes")
  T.eq(S.size("text.o:sFont3Widths"), 254, build .. " font3 width table")
end

require("src.import.gba.versions").select("firered")
T.finish("game3_rs_revision_symbol_sizes_2828")
