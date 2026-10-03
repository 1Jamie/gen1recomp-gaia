local U=require('tests.drivers.util')
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local SaveData=require('src.core.SaveData')
local Version=require('src.core.GameVersion')

return function(game)
  local deadline=love.timer.getTime()+25
  local old={}
  for _,k in ipairs({'writeSave','writeOptions','persistOptions'}) do old[k]=rawget(game,k) end
  local keys={'save','saveOptions','saveLiveOptions','writeSlot','writeCartSlot'}
  local writers={}
  for _,k in ipairs(keys) do writers[k]=SaveData[k] end
  local volume=love.audio.getVolume()
  local observationFailure
  local ok,err=xpcall(function()
    assert(Version.generation()==1,'Gen1 required')
    local identity=os.getenv('POKEPORT_IDENTITY') or ''
    assert(identity~='' and identity~='pokemon-love2d','isolated READY identity required')
    local out=assert(os.getenv('POKEPORT_SHOT_DIR'),'shot directory required')
    local function forbidden() error('#2645 unexpected persistent write') end
    for _,k in ipairs({'writeSave','writeOptions','persistOptions'}) do game[k]=forbidden end
    for _,k in ipairs(keys) do SaveData[k]=forbidden end
    love.audio.setVolume(0)
    local function wait(n)
      for _=1,n do
        assert(not observationFailure,observationFailure)
        assert(love.timer.getTime()<deadline,'#2645 deadline')
        U.wait(1)
      end
    end
    local function settle(fn,label)
      for _=1,1600 do if fn() then return end;wait(1) end
      error('#2645 '..label)
    end
    local function fullyTyped(b)
      local row=b.shown and b.shown[#b.shown]
      return b.current and row and b.codes and #row==#b.codes and b.lineIndex==#b.lines
        and b.total and b.total>0 and b.charIndex>=b.total and not b.scrollPx and not b.msgWaiting
    end
    local function move(id)
      local def=assert(game.data.moves[id],'required imported move '..id)
      return {id=id,pp=def.pp,maxPp=def.pp}
    end
    local used='used '..assert(game.data.moves.SOLARBEAM).name
    game:startNewGame({intro=false})
    game.save.options.animations=false;game.save.options.textSpeed=1
    do
      U.teleport(game,'PALLET_TOWN',9,7,'down')
      local player=Pokemon.new(game.data,'MEWTWO',70)
      player.moves={move('SOLARBEAM')}
      game.save.party={player}
      local battle=Battle.newWild(game,'MEWTWO',70)
      battle.enemy.mon.moves={move('SOLARBEAM')}
      battle.enemy.curMoves=battle.enemy.mon.moves
      battle.rng=function(a)return a or 0 end
      local hp={player=battle.player.mon.hp,enemy=battle.enemy.mon.hp}
      local seenUsed={player=0,enemy=0}
      local seenCharge={player=0,enemy=0}
      local seenRows={}
      local function rowSide(row)
        return row.text:find('Enemy '..battle.enemy.name,1,true) and 'enemy' or 'player'
      end
      local update=battle.update
      battle.update=function(self,...)
        update(self,...)
        local row=self.current
        if row and row.text and not seenRows[row] then
          seenRows[row]=true
          local side=rowSide(row)
          local user=side=='player' and self.player or self.enemy
          if row.text:find(used,1,true) then
            seenUsed[side]=seenUsed[side]+1
            if user.charging then observationFailure='used SolarBeam page reached consumer during charge' end
          end
          if row.text:find('took in sunlight',1,true) then seenCharge[side]=seenCharge[side]+1 end
        end
      end
      game.stack:push(battle)
      local function advanceUntil(fn,label)
        for _=1,1600 do
          if fn() then return end
          if battle.current and not battle.current.auto and fullyTyped(battle) then U.tap(game,'a') end
          wait(1)
        end
        error(label)
      end
      advanceUntil(function()return battle.phase=='menu' end,'actual battle intro/menu did not settle')
      U.tap(game,'a')
      settle(function()return battle.phase=='moveSelect' end,'actual move list missing')
      U.tap(game,'a')
      local captured={}
      for _,stage in ipairs({'charge','release'}) do for _=1,2 do
        local fragment=stage=='charge' and 'took in sunlight' or used
        advanceUntil(function()
          return battle.current and not captured[battle.current] and battle.current.text:find(fragment,1,true) and fullyTyped(battle)
        end,'actual '..stage..' page did not settle')
        local row=battle.current
        local side=rowSide(row)
        local user=side=='player' and battle.player or battle.enemy
        local function check()
          assert(game.stack:top()==battle and battle.current==row and fullyTyped(battle),'capture lost intended readable page')
          assert(row.text:find(fragment,1,true),'wrong stage page')
          assert(seenCharge[side]==1,'charge page count')
          if stage=='charge' then
            assert(user.charging and seenUsed.player==0 and seenUsed.enemy==0,'charge phase announced attack/lost state')
            assert(battle.player.mon.hp==hp.player and battle.enemy.mon.hp==hp.enemy,'charge caused damage')
          else assert(not user.charging and seenUsed[side]==1,'release state/page count') end
        end
        check();assert(U.still(game,out..'/'..side..'-'..stage..'.png'),'capture failed');check()
        captured[row]=true
        if not row.auto then U.tap(game,'a') else wait(1) end
      end end
      advanceUntil(function()return battle.phase=='menu' and not battle.player.charging and not battle.enemy.charging end,'release turn did not complete')
      for _,side in ipairs({'player','enemy'}) do
        local mon=battle[side].mon
        assert(mon.hp<hp[side] and mon.hp>0,'normal release damage/survival missing')
        assert(seenUsed[side]==1 and seenCharge[side]==1,'both-turn source text count')
      end
      print('PASS #2645 '..Version.get()..' actual normal move selection, both sides charge sunlight only, release announcement once, damage after release')
    end
    U.teleport(game,'PALLET_TOWN',9,7,'down')
    settle(function()return game.stack:top()==game.overworld and not game.overworld.transitioning end,'final field did not settle')
    print('PASS #2645 four settled text captures, both sides, animations-off fixture and no persistent writes')
  end,debug.traceback)
  for _,k in ipairs({'writeSave','writeOptions','persistOptions'}) do game[k]=old[k] end
  for _,k in ipairs(keys) do SaveData[k]=writers[k] end
  love.audio.setVolume(volume)
  if not ok then print('FAIL #2645 '..tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
