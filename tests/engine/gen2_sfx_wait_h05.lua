package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
love.audio=love.audio or {}
local GameVersion=require('src.core.GameVersion')
local Game2=require('src.core.Game2')
local Sound=require('src.core.Sound')
local ChipAudio=require('src.core.ChipAudio')
local Wait=require('src.ui.gen2.WaitPlaySFX')
local BattleState=require('src.ui.gen2.BattleState')
local Party=require('src.ui.gen2.PartyMenu')
local Pack=require('src.ui.gen2.PackMenu')
local Pc=require('src.ui.gen2.ItemPcMenu')
local Summary=require('src.ui.gen2.SummaryMenu')
local checks,failures=0,0
local function eq(got,want,name)
  checks=checks+1
  if got~=want then failures=failures+1;if failures<=25 then print('FAIL '..name..' got='..tostring(got)..' want='..tostring(want)) end end
end
local now,created=0,{}
local function source(name)
  local s={duration=.5,pitch=1,plays={},stops={}}
  function s:getDuration() if self.invalidDuration then return self.invalidDuration end;return self.duration end
  function s:getPitch() return self.pitch end
  function s:setPitch(p) self.pitch=p end
  function s:setVolume() end
  function s:play() self.started=now;self.stopped=false;self.plays[#self.plays+1]=now end
  function s:stop() self.stopped=true;self.stops[#self.stops+1]=now end
  function s:isPlaying() return self.started and not self.stopped and (self.stuck or now-self.started<self.duration/self.pitch) end
  created[name]=s;return s
end
local realNew,realAudioNew=ChipAudio.newSfx,love.audio.newSource
ChipAudio.newSfx=function(_,name) return source(name) end
love.audio.newSource=function(name) return source(name) end
local function game(speed)
  return setmetatable({options={speed=speed},stack={states={}},input={wasPressed=function() return false end}},Game2)
end
local step=Wait.step or function() return 1 end
eq(step(nil),1,'missing game step')
eq(step({logicSpeed=7}),1,'noncallable speed step')
for _,v in ipairs({false,'20',0,-2,.5,0/0,math.huge}) do eq(step({logicSpeed=function() return v end}),1,'invalid speed fallback '..tostring(v)) end
eq(step({logicSpeed=function() return nil end}),1,'nil speed fallback')
eq(step(game(20)),.05,'actual Game2 speed step')
local locked=game(200);locked.stack.states={{isFixedSpeed=true}}
eq(step(locked),1,'actual Game2 fixed screen lock')
locked.stack.states={};locked.linkSession={}
eq(step(locked),1,'actual Game2 link lock')
eq(Wait.waiting(nil,game(200)),false,'no pending wait')
eq(Wait.waiting(Wait.arm('H05_NEVER_PLAYED'),game(200)),false,'no Source releases immediately')
local fixture={audio={sfx={H05_PORTABLE={file='H05_PORTABLE'}}}}
local src=assert(Sound.play(fixture,'H05_PORTABLE'))
local function advance(g) now=now+1/(60*g:logicSpeed()) end
local function portable(label,speed,configure,wantMin,wantMax,change)
  now=0;Sound.play(fixture,'H05_PORTABLE');src.duration=.5;src.stuck=nil;src.invalidDuration=nil
  if configure then configure(src) end
  local g=game(speed);local pending=Wait.arm('H05_PORTABLE',3);local released=false
  for i=1,15000 do
    if change then change(g,i,now) end
    advance(g)
    if not Wait.waiting(pending,g) then released=true;break end
  end
  eq(released,true,label..' finite release')
  eq(now>=wantMin and now<=wantMax,true,label..' real-time budget '..now)
  src:stop()
end
portable('dynamic20 -> 1',20,nil,.5,.55,function(g,_,time) if time>=.1 then g.options.speed=1 end end)
portable('dynamic1 -> 200',1,nil,.5,.55,function(g,_,time) if time>=.1 then g.options.speed=200 end end)
portable('natural early completion',200,function(s) s.duration=.03 end,.03,.04)
portable('stuck source ceiling',200,function(s) s.stuck=true end,.53,.54)
portable('invalid duration finite fallback',20,function(s) s.invalidDuration='bad';s.stuck=true end,.049,.052)
for _,speed in ipairs({1,20,200}) do
  now=0;Sound.play(fixture,'H05_PORTABLE');src.stuck=true;src.duration=.5;src.invalidDuration=nil
  local g=game(speed);g.data=fixture
  local state=setmetatable({game=g,phase='resolving',slideFrame=999,messageTimer=100,waitSfx='H05_PORTABLE'},BattleState)
  local stopCount=#src.stops;local released=false
  for _=1,15000 do advance(g);state:update(0);if not state.waitSfx then released=true;break end end
  eq(released,true,'battle stuck finite '..speed)
  eq(now>=.53 and now<=.551,true,'battle stuck ceiling real time '..speed..' '..now)
  eq(#src.stops,stopCount+1,'battle stuck explicitly stopped '..speed)
  src:stop()
end
local oldVersion=GameVersion.get()
for _,version in ipairs({'gold','silver','crystal'}) do
  local root=os.getenv('POKEPORT_GEN2_'..version:upper()..'_DATA')
  if not root then print('SKIP H05 actual '..version..' audio consumers; set POKEPORT_GEN2_'..version:upper()..'_DATA')
  else
    GameVersion.set(version)
    local data={audio=assert(loadfile(root..'/audio.lua'))()}
    assert(data.audio.sfx.Sfx_SwitchPokemon and data.audio.sfx.Sfx_HitEndOfExpBar,'required real audio metadata absent')
    for _,speed in ipairs({1,20,200}) do
      local g=game(speed);g.data=data
      for _,row in ipairs({{'party',Party,'playSfxTwice'},{'pack',Pack,'playSfxTwice'},{'pc',Pc,'playPcSfxTwice'},{'summary',Summary,'playSwapSfxTwice'}}) do
        local name,mod,method=unpack(row);now=0
        local state=setmetatable({game=g,data=data},mod)
        state[method](state,'Sfx_SwitchPokemon')
        local s=assert(created.Sfx_SwitchPokemon);s.duration=.5;s.stuck=nil;s.invalidDuration=nil
        local plays=#s.plays;local released=false
        for _=1,15000 do advance(g);if not state:tickRepeatSfx() then released=true;break end end
        eq(released,true,version..' '..name..' bounded release '..speed)
        eq(#s.plays,plays+1,version..' '..name..' actual second beep '..speed)
        eq(now>=.5 and now<=.551,true,version..' '..name..' waits natural duration '..speed..' '..now)
        s:stop()
      end
      now=0
      local s=assert(Sound.play(data,'Sfx_SwitchPokemon'));s.duration=.5;s.stuck=nil
      local stops=#s.stops
      local state=setmetatable({game=g,phase='resolving',slideFrame=999,messageTimer=100,waitSfx='Sfx_SwitchPokemon'},BattleState)
      local released=false
      for _=1,15000 do advance(g);state:update(0);if not state.waitSfx then released=true;break end end
      eq(released,true,version..' actual battle bounded '..speed)
      eq(now>=.5 and now<=.551,true,version..' actual battle sound duration '..speed)
      eq(#s.stops,stops,version..' natural battle sound not cut '..speed)
      s:stop();now=0
      s=assert(Sound.play(data,'Sfx_HitEndOfExpBar'));s.duration=.5;s.stuck=nil
      state=setmetatable({game=g,expBurst={frame=0,line='GREW'},playSfx=function() end},BattleState)
      for i=1,8 do state:stepExpBurst({});eq(state.expBurst.frame,i,version..' EXP animation frame unchanged '..speed..'/'..i) end
      released=false
      for _=1,15000 do advance(g);state:stepExpBurst({lineSfx='Sfx_SwitchPokemon'});if not state.expBurst then released=true;break end end
      eq(released,true,version..' actual EXP bounded '..speed)
      eq(now>=.5 and now<=.551,true,version..' actual EXP natural drain '..speed)
      eq(state.message,'GREW',version..' actual EXP next line '..speed)
      s:stop()
    end
  end
end
GameVersion.set(oldVersion)
ChipAudio.newSfx,love.audio.newSource=realNew,realAudioNew
print('H05 SFX waits '..(checks-failures)..'/'..checks)
assert(failures==0,tostring(failures)..' H05 failures')
