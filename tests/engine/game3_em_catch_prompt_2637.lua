package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = require("tests.love_stub")
local T = require("tests.harness")
local Battle = require("src.core.game3.battle.init")
local Ui = require("src.core.game3.battle.ui")
local Dex = require("src.ui.game3.rse.pokedex")
local Pokemon = require("src.core.game3.pokemon")
local Text = require("src.core.game3.battle.battle_text")
local Pal = require("src.core.game3.pal_fade")
local Chrome = require("src.ui.game3.battle_chrome")
local Bg = require("src.core.game3.battle.bg")
Text.get = function(_, args) return args and args.opponentMon1 or "caught" end
Pokemon.name = function() return "WURMPLE" end
Pokemon.speciesFromNational = function() return 290 end
Pokemon.picSpecies = function(sp) return sp end
local shinyImage, normalImage = {}, {}
Pokemon.frontPic = function(_, _, shiny) return { image = shiny and shinyImage or normalImage } end
local dexOpts, answer, namingOpts, gave
Dex.showCaughtMon = function(_, opts) dexOpts = opts end
Ui.askYesNo = function(_, cb) answer = cb end
package.loaded["src.ui.game3.naming"] = {
  open = function(opts) namingOpts = opts end,
  isOpen = function() return namingOpts ~= nil end,
  monTitle = function(name) return name end,
}
package.loaded["src.core.game3.battle.catching"] = {
  givePending = function(_, res) gave = res.mon; res.pending = nil end,
}
local Storage = require("src.core.game3.storage")
Storage.pcTransferMessage = function() return "transfer" end
local function begin(version, first, location)
  dexOpts, answer, namingOpts, gave = nil, nil, nil, nil
  Ui.reset({ headless = false })
  local mon = { species = 290, name = "WURMPLE", personality = 0x10001, otId = 123, otSecretId = 0 }
  local enemyMon = { species = 290, name = "WURMPLE", personality = 0x10001, otId = 0, otSecretId = 0 }
  local session = { version = version, party = {}, flags = {}, vars = {} }
  package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
  Battle._active, Battle._headless = true, false
  Battle._st = { session = session, enemy = { mon = enemyMon } }
  local res = { mon = mon, firstTimeCaught = first, location = location or "party", pending = location == "pc" }
  Battle.startPostCatchFlow(res)
  return mon, res
end
local function leaveDex()
  local sprite = { img = normalImage, x = 92, y = 80, x2 = 0, y2 = 0 }
  local s = { pal = Pal.new(), caught = { dexNum = 265, personality = dexOpts.personality,
    otId = dexOpts.otId, otSecretId = dexOpts.otSecretId, shiny = dexOpts.shiny,
    mon = sprite, onDone = dexOpts.onDone } }
  Dex.Host._s = s
  Dex.tasks.caughtExit(s)
  T.eq(Dex.Host._s, nil, "dex fullscreen state released")
  T.check(Ui._caughtDexScene and Ui._caughtDexScene.sprite == sprite, "same caught sprite retained across callback")
  T.eq(sprite.img, shinyImage, "caught exit reloads shiny sprite palette from mon identity")
  T.eq(Battle._phase, "catch_dex_return", "background return fade owns phase before question")
  T.eq(answer, nil, "nickname input waits for BG return fade")
  T.eq(Ui._caughtDexScene and Ui._caughtDexScene.pal.fade.mask, 0xFFFF, "Emerald fades BG palettes only")
  T.eq(Ui._caughtDexScene and Ui._caughtDexScene.pal.slots[16].y, 0, "Emerald retained OBJ palette remains visible")
  Battle._headless = true
  for _ = 1, 60 do Battle.update(1 / 60, {}) end
  Battle._headless = false
  T.eq(Battle._phase, "catch_nickname_prompt", "battle dispatch reaches nickname question after fade")
  T.eq(sprite.x, 120, "retained sprite reaches Emerald x120")
  T.eq(sprite.y, 80, "retained sprite reaches Emerald y80")
  T.eq(Ui._caughtDexScene and Ui._caughtDexScene.personality, 0x10001, "handoff preserves personality")
  T.eq(Ui._caughtDexScene and Ui._caughtDexScene.otId, 0, "dex retains target OT instead of newly assigned caught OT")
  return sprite
