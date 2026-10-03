local U=require('tests.drivers.util')
local Mon=require('src.battle.gen2.Mon')
local Damage=require('src.battle.gen2.Damage')
local SaveData=require('src.core.SaveData')

return function(game)
  local deadline=love.timer.getTime()+25
  local oldWrite,oldOptions,oldPersist=rawget(game,'writeSave'),rawget(game,'writeOptions'),rawget(game,'persistOptions')
  local oldSpeed,oldVolume=game.speedOverride,love.audio.getVolume()
  local ok,err=xpcall(function()
    local identity=os.getenv('POKEPORT_IDENTITY') or ''
    assert(identity~='' and identity~='pokemon-love2d','isolated READY identity required')
    local version=game.save.version
    assert(version=='gold' or version=='silver' or version=='crystal','Gen2 edition required')
    local root=assert(os.getenv('POKEPORT_GEN2_'..version:upper()..'_DATA'),'explicit actual edition dataset required')
    local sourceMoves=assert(loadfile(root..'/moves.lua'))()
    for _,id in ipairs({'SKETCH','NIGHTMARE','PSYCH_UP','MIST','FOCUS_ENERGY'}) do
      assert(sourceMoves[id] and game.data.moves[id] and sourceMoves[id].effect==game.data.moves[id].effect,'actual edition move metadata mismatch '..id)
    end
    local out=assert(os.getenv('POKEPORT_SHOT_DIR'))
    game.writeSave=function() error('H03 unexpected save write') end
    game.writeOptions=game.writeSave;game.persistOptions=game.writeSave
    love.audio.setVolume(0);game.speedOverride=200
    assert(game:logicSpeed()==200,'actual clock did not accelerate')
    local function wait(n)
      for _=1,n do assert(love.timer.getTime()<deadline,'H03 deadline');U.wait(1) end
    end
    local function shot(name)
      assert(U.still(game,out..'/h03-'..version..'-'..name..'.png'),'capture failed')
      assert(love.timer.getTime()<deadline,'H03 capture deadline')
    end
    for _=1,1200 do if game.world and game.world.map and not game.stack:top() then break end;wait(1) end
    local world=assert(game.world);assert(world.map and not game.stack:top(),'READY Gen2 world did not settle')
    local function entry(id) local d=assert(game.data.moves[id]);return {id=id,pp=d.pp,maxPp=d.pp,ppUps=0} end
    local function new(species,ids)
      local moves={};for _,id in ipairs(ids) do moves[#moves+1]=entry(id) end
      return assert(Mon.new(game.data,species,50,{moves=moves,dvs={attack=15,defense=15,speed=15,special=15}}))
    end
    local function menu(screen)
      for _=1,5000 do
        if screen.phase=='menu' and #screen.queue==0 and not screen.anim then return end
        U.tap(game,'a');wait(1)
      end
      error('actual move menu did not settle')
    end
    local function shown(screen,needle,name)
      for _=1,5000 do
        if screen.message and screen.message:find(needle,1,true) then
          for _=1,2000 do
            if not screen:syncTyper() and screen:messageArrowVisible() then shot(name);return end
            wait(1)
          end
          error('actual source dialog did not finish typing '..needle)
        end
        U.tap(game,'a');wait(1)
      end
      error('actual source dialog missing '..needle)
    end
    local function choose(screen,index)
      assert(screen:chooseMenu('fight'));assert(screen:chooseMove(index))
    end
    for _,row in ipairs({{'SKETCH','SMEARGLE','GROWL'},{'NIGHTMARE','GENGAR','SPLASH'},
        {'PSYCH_UP','ALAKAZAM','HARDEN'},{'MIST','VAPOREON','GROWL'},
        {'FOCUS_ENERGY','RATTATA','SPLASH'}}) do
      local id,species,foeMove=unpack(row)
      local ids=id=='NIGHTMARE' and {'HYPNOSIS','NIGHTMARE','SPLASH'}
        or id=='FOCUS_ENERGY' and {'FOCUS_ENERGY','TACKLE'} or {id}
      local player,enemy=new(species,ids),new('SNORLAX',{foeMove})
      game.save.party={player}
      assert(world:startBattle({wild=enemy}),'actual wild battle failed')
      local screen
      for _=1,1200 do
        screen=game.stack:top()
        if screen and screen.screenId=='Gen2BattleState' and screen.battle then break end
        wait(1)
      end
      assert(screen and screen.screenId=='Gen2BattleState' and screen.battle,'actual BattleState required')
      menu(screen)
      local battle=screen.battle
      battle.random=function(n) if n==256 then return 128 elseif n==100 then return 0 end;return n-1 end
      if id=='SKETCH' or id=='PSYCH_UP' then battle.stages.enemy.speed=6 end
      if id=='NIGHTMARE' then
        choose(screen,1);menu(screen)
        assert(enemy.status=='sleep' and enemy.statusTurns>2,'actual Hypnosis did not establish source sleep')
      end
      local slot=id=='NIGHTMARE' and 2 or 1
      local pp,turn=player.moves[slot].pp,battle.turn
      local hp=enemy.hp
      choose(screen,slot)
      assert(battle.turn==turn+1,'named move turn consumed incorrectly')
      if id=='SKETCH' then
        assert(player.moves[1].id=='GROWL' and player.moves[1].pp==game.data.moves.GROWL.pp,'actual prior enemy command was not permanently copied')
        assert(battle:volatile(player).lastMove==nil,'Sketch did not clear last move')
        shown(screen,'SKETCHED','sketch-first-page');U.tap(game,'a');wait(1)
        shown(screen,'GROWL!','sketch-move-page');menu(screen)
      elseif id=='NIGHTMARE' then
        assert(player.moves[slot].pp==pp-1 and battle:volatile(enemy).nightmare,'Nightmare producer/PP missing')
        assert(enemy.hp==hp-math.max(1,math.floor(enemy.maxHp/4)),'actual Nightmare quarter residual missing')
        shown(screen,'NIGHTMARE!','nightmare-started');menu(screen)
        enemy.item='MINT_BERRY';choose(screen,3)
        assert(enemy.status==nil and enemy.item==nil and not battle:volatile(enemy).nightmare,'held status recovery did not clear actual Nightmare')
        shown(screen,'status!','nightmare-held-cure');menu(screen)
      elseif id=='PSYCH_UP' then
        assert(player.moves[slot].pp==pp-1 and battle.stages.player.defense==1 and battle.stages.enemy.defense==1,'actual foe Harden stages were not copied')
        assert(battle.stages.player~=battle.stages.enemy,'stage arrays aliased')
        shown(screen,'copied the stat','psych-up-first-page');U.tap(game,'a');wait(1)
        shown(screen,'changes of','psych-up-target-page');menu(screen)
      elseif id=='MIST' then
        assert(player.moves[slot].pp==pp-1 and battle:volatile(player).mist and battle.stages.player.attack==0,'actual Mist did not block actual Growl')
        shown(screen,'shrouded in MIST!','mist-protected');menu(screen)
        choose(screen,1);shown(screen,'But it failed!','mist-repeated');menu(screen)
      else
        assert(player.moves[slot].pp==pp-1 and battle:volatile(player).focusEnergy,'Focus Energy producer/PP missing')
        shown(screen,'getting pumped!','focus-energy');menu(screen)
        battle.random=function(n) return n==Damage.criticalChance(0) and 1 or 0 end
        choose(screen,2);shown(screen,'A critical hit!','focus-energy-critical');menu(screen)
      end
      battle.random=function() return 0 end
      assert(screen:chooseMenu('run'),'actual RUN missing')
      for _=1,5000 do if not game.stack:top() then break end;U.tap(game,'a');wait(1) end
      assert(not game.stack:top() and world.map,'actual battle did not return to world')
      if id=='SKETCH' then
        assert(player.moves[1].id=='GROWL' and not player.volatile,'cleanup lost permanent Sketch')
        local restored=assert(SaveData.decode(SaveData.encode(game.save)))
        assert(restored.party[1].moves[1].id=='GROWL','actual no-write save encoding lost Sketch')
      end
    end
    print('PASS H03 actual typed named-command pages, move menu, PP/turn, canonical consumers and Sketch persistence '..version)
  end,debug.traceback)
  game.writeSave,game.writeOptions,game.persistOptions=oldWrite,oldOptions,oldPersist
  game.speedOverride=oldSpeed;love.audio.setVolume(oldVolume)
  if not ok then print('FAIL H03 '..tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
