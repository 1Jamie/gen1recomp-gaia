package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
require("src.core.Logger").warn=function()end
local T=require("tests.harness").suite("Gen2 NPC trade Typer H10")
local Trade=require("src.ui.gen2.TradeMenu")
local Typer=require("src.ui.gen2.Typer")
local Chrome=require("src.ui.gen2.Chrome")
local World=require("src.world.gen2.World")
local Stack=require("src.core.StateStack")
local Vm=require("src.script.gen2.Vm")
local Save=require("src.core.gen2.Save")
local Mon=require("src.battle.gen2.Mon")
local Npc=require("src.core.gen2.NpcTrade")
local Serializer=require("src.core.SaveSerializer")
local edge,held={},{}
local input={wasPressed=function(_,k)return edge[k] end,isDown=function(_,k)return held[k] end}
local function tick(menu,key)
 edge=key and {[key]=true} or {};menu:update();edge={}
end
local function done(menu)
 for _=1,3000 do if not Typer.typing(menu)then return end;tick(menu)end
 error("bounded typing failed")
end
local function finishRecord(menu,field)
 for _=1,40 do
  local r=menu[field];if not r then return end
  done(menu);tick(menu,"a")
 end
 error("bounded text pages failed")
end
local printed,original={},Chrome.print
Chrome.print=function(text,x,y,...)printed[#printed+1]={text=text,x=x,y=y};return original(text,x,y,...)end
local function choiceVisible(menu)
 printed={};menu:draw()
 for _,r in ipairs(printed)do if r.x==16 and r.y==8 then return true end end
 return false
end
for _,edition in ipairs({"gold","silver","crystal"})do
 require("src.core.GameVersion").set(edition)
 local root=os.getenv("POKEPORT_GEN2_"..edition:upper().."_DATA")
 if not root then print("SKIP H10 actual "..edition.." data")else
  local data={}
  for _,name in ipairs({"pokemon","moves","items","constants"})do data[name]=assert(loadfile(root.."/"..name..".lua"))()end
  local events=assert(loadfile(root.."/events.lua"))()
  local scripts=assert(loadfile(root.."/scripts.lua"))()
  local text=assert(loadfile(root.."/text.lua"))()
  local save=Save.newGame({trainerId=1234});save.options={textSpeed="SLOW"}
  local stack=setmetatable({},{__index=Stack});stack:init()
  local game={data=data,save=save,stack=stack,input=input}
  local world=setmetatable({game=game,eventTables=events,text=text},World);game.world=world
  local cmd
  for _,list in pairs(scripts)do if type(list)=="table"then for _,row in ipairs(list)do
   if type(row)=="table" and row.op=="trade"then cmd=row;break end
  end end if cmd then break end end
  local resumed=0
  local vm=Vm.new(scripts,text,nil,{eventTables=events,npcTrade=function(id,cb)
   world:openNpcTrade(id,function()resumed=resumed+1;cb()end)
  end})
  T.check(vm:start({assert(cmd),{op="end"}}),edition.." actual imported trade dispatch")
  local menu=stack:top()
  T.eq(menu.screenId,"Gen2TradeMenu",edition.." actual World/Screens consumer")
  T.check(menu.typer~=nil,edition.." intro creates source Typer")
  local before=menu.confirm.page
  tick(menu,"a")
  T.eq(menu.confirm and menu.confirm.page,before,edition.." premature A cannot change page")
  T.check(not menu.picking,edition.." premature A cannot open party")
  T.check(vm:running() and resumed==0,edition.." VM blocks while text owns UI")
  T.check(not choiceVisible(menu),edition.." choice hidden while intro types")
  tick(menu,"b")
  T.eq(menu.confirm and menu.confirm.page,before,edition.." premature B cannot cancel while typing")
  tick(menu,"down");tick(menu,"up")
  T.eq(menu.confirm and menu.confirm.choice,1,edition.." typing ignores choice navigation")
  for _=1,40 do
   if not menu.confirm or menu.confirm.page==#menu.confirm.pages then break end
   done(menu);tick(menu,"a")
  end
  if menu.confirm then
   T.check(not choiceVisible(menu),edition.." final page choice waits for typing")
   done(menu)
   T.check(choiceVisible(menu),edition.." source YesNo appears after final text")
   tick(menu,"down");T.eq(menu.confirm.choice,2,edition.." completed text permits No selection")
   tick(menu,"up");T.eq(menu.confirm.choice,1,edition.." completed text permits Yes selection")
   tick(menu,"a")
  end
  T.check(menu.picking and stack:top().screenId=="Gen2PartyMenu",edition.." normal choice opens real party")
  edge={b=true};stack:update();edge={}
  T.check(menu.message~=nil and not menu.picking,edition.." real party cancel begins cancellation text")
  T.check(Typer.typing(menu),edition.." cancellation uses Typer")
  finishRecord(menu,"message")
  T.eq(resumed,1,edition.." actual close resumes VM exactly once")
  T.check(not vm:running(),edition.." VM resumes to imported end")
  menu:close();T.eq(resumed,1,edition.." repeated close cannot repeat callback")
  for _,speed in ipairs({"FAST","MID","SLOW"})do
   save.options.textSpeed=speed
   local m=Trade.new(game,{save=save,eventTables=events,trade=0})
   m:sayRaw("é♂\nB",nil,function()end)
   local expected=({FAST=1,MID=3,SLOW=5})[speed]
   local total=m.typer and m.typer.total or 3
   T.eq(total,3,edition.." UTF8 is three glyphs")
   for _=1,expected-1 do tick(m)end
   T.eq(m.typer and m.typer.shown,0,edition.." "..speed.." source delay before first glyph")
   tick(m)
   T.eq(m.typer and m.typer.shown,1,edition.." "..speed.." first source glyph")
   held={a=true};tick(m);held={}
   T.eq(m.typer and m.typer.shown,2,edition.." "..speed.." held A accelerates one glyph")
   held={b=true};tick(m);held={}
   T.check(m.typer and m.typer:done(),edition.." held B completes text without callback")
  end
  local m=Trade.new(game,{save=save,eventTables=events,trade=0})
  m:sayRaw("one\ntwo\vthree\ffour",nil,function()end)
  done(m);tick(m,"a")
  T.eq(m.message.pages[2][1],"two",edition.." scroll keeps previous last line")
  T.check(m.message.pages[2].scrolled==true,edition.." scroll metadata marks retained line")
  T.eq(m.typer and m.typer.shown,3,edition.." retained scroll line is already visible")
  T.eq(m.typer and m.typer:lines()[2],"",edition.." new scroll line types from empty")
  T.eq(#m.message.pages,3,edition.." page order unchanged")
  for _,dialog in ipairs({Npc.DIALOG_CANCEL,Npc.DIALOG_WRONG,Npc.DIALOG_COMPLETE,Npc.DIALOG_AFTER})do
   m:say(dialog,function()end)
   T.check(Typer.typing(m),edition.." source "..dialog.." delays printing")
  end
  m=Trade.new(game,{save=save,eventTables=events,trade=0})
  local wrong=assert(Mon.new(data,m.row.give=="PIDGEY" and "RATTATA" or "PIDGEY",20))
  save.party={wrong};m:chose(1)
  T.check(m.message~=nil and Typer.typing(m),edition.." actual wrong-species branch types refusal")
  T.check(save.party[1]==wrong and not Npc.done(save,0),edition.." refusal preserves party and completion flag")
  m=Trade.new(game,{save=save,eventTables=events,trade=3})
  local wrongGender=assert(Mon.new(data,m.row.give,20,{dvs={attack=15,defense=15,speed=15,special=15}}))
  T.check(not Npc.genderOk(m.row,wrongGender),edition.." actual source gender-restricted fixture")
  save.party={wrongGender};m:chose(1)
  T.check(m.message~=nil and Typer.typing(m),edition.." actual wrong-gender branch types refusal")
  T.check(save.party[1]==wrongGender and not Npc.done(save,3),edition.." gender refusal preserves party and completion flag")
  m=Trade.new(game,{save=save,eventTables=events,trade=0})
  local given=assert(Mon.new(data,m.row.give,20,{dvs={attack=0,defense=15,speed=0,special=15}}))
  if not Npc.genderOk(m.row,given)then given=assert(Mon.new(data,m.row.give,20,{dvs={attack=15,defense=15,speed=15,special=15}}))end
  T.check(Npc.genderOk(m.row,given),edition.." valid source trade fixture")
  local givenBytes=Serializer.encode(given)
  local neighbor=assert(Mon.new(data,"PIDGEY",10));neighbor.opaqueH10={keep=true}
  save.party={given,neighbor};local callback=0;m.onClose=function()callback=callback+1 end
  m:chose(1)
  T.check(Npc.done(save,0),edition.." source sets trade flag before cable text")
  T.check(save.party[1]==given,edition.." exchange waits until cable text finishes")
  T.check(Typer.typing(m),edition.." cable text delays transaction callback")
  finishRecord(m,"message")
  local anim=stack:top()
  T.eq(anim and anim.screenId,"Gen2TradeAnim",edition.." normal animation pushed after real exchange")
  T.check(m.animating,edition.." normal animation owns input")
  T.check(save.party[1]==neighbor and neighbor.opaqueH10.keep,edition.." untouched neighbor identity and opaque data preserved")
  T.eq(save.party[2].species,m.row.get,edition.." real received species")
  T.eq(save.party[2].level,20,edition.." real trade level unchanged")
  T.same(save.party[2].dvs,Npc.dvs(m.row),edition.." received source DVs unchanged")
  T.eq(Serializer.encode(given),givenBytes,edition.." trade does not mutate given mon identity payload")
  local restored=assert(Serializer.decode(Serializer.encode(save)))
  T.same(restored.party[2].dvs,save.party[2].dvs,edition.." native in-memory serialization retains source DVs")
  T.check(restored.party[1].opaqueH10.keep and restored.tradeFlags[0],edition.." native serialization retains opaque neighbor and trade flag")
  local updates=0
  for _=1,10000 do
   if not m.animating then break end
   stack:update();updates=updates+1
  end
  T.check(updates>1000 and not m.animating,edition.." normal full animation completes without skip")
  T.check(m.message~=nil and Typer.typing(m),edition.." traded text types after animation")
  finishRecord(m,"message")
  T.eq(callback,1,edition.." complete dialogue closes once")
 end
end
Chrome.print=original
T.finish()
