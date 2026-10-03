local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_catch_prompt_2637", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_catch_prompt_2637")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local Ui = require("src.core.game3.battle.ui")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local Bag = require("src.core.game3.bag")
  local BagMenu = require("src.ui.game3.bag_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Naming = require("src.ui.game3.naming")
  local RseDex = require("src.ui.game3.rse.pokedex")
  local Dex = require("src.core.game3.dex")
  local Storage = require("src.core.game3.storage")
  local session = Runtime.getSession()
  local version = os.getenv("POKEPORT_TEST_VERSION") or "emerald"
  if not S.check(session.version == version, "capture driver version " .. version) then return S.finish() end
  local C = require("src.core.game3.constants").of(version)
  local function species(name) return C:require("species", "SPECIES_" .. name) end
  local starter = species(version == "emerald" and "TREECKO" or "CHARMANDER")
  local target = species(version == "emerald" and "WURMPLE" or "MAGIKARP")
  local pcTarget = species(version == "emerald" and "POOCHYENA" or "PIDGEY")
  local master = C:require("items", "ITEM_MASTER_BALL")
  session.party, session.dex = {}, Dex.new()
  Party.giveMon(session, starter, 12)
  if version == "emerald" then
    F.setVar("VAR_LITTLEROOT_INTRO_STATE", 7)
    F.setVar("VAR_LITTLEROOT_TOWN_STATE", 4)
    F.setVar("VAR_ROUTE101_STATE", 3)
    F.setFlag("FLAG_RESCUED_BIRCH", true)
  end
  S.check(F.goTo(game, version == "emerald" and "EM_ROUTE101" or "FR_ROUTE1", 10, 10, "down"),
    "capture approach map loaded")

  local function throw()
    Bag.add(session.bag, master, 1)
    U.tap(game, "right")
    U.wait(12)
    U.tap(game, "a")
    U.wait(60)
    for _ = 1, 6 do
      if BagMenu.currentPocket() == "POKE_BALLS" then break end
      U.tap(game, "right")
      U.wait(32)
    end
    if not S.check(BagMenu.currentPocket() == "POKE_BALLS", "capture bag reached Poke Balls") then return false end
    U.tap(game, "a")
    U.wait(20)
    U.tap(game, "a")
    U.wait(20)
    return true
  end
  local function capture(sp, first, yes, pc, tag)
    local partyBefore = #session.party
    if not S.check(Bridge.startWild(Runtime._mod, game, { species = sp, level = 3 }, { fade = false }) == true,
        tag .. " wild encounter started") then return false end
    local thrown, dexSeen, promptSeen, typed, pcMessageSeen = false, false, false, false, false
    local name, snapshot, image
    for frame = 1, 12000 do
      if not Battle.isActive() then break end
      local phase = Battle._phase
      if phase == "command" and Ui._mode == "menu" and not thrown then
        thrown = true
        if not throw() then return false end
      elseif phase == "pokedex_reg" then
        dexSeen = true
        local ds = RseDex.active()
        if version == "emerald" and ds and ds.fn == "caughtInput" then
          snapshot, image = ds.caught.mon, ds.caught.mon.img
          S.check(S.still(game, tag .. "_dex.png"), tag .. " stable caught dex screenshot")
          U.tap(game, "a")
        elseif version ~= "emerald" and frame % 18 == 0 then
          U.tap(game, "a")
        else U.wait(1) end
      elseif phase == "catch_dex_return" then
        U.wait(1)
      elseif phase == "catch_nickname_prompt" and Choice.isOpen() then
        if not promptSeen then
          promptSeen = true
          local c = Ui._caughtDexScene
          if first then
            if version == "emerald" then
              S.check(c and c.sprite == snapshot, tag .. " prompt retains same dex sprite")
            end
            local cy = version == "emerald" and 80 or 64
            S.check(c and c.sprite.x == 120 and c.sprite.y == cy, tag .. " prompt source center120," .. cy)
            local battleMon = Battle._st.enemy.mon
            local expected = Pokemon.frontPic(Pokemon.picSpecies(sp, battleMon.personality), nil,
              Pokemon.isShiny(battleMon), battleMon.personality)
            S.check(c and c.sprite.img == expected.image, tag .. " prompt uses restored caught palette")
          else
            S.check(c == nil, tag .. " existing capture branch presentation preserved")
          end
          S.check(S.still(game, tag .. "_question.png"), tag .. " stable nickname question screenshot")
          U.tap(game, yes and "a" or "b")
          U.wait(24)
        else U.wait(1) end
      elseif Naming.isOpen() then
        local ns = Naming._state
        if ns and ns.pcPages then
          if Message.isTyping() then U.wait(1) else
            U.tap(game, "a")
            U.wait(20)
          end
        elseif not typed then
          typed = true
          U.wait(24)
          for _ = 1, 3 do U.tap(game, "a"); U.wait(12) end
          name = Naming._state and Naming._state.name
          S.check(name == "AAA", tag .. " three input taps type exactly AAA")
          S.check(Ui._caughtDexScene == nil, tag .. " fullscreen naming releases caught scene")
          S.check(S.still(game, tag .. "_naming.png"), tag .. " stable keyboard screenshot")
          U.tap(game, "start")
          U.wait(20)
          U.tap(game, "a")
          U.wait(20)
        else U.wait(1) end
      elseif phase == "catch_pc_msg" and not pcMessageSeen then
        pcMessageSeen = true
        S.check(Ui._caughtDexScene ~= nil == first, tag .. " PC No preserves first-capture scene")
        if first then
          local c = Ui._caughtDexScene
          S.check(c and c.sprite.x == 120 and c.sprite.y == (version == "emerald" and 80 or 64),
            tag .. " PC transfer retains source center")
        end
        for _ = 1, 180 do if not Message.isTyping() then break end; U.wait(1) end
        S.check(S.still(game, tag .. "_pc_message.png"), tag .. " stable PC transfer screenshot")
      elseif Message.isOpen() and not Message.isTyping() and frame % 18 == 0 then
        U.tap(game, "a")
      else U.wait(1) end
    end
    S.check(not Battle.isActive(), tag .. " capture completed")
    S.check(dexSeen == first, tag .. " dex registration branch correct")
    S.check(promptSeen, tag .. " nickname question reached")
    S.check(typed == yes, tag .. " naming Yes No route correct")
    S.check(pcMessageSeen == (pc and not yes), tag .. " PC transfer message route correct")
    S.check(Ui._caughtDexScene == nil and not Naming.isOpen(), tag .. " capture presentation cleared")
    local mon
    if pc then
      local storage = Storage.ensure(session)
      for _, box in ipairs(storage.boxes or {}) do
        for _, candidate in pairs(box.mons or {}) do
          if tonumber(candidate.species or candidate.speciesId) == sp and (not yes or candidate.nickname == name) then
            mon = candidate
          end
        end
      end
    else
      mon = session.party[partyBefore + 1]
    end
    S.check(mon and tonumber(mon.species or mon.speciesId) == sp, tag .. " correct mon reached " .. (pc and "PC" or "party"))
    if yes then S.check(mon and mon.nickname == "AAA", tag .. " destination retains AAA nickname") end
    U.wait(40)
    return not Battle.isActive()
  end
  if not capture(target, true, true, false, version .. "_new_party_yes") then return S.finish() end
  if not capture(target, false, true, false, version .. "_repeat_party_yes") then return S.finish() end
  session.dex = Dex.new()
  if not capture(target, true, false, false, version .. "_new_party_no") then return S.finish() end
  if not capture(target, false, false, false, version .. "_repeat_party_no") then return S.finish() end
  while #session.party < 6 do Party.giveMon(session, starter, 12) end
  if not capture(pcTarget, true, true, true, version .. "_new_pc_yes") then return S.finish() end
  if not capture(pcTarget, false, true, true, version .. "_repeat_pc_yes") then return S.finish() end
  session.dex = Dex.new()
  if not capture(pcTarget, true, false, true, version .. "_new_pc_no") then return S.finish() end
  capture(pcTarget, false, false, true, version .. "_repeat_pc_no")
  S.finish()
end
