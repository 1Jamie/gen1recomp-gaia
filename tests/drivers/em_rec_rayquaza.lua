local U = require("tests.drivers.util")
local Rec = require("tests.drivers.em_rec")
local DIR = os.getenv("EM_REC_DIR") or ".bazinga/emerald/rec/rayquaza"

return function(game)
  io.stdout:setvbuf("line")
  Rec.install(game, { dir = DIR, fast = tonumber(os.getenv("POKEPORT_SPEED")) or 200 })
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local Rse = require("src.core.game3.rse.init")
  local Encounters = require("src.core.game3.encounters")
  local Message = require("src.ui.game3.message")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local Commands = require("src.core.game3.battle.commands")
  local PartyMenu = require("src.ui.game3.party_menu")
  local StatGrowth = require("src.ui.game3.stat_growth")
  local Player = require("src.core.game3.player")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  Encounters.onStep = function() return nil end
  local function mv(name) return C.moves.byName["MOVE_" .. name] end

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 80, "")
  local m = session.party[1]
  m.moves = { mv("ICE_BEAM"), mv("SURF"), mv("EARTHQUAKE"), mv("PROTECT") }
  m.pp = { 10, 15, 10, 10 }
  m.maxPp = { 10, 15, 10, 10 }
  m.hp = m.maxHp or m.hp
  Party.giveMon(session, C.species.byName.SPECIES_METAGROSS, 80, "")

  Rse.setFlag("FLAG_DEFEATED_RAYQUAZA", false)
  Rse.setFlag("FLAG_HIDE_SKY_PILLAR_TOP_RAYQUAZA", true)
  Rse.setVar("VAR_SKY_PILLAR_STATE", 2)
  Rse.setVar("VAR_SKY_PILLAR_RAYQUAZA_CRY_DONE", 1)
  local sx, sy = tonumber(os.getenv("EM_REC_X")) or 14, tonumber(os.getenv("EM_REC_Y")) or 11
  Map.load(nil, game, "EM_SKY_PILLAR_TOP", { x = sx, y = sy, facing = "up" })
  local s = Runtime.getSession()
  s.x, s.y, s.facing = sx, sy, "up"
  U.wait(60)
  for _ = 1, 300 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    U.wait(1)
  end

  local last = {}
  Rec.onTickHook = function()
    if not Rec.armed then return end
    local function edge(key, v, label)
      if last[key] ~= v then
        last[key] = v
        Rec.mark(label .. "=" .. tostring(v))
      end
    end
    local T = package.loaded["src.core.game3.battle_transition"]
    edge("transition", T and T.isActive() or false, "transition")
    edge("battle", Battle.isActive(), "battle")
    edge("msg", Message.isOpen(), "msg")
  end

  Rec.arm("sky_pillar_top")
  U.wait(50)
  for _ = 1, 20 do
    if Player.cellY <= 7 then break end
    U.hold(game, "up", 8)
  end
  U.wait(4)
  for _ = 1, 30 do
    if not Player.moving then break end
    U.wait(1)
  end
  print(string.format("[driver] player at %d,%d facing %s", Player.cellX, Player.cellY, tostring(Player.facing)))
  U.wait(30)
  for _ = 1, 10 do
    U.tap(game, "a")
    U.wait(10)
    if (Space.vm and Space.vm:isRunning()) or Battle.isActive() then break end
    U.wait(20)
  end
  for _ = 1, 4000 do
    if Battle.isActive() then break end
    U.wait(1)
  end
  if not Battle.isActive() then
    print("FAIL rayquaza battle did not start")
    Rec.finish()
    love.event.quit(1)
    U.wait(10)
    return
  end
  do
    local st = Battle._st
    local ks = {}
    for k, v in pairs(st.kinds or {}) do if v then ks[#ks + 1] = tostring(k) end end
    print("[driver] kinds " .. table.concat(ks, ",") .. " wild=" .. tostring(st.wild) .. " exp0=" .. tostring(session.party[1].exp))
  end
  local plan = { 2, 1, 1, 1, 1, 1 }
  local function moveUsable(st, slot, id)
    local ok, r = pcall(Commands.moveUsable, st, slot, id)
    return ok and r
  end
  local guard = 0
  while Battle.isActive() and guard < 40000 do
    guard = guard + 1
    local st = Battle._st
    local phase = Battle._phase
    if phase ~= Rec._lastPhase then
      Rec._lastPhase = phase
      local lg = Ui.log and Ui.log() or {}
      local ok, txt = pcall(require("src.core.game3.scripting.text_ir").toAscii, lg[#lg] or "", {})
      print(string.format("[driver] f=%d phase %s log#%d %s", Rec.tick - (Rec.armTick or 0), tostring(phase), #lg, tostring(ok and txt or lg[#lg])))
    end
    if PartyMenu.isOpen and PartyMenu.isOpen() then
      U.tap(game, "b")
      U.wait(10)
    elseif phase == "command" and Ui._mode == "menu" and not Anim.busy() then
      U.wait(20)
      U.tap(game, "a")
      U.wait(6)
    elseif phase == "command" and Ui._mode == "moves" then
      local who = Ui.activeBattler and Ui.activeBattler() or 0
      local slot = plan[((st and st.turn) or 0) + 1] or 1
      if not moveUsable(st, slot, who) then slot = 1 end
      U.wait(12)
      for _ = 1, 6 do
        local cur = (Ui._moveIndex or 1) - 1
        local want = slot - 1
        if cur == want then break end
        local key
        if cur % 2 ~= want % 2 then
          key = (cur % 2 == 0) and "right" or "left"
        else
          key = (cur < want) and "down" or "up"
        end
        U.tap(game, key)
        U.wait(8)
      end
      U.wait(8)
      U.tap(game, "a")
      U.wait(6)
    elseif phase == "command" and (Ui._mode == "selmsg" or Ui._mode == "target") then
      U.tap(game, "a")
      U.wait(6)
    elseif StatGrowth.isOpen() then
      U.wait(40)
      U.tap(game, "a")
      U.wait(4)
    else
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
      if Ui.choiceActive and Ui.choiceActive() then U.tap(game, "b") U.wait(4) end
    end
  end
  Rec.mark("battle_over")
  print("[driver] exp1=" .. tostring(Runtime.getSession().party[1].exp) .. " lv=" .. tostring(Runtime.getSession().party[1].level))
  for _ = 1, 1200 do
    if not (Space.vm and Space.vm:isRunning()) and not Battle.isActive() then break end
    if Message.isOpen() then U.tap(game, "a") end
    U.wait(2)
  end
  U.wait(90)
  print("[driver] FLAG_DEFEATED_RAYQUAZA=" .. tostring(Rse.flag and Rse.flag("FLAG_DEFEATED_RAYQUAZA")))
  Rec.mark("stop")
  Rec.finish()
  love.event.quit(0)
  U.wait(10)
end
