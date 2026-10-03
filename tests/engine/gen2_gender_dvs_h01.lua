package.path = './?.lua;./?/init.lua;' .. package.path
local Mon = require('src.battle.gen2.Mon')
local Codec = require('src.save_convert.Gen2Save')
local Battle = require('src.battle.gen2.Battle')
local Breeding = require('src.core.gen2.Breeding')
local Trade = require('src.core.gen2.NpcTrade')
local Runtime = require('src.mods.Runtime')
local Hooks = require('src.mods.Hooks')
local Events = require('src.mods.Events')
local GameVersion = require('src.core.GameVersion')
local checks, failures = 0, 0
local function eq(got,want,name)
  checks=checks+1
  if got~=want then
    failures=failures+1
    if failures<=20 then print('FAIL '..name..' got='..tostring(got)..' want='..tostring(want)) end
  end
end
local function source(ratio,d)
  if ratio==nil or ratio==255 then return 'unknown' end
  if ratio==0 then return 'male' end
  if ratio==254 then return 'female' end
  return d.attack*16+d.speed<=ratio and 'female' or 'male'
end
for ratio=0,255 do for a=0,15 do for s=0,15 do
  local d={attack=a,speed=s}
  eq(Mon.vanillaGender({genderRatio=ratio},d),source(ratio,d),'source byte '..ratio..'/'..a..'/'..s)
