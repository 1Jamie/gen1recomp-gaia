local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("em_daycare_rse", "/tmp/em_daycare_rse")

local function C()
  return require("src.core.game3.constants").of("emerald")
end

local function makeMon(sess, speciesName, personality, extra)
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local species = C():require("species", speciesName)
  local scratch = setmetatable({ party = {}, dex = { seen = {}, owned = {}, caught = {} } }, { __index = sess })
  local ok, _, mon = Party.giveMon(scratch, species, 20)
  assert(ok and mon, "giveMon " .. speciesName)
  mon.personality = personality
  mon.nature = Pokemon.natureId(personality)
  mon.gender = Pokemon.gender(species, personality)
  for k, v in pairs(extra or {}) do mon[k] = v end
  Pokemon.applyStats(mon)
  return mon
end

local function dayCareCount()
  local Daycare = require("src.core.game3.daycare")
  return Daycare.count(Daycare.stateOf())
end

local function talk(game, mapId, x, y, until_, frames)
  X.goTo(d, game, mapId, x, y, "up")
  X.settle(game, 60)
  return X.mash(game, until_, frames or 900)
end

return function(game)
  local sess = X.newGame(d, game, 0)
  if not sess then return d.finish() end
  local Daycare = require("src.core.game3.daycare")
  sess.party = {
    makeMon(sess, "SPECIES_PIKACHU", 0x00000100, { item = C():require("items", "ITEM_LIGHT_BALL") }),
    makeMon(sess, "SPECIES_DITTO", 0x00000003),
    makeMon(sess, "SPECIES_SLUGMA", 0x00000004, { ability = C():require("abilities", "ABILITY_FLAME_BODY"),
      abilityId = C():require("abilities", "ABILITY_FLAME_BODY") }),
    makeMon(sess, "SPECIES_ZIGZAGOON", 0x00000005),
  }
  d.check(require("src.core.game3.pokemon").gender(25, 0x100) == "F", "Pikachu parent is female")

  local okOne = talk(game, "EM_ROUTE117_POKEMON_DAY_CARE", 2, 3, function() return dayCareCount() >= 1 end, 1500)
  d.check(okOne, "daycare lady takes the first Pokemon through ChooseSendDaycareMon + StoreSelectedPokemonInDaycare")
  local okTwo = X.mash(game, function() return dayCareCount() >= 2 end, 900)
  d.check(okTwo, "a second Pokemon joins (GetDaycareState=DAYCARE_TWO_MONS, VM " .. X.vmWhere() .. ")")
  X.mash(game, function() return not X.scriptRunning() end, 600, "b")
  d.shot(game, "01_daycare_two_mons.png")
  d.check(type(sess.modData) == "table" and type(sess.modData.emerald_daycare) == "table" and sess.modData.firered_daycare == nil,
    "daycare saves under the Emerald key (modData.emerald_daycare)")
  local dc = Daycare.stateOf(sess)
  local species = { Daycare.speciesOf(Daycare.mon(dc, 1)), Daycare.speciesOf(Daycare.mon(dc, 2)) }
  d.note("daycare holds " .. table.concat(species, ","))

  local pending = false
  for _ = 1, 256 * 80 do
    Daycare.step(sess)
    if Daycare.isEggPending(dc) then pending = true break end
  end
  d.check(pending, "walking with a compatible pair makes an egg pending")
  d.check(X.flag("FLAG_PENDING_DAYCARE_EGG"), "FLAG_PENDING_DAYCARE_EGG (Emerald 0x86) is set by name")

  X.setFlag("FLAG_RECEIVED_POKENAV", true)
  local eggTrace = {}
  X.goTo(d, game, "EM_ROUTE117", 45, 8, "up")
  local man = require("src.core.game3.objects").find(3)
  local mx, my = man and man.cellX or 47, man and man.cellY or 4
  d.note(string.format("daycare man stands at (%s,%s) with an egg pending", tostring(mx), tostring(my)))
  local okEgg = talk(game, "EM_ROUTE117", mx, my + 1, function()
    local w = X.vmWhere()
    if eggTrace[#eggTrace] ~= w then eggTrace[#eggTrace + 1] = w end
    for _, m in ipairs(sess.party or {}) do if m.isEgg then return true end end
    return false
  end, 1500)
  X.mash(game, function() return not X.scriptRunning() end, 600, "b")
  d.check(okEgg, "the daycare man hands over the egg (GiveEggFromDaycare)")
  if not okEgg then
    local s2 = X.session()
    for i = 1, math.min(#eggTrace, 30) do d.note("egg trace " .. eggTrace[i]) end
    d.note("egg talk: map " .. tostring(s2.map) .. " VM " .. X.vmWhere() .. " pending " .. tostring(Daycare.isEggPending(dc)))
    d.shot(game, "02a_egg_talk.png")
    local ok, err = pcall(function() return require("src.core.game3.breeding").giveEggFromDaycare(sess) end)
    d.note("direct giveEggFromDaycare: " .. tostring(ok) .. " " .. tostring(err))
  end
  local egg
  for _, m in ipairs(sess.party or {}) do if m.isEgg then egg = m end end
  if egg then
    d.check(Daycare.speciesOf(egg) == C():require("species", "SPECIES_PICHU"), "egg species is Pichu (" .. tostring(egg.species) .. ")")
    local volt = false
    for _, mv in ipairs(egg.moves or {}) do
      if mv == C():require("moves", "MOVE_VOLT_TACKLE") then volt = true end
    end
    d.check(volt, "Light Ball parent teaches the Pichu egg Volt Tackle (daycare.c GiveVoltTackleIfLightBall)")
    d.check(not X.flag("FLAG_PENDING_DAYCARE_EGG"), "script clears FLAG_PENDING_DAYCARE_EGG")
  end
  d.check(Daycare.eggCyclesToSubtract(sess) == 2, "Flame Body Slugma in the party halves egg cycles (subtract 2)")
  if egg then
    egg.friendship, egg.eggCycles = 6, 6
    dc.stepCounter = 254
    Daycare.step(sess)
    d.check(egg.friendship == 4, "one egg cycle tick removes 2 cycles with Flame Body (" .. tostring(egg.friendship) .. ")")
  end
  d.shot(game, "02_egg_received.png")
  d.finish()
end
