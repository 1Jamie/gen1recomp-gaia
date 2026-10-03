package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local BS = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local Stats = require("src.pokemon.Stats")
local Damage = require("src.battle.Damage")
local Effects = require("src.battle.MoveEffects")
local AI = require("src.battle.TrainerAI")
local Items = require("src.inventory.ItemEffects")
local Save = require("src.core.SaveData")
local Status = require("src.battle.Status")
local faithful = require("src.battle.rulesets.gen1_faithful")
local modern = require("src.battle.rulesets.modern_clean")
local function fresh(data, id)
  data, id = data or Data, id or "FIXMON_A"
  local save=Save.newGame()
  local function mon() return Pokemon.new(data,id,100,function() return 15 end) end
  local p,e=BS.makeBattler(data,mon(),true,save),BS.makeBattler(data,mon(),false)
  return {data=data,player=p,enemy=e,ruleset=faithful,kind="wild",trainer={name="LASS"}},save
end
local function effective(who,stat)
  return Status.applyPenalty(who,stat,Damage.applyBadgeBoost(who,stat,Stats.applyStage(who.curStats[stat],who.stages[stat] or 0)))
end
local function nothing(data) return data.text and data.text._NothingHappenedText or "Nothing happened!" end
for _,stat in ipairs({"attack","defense","speed","special"}) do
  for _,side in ipairs({"player","enemy"}) do
    for stage=0,6 do
      for _,delta in ipairs({1,2}) do
        local b=fresh();local who=b[side]
        who.curStats={attack=999,defense=999,speed=999,special=999,hp=who.mon.stats.hp}
        who.stages[stat]=stage
        who.statusPenaltyStacks={attack=0,speed=0};who.badgeExtraBoosts={attack=2,speed=3}
        local oldPenalty=who.statusPenaltyStacks;local oldBadge=who.badgeExtraBoosts
        local msgs=Effects.changeStage(b,who,stat,delta,false)
        T.check(msgs.failed,side..stat..stage..delta.." capped stat fails")
        T.eq(msgs[1],nothing(b.data),"999 prints source no-effect line")
        T.eq(who.stages[stat],stage==6 and 6 or math.min(6,stage+delta)-1,"one-decrement source rollback")
        T.eq(who.statusPenaltyStacks,oldPenalty,"failed raise does not replace status stacks")
        T.eq(who.statusPenaltyStacks[stat],(stat=="attack" or stat=="speed") and 0 or nil,"failed raise leaves penalty contents")
        T.eq(who.badgeExtraBoosts,oldBadge,"failed raise preserves badge metadata")
        T.eq(who.badgeExtraBoosts.speed,3,"failed raise does not reapply other badges")
      end
    end
  end
  for _,side in ipairs({"player","enemy"}) do
    local b=fresh();local who=b[side];who.curStats[stat]=998;who.stages[stat]=0
    T.check(not Effects.changeStage(b,who,stat,1,false).failed,"998 can rise and reach999")
    T.eq(who.stages[stat],1,"998 reaches +1")
    T.eq(effective(who,stat),999,"successful rise clamps numeric stat")
    T.check(Effects.changeStage(b,who,stat,1,false).failed,"next rise at newly reached999 fails")
    T.eq(who.stages[stat],1,"next rise retains +1")
    T.check(not Effects.changeStage(b,who,stat,-1,false).failed,"capped numeric stat can still fall")
    T.eq(who.stages[stat],0,"stat-down has no999guard")
    local clean=fresh();clean.ruleset=modern;clean[side].curStats[stat]=999
    T.check(not Effects.changeStage(clean,clean[side],stat,2,false).failed,"modern_clean retains previous no-rollback behavior")
    T.eq(clean[side].stages[stat],2,"modern_clean+2 keeps both stages")
  end
end
for _,stat in ipairs({"accuracy","evasion"}) do
  local b=fresh();b.player.curStats[stat]=999
  T.check(not Effects.changeStage(b,b.player,stat,2,false).failed,"non-numeric modifier bypasses999guard")
  T.eq(b.player.stages[stat],2,"accuracy/evasion retain both increments")
