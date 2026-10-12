package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")

package.loaded["src.core.game3.runtime"] = { getSession = function() return nil end }

local Pokemon = require("src.core.game3.pokemon")
Pokemon._names = { [25] = "PIKACHU", [201] = "UNOWN", [410] = "DEOXYS" }
Pokemon._front, Pokemon._back = {}, {}
local vanillaPic = { image = "vanilla-pic", w = 64, h = 64 }
local vanillaIcon = { image = "vanilla-icon", w = 32, h = 32, sheetH = 64, frames = 2,
                      quads = { [0] = "q0", [1] = "q1" } }
Pokemon.install = function() end
Pokemon.frontPic = function() return vanillaPic end
Pokemon.backPic = function() return vanillaPic end
Pokemon.icon = function() return vanillaIcon end
Pokemon.monIcon = function(mon) return Pokemon.icon(Pokemon.monPicSpecies(mon)) end

local Gen3Compat = require("src.mods.Gen3Compat")
local game = { phase = "field", data = {}, mods = { content = {} } }
Gen3Compat.bind(function() return game end)
Runtime.hooks = Hooks.new()
Gen3Compat.applyMerged(game)

local sprites, icons = {}, {}
Runtime.hooks:wrap("pokemon.sprite", function(next, path, ctx)
  sprites[#sprites + 1] = { path = path, species = ctx.species, gen3Species = ctx.gen3Species,
                            letter = ctx.letter, form = ctx.form }
  return next(path, ctx)
end)
Runtime.hooks:wrap("pokemon.icon", function(next, path, ctx)
  icons[#icons + 1] = { path = path, species = ctx.species, gen3Species = ctx.gen3Species,
                        letter = ctx.letter }
  return next(path, ctx)
end)

local UNOWN_F, UNOWN_N, UNOWN_QMARK = 417, 425, 439

local ok, back = pcall(Pokemon.backPic, UNOWN_F, 0, false, "battle")
T.check(ok, "backPic on an Unown form does not raise: " .. tostring(back))
T.eq(ok and back, vanillaPic, "a pass-through sprite hook keeps the vanilla back pic")
local s = sprites[#sprites] or {}
T.eq(s.species, "UNOWN", "sprite ctx.species is the base species")
T.eq(s.gen3Species, UNOWN_F, "sprite ctx.gen3Species keeps the form index")
T.eq(s.path, "data/generated/gba/pokemon/back/417.rgba", "sprite path is the form's own pic")
T.eq(s.letter, 6, "sprite ctx.letter is F")

ok = pcall(Pokemon.frontPic, UNOWN_QMARK, 0, false, 0, "summary")
T.check(ok, "frontPic on Unown ? does not raise")
s = sprites[#sprites] or {}
T.eq(s.species, "UNOWN", "front ctx.species is UNOWN for the ? form")
T.eq(s.letter, 28, "front ctx.letter is ? (28)")
T.eq(s.path, "data/generated/gba/pokemon/front/439.rgba", "front path is the ? form's pic")

local p = 0x00010001
local mon = { species = 201, personality = p }
local formSp = Pokemon.monPicSpecies(mon)
local okI, icon = pcall(Pokemon.monIcon, mon)
T.check(okI, "monIcon on an Unown form does not raise: " .. tostring(icon))
T.eq(okI and icon, vanillaIcon, "a pass-through icon hook keeps the vanilla icon")
local i = icons[#icons] or {}
T.eq(i.species, "UNOWN", "icon ctx.species is the base species")
T.eq(i.gen3Species, formSp, "icon ctx.gen3Species is the form index")
T.eq(i.path, "data/generated/gba/pokemon/icons/" .. formSp .. ".rgba", "icon path is the form's icon")

okI = pcall(Pokemon.icon, UNOWN_N)
T.check(okI, "icon on Unown N does not raise")
T.eq((icons[#icons] or {}).letter, 14, "icon ctx.letter is N")

pcall(Pokemon.icon, 201)
i = icons[#icons] or {}
T.eq(i.species, "UNOWN", "base Unown stays UNOWN")
T.eq(i.letter, 1, "base Unown is letter A")

pcall(Pokemon.backPic, 410, 2, false, "battle")
s = sprites[#sprites] or {}
T.eq(s.species, "DEOXYS", "Deoxys keeps its own name")
T.eq(s.form, 2, "Deoxys keeps its form")
T.eq(s.letter, nil, "a non-Unown has no letter")

T.eq(Gen3Compat.speciesName(UNOWN_F), "UNOWN", "speciesName folds Unown forms")
T.eq(Gen3Compat.speciesName(25), "PIKACHU", "speciesName leaves other species alone")

T.finish("gen3 unown form mod hooks bug 2904")
