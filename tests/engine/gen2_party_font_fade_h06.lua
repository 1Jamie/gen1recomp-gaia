package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness").suite("Gen2 normal party font fade H06")
local Version=require("src.core.GameVersion")
local Fade=require("src.ui.gen2.MenuFade")
local Game2=require("src.core.Game2")
local Stack=require("src.core.StateStack")
local Save=require("src.core.gen2.Save")
local Mon=require("src.battle.gen2.Mon")
local initial=Version.get()
local constants={OUT_FRAMES=8,OUT_WHITE_FRAMES=2,IN_RAMP_FRAMES=6,
 PARTY_FONT_FRAMES=3,PARTY_WHITE=11,PARTY_ICON_FRAMES=3,PACK_RELOAD_FRAMES=2,
 PACK_WHITE=16,GEAR_RELOAD_FRAMES=5,GEAR_WHITE=20,GEAR_EXIT_WHITE=4,
 CARD_RELOAD_FRAMES=2,CARD_WHITE=14,DEX_RELOAD_FRAMES=6,DEX_WHITE=27,OPTION_WHITE=8}
for key,value in pairs(constants)do T.eq(Fade[key],value,"public constant retained "..key)end
for _,edition in ipairs({"gold","silver","crystal"})do
 Version.set(edition)
 local root=os.getenv("POKEPORT_GEN2_"..edition:upper().."_DATA")
 if not root then print("SKIP H06 normal party actual "..edition.." data")else
  local data={pokemon=assert(loadfile(root.."/pokemon.lua"))()}
  local font=edition=="crystal" and 3 or 6
  for _,n in ipairs({0,1,6})do
   local save=Save.newGame({trainerId=1234});save.party={}
   for i=1,n do save.party[i]=assert(Mon.new(data,"PIDGEY",20))end
   local identities={};for i,mon in ipairs(save.party)do identities[i]=mon end
   local stack=setmetatable({},{__index=Stack});stack:init()
   local game=setmetatable({save=save,data=data,stack=stack,world={}},Game2)
   local opened=0;local actualPush=Game2.pushStartMenuItem
   game.pushStartMenuItem=function(self,id)opened=opened+1;return actualPush(self,id)end
   game:openStartMenuItem("pokemon")
   local fade=stack:top();local white=8+font+3*n;local total=8+white
   local label=edition.." party"..n
   T.eq(fade.screenId,"Gen2MenuFade",label.." actual Game2/Screens fade")
   T.eq(fade.white,white,label.." actual source reload budget")
   T.eq(fade.total,total,label.." actual full budget")
   T.eq(fade:level(),.25,label.." first palette endpoint")
   local whiteDraws=0;local ramp={.25,.25,.5,.5,.75,.75,1,1}
   for f=1,total do
    if f<=8 then T.eq(fade:level(),ramp[f],label.." outward source ramp"..f)end
    if stack:top()==fade and fade:level()==1 then whiteDraws=whiteDraws+1 end
    fade:update()
    if f==total-1 then
     T.eq(stack:top(),fade,label.." final white tick still owns stack")
     T.eq(opened,0,label.." no early real party construction")
    end
   end
   T.eq(whiteDraws,2+white,label.." white draw ticks include full reload")
   T.eq(opened,1,label.." actual party constructed exactly once")
   T.eq(stack:top() and stack:top().screenId,"Gen2PartyMenu",label.." real party handoff")
   fade:update();T.eq(opened,1,label.." repeated update cannot repeat handoff")
   for i,mon in ipairs(identities)do T.eq(save.party[i],mon,label.." party identity retained"..i)end
   game:closeStartMenuItem("pokemon")
   local closing=stack:top()
   T.eq(closing.kind,"in",label.." actual Game2 close")
   T.eq(closing.white,23,label.." closing reload unchanged")
   T.eq(closing.total,29,label.." closing duration unchanged")
   local inward={.75,.75,.5,.5,.25,.25}
   for f=1,29 do
    if f<=23 then T.eq(closing:level(),1,label.." unchanged close white"..f)
    else T.eq(closing:level(),inward[f-23],label.." source inward ramp"..(f-23))end
    closing:update()
   end
   T.eq(stack:top(),nil,label.." actual close handoff")
   T.eq(closing:level(),0,label.." final field uncovered endpoint")
   closing:update();T.eq(stack:top(),nil,label.." repeated close update safe")
  end
  for page,value in pairs({pack=16,pokegear=20,status=14,pokedex=27,option=8})do
   T.eq(Fade.openWhite(page,6),value,edition.." other page budget unchanged "..page)
   T.eq(Fade.closeWhite(page),page=="pokegear" and 27 or 23,edition.." other close budget unchanged "..page)
  end
  T.eq(Fade.openWhite("save"),nil,edition.." SAVE remains immediate")
  T.eq(Fade.openWhite("mods"),nil,edition.." MODS remains immediate")
 end
end
for _,edition in ipairs({"red","yellow","emerald","firered","leafgreen"})do
 Version.set(edition)
 for _,n in ipairs({0,1,6})do T.eq(Fade.openWhite("pokemon",n),11+3*n,edition.." non-Gen2 legacy fallback"..n)end
end
Version.set(initial)
T.finish()
