local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("fr_roamer_fixed_pid_2882", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/fr_roamer_fixed_pid_2882")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local Ui = require("src.core.game3.battle.ui")
  local Party = require("src.core.game3.party")
  local Roamer = require("src.core.game3.roamer")
  local session = Runtime.getSession()
  local C = require("src.core.game3.constants").of(session.version)
  session.party = {}
  Party.giveMon(session, C:require("species", "SPECIES_CHARIZARD"), 60)
  if not S.check(F.goTo(game, "FR_ROUTE_1", 10, 10, "down"), "route 1 loaded") then return S.finish() end

  if not S.check(Roamer.init(session, 1), "InitRoamer ran") then return S.finish() end
  local r = session.roamer
  r.map = "FR_ROUTE_1"
  local pid = r.personality
  local ivs = Roamer.instanceIvs(r.ivs, true)
  S.note(string.format("roamer species=%d pid=%08x hp=%d", r.species, pid, r.hp))

  local function encounter(tag)
    local enc
    for _ = 1, 64 do
      enc = Roamer.tryEncounter(session, session.map, "land")
      if enc then break end
    end
    if not S.check(enc ~= nil, tag .. " roamer encounter rolled") then return nil end
    if not S.check(Bridge.startWild(Runtime._mod, game, enc, { fade = false }) == true, tag .. " battle started") then
      return nil
    end
    for i = 1, 3000 do
      if Battle._phase == "command" and Ui._mode == "menu" then break end
      if Battle._phase ~= "command" and i % 20 == 0 then U.tap(game, "a") end
      U.wait(1)
    end
    S.check(Battle._phase == "command", tag .. " reached the command menu")
    return Battle.getState()
  end

  local function same(a, b)
    for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
      if a[k] ~= b[k] then return false end
    end
    return true
  end

  local st = encounter("first")
  if not st then return S.finish() end
  local m = st.enemy.mon
  S.check(m.species == r.species, "first battle foe is the roamer species")
  S.check(m.personality == pid, string.format("first battle personality %08x is the roamer's", m.personality or -1))
  S.check(same(m.ivs, ivs), "first battle IVs are the roamer's")
  S.still(game, "2882_01_first_roamer_battle.png")
  local hurt = m.maxHp - 25
  m.hp = hurt
  st.enemy.status, m.status = "PAR", "PAR"
  Battle.abort("run")
  U.wait(60)
  F.settle(game, 300)
  S.check(r.active, "roamer stays active after the player runs")
  S.check(r.hp == hurt, "roamer HP " .. tostring(r.hp) .. " saved after the first battle")
  S.check(r.status == Roamer.statusWord(session, "PAR"), "roamer paralysis saved after the first battle")
  r.map = session.map

  st = encounter("second")
  if not st then return S.finish() end
  m = st.enemy.mon
  S.check(m.personality == pid, string.format("second battle personality %08x is unchanged", m.personality or -1))
  S.check(same(m.ivs, ivs), "second battle IVs are unchanged")
  S.check(m.hp == hurt, "second battle starts at the saved HP " .. tostring(m.hp))
  S.check(st.enemy.status == "PAR", "second battle starts paralyzed")
  S.still(game, "2882_02_second_roamer_battle_damaged.png")
  Battle.abort("run")
  U.wait(60)
  return S.finish()
end
