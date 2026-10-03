package.path='./?.lua;./?/init.lua;'..package.path
love=love or require('tests.love_stub')
local T=require('tests.harness').suite('Gen1 charge announcement #2645')
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Data=require('src.core.Data')
local Version=require('src.core.GameVersion')
local Font=require('src.render.Font')
local Runtime=require('src.mods.Runtime')
local Hooks=require('src.mods.Hooks')
local Events=require('src.mods.Events')
local TypeChart=require('src.battle.TypeChart')
local old={version=Version.get(),events=Runtime.events,hooks=Runtime.hooks,errors=Runtime.errors,data={}}
for k,v in pairs(Data) do old.data[k]=v end
local fontBindings={}
local resetFontCaches
local typeBindings={}
for i=1,100 do
  local k,v=debug.getupvalue(TypeChart.load,i)
  if not k then break end
  typeBindings[#typeBindings+1]={i,v}
end
for i=1,100 do
  local k,v=debug.getupvalue(Font.load,i)
  if not k then break end
  if k=='state' or k=='loadedFrom' then fontBindings[#fontBindings+1]={i,v} end
  if k=='resetTextCaches' then resetFontCaches=v end
end
local phrases={SOLARBEAM='took in sunlight',RAZOR_WIND='made a whirlwind',SKULL_BASH='lowered its head',
  SKY_ATTACK='is glowing',FLY='flew up high',DIG='dug a hole'}
local function countText(b,fragment)
  local n=0
  for _,r in ipairs(b.queue) do if r.text and r.text:find(fragment,1,true) then n=n+1 end end
  return n
end
local ok,err=xpcall(function()
for _,version in ipairs({'red','blue','yellow'}) do
  local root=os.getenv('GEN1_'..version:upper()..'_CACHE')
  if root then
    Version.set(version)
    local data={}
    for _,key in ipairs({'pokemon','moves','items','maps','tilesets','text','sprites','field','constants','font','type_chart'}) do
      data[key]=assert(loadfile(root..'/data/generated/'..key..'.lua'))()
      Data[key]=data[key]
    end
    Font.load(data)
    local function fresh(id,enemy)
      local save=Save.newGame()
      save.options.animations=false;save.options.textSpeed=1
      local mon=Pokemon.new(data,'MEWTWO',50)
      local move={id=id,pp=data.moves[id].pp,maxPp=data.moves[id].pp}
      mon.moves={move};save.party={mon}
      local stack={push=function()end,top=function()end}
      local game={data=data,save=save,stack=stack,input={wasPressed=function()return true end,isDown=function()return true end}}
      local b=Battle.newWild(game,'MEWTWO',80)
      b.rng=function(a)return a or 0 end
      local user,target=b.player,b.enemy
      if enemy then user,target=b.enemy,b.player;user.curMoves={move};user.mon.moves={move} end
      return b,user,target,move
    end
    for _,id in ipairs({'SOLARBEAM','RAZOR_WIND','SKULL_BASH','SKY_ATTACK','FLY','DIG'}) do
      for _,enemy in ipairs({false,true}) do
        local label=version..' '..id..' '..(enemy and 'enemy' or 'player')
        Runtime.install(Events.new(),Hooks.new())
        local b,user,target,move=fresh(id,enemy)
        local hp,pp=target.mon.hp,move.pp
        T.check(b:effectRecord(data.moves[id].effect).charge~=nil,label..' actual ROM effect reaches charge record')
        b:performMove(user,target,move)
        T.eq(countText(b,'used '..data.moves[id].name),0,label..' no used announcement on charging turn')
        T.eq(countText(b,phrases[id]),1,label..' one source charge text')
        T.eq(target.mon.hp,hp,label..' charge does no damage')
        T.eq(user.charging,move,label..' selected instance retained')
        T.eq(user.invulnerable==true,id=='FLY' or id=='DIG',label..' source invulnerability unchanged')
        T.eq(move.pp,enemy and pp or pp-1,label..' prior faithful side PP policy unchanged')
        local observed,drained={},false
        for frame=1,1000 do
          local active=b:updateQueue()
          if b.current and b.current.text then observed[b.current.text]=true end
          if not active then drained=true;break end
        end
        T.check(drained,label..' actual queue drains within bound')
        local announced=false
        for text in pairs(observed) do if text:find('used '..data.moves[id].name,1,true) then announced=true end end
        T.eq(announced,false,label..' actual text consumer never starts used page during charge')
        b.queue={};b.nextInsert=0;b.current=nil;b.waitFrames=nil
        local releasePP=move.pp
        b:performMove(user,target,move)
        T.eq(countText(b,'used '..data.moves[id].name),1,label..' release announces once')
        T.eq(countText(b,phrases[id]),0,label..' release has no second charge page')
        T.eq(user.charging,nil,label..' release clears charge')
        T.eq(user.invulnerable,nil,label..' release clears invulnerability')
        T.eq(move.pp,releasePP,label..' release retains current continuation PP policy')
      end
    end
    for _,required in ipairs({true,false}) do
      local b,user,target,move=fresh('SOLARBEAM',false)
      local events,hooks=Events.new(),Hooks.new()
      Runtime.install(events,hooks)
      local sequence,original={}
      events:on('battle.move_used',function(c)
        sequence[#sequence+1]='event'
        T.eq(c.user,user,version..' event user unchanged')
        original=c.battle.queue[1]
        c.battle:sayNextAuto(original.text)
      end)
      hooks:wrap('battle.charge_required',function(nextFn,c)
        sequence[#sequence+1]='hook'
        T.eq(c.isCalled,false,version..' ordinary hook context')
        c.battle:sayNext('hook-owned text')
        return required
      end)
      local hp=target.mon.hp
      b:performMove(user,target,move)
      T.eq(table.concat(sequence,','),'event,hook',version..' public event/hook order preserved')
      T.eq(countText(b,'used '..data.moves.SOLARBEAM.name),required and 1 or 2,version..' only owned announcement removed after actual decision '..tostring(required))
      T.eq(countText(b,'hook-owned text'),1,version..' nested hook text retained')
      local present=false
      for _,r in ipairs(b.queue) do if r==original then present=true end end
      T.eq(present,not required,version..' exact original row identity '..tostring(required))
      T.eq(user.charging~=nil,required,version..' hook charge decision honored')
      T.eq(target.mon.hp==hp,required,version..' hook bypass damages normally')
    end
    do
      local b,user,target,move=fresh('SOLARBEAM',false)
      local hooks,events=Hooks.new(),Events.new()
      Runtime.install(events,hooks)
      local called
      hooks:wrap('battle.charge_required',function(nextFn,c)called=c.isCalled;return nextFn(c) end)
      local pp=move.pp
      b:performMove(user,target,move,true)
      T.eq(called,true,version..' called hook context retained')
      T.eq(move.pp,pp,version..' called charge keeps PP')
      T.eq(countText(b,'used '..data.moves.SOLARBEAM.name),0,version..' called charge follows source charge branch')
    end
    do
      Runtime.install(Events.new(),Hooks.new())
      local b,user,target,move=fresh('TACKLE',false)
      b:performMove(user,target,move)
      T.eq(countText(b,'used '..data.moves.TACKLE.name),1,version..' ordinary attack announcement retained')
      T.eq(user.charging,nil,version..' ordinary attack has no charge')
    end
    for _,caller in ipairs({'METRONOME','MIRROR_MOVE'}) do
      Runtime.install(Events.new(),Hooks.new())
      local b,user,target,move=fresh(caller,false)
      target.lastMove='SOLARBEAM'
      local pick
      for i,id in ipairs(data.constants.moveOrder) do if id=='SOLARBEAM' then pick=i end end
      b.rng=function(a,limit) return limit==#data.constants.moveOrder and assert(pick) or a or 0 end
      b:performMove(user,target,move)
      T.eq(countText(b,'used '..data.moves[caller].name),1,version..' outer '..caller..' announcement survives nested charge')
      T.eq(countText(b,'used '..data.moves.SOLARBEAM.name),0,version..' nested SolarBeam charge suppresses only its announcement')
      T.eq(countText(b,'took in sunlight'),1,version..' nested charge text survives')
      T.eq(user.charging and user.charging.id,'SOLARBEAM',version..' actual called-move dispatch retains charge instance')
    end
    do
      Runtime.install(Events.new(),Hooks.new())
      local b,user,target,move=fresh('TACKLE',false)
      local copied={}
      for k,v in pairs(data) do copied[k]=v end
      copied.moves={}
      for k,v in pairs(data.moves) do copied.moves[k]=v end
      local custom={}
      for k,v in pairs(data.moves.TACKLE) do custom[k]=v end
      custom.chargeText='%s\ncustom charge page!'
      copied.moves.TACKLE=custom
      copied.move_effects={[custom.effect]={charge={},announceAnim=false}}
      b.data=copied
      b:performMove(user,target,move)
      T.eq(countText(b,'used '..custom.name),0,version..' general merged charge record suppresses announcement')
      T.eq(countText(b,'custom charge page'),1,version..' merged chargeText preserved')
      T.eq(user.charging,move,version..' merged record charge stored without announcement animation')
      T.eq(#b.queue,1,version..' absent announcement animation leaves only charge page')
    end
  else print('SKIP #2645 actual '..version..' cache not explicitly supplied') end
end
end,debug.traceback)
for k in pairs(Data) do if old.data[k]==nil then Data[k]=nil end end
for k,v in pairs(old.data) do Data[k]=v end
Version.set(old.version)
Runtime.install(old.events,old.hooks,old.errors)
for _,binding in ipairs(fontBindings) do debug.setupvalue(Font.load,binding[1],binding[2]) end
if resetFontCaches then resetFontCaches() end
for _,binding in ipairs(typeBindings) do debug.setupvalue(TypeChart.load,binding[1],binding[2]) end
assert(ok,err)
T.finish()
