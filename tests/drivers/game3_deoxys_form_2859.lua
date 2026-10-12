local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_deoxys_form_2859", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_deoxys_form_2859")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local Ui = require("src.core.game3.battle.ui")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local Dex = require("src.core.game3.dex")
  local session = Runtime.getSession()
  local version = session.version
  local C = require("src.core.game3.constants").of(version)
  local deoxys = C:require("species", "SPECIES_DEOXYS")
  local tag = version

  session.party, session.dex = {}, Dex.new()
  Party.giveMon(session, deoxys, 50)
  local mon = session.party[1]
  S.check(mon and tonumber(mon.species) == deoxys, tag .. " Deoxys in party")

  local formPic, normalPic = Pokemon.monFrontPic(mon), Pokemon.monFrontPicDontHandleDeoxys(mon)
  S.check(formPic ~= nil and normalPic ~= nil and formPic.image ~= normalPic.image,
    tag .. " form front pic differs from Normal Forme")
  local formIcon, normalIcon = Pokemon.monIcon(mon), Pokemon.monIconDontHandleDeoxys(mon)
  S.check(formIcon ~= nil and normalIcon ~= nil and formIcon.image ~= normalIcon.image,
    tag .. " form icon differs from Normal Forme")

  if version == "emerald" then
    F.setVar("VAR_LITTLEROOT_INTRO_STATE", 7)
    F.setVar("VAR_LITTLEROOT_TOWN_STATE", 4)
    F.setVar("VAR_ROUTE101_STATE", 3)
    F.setFlag("FLAG_RESCUED_BIRCH", true)
  end
  S.check(F.goTo(game, version == "emerald" and "EM_ROUTE101" or "FR_ROUTE_1", 10, 10, "down"), tag .. " map loaded")

  local function settle()
    for _ = 1, 120 do
      if not (SummaryMenu._slide and SummaryMenu._slide.active) then break end
      U.wait(1)
    end
    U.wait(12)
  end
  SummaryMenu.openMenu(session.party, 1, {})
  settle()
  S.check(S.still(game, tag .. "_01_summary_info_form.png"), tag .. " summary info shot")
  U.tap(game, "right") settle()
  S.check(S.still(game, tag .. "_02_summary_skills_form_stats.png"), tag .. " summary skills shot")
  for _ = 1, 4 do U.tap(game, "b") settle() end
  F.settle(game, 120)

  if not S.check(Bridge.startWild(Runtime._mod, game, { species = deoxys, level = 30 }, { fade = false }) == true,
      tag .. " wild Deoxys battle started") then return S.finish() end
  local Message = require("src.ui.game3.message")
  local reached = false
  for frame = 1, 8000 do
    if not Battle.isActive() then break end
    if Battle._phase == "command" and Ui._mode == "menu" then reached = true break end
    if Message.isOpen() and not Message.isTyping() and frame % 18 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  S.note("battle phase " .. tostring(Battle._phase) .. " mode " .. tostring(Ui._mode) .. " active " .. tostring(Battle.isActive()))
  if S.check(reached, tag .. " battle command menu reached") then
    U.wait(30)
    local player = Ui.battlerPic("player")
    local enemy = Ui.battlerPic("enemy")
    local st = Battle._st
    local pm, em = st.player.mon, st.enemy.mon
    local wantBack = Pokemon.backPic(Pokemon.picSpecies(deoxys, pm.personality), 0, Pokemon.isShiny(pm))
    local wantFront = Pokemon.frontPicDontHandleDeoxys(Pokemon.picSpecies(deoxys, em.personality), 0,
      Pokemon.isShiny(em), em.personality)
    S.check(player ~= nil and wantBack ~= nil and player.image == wantBack.image,
      tag .. " player Deoxys back pic is the game's form")
    S.check(enemy ~= nil and wantFront ~= nil and enemy.image == wantFront.image,
      tag .. " opponent Deoxys front pic is Normal Forme")
    S.check(S.still(game, tag .. "_03_battle_player_form_enemy_normal.png"), tag .. " battle shot")
  end
  S.finish()
end
