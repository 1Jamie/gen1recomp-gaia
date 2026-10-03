local overallChecks,overallFailures=0,0
local savedWarn
do
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
savedWarn=require('src.core.Logger').warn
require('src.core.Logger').warn=function() end
local Mon=require('src.battle.gen2.Mon')
local Battle=require('src.battle.gen2.Battle')
local BattleState=require('src.ui.gen2.BattleState')
local Damage=require('src.battle.gen2.Damage')
local Save=require('src.core.gen2.Save')
local SaveData=require('src.core.SaveData')
local Gen2Save=require('src.save_convert.Gen2Save')
local Version=require('src.core.GameVersion')
local Registry=require('src.mods.Registry')
local checks,failures={},{}
local function eq(group,got,want,label)
  checks[group]=(checks[group] or 0)+1
  if got~=want then
    failures[group]=(failures[group] or 0)+1
    print('FAIL '..group..' '..label..' got='..tostring(got)..' want='..tostring(want))
  end
end
local function has(events,kind,needle)
  for _,e in ipairs(events) do if e.kind==kind and (not needle or (e.text or ''):find(needle,1,true)) then return true end end
  return false
end
local oldVersion=Version.get()
for _,version in ipairs({'gold','silver','crystal'}) do
  Version.set(version)
  local root=os.getenv('POKEPORT_GEN2_'..version:upper()..'_DATA')
  if not root then print('SKIP H03 actual '..version..' current-effects.lua; set explicit POKEPORT_GEN2_'..version:upper()..'_DATA') else
  local data={}
  for _,key in ipairs({'pokemon','moves','items','maps','sprites','type_chart','constants'}) do
    data[key]=assert(loadfile(root..'/'..key..'.lua'))()
  end
  local registry=Registry.new('move_effects')
  Battle.registerMoveEffectsInto(registry,data,'engine')
  data.gen2MoveEffects={}
  for id in pairs(registry.ops) do data.gen2MoveEffects[id]=registry:get(id) end
  local function entry(id) local d=assert(data.moves[id]);return {id=id,pp=d.pp,maxPp=d.pp,ppUps=0} end
  local function new(species,ids)
    local moves={};for _,id in ipairs(ids) do moves[#moves+1]=entry(id) end
    return assert(Mon.new(data,species,50,{moves=moves,dvs={attack=15,defense=15,speed=15,special=15}}))
  end
  local function make(species,ids)
    local player,enemy=new(species,ids),new('SNORLAX',{'TACKLE','SPLASH'})
    local save=Save.newGame({playerName='EFFECTS'});save.party={player}
    assert(data.maps.NEW_BARK_TOWN)
    save.position={map='NEW_BARK_TOWN',x=5,y=5,facing='down'}
    local battle=Battle.new({data=data,party=save.party,wild=enemy,save=save,random=function(n) return n==256 and 128 or 0 end})
    return battle,player,enemy,save
  end
  for _,id in ipairs({'SKETCH','NIGHTMARE','PSYCH_UP','MIST','FOCUS_ENERGY'}) do
    local def=assert(data.moves[id]);local record=Battle.moveEffectRecordFor(data,def.effect)
    print('DATA '..version..' '..id..' index='..def.index..' effect='..def.effect..' power='..def.power..' pp='..def.pp..' mergedKind='..tostring(record and record.kind)..' run='..type(record and record.run))
    eq('control',def.power,0,version..' actual '..id..' is non-damaging')
  end
  do
    local b,p,e,s=make('SMEARGLE',{'SKETCH'})
    b:useMove(e,p,'TACKLE');b:takeEvents()
    local pp=p.moves[1].pp
    b:useMove(p,e,'SKETCH');local events=b:takeEvents()
    eq('sketch',p.moves[1].id,'TACKLE',version..' actual enemy move copied permanently')
    eq('sketch',p.moves[1].pp,data.moves.TACKLE.pp,version..' copied base PP')
    eq('sketch',p.moves[1].maxPp,data.moves.TACKLE.pp,version..' copied max PP')
    eq('sketch',p.moves[1].ppUps,0,version..' copied PP Ups reset')
    eq('sketch',b:volatile(p).lastMove,nil,version..' ClearLastMove after Sketch')
    eq('sketch',has(events,'message','SKETCHED'),true,version..' source Sketch success text')
    eq('control',s.party[1],p,version..' Battle mutates real save party')
    local screen=BattleState.new({data=data,save=s,options=s.options},{battle=b})
    screen:completeBattle()
    local restored=assert(SaveData.decode(SaveData.encode(s)))
    eq('sketch',restored.party[1].moves[1].id,'TACKLE',version..' actual cleanup/serializer retains copied move')
    local bytes,why=Gen2Save.encode(s,version,nil,data);assert(bytes,why)
    local cart=assert(Gen2Save.decode(bytes,version,data))
    eq('sketch',cart.party[1].moves[1].id,'TACKLE',version..' actual SRAM encode/decode retains copied move')
    eq('control',cart.party[1].moves[1].id,p.moves[1].id,version..' SRAM matches actual present move')
    eq('control',pp,data.moves.SKETCH.pp,version..' real Sketch starts at source base PP')
  end
  for _,case in ipairs({'none','struggle','known','substitute','transformed','link'}) do
    local ids=case=='known' and {'SKETCH','TACKLE'} or {'SKETCH'}
    local b,p,e=make('SMEARGLE',ids)
    if case~='none' then b:volatile(e).lastMove=case=='struggle' and 'STRUGGLE' or 'TACKLE' end
    if case=='substitute' then b:volatile(e).substitute=20 end
    if case=='transformed' then b:volatile(e).transformed=true end
    if case=='link' then b.linkBattle=true end
    local hp=e.hp;b:useMove(p,e,'SKETCH');local events=b:takeEvents()
    eq('control',p.moves[1].id,'SKETCH',version..' refused Sketch '..case..' does not replace')
    eq('control',e.hp,hp,version..' refused Sketch '..case..' does not damage')
    eq('sketch',has(events,'message'),true,version..' refused Sketch '..case..' source refusal text')
    eq('sketch',b:volatile(p).lastMove,nil,version..' refused Sketch '..case..' clears last move')
  end
  do
    local b,p,e=make('GENGAR',{'NIGHTMARE'});e.status='sleep';e.statusTurns=4
    local hp=e.hp
    b:useMove(p,e,'NIGHTMARE');local events=b:takeEvents()
    eq('nightmare',b:volatile(e).nightmare,true,version..' real sleeping target flagged')
    eq('nightmare',has(events,'message','NIGHTMARE'),true,version..' Nightmare source success text')
    eq('control',e.hp,hp,version..' Nightmare has no direct damage')
    b:takeTurn({kind='item'})
    eq('nightmare',e.hp,hp-math.max(1,math.floor(e.maxHp/4)),version..' real residual turn quarter HP')
    eq('control',e.status,'sleep',version..' residual test remains asleep')
  end
  for _,case in ipairs({'awake','hidden','substitute','repeat'}) do
    local b,p,e=make('GENGAR',{'NIGHTMARE'})
    e.status='sleep';e.statusTurns=4
    if case=='awake' then e.status=nil end
    if case=='hidden' then b:volatile(e).vanished=true;b:volatile(e).chargeMove='FLY' end
    if case=='substitute' then b:volatile(e).substitute=20 end
    if case=='repeat' then b:volatile(e).nightmare=true end
    b:useMove(p,e,'NIGHTMARE');local events=b:takeEvents()
    eq('nightmare',has(events,'message','failed'),true,version..' Nightmare '..case..' source refusal')
    if case~='repeat' then eq('control',b:volatile(e).nightmare,nil,version..' Nightmare '..case..' retains no flag') end
  end
  do
    local b,p,e=make('GENGAR',{'NIGHTMARE'})
    e.status='sleep';e.statusTurns=3;b:volatile(e).nightmare=true
    local hp=e.hp
    b:tickSeedAndCurse(e)
    eq('nightmare',e.hp,hp-math.max(1,math.floor(e.maxHp/4)),version..' isolated canonical Nightmare residual consumer')
    e.statusTurns=1;b:canAct(e,'TACKLE')
    eq('control',e.status,nil,version..' actual wake-up clears major status')
    eq('nightmare',b:volatile(e).nightmare,nil,version..' actual wake-up clears Nightmare')
    b:clearVolatile(e)
    eq('control',e.volatile,nil,version..' switch/cleanup discards Nightmare volatile')
  end
  for _,side in ipairs({'player','enemy'}) do
    local b,p,e=make('ALAKAZAM',{'PSYCH_UP'})
    e.moves={entry('PSYCH_UP')}
    local actor,target=side=='player' and p or e,side=='player' and e or p
    local own=b.stages[side];local other=b.stages[side=='player' and 'enemy' or 'player']
    own.attack=5;other.attack=-2;other.defense=3;other.speed=-1;other.specialAttack=2;other.specialDefense=-3;other.accuracy=1;other.evasion=4
    local before={};for k,v in pairs(other) do before[k]=v end
    b:useMove(actor,target,'PSYCH_UP');local events=b:takeEvents()
    for _,key in ipairs(Battle.LINK_STAGES) do
      eq('psych-up',own[key],before[key],version..' '..side..' Psych Up copied '..key)
      eq('control',other[key],before[key],version..' '..side..' target '..key..' unchanged')
    end
    eq('psych-up',has(events,'message','copied'),true,version..' '..side..' copied-stats source text')
    eq('control',own==other,false,version..' '..side..' stage tables stay distinct')
  end
  do
    local b,p,e=make('ALAKAZAM',{'PSYCH_UP'});b.stages.player.attack=5
    b:useMove(p,e,'PSYCH_UP');local events=b:takeEvents()
    eq('psych-up',has(events,'message','failed'),true,version..' unmodified target source refusal')
    eq('control',b.stages.player.attack,5,version..' unmodified target leaves user stages')
  end
  do
    local b,p,e=make('VAPOREON',{'MIST'})
    b:useMove(p,e,'MIST');local events=b:takeEvents()
    eq('mist',b:volatile(p).mist,true,version..' actual Mist sets canonical volatile')
    eq('mist',has(events,'message','MIST'),true,version..' source Mist success message')
    b:useMove(e,p,'GROWL')
    eq('mist',b.stages.player.attack,0,version..' actual Growl blocked after Mist')
    b:takeEvents();b:useMove(p,e,'MIST')
    eq('mist',has(b:takeEvents(),'message','failed'),true,version..' repeated Mist source refusal')
    local control,cp,ce=make('VAPOREON',{'MIST'})
    control:useBattleItem('GUARD_SPEC');control:takeEvents();control:useMove(ce,cp,'GROWL')
    eq('control',control:volatile(cp).mist,true,version..' Guard Spec actual producer sets same flag')
    eq('control',control.stages.player.attack,0,version..' existing canonical Mist consumer protects Guard Spec')
  end
  do
    local b,p,e=make('RATTATA',{'FOCUS_ENERGY','TACKLE'})
    b.random=function(n) return n==Damage.criticalChance(0) and 1 or 0 end
    b:useMove(p,e,'FOCUS_ENERGY');local events=b:takeEvents()
    eq('focus-energy',b:volatile(p).focusEnergy,true,version..' actual Focus Energy sets canonical volatile')
    eq('focus-energy',has(events,'message','pumped'),true,version..' source Focus Energy success message')
    local level=Damage.criticalLevel({focusEnergy=b:volatile(p).focusEnergy})
    eq('focus-energy',level,1,version..' actual consumer critical level increment')
    local _,info=b:hitOnce(p,e,data.moves.TACKLE)
    eq('focus-energy',info.critical,true,version..' actual hitOnce chosen rung produces critical')
    b:takeEvents();b:useMove(p,e,'FOCUS_ENERGY')
    eq('focus-energy',has(b:takeEvents(),'message','failed'),true,version..' repeated Focus Energy source refusal')
    local control,cp,ce=make('RATTATA',{'TACKLE'})
    control.random=b.random;control:useBattleItem('DIRE_HIT')
    local _,ci=control:hitOnce(cp,ce,data.moves.TACKLE)
    eq('control',control:volatile(cp).focusEnergy,true,version..' Dire Hit actual producer sets same flag')
    eq('control',ci.critical,true,version..' canonical critical consumer positive through Dire Hit')
  end
end
end
Version.set(oldVersion)
local total,failed=0,0
for _,group in ipairs({'control','sketch','nightmare','psych-up','mist','focus-energy'}) do
  local n,f=checks[group] or 0,failures[group] or 0
  print('RESULT '..group..' '..(n-f)..'/'..n..' failures='..f);total=total+n;failed=failed+f
end
print('CURRENT effects source-expectation '..(total-failed)..'/'..total..' failures='..failed)

overallChecks=overallChecks+total;overallFailures=overallFailures+failed
end
do
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
require('src.core.Logger').warn=function() end
local Battle=require('src.battle.gen2.Battle')
local BattleState=require('src.ui.gen2.BattleState')
local Mon=require('src.battle.gen2.Mon')
local Save=require('src.core.gen2.Save')
local Ai=require('src.battle.gen2.Ai')
local Version=require('src.core.GameVersion')
local checks,failures=0,0
local function eq(got,want,name)
  checks=checks+1
  if got~=want then failures=failures+1;print('FAIL '..name..' got='..tostring(got)..' want='..tostring(want)) end
end
local oldVersion=Version.get()
for _,version in ipairs({'gold','silver','crystal'}) do
  Version.set(version)
  local root=os.getenv('POKEPORT_GEN2_'..version:upper()..'_DATA')
  if not root then print('SKIP H03 actual '..version..' nightmare-consumers.lua; set explicit POKEPORT_GEN2_'..version:upper()..'_DATA') else
  local data={}
  for _,key in ipairs({'pokemon','moves','items','type_chart'}) do data[key]=assert(loadfile(root..'/'..key..'.lua'))() end
  local function new(id,move)
    local def=assert(data.moves[move])
    return assert(Mon.new(data,id,50,{moves={{id=move,pp=def.pp,maxPp=def.pp}},dvs={attack=15,defense=15,speed=15,special=15}}))
  end
  local function make()
    local p,e=new('GENGAR','NIGHTMARE'),new('SNORLAX','SPLASH')
    local s=Save.newGame({playerName='CONSUMER'});s.party={p}
    return Battle.new({data=data,party=s.party,wild=e,save=s,random=function() return 0 end}),p,e,s
  end
  do
    local b,p,e=make();e.status='sleep';e.statusTurns=3;e.item='MINT_BERRY';b:volatile(e).nightmare=true
    b:tickHeldItem(e)
    eq(e.status,nil,version..' actual held Mint Berry cures sleep')
    eq(e.item,nil,version..' actual held Mint Berry is consumed')
    eq(b:volatile(e).nightmare,nil,version..' held status cure clears Nightmare')
  end
  do
    local b,p,e,s=make();p.status='sleep';p.statusTurns=3;b:volatile(p).nightmare=true;s.inventory.FULL_HEAL=1
    local screen=BattleState.new({data=data,save=s,options=s.options},{battle=b})
    screen:applyPartyItem('FULL_HEAL','status',p,nil,1)
    eq(p.status,nil,version..' actual BattleState Full Heal cures sleep')
    eq(s.inventory.FULL_HEAL,nil,version..' actual BattleState consumes Full Heal')
    eq(b:volatile(p).nightmare,nil,version..' actual player status cure clears Nightmare')
  end
  do
    local b,p=make();b:volatile(p).nightmare=true;b:volatile(p).turnsTaken=3
    local signature=b:linkSignature('host').volatile
    b:volatile(p).nightmare=nil
    eq(signature~=b:linkSignature('host').volatile,true,version..' link signature distinguishes Nightmare flag')
    b:volatile(p).nightmare=true
    local smart=b:smartAiState()
    eq(smart.playerNightmare,true,version..' real Battle AI bridge exposes canonical Nightmare')
    eq(Ai.SMART.EFFECT_TRAP_TARGET({random=function(n) return n-1 end},smart),-2,version..' actual SMART trapping encourages Nightmare target')
  end
  do
    local b,p,e=make();p.moves={{id='BATON_PASS',pp=data.moves.BATON_PASS.pp,maxPp=data.moves.BATON_PASS.pp}}
    local bench=new('SNORLAX','SPLASH');b.party[2]=bench
    b:volatile(p).nightmare=true;b:volatile(p).mist=true;b.stages.player.attack=3
    b:useMove(p,e,'BATON_PASS')
    eq(b.player,bench,version..' actual Baton Pass switches active')
    eq(b:volatile(bench).nightmare,nil,version..' existing Baton Pass excludes Nightmare')
    eq(b:volatile(bench).mist,true,version..' existing Baton Pass retains Mist')
    eq(b.stages.player.attack,3,version..' existing Baton Pass retains stages')
  end
  for _,case in ipairs({'awake','sleep','poison','repeat'}) do
    local b,p=make()
    if case=='sleep' or case=='repeat' then p.status='sleep' elseif case=='poison' then p.status='poison' end
    if case=='repeat' then b:volatile(p).nightmare=true end
    local sourceScore=(case=='awake' or case=='repeat') and 30 or 20
    eq(Ai.LAYERS.BASIC.score({defender={status=p.status,nightmare=b:volatile(p).nightmare}},data.moves.NIGHTMARE,20),sourceScore,
      version..' actual BASIC Nightmare '..case..' preserves source any-status quirk')
  end
  for _,item in ipairs({'FULL_HEAL','FULL_RESTORE'}) do
    local b,p,e=make();e.status='sleep';e.statusTurns=3;b:volatile(e).nightmare=true
    b.trainer={name='TRAINER',items={item}}
    b:enemyUseItem(item)
    eq(e.status,nil,version..' trainer AI '..item..' clears status')
    eq(b:volatile(e).nightmare,true,version..' trainer AI '..item..' preserves source Nightmare bug')
    local hp=e.hp;b:tickSeedAndCurse(e)
    eq(e.hp,hp-math.max(1,math.floor(e.maxHp/4)),version..' trainer '..item..' source flag still chips without sleep')
  end
end
end
Version.set(oldVersion)
print('Nightmare consumer source-expectation '..(checks-failures)..'/'..checks..' failures='..failures)

overallChecks=overallChecks+checks;overallFailures=overallFailures+failures
end
do
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local Battle=require('src.battle.gen2.Battle')
local Mon=require('src.battle.gen2.Mon')
local Version=require('src.core.GameVersion')
local checks,failures=0,0
local function eq(got,want,name)
  checks=checks+1
  if got~=want then failures=failures+1;print('FAIL '..name..' got='..tostring(got)..' want='..tostring(want)) end
end
local oldVersion=Version.get()
for _,version in ipairs({'gold','silver','crystal'}) do
  Version.set(version)
  local root=os.getenv('POKEPORT_GEN2_'..version:upper()..'_DATA')
  if not root then print('SKIP H03 actual '..version..' no-checkhit.lua; set explicit POKEPORT_GEN2_'..version:upper()..'_DATA') else
  local data={}
  for _,key in ipairs({'pokemon','moves','items','type_chart'}) do data[key]=assert(loadfile(root..'/'..key..'.lua'))() end
  local species={SKETCH='SMEARGLE',NIGHTMARE='GENGAR',PSYCH_UP='ALAKAZAM',MIST='VAPOREON',FOCUS_ENERGY='RATTATA'}
  for _,id in ipairs({'SKETCH','NIGHTMARE','PSYCH_UP','MIST','FOCUS_ENERGY'}) do
    local function make()
      local md=assert(data.moves[id])
      local p=assert(Mon.new(data,species[id],50,{moves={{id=id,pp=md.pp,maxPp=md.pp}}}))
      local e=assert(Mon.new(data,'SNORLAX',50,{moves={{id='TACKLE',pp=data.moves.TACKLE.pp,maxPp=data.moves.TACKLE.pp}}}))
      local b=Battle.new({data=data,party={p},wild=e,random=function(n) return n-1 end})
      b:volatile(e).lastMove='TACKLE';e.status='sleep';e.statusTurns=3;b.stages.enemy.attack=2
      return b,p,e
    end
    local b,p,e=make();local calls=0;local old=b.accuracyRoll
    b.accuracyRoll=function(self,...) calls=calls+1;return old(self,...) end
    b:useMove(p,e,id)
    eq(calls,0,version..' '..id..' source effect has no checkhit/accuracy RNG')
    local b2,p2,e2=make();b2:volatile(e2).lockOn=true
    b2:useMove(p2,e2,id)
    eq(b2:volatile(e2).lockOn,true,version..' '..id..' no-checkhit does not consume target Lock-On')
  end
end
end
Version.set(oldVersion)
print('No-checkhit source-expectation '..(checks-failures)..'/'..checks..' failures='..failures)

overallChecks=overallChecks+checks;overallFailures=overallFailures+failures
end

do
local Battle=require('src.battle.gen2.Battle')
local BattleState=require('src.ui.gen2.BattleState')
local Mon=require('src.battle.gen2.Mon')
local Save=require('src.core.gen2.Save')
local SaveData=require('src.core.SaveData')
local Strings=require('src.core.Strings')
local Version=require('src.core.GameVersion')
local Stack=require('src.core.StateStack')
local function eq(got,want,label)
  overallChecks=overallChecks+1
  if got~=want then overallFailures=overallFailures+1;print('FAIL '..label..' got='..tostring(got)..' want='..tostring(want)) end
end
local oldVersion=Version.get()
for _,version in ipairs({'gold','silver','crystal'}) do
  local root=os.getenv('POKEPORT_GEN2_'..version:upper()..'_DATA')
  if not root then print('SKIP H03 actual '..version..' UI, transform and ordering; set explicit edition dataset') else
    Version.set(version)
    local data={}
    for _,key in ipairs({'pokemon','moves','items','type_chart'}) do data[key]=assert(loadfile(root..'/'..key..'.lua'))() end
    local function entry(id) local d=assert(data.moves[id]);return {id=id,pp=d.pp,maxPp=d.pp,ppUps=0} end
    local function make(species,ids,enemyIds)
      local function new(spec,ms)
        local moves={};for _,id in ipairs(ms) do moves[#moves+1]=entry(id) end
        return assert(Mon.new(data,spec,50,{moves=moves,dvs={attack=15,defense=15,speed=15,special=15}}))
      end
      local p,e=new(species,ids),new('SNORLAX',enemyIds or {'SPLASH'})
      local save=Save.newGame({playerName='NAMED'});save.party={p};save.inventory={}
      local input={wasPressed=function() return true end,isDown=function() return false end}
      local game={data=data,save=save,options=save.options,input=input}
      game.stack=setmetatable({}, {__index=Stack});game.stack:init()
      local b=Battle.new({data=data,party=save.party,wild=e,save=save,random=function(n) return n==256 and 128 or 0 end})
      local screen=BattleState.new(game,{battle=b});game.stack:push(screen)
      return b,p,e,screen,game
    end
    local function settle(screen)
      for _=1,4000 do
        if screen.phase=='menu' and #screen.queue==0 and not screen.anim then return end
        screen:update(1/60)
      end
      error(version..' actual move UI did not settle phase='..tostring(screen.phase)..' message='..tostring(screen.message)..' q='..#screen.queue..' anim='..tostring(screen.anim)..' slide='..tostring(screen.backpicSlide))
    end
    do
      local b,p,e,screen=make('DITTO',{'TRANSFORM'},{'SKETCH','SPLASH'})
      local original=Mon.partyMoves(p)
      b:useMove(p,e,'TRANSFORM');b:takeEvents()
      eq(b:volatile(p).transformed,true,version..' actual transformed user')
      b:useMove(e,p,'SPLASH');b:takeEvents()
      b:useMove(p,e,'SKETCH');local events=b:takeEvents()
      eq(p.moves[1].id,'SKETCH',version..' target already-known move cannot be Sketched')
      eq(events[#events].text,Strings("It didn't affect\n%s!",b:monName(e)),version..' exact target refusal text')
      e.moves[2]=entry('TACKLE');b:useMove(e,p,'TACKLE');b:takeEvents()
      b:useMove(p,e,'SKETCH');events=b:takeEvents()
      eq(original[1].id,'TACKLE',version..' source transformed-user party slot glitch retained')
      eq(p.moves[1].id,'TACKLE',version..' transformed battle slot copied')
      eq(original[1]==p.moves[1],false,version..' party/battle copies distinct')
      eq(original[1].pp,data.moves.TACKLE.pp,version..' transformed copy base PP')
      b:untransform(p)
      eq(p.species,'DITTO',version..' cleanup restores original species')
      eq(p.moves,original,version..' cleanup restores owned party moves')
      eq(p.moves[1].id,'TACKLE',version..' cleanup keeps permanent transformed Sketch')
      eq(events[#events].text,Strings('%s\nSKETCHED\v%s!',b:monName(p),data.moves.TACKLE.name),version..' source Sketch text controls')
    end
    do
      local b,p,e=make('SMEARGLE',{'SKETCH','SKETCH'},{'TACKLE'})
      b:useMove(e,p,'TACKLE');b:takeEvents();b:useMove(p,e,'SKETCH')
      eq(p.moves[1].id,'SKETCH',version..' source reverse Sketch scan leaves first duplicate')
      eq(p.moves[1].pp,0,version..' chosen move PP consumed once before copying')
      eq(p.moves[2].id,'TACKLE',version..' source reverse Sketch scan replaces last duplicate')
      eq(b:volatile(p).turnsTaken,1,version..' Sketch own turn bookkeeping once')
      b:volatile(p).lastMove='TACKLE';b.linkBattle=true;p.moves[1].pp=1
      b:useMove(p,e,'SKETCH');local events=b:takeEvents()
      eq(b:volatile(p).lastMove,nil,version..' link refusal still ClearLastMove')
      eq(events[#events].text,Strings('But nothing\nhappened.'),version..' exact link refusal')
    end
    do
      local b,p,e=make('ALAKAZAM',{'PSYCH_UP'})
      b.stages.player.attack=2;b.stages.enemy.attack=2
      local stages=b.stages.player;local stats=p.stats;local base=stats.attack
      b:useMove(p,e,'PSYCH_UP');local events=b:takeEvents()
      eq(events[#events].text,Strings('%s\ncopied the stat\fchanges of\n%s!',b:monName(p),b:monName(e)),version..' equal already-raised stages still succeed/source para')
      eq(b.stages.player,stages,version..' stages mutated in place')
      eq(p.stats,stats,version..' base stat table retained')
      eq(p.stats.attack,base,version..' base Attack unchanged')
      b.stages.enemy.attack=6
      eq(b.stages.player.attack,2,version..' copied stages never alias target')
    end
    for _,kind in ipairs({'seed-nightmare-curse','nightmare-faint'}) do
      local b,p,e=make('GENGAR',{'NIGHTMARE'})
      local state=b:volatile(e);state.leechSeed=true;state.nightmare=true;state.cursed=true
      local hp=e.hp;local seed=math.max(1,math.floor(e.maxHp/8));local quarter=math.max(1,math.floor(e.maxHp/4))
      if kind=='nightmare-faint' then e.hp=seed+1 end
      b:tickSeedAndCurse(e);local events=b:takeEvents();local labels={}
      for _,ev in ipairs(events) do if ev.kind=='message' then labels[#labels+1]=ev.text end end
      eq(labels[1],Strings('LEECH SEED saps %s!',b:monName(e)),version..' seed first '..kind)
      eq(labels[2],Strings('%s\nhas a NIGHTMARE!',b:monName(e)),version..' Nightmare after seed '..kind)
      if kind=='nightmare-faint' then
        eq(e.hp,0,version..' residual Nightmare may faint')
        eq(#labels,2,version..' no Curse after Nightmare faint')
      else
        eq(labels[3],Strings("%s's hurt by the CURSE!",b:monName(e)),version..' Curse last')
        eq(e.hp,hp-seed-2*quarter,version..' source combined residual damage')
      end
    end
    for _,item in ipairs({'FULL_HEAL','FULL_RESTORE','MINT_BERRY'}) do
      local b,p,e,screen,game=make('GENGAR',{'NIGHTMARE'})
      p.status='sleep';p.statusTurns=3;p.hp=p.hp-1;b:volatile(p).nightmare=true
      game.save.inventory[item]=1
      screen:applyPartyItem(item,item=='FULL_RESTORE' and 'heal' or 'status',p,nil,1)
      eq(b:volatile(p).nightmare,nil,version..' player actual '..item..' clears Nightmare')
      eq(p.status,nil,version..' player actual '..item..' cures sleep')
      eq(game.save.inventory[item],nil,version..' player actual '..item..' spent')
    end
    do
      local b,p,e,screen,game=make('GENGAR',{'NIGHTMARE'})
      p.hp=p.hp-5;p.status='sleep';p.statusTurns=3;b:volatile(p).nightmare=true;game.save.inventory.POTION=1
      screen:applyPartyItem('POTION','heal',p,nil,1)
      eq(b:volatile(p).nightmare,true,version..' HP-only Potion does not clear Nightmare')
      eq(p.status,'sleep',version..' HP-only Potion does not heal status')
    end
    for _,case in ipairs({
      {item='FULL_RESTORE',action='heal',hurt=true,used=true,clears=true},
      {item='FULL_HEAL',action='status',confused=true,used=true,clears=true},
      {item='FULL_HEAL',action='status',used=false,clears=false},
      {item='FULL_RESTORE',action='heal',used=false,clears=false},
      {item='POTION',action='heal',hurt=true,used=true,clears=false},
    }) do
      local b,p,e,screen,game=make('GENGAR',{'NIGHTMARE'})
      local tag=version..' accepted-status-zero '..case.item..(case.hurt and ' HP' or case.confused and ' confusion' or ' healthy')
      if case.hurt then p.hp=p.hp-5 end
      local state=b:volatile(p);state.nightmare=true
      if case.confused then state.confuseCount=3 end
      game.save.inventory[case.item]=1
      screen:applyPartyItem(case.item,case.action,p,nil,1)
      eq(p.status,nil,tag..' keeps empty major-status byte')
      eq(game.save.inventory[case.item] or 0,case.used and 0 or 1,tag..' source accepted/refused consumption')
      eq(not not state.nightmare,not case.clears,tag..' source HealStatus active volatile ownership')
      eq(state.confuseCount,nil,tag..' confusion cleared or stays absent')
    end
    for _,held in ipairs({'none','a','b'}) do
      local b,p,e,screen,game=make('RATTATA',{'FOCUS_ENERGY'})
      game.input.isDown=function(_,key) return key==held end
      settle(screen)
      screen.phase='resolving';screen.queue={{kind='text-pause'},{kind='message',text='NEXT'}}
      screen:showPages('OLD');screen:syncTyper();screen:advanceQueue()
      if held=='none' then
        eq(screen.message,nil,version..' Focus pre-pause blanks previous text')
        eq(screen.typer,nil,version..' Focus pre-pause discards preceding text painter')
        eq(table.concat(screen:messageLines(),''),'',version..' actual pre-pause visible rows blank')
        eq(screen.messageDelay,30,version..' source pause starts30 logic frames')
        screen.syncTyper=function() return false end;screen.stepHpAnim=function() return false end;screen.stepExpAnim=function() return false end
        game.input.isDown=function(_,key) return key=='a' end
        for _=1,30 do screen:update(1/60);eq(screen.message,nil,version..' late held A cannot skip pause') end
        screen:update(1/60)
        eq(screen.message,'NEXT',version..' source pause ends before next message')
      else
        eq(screen.message,'NEXT',version..' source initial held '..held..' skips pause')
        eq(screen.messageDelay or 0,0,version..' held '..held..' creates no delay')
      end
    end
    for _,row in ipairs({{'MIST','VAPOREON','mist'},{'FOCUS_ENERGY','RATTATA','focusEnergy'},{'NIGHTMARE','GENGAR','nightmare'},{'PSYCH_UP','ALAKAZAM','stages'},{'SKETCH','SMEARGLE','moves'}}) do
      local id,species,field=unpack(row)
      local b,p,e,screen=make(species,{id},{'SPLASH'})
      settle(screen);e.status='sleep';e.statusTurns=7
      if id=='PSYCH_UP' then b.stages.enemy.attack=2 end
      if id=='SKETCH' then e.status=nil;b:useMove(e,p,'TACKLE');b:takeEvents();e.moves={entry('SPLASH')} end
      local pp=p.moves[1].pp;local turn=b.turn
      eq(screen:chooseMenu('fight'),true,version..' '..id..' actual FIGHT')
      eq(screen:chooseMove(1),true,version..' '..id..' actual move selection')
      eq(b.turn,turn+1,version..' '..id..' actual UI spends one turn')
      if id=='SKETCH' then eq(p.moves[1].id,'TACKLE',version..' UI permanent Sketch')
      else eq(p.moves[1].pp,pp-1,version..' '..id..' UI spends one PP') end
      if field=='stages' then eq(b.stages.player.attack,2,version..' UI actual PsychUp stages')
      elseif field~='moves' then eq(b:volatile(id=='NIGHTMARE' and e or p)[field],true,version..' UI '..id..' canonical state') end
      settle(screen)
      eq(screen.phase,'menu',version..' '..id..' actual typing/queue returns to menu')
    end
    for _,row in ipairs({{'SKETCH','SMEARGLE'},{'NIGHTMARE','GENGAR'},{'PSYCH_UP','ALAKAZAM'},
        {'MIST','VAPOREON'},{'FOCUS_ENERGY','RATTATA'}}) do
      local id,species=unpack(row)
      local b,p,e=make(species,{id},{'TACKLE'})
      b:useMove(e,p,'TACKLE');b:takeEvents();e.status='sleep';e.statusTurns=7;b.stages.enemy.attack=2
      local Runtime=require('src.mods.Runtime')
      local Events=require('src.mods.Events')
      local Hooks=require('src.mods.Hooks')
      local oldEvents,oldHooks,oldErrors=Runtime.events,Runtime.hooks,Runtime.errors
      local events,seen=Events.new(),{}
      Runtime.install(events,Hooks.new(),{})
      local remove=events:on('battle.move_used',function(payload) seen[#seen+1]=payload end,0,'h03')
      local ok,err=pcall(function() b:useMove(p,e,id) end)
      remove();Runtime.install(oldEvents,oldHooks,oldErrors)
      assert(ok,err)
      eq(#seen,1,version..' '..id..' existing move-used hook exactly once')
      local payload=seen[1] or {}
      eq(payload.user,p,version..' '..id..' hook user')
      eq(payload.target,e,version..' '..id..' hook target')
      eq(payload.move,data.moves[id],version..' '..id..' hook actual move record')
      eq(payload.isCalled,false,version..' '..id..' hook ordinary call')
      eq(payload.moveId,id,version..' '..id..' hook ID')
      eq(payload.side,'player',version..' '..id..' hook actor side')
      eq(b:volatile(e).lastMove,'TACKLE',version..' '..id..' leaves opponent last move owned')
      b:clearVolatile(p);b:clearVolatile(e);p.moves={entry(id)};p.moves[1].pp=0
      b:useMove(p,e,id)
      local ev=b:takeEvents()
      eq(ev[#ev].text,Strings("There's no PP left\nfor this move!"),version..' '..id..' zero PP refusal preserved')
      eq(b:volatile(p).turnsTaken,nil,version..' '..id..' zero PP spends no command turn')
    end
    for _,row in ipairs({{'SKETCH','SMEARGLE','GROWL','SKETCHED'},
        {'NIGHTMARE','GENGAR','SPLASH','NIGHTMARE!'},
        {'PSYCH_UP','ALAKAZAM','HARDEN','copied the stat'},
        {'MIST','VAPOREON','GROWL','shrouded in MIST!'},
        {'FOCUS_ENERGY','RATTATA','SPLASH','getting pumped!'}}) do
      local id,species,foeMove,needle=unpack(row)
      local ids=id=='NIGHTMARE' and {'HYPNOSIS','NIGHTMARE','SPLASH'}
        or id=='FOCUS_ENERGY' and {'FOCUS_ENERGY','TACKLE'} or {id}
      local b,p,e,screen=make(species,ids,{foeMove})
      settle(screen);b.random=function(n) if n==256 then return 128 elseif n==100 then return 0 end;return n-1 end
      if id=='SKETCH' or id=='PSYCH_UP' then b.stages.enemy.speed=6 end
      if id=='NIGHTMARE' then
        screen:chooseMenu('fight');screen:chooseMove(1);settle(screen)
        eq(e.status,'sleep',version..' driver actual Hypnosis establishes sleep')
        eq(e.statusTurns>2,true,version..' driver source sleep lasts through Nightmare')
      end
      local slot=id=='NIGHTMARE' and 2 or 1
      local hp=e.hp;screen:chooseMenu('fight');screen:chooseMove(slot)
      local seen={}
      local function observed()
        for _=1,4000 do
          if screen.message then seen[#seen+1]=screen.message end
          if screen.phase=='menu' and #screen.queue==0 and not screen.anim then return end
          screen:update(1/60)
        end
        error('driver readiness actual UI did not settle '..id)
      end
      local function saw(text)
        for _,page in ipairs(seen) do if page:find(text,1,true) then return true end end
        return false
      end
      observed();eq(saw(needle),true,version..' actual driver source dialog reachable '..id)
      if id=='SKETCH' then
        eq(p.moves[1].id,'GROWL',version..' actual fast opponent command Sketched')
        eq(saw('GROWL!'),true,version..' actual driver Sketch second page')
      elseif id=='NIGHTMARE' then
        eq(e.hp,hp-math.max(1,math.floor(e.maxHp/4)),version..' actual driver Nightmare residual')
        e.item='MINT_BERRY';screen:chooseMenu('fight');screen:chooseMove(3);observed()
        eq(e.status,nil,version..' actual driver held sleep cure')
        eq(b:volatile(e).nightmare,nil,version..' actual driver held Nightmare cure')
        eq(saw('status!'),true,version..' actual driver cure page reachable')
      elseif id=='PSYCH_UP' then
        eq(b.stages.player.defense,1,version..' actual faster opponent Harden copied')
        eq(saw('changes of'),true,version..' actual driver PsychUp paragraph')
      elseif id=='MIST' then
        eq(b.stages.player.attack,0,version..' actual driver Growl blocked')
        screen:chooseMenu('fight');screen:chooseMove(1);observed()
        eq(saw('But it failed!'),true,version..' actual driver repeated Mist refusal')
      else
        b.random=function(n) return n==require('src.battle.gen2.Damage').criticalChance(0) and 1 or 0 end
        screen:chooseMenu('fight');screen:chooseMove(2);observed()
        eq(saw('A critical hit!'),true,version..' actual driver Focus critical consumer')
      end
      b.random=function() return 0 end
      screen:chooseMenu('run')
      eq(b.over,true,version..' actual driver run exits '..id)
    end
    do
      local b,p,e=make('VAPOREON',{'MIST'})
      local calls=0
      data.gen2MoveEffects={EFFECT_MIST={kind='primary',run=function(self,user,target,def,id,sure)
        calls=calls+1;eq(user,p,version..' merged owner user');eq(target,e,version..' merged owner target')
        eq(def,data.moves.MIST,version..' merged owner move');eq(id,'MIST',version..' merged owner ID');eq(sure,true,version..' source no-hit dispatch')
      end}}
      b:volatile(e).lockOn=true;b:useMove(p,e,'MIST')
      eq(calls,1,version..' mod merged command dispatched once')
      eq(b:volatile(p).mist,nil,version..' vanilla does not overwrite merged owner')
      eq(b:volatile(e).lockOn,true,version..' merged no-hit command retains Lock-On')
      data.gen2MoveEffects=nil
    end
  end
end
Version.set(oldVersion)
end
print('H03 named move effects '..(overallChecks-overallFailures)..'/'..overallChecks)
require('src.core.Logger').warn=savedWarn
assert(overallFailures==0,tostring(overallFailures)..' H03 failures')
