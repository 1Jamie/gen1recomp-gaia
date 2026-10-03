local U = require("tests.drivers.util")

return function(game)
  local deadline = love.timer.getTime() + 25
  local ok, err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY") or ""
    assert(identity ~= "" and identity ~= "pokemon-love2d", "isolated native identity required")
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "shot directory required")
    local function wait(n)
      for _ = 1, n do assert(love.timer.getTime() < deadline, "#2642 watchdog"); U.wait(1) end
    end
    local function untilReady(fn, label, limit)
      for _ = 1, limit or 1500 do if fn() then return end; wait(1) end
      error("#2642 did not settle: " .. label)
    end
    untilReady(function() return game.phase == "boot" and game.boot end, "native boot")
    game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 })
    local Runtime = require("src.core.game3.runtime")
    local Party = require("src.core.game3.party")
    local Pokemon = require("src.core.game3.pokemon")
    local Bridge = require("src.core.game3.battle_bridge")
    local Battle = require("src.core.game3.battle")
    local Ui = require("src.core.game3.battle.ui")
    local Anim = require("src.core.game3.battle.anim")
    local Experience = require("src.core.game3.battle.experience")
    local Growth = require("src.ui.game3.stat_growth")
    local Summary = require("src.ui.game3.summary_menu")
    local Version = require("src.core.GameVersion")
    local Schema = require("src.core.game3.save_schema_firered")
    local SaveData = require("src.core.SaveData")
    assert(Version.get() == "emerald", "Emerald READY cache required")
    untilReady(function() return Runtime.getSession() and game.phase == "field" end, "native field")
    local Fade = require("src.ui.game3.fade")
    local function uncovered() return not Fade.isActive() and Fade.t == 0 and not Fade.lockInput end
    untilReady(uncovered, "uncovered new field")
    local session = Runtime.getSession()
    session.party = {}
    assert(Party.giveMon(session, 277, 5), "actual native Treecko gift failed")
    local mon = session.party[1]
    mon.exp = Experience.expForLevel(mon, 6) - 1
    local mapping = { atk = "attack", def = "defense", spe = "speed", spa = "spAtk", spd = "spDef" }
    local function current()
      for short, long in pairs(mapping) do assert(mon[short] == mon[long], "stale native stat alias " .. short) end
    end
    local function skills(name)
      assert(not Battle.isActive(), "summary requires completed battle")
      untilReady(uncovered, "uncovered summary field")
      Summary.openMenu(session.party, 1, { page = 1 })
      untilReady(function() return Summary.isOpen() and not Summary._slide.active end, "Skills")
      wait(8)
      current()
      untilReady(uncovered, "uncovered Skills")
      print(string.format("STATS #2642 %s name=%s level=%s hp=%s/%s attack=%s defense=%s spAtk=%s spDef=%s speed=%s",
        name, tostring(mon.name), tostring(mon.level), tostring(mon.hp), tostring(mon.maxHp),
        tostring(mon.attack), tostring(mon.defense), tostring(mon.spAtk), tostring(mon.spDef), tostring(mon.speed)))
      assert(U.still(game, out .. "/" .. name .. ".png"), "Skills capture failed")
      Summary.close(); wait(8)
    end
    skills("01-treecko-level5-skills")
    for round = 1, 2 do
      local beforeLevel = mon.level
      local beforeStats = {}; for short, long in pairs(mapping) do beforeStats[short] = mon[long] end
      assert(Bridge.startWild(Runtime._mod, game, { species = 129, level = 14, moves = { 150 }, pp = { 40 } },
        { fade = false }), "actual Magikarp battle failed")
      local growthShot, frames = false, 0
      while Battle.isActive() do
        frames = frames + 1; assert(frames < 10000, "battle frame bound")
        if Growth.isOpen() and not growthShot then
          growthShot = true
          assert(Growth._newStats and Growth._oldStats, "production level-up delta missing")
          untilReady(uncovered, "uncovered battle level-up")
          for _, row in ipairs({ { "old", Growth._oldStats }, { "new", Growth._newStats } }) do
            local stats = row[2]
            print(string.format("GROWTH #2642 round=%d page=%s %s maxHp=%s atk=%s def=%s spa=%s spd=%s spe=%s",
              round, tostring(Growth._page), row[1], tostring(stats.maxHp), tostring(stats.atk),
              tostring(stats.def), tostring(stats.spa), tostring(stats.spd), tostring(stats.spe)))
          end
          assert(U.still(game, out .. "/0" .. (round * 2) .. "-battle-levelup-delta.png"), "level-up capture failed")
        end
        if Anim.vm() and Anim.vm():busy() then wait(1)
        else U.tap(game, "a"); wait(3) end
      end
      untilReady(function() return game.phase == "field" end, "battle writeback")
      assert(growthShot and mon.level > beforeLevel, "real battle did not gain a level")
      assert(mon.hp > 0, "real battle did not win")
      current()
      local increased = false
      for short, long in pairs(mapping) do if mon[long] > beforeStats[short] then increased = true end end
      assert(increased, "production canonical stats did not increase")
      skills("0" .. (round * 2 + 1) .. "-treecko-current-skills")
      print("PASS #2642 actual battle " .. round .. " level " .. beforeLevel .. "→" .. mon.level .. " current aliases and Skills")
    end
    assert(game:saveGame() == true, "isolated native save failed")
    local restored = assert(SaveData.load("emerald"))
    for short, long in pairs(mapping) do assert(restored.party[1][short] == mon[long], "native save alias " .. short) end
    assert(Schema.fromSaveTable(restored).party[1].level == mon.level, "native schema level roundtrip")
  end, debug.traceback)
  if not ok then print("FAIL #2642 " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
  while true do coroutine.yield() end
end
