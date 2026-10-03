package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness").suite("Gen2 Sky Attack OBJ palette H08")
local G=love.graphics
local function copy(t)local out={};for k,v in pairs(t)do out[k]=type(v)=="table" and copy(v) or v end;return out end
G.newShader=function(source)return {source=source,uniforms={},send=function(self,k,v)self.uniforms[k]=copy(v)end}end
local quadCtor=G.newQuad
G.newQuad=function(...)local q=quadCtor(...);q.getViewport=function(self)return self.x,self.y,self.w,self.h end;return q end
local Palette=require("src.render.GbcPalette")
local Runner=require("src.battle.gen2.AnimRunner")
local Objects=require("src.battle.gen2.AnimObjects")
local View=require("src.ui.gen2.BattleAnimView")
local bit=require("bit")
local function sameUniforms(u,colors)
 if not u then return false end
 for i=1,4 do local got=u["pal"..(i-1)];if not got then return false end
  for j=1,3 do if math.abs(got[j]-colors[i][j]/255)>1e-9 then return false end end
 end
 return true
end
local function draw(view,runner,battle)
 local rows={};local prior={caller=true};G.setShader(prior)
 G.draw=function(image,q,x,y,rot,sx,sy)
  local shader=G.getShader()
  rows[#rows+1]={uniforms=shader and shader.uniforms and copy(shader.uniforms),shader=shader,x=x,y=y,sx=sx,sy=sy}
 end
 local bgp=Palette.bgp
 local uses,actualUse=0,Palette.useRaw
 Palette.useRaw=function(colors)uses=uses+1;return actualUse(colors)end
 view:drawObjects(runner,battle or {})
 Palette.useRaw=actualUse
 T.eq(G.getShader(),prior,"caller shader restored")
 T.eq(Palette.bgp,bgp,"active BG byte preserved by OBJ draw")
 T.check(#rows>0,"actual imported OAM draws")
 return rows,uses
end
local function imageView(data,palettes,root)
 local view=View.new(data,palettes)
 for _,gfx in pairs(data.gfx)do
  local path=root.."/../../"..gfx.image
  local file=assert(io.open(path,"rb"),"actual imported art required");file:close()
  view.images[gfx.image]=G.newImage(path)
 end
 return view
end
local oldMode,oldRamp,oldBgp=Palette.mode,Palette.customRamp,Palette.bgp
for _,edition in ipairs({"gold","silver","crystal"})do
 local root=os.getenv("POKEPORT_GEN2_"..edition:upper().."_DATA")
 if not root then print("SKIP H08 actual "..edition.." cache")else
  local data=assert(loadfile(root.."/battle_anims.lua"))()
  local constants=assert(loadfile(root.."/constants.lua"))()
  local palettes=assert(loadfile(root.."/palettes.lua"))()
  T.eq(data.objects.BATTLE_ANIM_OBJ_SKY_ATTACK.palette,"PAL_BATTLE_OB_GRAY",edition.." imported source slot")
  for _,sgb in ipairs({false,true})do for turn=0,1 do
   Palette.setMode("gbc");Palette.setCustomRamp(nil);Palette.setBgp(0x1b)
   local runner=Runner.new({data=data,constants=constants,battleTurn=turn,animId="SKY_ATTACK",param=0,sgb=sgb})
   runner:start(data.moves.SKY_ATTACK)
   local view=imageView(data,palettes,root);local beats=0
   for _=1,200 do
    runner:step()
    if runner.objects.obp0~=nil and beats<8 then
     beats=beats+1
     local byte=(sgb and {0xff,0xff,0,0} or {0xff,0xaa,0x55,0xaa})[math.floor((beats-1)/2)+1]
     byte=bit.band(byte,turn==0 and 0xf0 or 0xcc)
     T.eq(runner.objects.obp0,byte,edition.." exact two-frame object cycle")
     T.eq(runner.bg.obp0,byte,edition.." source-ordered shared register write")
     local rows=draw(view,runner)
     T.check(sameUniforms(rows[1].uniforms,Palette.remap(Palette.resolve(palettes.battleObjects.PAL_BATTLE_OB_GRAY),byte)),edition.." actual source OBJ uniforms")
    end
    if beats==8 then break end
   end
   T.eq(beats,8,edition.." eight imported script beats")
   local oam=runner:oam();local one=copy(assert(oam[1]));local loaded=runner.loaded
   local fixture={objects=runner.objects,bg=runner.bg,loaded=loaded,oam=function()return {one,copy(one)}end}
   for _,mode in ipairs({"gbc","dmg","classic","custom"})do
    Palette.setMode(mode=="custom" and "gbc" or mode)
    Palette.setCustomRamp(mode=="custom" and {{11,22,33},{44,55,66},{77,88,99},{111,122,133}} or nil)
    Palette.setBgp(0xff)
    runner.bg.obp0=0x50
    local first
    for _,slot in ipairs({"GRAY","YELLOW","RED","GREEN","BLUE","BROWN"})do
     one.palette="PAL_BATTLE_OB_"..slot
     local rows,uses=draw(view,fixture)
     T.eq(uses,1,"same-palette OBJ pair keeps one shader configuration")
     local colors=Palette.resolve(palettes.battleObjects[one.palette])
     local expected=(slot=="GRAY" or slot=="YELLOW") and Palette.remap(colors,0x50) or colors
     T.check(sameUniforms(rows[1].uniforms,expected),edition.." "..mode.." exact scope "..slot)
     T.check(sameUniforms(rows[2].uniforms,expected),edition.." repeated object same uniforms "..slot)
     T.check(rows[1].shader.source:find("px.a",1,true)~=nil,"shared shader keeps texture alpha path")
     local pos={rows[1].x,rows[1].y,rows[1].sx,rows[1].sy}
     if not first then first=pos else T.same(pos,first,"OBJ palette change preserves geometry/flip")end
    end
    for _,slot in ipairs({"ENEMY","PLAYER"})do
     one.palette="PAL_BATTLE_OB_"..slot
     local battle={enemy={species="PIDGEY"},player={species="PIDGEY"}}
     local rows=draw(view,fixture,battle)
     T.check(sameUniforms(rows[1].uniforms,Palette.resolve(view:objPalette(one.palette,battle))),edition.." battler slot excludes OBJ/BG bytes "..slot)
    end
   end
   Palette.setMode("gbc");Palette.setCustomRamp(nil);Palette.setBgp(0x1b)
   Runner.COMMANDS.obp0(runner,{"obp0",0x1b})
   T.eq(runner.bg.obp0,0x1b,"explicit command is canonical last writer")
   one.palette="PAL_BATTLE_OB_GRAY"
   T.check(sameUniforms(draw(view,fixture)[1].uniforms,Palette.remap(palettes.battleObjects[one.palette],0x1b)),"old object shadow cannot defeat command")
   Runner.COMMANDS.resetobp0(runner)
   local reset=sgb and 0xf0 or 0xe0
   T.eq(runner.bg.obp0,reset,"source reset writes canonical owner")
   T.check(sameUniforms(draw(view,fixture)[1].uniforms,Palette.remap(palettes.battleObjects[one.palette],reset)),"old shadow cannot defeat reset")
   local st=runner.bg:queue("BATTLE_BG_EFFECT_CYCLE_OBPALS_GRAY_AND_YELLOW",0,0,1)
   runner.bg:playFrame()
   T.eq(runner.bg.obp0,0x90,"source second BG cycle value runs after command and owns register")
   runner.objects:playFrame()
   T.eq(runner.bg.obp0,runner.objects.obp0,"object function is final writer after BG effect")
   runner.objects:clearObjs();runner.bg.obp0=0x1b;runner.objects:playFrame()
   T.eq(runner.bg.obp0,0x1b,"inactive object does not replay retained shadow")
   local available=Palette.available;Palette.available=function()return false end
   local rows=draw(view,fixture);Palette.available=available
   T.eq(rows[1].shader.caller,true,"shaderless fallback delegates with caller intact")
   for _=1,2 do
    runner:start(data.moves.SKY_ATTACK)
    T.eq(runner.bg.obp0,0xe4,"repeat start resets canonical owner")
    T.eq(runner.objects.obp0,nil,"repeat start clears debug shadow")
    for _=1,1000 do if not runner:step()then break end end
    T.check(runner:done(),"normal imported script terminates")
   end
  end end
  data.scripts.H08_COMMAND_CONTROL={{"obp0",0x1b},{"wait",1},{"resetobp0"},{"wait",1},{"obp1",0xaa},{"wait",1},{"ret"}}
  local command=Runner.new({data=data,constants=constants})
  command:start("H08_COMMAND_CONTROL")
  for frame=1,6 do
   command:step()
   T.eq(command.bg.obp0,frame<=2 and 0x1b or 0xe0,"actual command fetch/wait/reset order"..frame)
  end
  T.eq(command.bg.obp1,0xaa,"OBP1 command retains independent owner")
  command:step();T.check(command:done(),"actual command script terminates")
  local ordered=Runner.new({data=data,constants=constants,animId="SKY_ATTACK"})
  ordered:start(data.moves.SKY_ATTACK)
  for _=1,200 do ordered:step();if ordered.objects.obp0 then break end end
  data.scripts.H08_ORDER_CONTROL={{"obp0",0x1b},{"bgeffect","BATTLE_BG_EFFECT_CYCLE_OBPALS_GRAY_AND_YELLOW",0,0,1},{"wait",1}}
  ordered.address={key="H08_ORDER_CONTROL",index=1};ordered.delay=0
  ordered:step()
  T.eq(ordered.bg.obp0,ordered.objects.obp0,"actual Runner.step commands/BG/OBJ final-writer order")
  local view=imageView(data,palettes,root)
  local first=copy(assert(ordered:oam()[1]));first.palette="PAL_BATTLE_OB_GRAY"
  local second=copy(first);second.palette="PAL_BATTLE_OB_RED"
  local red=palettes.battleObjects.PAL_BATTLE_OB_RED
  palettes.battleObjects.PAL_BATTLE_OB_RED=palettes.battleObjects.PAL_BATTLE_OB_GRAY
  local fixture={objects=ordered.objects,bg=ordered.bg,loaded=ordered.loaded,oam=function()return {first,second}end}
  Palette.setMode("gbc");Palette.setCustomRamp(nil);Palette.setBgp(0xff);ordered.bg.obp0=0x50
  local rows,uses=draw(view,fixture)
  T.eq(uses,2,"aliased colors with distinct source scope keep separate shader runs")
  T.check(sameUniforms(rows[1].uniforms,Palette.remap(palettes.battleObjects.PAL_BATTLE_OB_GRAY,0x50)),"aliased source palette affected slot remaps")
  T.check(sameUniforms(rows[2].uniforms,palettes.battleObjects.PAL_BATTLE_OB_GRAY),"aliased fixed slot remains unaffected within batch")
  palettes.battleObjects.PAL_BATTLE_OB_RED=red
  ordered.bg.obp0=nil;ordered.objects.obp0=0xff
  rows=draw(view,fixture)
  T.check(sameUniforms(rows[1].uniforms,palettes.battleObjects.PAL_BATTLE_OB_GRAY),"present owner nil is identity and excludes stale shadow")
  local pool=Objects.new(data,constants,{battleTurn=0})
  pool:queue("BATTLE_ANIM_OBJ_SKY_ATTACK",64,80,0,function()return 0 end)
  pool:playFrame();pool:playFrame()
  T.eq(pool.obp0,0xf0,"standalone pool preserves source palette seam")
  local charge=Runner.new({data=data,constants=constants,animId="SKY_ATTACK",param=1})
  charge:start(data.moves.SKY_ATTACK);for _=1,48 do charge:step()end
  T.eq(charge.objects.obp0,nil,edition.." source charge branch avoids Sky Attack object")
 end
end
Palette.setMode(oldMode);Palette.setCustomRamp(oldRamp);Palette.setBgp(oldBgp)
T.finish()
