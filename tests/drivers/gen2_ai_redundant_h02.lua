local U=require('tests.drivers.util')
local Mon=require('src.battle.gen2.Mon')
local Ai=require('src.battle.gen2.Ai')

return function(game)
  local deadline=love.timer.getTime()+25
  local oldWrite=rawget(game,'writeSave')
  local ok,err=xpcall(function()
    local identity=os.getenv('POKEPORT_IDENTITY') or ''
    assert(identity~='' and identity~='pokemon-love2d','isolated READY identity required')
    local out=assert(os.getenv('POKEPORT_SHOT_DIR'))
    game.writeSave=function() error('H02 unexpected save write') end
    local function wait(n)
      for _=1,n do assert(love.timer.getTime()<deadline,'H02 deadline');U.wait(1) end
    end
    for _=1,1200 do if game.world and game.world.map and not game.stack:top() then break end;wait(1) end
    local world=assert(game.world);assert(world.map and not game.stack:top(),'READY world did not settle')
    local function new(id)
      return assert(Mon.new(game.data,id,30,{dvs={attack=15,defense=3,speed=15,special=5}}))
    end
    local enemy,player=new('NIDORAN_M'),new('NIDORAN_M')
    enemy.moves={{id='ATTRACT',pp=15,maxPp=15},{id='TACKLE',pp=35,maxPp=35}}
    player.moves={{id='SPLASH',pp=40,maxPp=40}}
    game.save.party={player}
    local class=assert(game.data.trainers.classes.WHITNEY)
    assert(world:startBattle({trainer={party={enemy},attributes=class.attributes,class='WHITNEY',name='WHITNEY'}}),'actual battle did not start')
    local screen
    for _=1,1600 do
      screen=game.stack:top()
      if screen and screen.battle and screen.phase=='menu' and #screen.queue==0 and not screen.anim then break end
      if screen and screen.battle then U.tap(game,'a') end;wait(2)
    end
    assert(screen and screen.battle and screen.phase=='menu','actual battle did not reach menu')
    local b=screen.battle;b.random=function() return 0 end
    assert(Ai.SMART.EFFECT_ATTRACT==Ai.SMART.EFFECT_SWAGGER,'SMART source alias changed')
    assert(b:vanillaEnemyMove()=='TACKLE','actual trainer picked same-gender Attract')
    assert(U.still(game,out..'/h02-same-gender-native-battle.png'),'capture failed')
    screen:submit({kind='move',move='SPLASH'})
    local pictured=false
    for _=1,1600 do
      if screen.message and screen.message:upper():find('TACKLE',1,true) then
        local expected=screen.message
        screen:syncTyper()
        while screen.typer and not screen.typer:done() do
          wait(1)
          assert(screen.message==expected,'target message advanced before capture')
        end
        assert(table.concat(screen:messageLines(),' '):upper():find('TACKLE',1,true),'target text is not rendered')
        assert(U.still(game,out..'/h02-trainer-uses-tackle.png'),'capture failed');pictured=true;break
      end
      U.tap(game,'a');wait(2)
    end
    assert(pictured,'actual selected enemy move not shown')
    enemy.moves[1]={id='SWAGGER',pp=15,maxPp=15}
    b:volatile(player).confuseCount=2
    assert(b:vanillaEnemyMove()=='TACKLE','actual trainer picked redundant Swagger')
    b:volatile(player).confuseCount=nil;b:volatile(player).attract=true
    local choose,captured=Ai.choose
    Ai.choose=function(c) captured=c;return choose(c) end
    local success,result=pcall(b.vanillaEnemyMove,b);Ai.choose=choose
    assert(success,result)
    captured.flags=Ai.FLAGS.BASIC
    local _,scores=Ai.choose(captured)
    assert(scores[1]==20,'in-love alone dismissed Swagger')
    print('PASS H02 actual trainer dispatch, rendered selected turn, confused Swagger rejection, in-love Swagger and SMART alias '..game.save.version)
  end,debug.traceback)
  game.writeSave=oldWrite
  if not ok then print('FAIL H02 '..tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
