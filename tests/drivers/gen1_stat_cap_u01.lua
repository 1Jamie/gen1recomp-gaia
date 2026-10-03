local U=require("tests.drivers.util")
local BS=require("src.battle.BattleState")
local Pokemon=require("src.pokemon.Pokemon")
local Stats=require("src.pokemon.Stats")
local Damage=require("src.battle.Damage")
local Status=require("src.battle.Status")
local SaveData=require("src.core.SaveData")
return function(game)
  local deadline=love.timer.getTime()+25
  local oldWrite,oldOptions,oldPersist=rawget(game,"writeSave"),rawget(game,"writeOptions"),rawget(game,"persistOptions")
  local oldSave,oldSaveOptions=SaveData.save,SaveData.saveOptions
  local originalSave=game.save
  local volume=love.audio.getVolume()
  local ok,err=xpcall(function()
    local identity=os.getenv("POKEPORT_IDENTITY") or ""
    assert(identity~="" and identity~="pokemon-love2d","isolated READY identity required")
    local version=require("src.core.GameVersion").get()
    assert(version=="red" or version=="blue" or version=="yellow","Gen1 edition required")
    local out=assert(os.getenv("POKEPORT_SHOT_DIR"))
    local function forbidden() error("U01unexpected persistent write") end
    game.writeSave,game.writeOptions,game.persistOptions=forbidden,forbidden,forbidden
    SaveData.save,SaveData.saveOptions=forbidden,forbidden
    love.audio.setVolume(0)
    local function wait(n) for _=1,n do assert(love.timer.getTime()<deadline,"U01deadline");U.wait(1) end end
    game.save=SaveData.newGame();game.save.player.name="RED"
    local mon=Pokemon.new(game.data,"MEWTWO",100,function() return 15 end)
    for k in pairs(mon.statExp) do mon.statExp[k]=65535 end
    mon.stats=Stats.calc(game.data.pokemon.MEWTWO,100,mon.dvs,mon.statExp);mon.hp=mon.stats.hp
    local def=assert(game.data.moves.AMNESIA)
    mon.moves={{id="AMNESIA",pp=def.pp,maxPp=def.pp}}
    game.save.party={mon};game.save.badges={}
    U.teleport(game,"PALLET_TOWN",10,8,"down")
    local battle=BS.newWild(game,"RATTATA",100)
    local splash=assert(game.data.moves.SPLASH)
    battle.enemy.mon.moves={{id="SPLASH",pp=splash.pp,maxPp=splash.pp}}
    battle.enemy.curMoves=battle.enemy.mon.moves
    game.stack:push(battle)
    local function menu()
      for _=1,4000 do
        if game.stack:top()==battle and battle.phase=="menu" and not battle.current and #battle.queue==0 then return end
        U.tap(game,"a");wait(1)
      end
      error("U01battle menu did not settle")
    end
    local function message(pattern,name)
      for _=1,4000 do
        local current=battle.current
        if current and current.text and current.text:find(pattern,1,true) then
          if battle.msgWaiting then U.tap(game,"a") end
          if battle.charIndex>=battle.total and not battle.scrollPx then
            assert(U.still(game,out.."/u01-"..version.."-"..name..".png"),"capture failed")
            return
          end
          wait(1)
        else U.tap(game,"a");wait(1) end
      end
      error("U01target text never rendered "..pattern)
    end
    local function amnesia()
      assert(battle.phase=="menu","settled battle menu required")
      U.tap(game,"a");wait(1)
      assert(battle.phase=="moveSelect","normal FIGHT input failed")
      U.tap(game,"a");wait(1)
    end
    menu();assert(battle.player.curStats.special==406,"actual maxDV/statEXP Mewtwo special")
    amnesia();message("greatly rose!","01-successful-amnesia");menu()
    amnesia();menu()
    local function effective() return Status.applyPenalty(battle.player,"special",Damage.applyBadgeBoost(battle.player,"special",Stats.applyStage(battle.player.curStats.special,battle.player.stages.special or 0))) end
    assert(battle.player.stages.special==4 and effective()==999,"two normal Amnesia turns did not reach999")
    amnesia();message("Nothing happened!","02-capped-amnesia")
    assert(battle.player.stages.special==5 and effective()==999,"source single-decrement cap rollback missing")
    menu();assert(battle.player.stages.special==5 and not battle.animPlaying,"failed Amnesia did not settle")
    assert(U.still(game,out.."/u01-"..version.."-03-settled-after-cap.png"),"capture failed")
    print("PASS U01 actual three Amnesia turns; canonical406→999; third failure+5stage; readable messages and settled menu",version)
  end,debug.traceback)
  game.writeSave,game.writeOptions,game.persistOptions=oldWrite,oldOptions,oldPersist
  SaveData.save,SaveData.saveOptions=oldSave,oldSaveOptions
  game.save=originalSave
  love.audio.setVolume(volume)
  if not ok then print("FAIL U01 "..tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
