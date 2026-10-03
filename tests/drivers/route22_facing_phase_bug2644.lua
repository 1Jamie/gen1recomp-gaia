local U=require('tests.drivers.util')
local Version=require('src.core.GameVersion')
local TextBox=require('src.render.TextBox')
local SaveData=require('src.core.SaveData')

return function(game)
  local deadline=love.timer.getTime()+25
  local old={}
  for _,key in ipairs({'writeSave','writeOptions','persistOptions'}) do old[key]=rawget(game,key) end
  local writeKeys={'save','saveOptions','saveLiveOptions','writeSlot','writeCartSlot'}
  local previousWrite={}
  for _,key in ipairs(writeKeys) do previousWrite[key]=SaveData[key] end
  local previousVolume=love.audio.getVolume()
  local trackedOw,previousUpdate
  local movementFailure
  local ok,err=xpcall(function()
    assert(Version.generation()==1,'Gen1 edition required')
    local identity=os.getenv('POKEPORT_IDENTITY') or ''
    assert(identity~='' and identity~='pokemon-love2d','isolated READY identity required')
    local out=assert(os.getenv('POKEPORT_SHOT_DIR'),'shot directory required')
    local function blocked() error('unexpected persistent write') end
    for _,key in ipairs({'writeSave','writeOptions','persistOptions'}) do game[key]=blocked end
    for _,key in ipairs(writeKeys) do SaveData[key]=blocked end
    love.audio.setVolume(0)
    local function wait(n)
      for _=1,n do assert(not movementFailure,movementFailure);assert(love.timer.getTime()<deadline,'#2644 deadline');U.wait(1) end
    end
    local function untilReady(fn,limit,label)
      for _=1,limit do if fn() then return end;wait(1) end
      error(label)
    end
    local function shot(name,check)
      check();assert(U.still(game,out..'/'..name..'.png'),'capture failed');check()
      assert(love.timer.getTime()<deadline,'capture deadline')
    end
    game:startNewGame({intro=false})
    game.save.objectToggles=game.save.objectToggles or {}
    for _,n in ipairs({1,2}) do for _,y in ipairs({4,5}) do
      local f=game.save.flags
      f.EVENT_GOT_POKEDEX=true
      f.EVENT_BEAT_BROCK=n==2 or nil
      f.EVENT_BEAT_GIOVANNI=n==2 or nil
      f.EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE=n==2 or nil
      f.EVENT_BEAT_ROUTE22_RIVAL_2ND_BATTLE=nil
      game.save.objectToggles.ROUTE_22={ROUTE22_RIVAL1=false,ROUTE22_RIVAL2=false}
      U.teleport(game,'ROUTE_22',30,y,'left')
      local ow=assert(game.overworld)
      untilReady(function()return game.stack:top()==ow and not ow.transitioning and not ow.runner:isRunning() and not ow.player.moving end,
        400,'actual Route22 field did not settle')
      local label='_Route22RivalBeforeBattleText'..n
      assert(type(game.data.text[label])=='string' and #game.data.text[label]>0,'required imported dialogue missing')
      local sourceObject
      for _,obj in ipairs(ow.map.def.objects) do if obj.index==n then sourceObject=obj end end
      assert(sourceObject and sourceObject.x==25 and sourceObject.y==5,'actual source object missing')
      local observations=0
      trackedOw=ow;previousUpdate=rawget(ow,'update')
      local update=ow.update
      ow.update=function(self,...)
        update(self,...)
        local rival=self:npcByIndex(n)
        if rival and rival.moving and self.runner.pc==2 then
          if self.player.facing~='left' then movementFailure='player turned before approach completed' end
          if rival.facing~='right' then movementFailure='approach left source row/direction' end
          observations=observations+1
        end
      end
      U.hold(game,'left',1)
      untilReady(function()return ow.player.cellX==29 and ow.player.cellY==y and ow.runner:isRunning() end,
        100,'normal player step did not start scene')
      local rival=assert(ow:npcByIndex(n),'selected rival absent')
      assert(ow.player.facing=='left','source initial LEFT missing')
      untilReady(function()return rival.moving and rival.cellX==26 end,100,'actual moving rival did not reach capture position')
      local function moving()
        assert(rival.moving and rival.cellX==26 and rival.cellY==5,'approach capture lost movement phase')
        assert(ow.player.facing=='left' and rival.facing=='right','approach facing mismatch')
        assert(game.stack:top()==ow and ow.runner.pc==2,'dialogue began during approach')
      end
      if y==4 then shot('rival'..n..'-upper-approach-left',moving) end
      untilReady(function()return getmetatable(game.stack:top())==TextBox end,180,'actual prebattle dialogue missing')
      local box=game.stack:top()
      untilReady(function()return box.waiting and #(box.shownSource or {})>0 end,600,'actual dialogue did not type/readably settle')
      local function final()
        assert(game.stack:top()==box and getmetatable(box)==TextBox and box.waiting,'intended readable dialogue lost')
        assert(ow.runner.script[ow.runner.pc][1]=='show_text' and ow.runner.script[ow.runner.pc][2]==label,'wrong dialogue boundary')
        assert(not rival.moving and #ow.scriptMoves==0,'final capture still approaching')
        assert(rival.cellX==(y==4 and 29 or 28) and rival.cellY==5,'final rival position')
        assert(ow.player.facing==(y==4 and 'down' or 'left') and rival.facing==(y==4 and 'up' or 'right'),'final paired turn missing')
        assert(observations>0,'actual moving frames were not observed')
        local beat='EVENT_BEAT_ROUTE22_RIVAL_'..(n==1 and '1ST' or '2ND')..'_BATTLE'
        assert(not game.save.flags[beat],'battle progression changed before battle')
      end
      shot('rival'..n..'-'..(y==4 and 'upper-down-up' or 'lower-left-right')..'-dialogue',final)
      print('PASS #2644 '..Version.get()..' rival'..n..' row'..y..' actual normal step, moving LEFT, final paired turn, readable text; observed='..observations)
      ow.update=previousUpdate;trackedOw=nil;previousUpdate=nil
    end end
    U.teleport(game,'PALLET_TOWN',9,7,'down')
    untilReady(function()return game.stack:top()==game.overworld and not game.overworld.transitioning end,400,'final field return')
    print('PASS #2644 six settled captures, both encounters/rows, no battle or persistent writes')
  end,debug.traceback)
  if trackedOw then trackedOw.update=previousUpdate end
  for _,key in ipairs({'writeSave','writeOptions','persistOptions'}) do game[key]=old[key] end
  for _,key in ipairs(writeKeys) do SaveData[key]=previousWrite[key] end
  love.audio.setVolume(previousVolume)
  if not ok then print('FAIL #2644 '..tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