end
for _,row in ipairs({{"attack","BRN"},{"speed","PAR"}}) do
  local b=fresh();local stat,status=unpack(row);local p,e=b.player,b.enemy
  p.curStats[stat]=999;p.mon.status=status;Status.bakePenalty(p)
  e.mon.status=status;Status.bakePenalty(e)
  T.check(effective(p,stat)<999,"actual status-adjusted stat is below999")
  T.check(not Effects.changeStage(b,p,stat,1,false).failed,"status penalty prevents false cap rejection")
  T.eq(Status.penaltyStacks(p,stat),0,"successful raise still clears affected user penalty")
  T.eq(Status.penaltyStacks(e,stat),2,"successful raise still stacks opponent penalty")
end
do
  local b=fresh();local p=b.player;p.curStats.attack=888;p.badges={BOULDERBADGE=true}
  T.eq(effective(p,"attack"),999,"badge-only numeric cap")
  T.check(Effects.changeStage(b,p,"attack",1,false).failed,"badge-only999blocks raise")
  T.eq(p.stages.attack,0,"badge cap preserves stage")
  p.hazeStatReset=true
  T.eq(effective(p,"attack"),888,"Haze suppresses badge boost")
  T.check(not Effects.changeStage(b,p,"attack",1,false).failed,"Haze effective value prevents false cap")
end
for item,stat in pairs({X_ATTACK="attack",X_DEFEND="defense",X_SPEED="speed",X_SPECIAL="special"}) do
  local b,save=fresh();b.player.curStats[stat]=999
  local result,msgs,extra=Items.use(b.data,save,item,nil,b)
  T.eq(result,"consumed","capped player X item still consumed")
  T.eq(#msgs,1,"item use line retained")
  T.eq(extra.afterMessages[1],nothing(b.data),"player X999no-effect line")
  T.eq(extra.useJingle,true,"player X999use jingle retained")
  T.eq(b.player.stages[stat],nil,"player X999does not increment")
  b.enemy.curStats[stat]=999
  local ai=AI.useItem(b,item)
  T.eq(#ai,2,"AI999used and no-effect lines without stat animation")
  T.eq(ai[2],nothing(b.data),"AI999no-effect line")
  T.eq(b.enemy.stages[stat],nil,"AI999does not increment")
end
local K=require("tests.save_compat._codec")
if K.gen1Available() then
  for _,version in ipairs({"red","blue","yellow"}) do
    local actual=K.gen1Data(version);local data={}
    for k,v in pairs(Data) do data[k]=v end
    for k,v in pairs(actual) do data[k]=v end
    local b,save=fresh(data,"MEWTWO")
    for _,who in ipairs({b.player,b.enemy}) do
      for stat in pairs(who.mon.statExp) do who.mon.statExp[stat]=65535 end
      who.mon.stats=Stats.calc(data.pokemon.MEWTWO,100,who.mon.dvs,who.mon.statExp)
      who.curStats=who.mon.stats;who.mon.hp=who.mon.stats.hp
    end
    T.eq(b.player.curStats.special,406,version.." actual maxDV/EXP Mewtwo")
    for _=1,2 do T.check(not Effects.primary.SPECIAL_UP2_EFFECT(b,b.player,b.enemy).failed,"first two canonical Amnesia rises") end
    T.eq(effective(b.player,"special"),999,version.." legal native stat cap")
    local msgs=Effects.primary.SPECIAL_UP2_EFFECT(b,b.player,b.enemy)
    T.check(msgs.failed,version.." actual Amnesia999rejected")
    T.eq(b.player.stages.special,5,version.." source Amnesia net+1rollback")
    b.enemy.stages.special=4
    T.eq(AI.useItem(b,"X_SPECIAL")[2],nothing(data),version.." actual AI cap message")
    T.eq(b.enemy.stages.special,4,version.." actual AI capped stage")
    local result,_,extra=Items.use(data,save,"X_SPECIAL",nil,b)
    T.eq(result,"consumed",version.." actual player X consumption")
    T.eq(extra.afterMessages[1],nothing(data),version.." actual player X cap message")
    T.eq(b.player.stages.special,5,version.." actual player X cap stage")
  end
else print("SKIP actual R/B/Y tables; numeric source-boundary checks still ran") end
T.finish("U01 Gen1 stat999 rollback")