end
local mon = begin("emerald", true)
local sprite = leaveDex()
local drewBg, drewPanel, draws, normalBattle = 0, 0, {}, 0
Chrome.drawPostDexBg = function() drewBg = drewBg + 1 end
Chrome.drawPanel = function(mode) if mode == "none" then drewPanel = drewPanel + 1 end end
Bg.sheetKey = function() return "grass" end
Bg.draw = function() normalBattle = normalBattle + 1 end
love.graphics.draw = function(img, x, y) draws[#draws + 1] = { img, x, y } end
Ui.draw()
T.eq(drewBg, 1, "question draws ROM post-dex BG3 screen")
T.eq(drewPanel, 1, "question draws battle textbox")
T.eq(normalBattle, 0, "question does not draw normal battlefield")
T.eq(draws[1] and draws[1][1], shinyImage, "question draws retained mon rather than captured battler")
T.eq(draws[1] and draws[1][2], 120, "question composite uses Emerald center")
answer(true)
T.eq(Ui._caughtDexScene, nil, "Yes releases retained presentation before fullscreen naming")
T.eq(namingOpts.species, 290, "Yes names caught species")
T.eq(namingOpts.personality, 0x10001, "Yes passes caught personality")
namingOpts.onDone("BUG")
T.eq(mon.nickname, "BUG", "naming completion writes caught mon nickname")
T.eq(Battle._phase, "ending", "party nickname completion ends capture")
begin("emerald", true)
leaveDex()
answer(false)
T.eq(Ui._caughtDexScene, nil, "No clears retained presentation")
T.eq(Battle._phase, "ending", "No completes party capture")
local pcMon = begin("emerald", true, "pc")
leaveDex()
answer(true)
T.eq(namingOpts.sentToPc, true, "PC capture preserves naming destination")
namingOpts.onDone("PCBUG")
T.eq(gave, pcMon, "PC completion gives the same caught mon")
T.eq(pcMon.nickname, "PCBUG", "PC destination retains nickname")
local noPcMon = begin("emerald", true, "pc")
leaveDex()
answer(false)
T.eq(gave, noPcMon, "PC No gives the same caught mon")
T.eq(Battle._phase, "catch_pc_msg", "PC No preserves transfer message phase")
local canceledMon = begin("emerald", true)
leaveDex()
answer(true)
local staleName = namingOpts.onDone
Battle.reset()
staleName("STALE")
T.eq(canceledMon.nickname, nil, "reset ignores stale naming completion")
begin("emerald", true)
local stale = dexOpts.onDone
Battle.reset()
stale({ sprite = sprite })
T.eq(Ui._caughtDexScene, nil, "reset rejects a stale dex callback")
T.eq(Battle._rseDex, nil, "reset clears dex ownership")
begin("emerald", true)
leaveDex()
Battle._st = nil
Battle.abort("run")
T.eq(Ui._caughtDexScene, nil, "abort clears retained presentation")
answer(true)
T.eq(namingOpts, nil, "aborted question cannot open naming")
begin("emerald", false)
T.eq(dexOpts, nil, "repeat capture skips dex")
T.eq(Ui._caughtDexScene, nil, "repeat capture keeps ordinary battle scene")
T.eq(Battle._phase, "catch_nickname_prompt", "repeat capture directly asks nickname")
answer(false)
for _, version in ipairs({ "emerald", "firered", "leafgreen" }) do
  local registration
  package.loaded["src.ui.game3.pokedex"] = { showRegistration = function(_, opts) registration = opts end }
  for _, first in ipairs({ true, false }) do
    for _, yes in ipairs({ true, false }) do
      for _, location in ipairs({ "party", "pc" }) do
        registration = nil
        local label = version .. " " .. tostring(first) .. " " .. tostring(yes) .. " " .. location
        local caught = begin(version, first, location)
        if first then
          if version == "emerald" then leaveDex() else
            T.check(registration ~= nil, label .. " registers new capture")
            registration.onDone()
            local c = Ui._caughtDexScene
            T.check(c and c.sprite.img == shinyImage, label .. " creates target shiny front sprite")
            T.eq(c and c.otId, 0, label .. " keeps enemy OT")
            T.eq(c and c.personality, 0x10001, label .. " keeps enemy personality")
            T.eq(c and c.pal.fade.mask, 0x1FFFF, label .. " BG and OBJ0 fade mask")
            if c then c.pal:updateFade() end
            T.eq(c and c.pal.slots[16].y, 16, label .. " caught OBJ0 fades from black")
            T.eq(answer, nil, label .. " input waits for return fade")
            Battle._headless = true
            for _ = 1, 60 do Battle.update(1 / 60, {}) end
            Battle._headless = false
          end
          local c = Ui._caughtDexScene
          T.eq(c and c.sprite.x, 120, label .. " caught center X")
          T.eq(c and c.sprite.y, version == "emerald" and 80 or 64, label .. " family center Y")
          drewBg, normalBattle, draws = 0, 0, {}
          Ui.draw()
          T.eq(drewBg, 1, label .. " draws ROM second screen")
          T.eq(normalBattle, 0, label .. " excludes ordinary battlefield")
          T.eq(draws[1] and draws[1][1], shinyImage, label .. " draws caught sprite")
        else
          T.eq(registration, nil, label .. " repeat skips FRLG registration")
          T.eq(dexOpts, nil, label .. " repeat skips RSE registration")
          T.eq(Ui._caughtDexScene, nil, label .. " repeat retains ordinary scene")
        end
        T.eq(Battle._phase, "catch_nickname_prompt", label .. " reaches question")
        answer(yes)
        if yes then
          T.eq(Ui._caughtDexScene, nil, label .. " naming resets sprites")
          T.eq(namingOpts.sentToPc, location == "pc", label .. " naming destination")
          namingOpts.onDone("NAMED")
          T.eq(caught.nickname, "NAMED", label .. " stores nickname")
          T.eq(Ui._caughtDexScene, nil, label .. " naming return does not resurrect scene")
        elseif location == "pc" then
          T.eq(Ui._caughtDexScene ~= nil, first, label .. " PC No keeps first-capture scene")
          T.eq(Battle._phase, "catch_pc_msg", label .. " PC message phase")
          if first then
            drewBg, normalBattle, draws = 0, 0, {}
            Ui.draw()
            T.eq(drewBg, 1, label .. " PC message draws right screen")
            T.eq(normalBattle, 0, label .. " PC message excludes ordinary battlefield")
            T.eq(draws[1] and draws[1][3], version == "emerald" and 80 or 64, label .. " PC message center Y")
          end
        else T.eq(Ui._caughtDexScene, nil, label .. " party terminal clears scene") end
        if location == "pc" then T.eq(gave, caught, label .. " gives same pending mon") end
        local staleAnswer = answer
        Battle.reset()
        T.eq(Ui._caughtDexScene, nil, label .. " reset clears scene")
        namingOpts = nil
        staleAnswer(true)
        T.eq(namingOpts, nil, label .. " stale question cannot reopen naming")
      end
    end
  end
  begin(version, true)
  local staleRegistration = version == "emerald" and dexOpts.onDone or registration.onDone
  Battle.reset()
  staleRegistration({ sprite = sprite })
  T.eq(Ui._caughtDexScene, nil, version .. " stale registration cannot restore scene")
  begin(version, true)
  if version == "emerald" then leaveDex() else
    registration.onDone()
    Battle._headless = true
    for _ = 1, 60 do Battle.update(1 / 60, {}) end
    Battle._headless = false
  end
  local abortedAnswer = answer
  Battle._st = nil
  Battle.abort("run")
  T.eq(Ui._caughtDexScene, nil, version .. " abort clears scene")
  abortedAnswer(true)
  T.eq(namingOpts, nil, version .. " aborted question stays closed")
end
T.finish("game3_em_catch_prompt_2637")
