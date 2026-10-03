local U=require('tests.drivers.util')
local Mon=require('src.battle.gen2.Mon')
local Codec=require('src.save_convert.Gen2Save')
local Screens=require('src.ui.Screens')
local Summary=require('src.ui.gen2.SummaryMenu')

return function(game)
  local deadline=love.timer.getTime()+25
  local oldWrite=rawget(game,'writeSave')
  local ok,err=xpcall(function()
    local identity=os.getenv('POKEPORT_IDENTITY') or ''
    assert(identity~='' and identity~='pokemon-love2d','isolated READY identity required')
    local out=assert(os.getenv('POKEPORT_SHOT_DIR'))
    game.writeSave=function() error('H01 unexpected save write') end
    local function wait(n)
      for _=1,n do assert(love.timer.getTime()<deadline,'H01 deadline');U.wait(1) end
    end
    for _=1,1200 do if game.world and game.world.map and not game.stack:top() then break end;wait(1) end
    local world=assert(game.world);assert(world.map and not game.stack:top(),'READY world did not settle')
    local function new(id,a,s)
      return assert(Mon.new(game.data,id,20,{dvs={attack=a,defense=3,speed=s,special=5}}))
    end
    for _,row in ipairs({{'CHANSEY',15,15,'female'},{'PIDGEY',7,15,'female'},{'PIDGEY',8,0,'male'},{'DITTO',15,15,'unknown'}}) do
      local id,a,s,gender=unpack(row)
      local mon=new(id,a,s)
      local menu=Screens.push(game,'Gen2SummaryMenu',{mon=mon})
      wait(8)
      assert(mon.gender==gender,id..' source gender mismatch')
      assert(Summary.at(menu:upperPlacements(),18,0)==(gender=='female' and '♀' or gender=='male' and '♂' or nil),'actual summary glyph mismatch')
      assert(U.still(game,out..'/h01-'..id..'-'..gender..'.png'),'capture failed')
      assert(love.timer.getTime()<deadline,'H01 capture deadline')
      game.stack:pop();wait(3)
    end
    local x=Codec.crosswalks(game.data)
    for _,row in ipairs({{'MACHOP',4,6},{'PIDGEY',8,10},{'VULPIX',12,14}}) do
      local id,a,want=unpack(row)
      local mon=new(id,a,0);mon.shiny=true
      local bytes={};Codec.util.putBoxMon(bytes,0,mon,x,game.save.version=='crystal')
      local decoded=Codec.util.decodeBoxMon(bytes,0,x,game.save.version=='crystal')
      assert(decoded.dvs.attack==want and Mon.vanillaGender(game.data.pokemon[id],decoded.dvs)==mon.gender,'actual export gender mismatch')
    end
    local chansey,enemy=new('CHANSEY',15,15),new('NIDORAN_M',15,15)
    local def=assert(game.data.moves.ATTRACT)
    chansey.moves={{id='ATTRACT',pp=def.pp,maxPp=def.pp}}
    enemy.moves={{id='TACKLE',pp=35,maxPp=35}}
    game.save.party={chansey}
    assert(world:startBattle({wild=enemy}),'actual battle failed to start')
    local screen
    for _=1,1600 do
      screen=game.stack:top()
      if screen and screen.battle and screen.phase=='menu' and #screen.queue==0 and not screen.anim then break end
      if screen and screen.battle then U.tap(game,'a') end;wait(2)
    end
    assert(screen and screen.battle and screen.phase=='menu','actual battle did not reach menu')
    assert(screen:genderSymbol(screen.battle.player)=='♀' and screen:genderSymbol(screen.battle.enemy)=='♂','actual battle HUD glyphs wrong')
    screen:submit({kind='move',move='ATTRACT'})
    local pictured=false
    for _=1,1600 do
      if screen.message and screen.message:lower():find('love',1,true) then
        local expected=screen.message
        screen:syncTyper()
        while screen.typer and not screen.typer:done() do
          wait(1)
          assert(screen.message==expected,'target message advanced before capture')
        end
        assert(table.concat(screen:messageLines(),' '):lower():find('love',1,true),'target text is not rendered')
        assert(U.still(game,out..'/h01-actual-attract-message.png'),'capture failed');pictured=true;break
      end
      U.tap(game,'a');wait(2)
    end
    assert(pictured and screen.battle:volatile(enemy).attract,'actual opposite-gender Attract did not land visibly')
    print('PASS H01 actual summary/HUD/Attract and in-memory SRAM writer '..game.save.version)
  end,debug.traceback)
  game.writeSave=oldWrite
  if not ok then print('FAIL H01 '..tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