end end end
eq(Mon.vanillaGender(nil,nil),'unknown','missing definition')
eq(Mon.vanillaGender({},nil),'unknown','missing ratio')
eq(Mon.vanillaGender({genderRatio=0},nil),'male','always male without DVs')
eq(Mon.vanillaGender({genderRatio=254},nil),'female','always female without DVs')
local oldEvents,oldHooks,oldErrors=Runtime.events,Runtime.hooks,Runtime.errors
local hooks=Hooks.new()
Runtime.install(Events.new(),hooks)
local ctx
local remove=hooks:wrap('gender.roll',function(nextFn,c)
  ctx=c;eq(nextFn(),'female','hook next boundary');return 'unknown'
end,0,'h01')
eq(Mon.gender({id='CHANSEY',genderRatio=254},{attack=15,speed=15},{level=20}),'unknown','valid override')
eq(ctx.ratio,254,'ratio context');eq(ctx.species,'CHANSEY','species context');eq(ctx.level,20,'level context')
remove()
remove=hooks:wrap('gender.roll',function() return 'invalid' end,0,'h01')
eq(Mon.gender({genderRatio=254},{attack=15,speed=15}),'female','invalid override fallback')
remove();Runtime.install(oldEvents,oldHooks,oldErrors)
local oldVersion=GameVersion.get()
local roots={gold=os.getenv('POKEPORT_GEN2_GOLD_DATA'),silver=os.getenv('POKEPORT_GEN2_SILVER_DATA'),crystal=os.getenv('POKEPORT_GEN2_CRYSTAL_DATA')}
for _,version in ipairs({'gold','silver','crystal'}) do
  local root=roots[version]
  if not root then print('SKIP H01 actual '..version..' cache consumers; set POKEPORT_GEN2_'..version:upper()..'_DATA')
  else
    GameVersion.set(version)
    local data={}
    for _,name in ipairs({'pokemon','moves','items','maps','field','constants','type_chart'}) do
      data[name]=assert(loadfile(root..'/'..name..'.lua'))()
    end
    local x=Codec.crosswalks(data)
    local function new(id,a,s)
      return assert(Mon.new(data,id,20,{dvs={attack=a,defense=3,speed=s or 0,special=5}}))
    end
    local chansey=new('CHANSEY',15,15)
    eq(chansey.gender,'female',version..' actual Chansey')
    Mon.refreshStats(chansey,data)
    eq(chansey.gender,'female',version..' refresh identity')
    eq(Breeding.genderOf(data,chansey),'female',version..' breeding consumer')
    eq(Trade.genderOk({gender=Trade.TRADE_GENDER_MALE},chansey),false,version..' trade consumer')
    local enemy=new('NIDORAN_M',15,15)
    enemy.moves={{id='ATTRACT',pp=15,maxPp=15}}
    local battle=Battle.new({data=data,party={chansey},wild=enemy,random=function() return 0 end})
    battle:useMove(enemy,chansey,'ATTRACT')
    eq(battle:volatile(chansey).attract,true,version..' actual Attract')
    for _,row in ipairs({{'MACHOP',4,6},{'PIDGEY',8,10},{'VULPIX',12,14}}) do
      local id,a,want=unpack(row)
      local mon=new(id,a)
      mon.moves={{id='TACKLE',pp=35,maxPp=35}}
      local beforeA,beforeS=mon.dvs.attack,mon.dvs.speed
      local original=source(data.pokemon[id].genderRatio,mon.dvs)
      local ordinary={};Codec.util.putBoxMon(ordinary,0,mon,x,version=='crystal')
      local normal=Codec.util.decodeBoxMon(ordinary,0,x,version=='crystal')
      eq(normal.dvs.attack,a,version..' ordinary Attack');eq(normal.dvs.speed,0,version..' ordinary Speed')
      mon.shiny=true
      local bytes={};Codec.util.putBoxMon(bytes,0,mon,x,version=='crystal')
      local out=Codec.util.decodeBoxMon(bytes,0,x,version=='crystal')
      eq(out.dvs.attack,want,version..' nearest same-gender candidate '..id)
      eq(source(data.pokemon[id].genderRatio,out.dvs),original,version..' actual exported gender '..id)
      eq(Mon.vanillaShiny(out.dvs),true,version..' candidate is shiny')
      eq(mon.dvs.attack,beforeA,version..' input Attack immutable');eq(mon.dvs.speed,beforeS,version..' input Speed immutable')
      local save={generation=2,version=version,player={name='GENDER',id=12345,money=3000},rival={name='SILVER'},mom={name='MOM'},position={map='PLAYERS_HOUSE_2F',x=3,y=3},party={mon},boxes={[1]={mon}},currentBox=1}
      local raw,err=Codec.encode(save,version,nil,data)
      eq(type(raw),'string',version..' full SRAM encode '..tostring(err))
      if raw then
        eq(#raw,32768,version..' SRAM size')
        eq(Codec.checksumValid(raw,Codec.layoutFor(version)),true,version..' SRAM checksum')
        local decoded=assert(Codec.decode(raw,version,data))
        eq(source(data.pokemon[id].genderRatio,decoded.party[1].dvs),original,version..' party SRAM gender')
        eq(source(data.pokemon[id].genderRatio,decoded.boxes[1][1].dvs),original,version..' box SRAM gender')
      end
    end
    local natural=new('PIDGEY',7,10);natural.dvs.defense=10;natural.dvs.special=10;natural.shiny=true
    local bytes={};Codec.util.putBoxMon(bytes,0,natural,x,version=='crystal')
    local out=Codec.util.decodeBoxMon(bytes,0,x,version=='crystal')
    eq(out.dvs.attack,7,version..' natural shiny Attack unchanged');eq(out.dvs.speed,10,version..' natural shiny Speed unchanged')
    local impossible=new('CYNDAQUIL',1,15);impossible.shiny=true
    bytes={};Codec.util.putBoxMon(bytes,0,impossible,x,version=='crystal')
    out=Codec.util.decodeBoxMon(bytes,0,x,version=='crystal')
    eq(out.dvs.attack,2,version..' impossible female-shiny policy unchanged')
    eq(Mon.vanillaShiny(out.dvs),true,version..' impossible policy still shiny')
    local unown=new('UNOWN',2,10);unown.dvs.defense=10;unown.dvs.special=10;unown.shiny=true
    bytes={};Codec.util.putBoxMon(bytes,0,unown,x,version=='crystal')
    out=Codec.util.decodeBoxMon(bytes,0,x,version=='crystal')
    eq(out.dvs.attack,2,version..' natural Unown unchanged')
    unown=new('UNOWN',0,0);unown.shiny=true
    local ok=pcall(Codec.util.putBoxMon,{},0,unown,x,version=='crystal')
    eq(ok,false,version..' impossible shiny Unown letter refuses')
  end
end
GameVersion.set(oldVersion)
print('H01 gender DVs '..(checks-failures)..'/'..checks)
assert(failures==0,tostring(failures)..' H01 failures')
