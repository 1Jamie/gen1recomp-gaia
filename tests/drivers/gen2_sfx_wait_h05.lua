local U=require('tests.drivers.util')
local Sound=require('src.core.Sound')
local Mon=require('src.battle.gen2.Mon')

return function(game)
  local deadline=love.timer.getTime()+25
  local oldPlay,oldStop=Sound.play,Sound.stop
  local oldWrite,oldOptions,oldPersist=rawget(game,'writeSave'),rawget(game,'writeOptions'),rawget(game,'persistOptions')
  local oldSpeed,oldDriverSpeed=game.speedOverride,game.driverSpeed
  local oldUpdateRaw,oldUpdate=rawget(game,"update"),game.update
  local oldVolume=love.audio.getVolume()
  local records,stops={},{ }
  local ok,err=xpcall(function()
    local identity=os.getenv('POKEPORT_IDENTITY') or ''
    assert(identity~='' and identity~='pokemon-love2d','isolated READY identity required')
    local out=assert(os.getenv('POKEPORT_SHOT_DIR'))
    game.driverSpeed=1
    game.update=function(self) return oldUpdate(self,love.timer.getDelta()) end
    game.writeSave=function() error('H05 unexpected save write') end
    game.writeOptions=game.writeSave;game.persistOptions=game.writeSave
    love.audio.setVolume(0)
    local function wait(n)
      for _=1,n do assert(love.timer.getTime()<deadline,'H05 deadline');U.wait(1) end
    end
    for _=1,1200 do if game.world and game.world.map and not game.stack:top() then break end;wait(1) end
    local world=assert(game.world);assert(world.map and not game.stack:top(),'READY Gen2 world did not settle')
    assert(game.save.version=='gold' or game.save.version=='silver' or game.save.version=='crystal','Gen2 edition required')
    local function ready(id)
      for _=1,1800 do
        local top=game.stack:top()
        if top and top.screenId==id then return top end
        wait(1)
      end
      error('actual screen did not settle '..id)
    end
    local function shot(name)
      assert(U.still(game,out..'/h05-'..game.save.version..'-'..name..'.png'),'capture failed')
      assert(love.timer.getTime()<deadline,'H05 capture deadline')
    end
    Sound.play=function(data,name)
      local key=Sound.resolve(data,name)
      local rows=records[key] or {};records[key]=rows
      local previous=rows[#rows]
      local premature=previous and previous.src:isPlaying() or false
      local src=oldPlay(data,name)
      if src then rows[#rows+1]={src=src,time=love.timer.getTime(),duration=src:getDuration()/src:getPitch(),premature=premature} end
      return src
    end
    Sound.stop=function(name)
      local rows=records[name];local row=rows and rows[#rows]
      stops[#stops+1]={name=name,playing=row and row.src:isPlaying() or false,time=love.timer.getTime()}
      return oldStop(name)
    end
    local function new(id)
      return assert(Mon.new(game.data,id,20,{dvs={attack=15,defense=15,speed=15,special=15}}))
    end
    game.save.party={new('CYNDAQUIL'),new('PIDGEY')}
    game.speedOverride=200
    assert(game:logicSpeed()==200,'actual clock did not accelerate')
    local cue='Sfx_SwitchPokemon'
    local function doubleBeep(menu,base,label)
      local rows=assert(records[cue]);local first=assert(rows[base+1],'first actual Source missing')
      assert(first.duration>0 and #rows==base+1 and menu.repeatSfx,'first beep/pending wait missing')
      assert(first.src:isPlaying(),'first beep finished before capture')
      shot(label..'-first-source-held')
      for _=1,12000 do
        if #rows>=base+2 then break end
        if first.src:isPlaying() then assert(menu.repeatSfx,'menu released under real Source') end
        wait(1)
      end
      local second=assert(rows[base+2],'second actual Source never started')
      assert(#rows==base+2 and not second.premature,'second beep truncated first')
      assert(second.time-first.time>=first.duration-.02,'second beep preceded actual duration')
      shot(label..'-second-source')
      for _=1,12000 do if not second.src:isPlaying() then break end;wait(1) end
      assert(not second.src:isPlaying(),'second Source did not finish')
    end
    game:openStartMenuItem('pokemon')
    local party=ready('Gen2PartyMenu');wait(4)
    party:beginSwitch(1)
    U.tap(game,'down');wait(2)
    local base=records[cue] and #records[cue] or 0
    U.tap(game,'a')
    doubleBeep(party,base,'party-swap')
    game.stack:pop();wait(8)
    game.save.inventory.POTION=1;game.save.inventory.ANTIDOTE=1
    game:openStartMenuItem('pack')
    local pack=ready('Gen2PackMenu');wait(4)
    for _=1,4 do if pack:pocket().id=='ITEM' then break end;pack:switchPocket(1) end
    assert(pack:pocket().id=='ITEM' and #pack.rows>=2,'actual Item pocket missing fixture')
    pack.index=1
    U.tap(game,'select');wait(2)
    assert(pack.switching==1,'actual SELECT did not arm swap')
    U.tap(game,'down');wait(2)
    base=records[cue] and #records[cue] or 0
    U.tap(game,'a')
    doubleBeep(pack,base,'pack-swap')
    game.stack:pop();wait(8)
    local player,enemy=new('CYNDAQUIL'),new('RATTATA')
    player.moves={{id='TACKLE',pp=35,maxPp=35}};enemy.moves={{id='TACKLE',pp=35,maxPp=35}}
    game.save.party={player};game.save.inventory.MASTER_BALL=1
    assert(world:startBattle({wild=enemy}),'actual wild battle failed')
    local screen
    for _=1,2500 do
      screen=game.stack:top()
      if screen and screen.battle and screen.phase=='menu' and #screen.queue==0 and not screen.anim then break end
      if screen and screen.battle then U.tap(game,'a') end;wait(2)
    end
    assert(screen and screen.battle and screen.phase=='menu','actual battle menu not ready')
    screen:useItem('MASTER_BALL')
    local caught
    for _=1,5000 do
      local rows=records.Sfx_CaughtMon
      if screen.waitSfx=='Sfx_CaughtMon' and rows and rows[#rows].src:isPlaying() then caught=rows[#rows];break end
      U.tap(game,'a');wait(2)
    end
    assert(caught and screen.message and screen.message:find('caught',1,true),'actual capture message/Source missing')
    for _=1,1000 do if not screen:syncTyper() then break end;wait(1) end
    assert(not screen:syncTyper() and screen.waitSfx=='Sfx_CaughtMon' and caught.src:isPlaying(),'capture typing/readiness did not settle under Source')
    shot('capture-jingle-dialog-held')
    for _=1,18000 do
      if not screen.waitSfx then break end
      if caught.src:isPlaying() then assert(screen.message and screen.message:find('caught',1,true),'dialog advanced under real jingle') end
      U.tap(game,'a');wait(1)
    end
    assert(not screen.waitSfx and not caught.src:isPlaying(),'actual jingle wait did not release naturally')
    for _,row in ipairs(stops) do assert(row.name~='Sfx_CaughtMon' or not row.playing,'battle prematurely stopped real capture Source') end
    shot('capture-jingle-completed')
    print('PASS H05 muted actual Sources, party/pack double-beep and typed capture wait '..game.save.version)
  end,debug.traceback)
  Sound.play,Sound.stop=oldPlay,oldStop
  game.writeSave,game.writeOptions,game.persistOptions=oldWrite,oldOptions,oldPersist
  game.speedOverride,game.driverSpeed=oldSpeed,oldDriverSpeed
  game.update=oldUpdateRaw
  love.audio.setVolume(oldVolume)
  if not ok then print('FAIL H05 '..tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
