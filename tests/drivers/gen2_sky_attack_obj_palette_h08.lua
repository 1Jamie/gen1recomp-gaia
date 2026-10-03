local U=require("tests.drivers.util")
local Mon=require("src.battle.gen2.Mon")
local Palette=require("src.render.GbcPalette")
return function(game)
 local deadline=love.timer.getTime()+25
 local writes={};for _,key in ipairs({"writeSave","writeOptions","persistOptions"})do writes[key]=rawget(game,key)end
 local speed,volume=game.speedOverride,love.audio.getVolume()
 local mode,ramp,bgp=Palette.mode,Palette.customRamp,Palette.bgp
 local function check()assert(love.timer.getTime()<deadline,"H08 25 second deadline")end
 local function wait(n)for _=1,n do check();U.wait(1)end end
 local function tap(key)check();U.tap(game,key);wait(1)end
 local ok,err=xpcall(function()
  local identity=os.getenv("POKEPORT_IDENTITY") or ""
  assert(identity~="" and identity~="pokemon-love2d","isolated READY identity required")
  local out=assert(os.getenv("POKEPORT_SHOT_DIR"),"explicit capture directory required")
  local version=game.save.version
  assert(version=="gold" or version=="silver" or version=="crystal","actual G/S/C required")
  for _,key in ipairs({"writeSave","writeOptions","persistOptions"})do game[key]=function()error("H08 attempted persistent write")end end
  love.audio.setVolume(0);game.speedOverride=1
  for _=1,1800 do if game.world and game.world.map and not game.stack:top() and not game.world:busy()then break end;wait(1)end
  assert(game.world and game.world.map and not game.stack:top() and not game.world:busy(),"native field did not settle")
  local player=assert(Mon.new(game.data,"MOLTRES",80))
  local enemy=assert(Mon.new(game.data,"SNORLAX",80))
  game.save.party={player}
  assert(game.world:startBattle({wild=enemy}),"actual world battle route")
  local screen
  for _=1,5000 do
   screen=game.stack:top()
   if screen and screen.battle and screen.phase=="menu" and #screen.queue==0 and not screen.anim then break end
   if screen and screen.battle then tap("a")else wait(1)end
  end
  assert(screen and screen.battle and screen.phase=="menu" and not screen.anim,"actual intro/menu readiness")
  assert(screen.animView and screen.anims.moves.SKY_ATTACK,"actual source animation and renderer required")
  local base=assert(screen.palettes.battleObjects.PAL_BATTLE_OB_GRAY)
  Palette.setMode("gbc");Palette.setCustomRamp(nil)
  local function gpu(byte,display)
   check()
   local oldMode,oldRamp,oldBgp=Palette.mode,Palette.customRamp,Palette.bgp
   Palette.setMode(display=="custom" and "gbc" or display)
   Palette.setCustomRamp(display=="custom" and {{11,22,33},{44,55,66},{77,88,99},{111,122,133}} or nil)
   Palette.setBgp(0xff)
   local colors=Palette.remap(Palette.resolve(base),byte)
   local G=love.graphics;local canvas=G.newCanvas(160,144)
   canvas:setFilter("nearest","nearest")
   local oldCanvas=G.getCanvas();G.push("all");G.setCanvas(canvas);G.origin();G.clear(0,0,0,0);G.setShader()
   screen.animView:drawObjects(screen.anim,screen.battle)
   G.setCanvas(oldCanvas);G.pop()
   local pixels=canvas:newImageData();local opaque,transparent=0,0
   for y=0,143 do for x=0,159 do
    local r,g,b,a=pixels:getPixel(x,y)
    if a>.99 then
     opaque=opaque+1;local matched=false
     for _,c in ipairs(colors)do if math.abs(r-c[1]/255)<2/255 and math.abs(g-c[2]/255)<2/255 and math.abs(b-c[3]/255)<2/255 then matched=true;break end end
     assert(matched,"actual GPU OBJ pixel disagrees with source palette "..display)
    elseif a==0 then transparent=transparent+1 end
   end end
   assert(opaque>0 and transparent>0,"actual GPU object/transparent pixels required")
   print("H08 GPU "..version.." "..display.." byte="..string.format("%02x",byte).." opaque="..opaque.." transparent="..transparent)
   pixels:release();canvas:release()
   Palette.setMode(oldMode);Palette.setCustomRamp(oldRamp);Palette.setBgp(oldBgp)
  end
  for _,side in ipairs({"player","enemy"})do
   screen:animForMove("SKY_ATTACK",side,0,1)
   assert(screen.anim and screen.anim.animId=="SKY_ATTACK" and screen.anim.param==0,"production attack-animation path")
   local expected=side=="player" and {0xf0,0xa0,0x50} or {0xcc,0x88,0x44}
   for index,byte in ipairs(expected)do
    for _=1,1000 do
     if screen.anim and screen.anim.objects.obp0==byte and #screen.anim:oam()>0 then break end
     wait(1)
    end
    assert(screen.anim and screen.anim.objects.obp0==byte and screen.anim.bg.obp0==byte,"actual source owner pulse "..side)
    gpu(byte,"gbc")
    if index==2 then for _,display in ipairs({"dmg","classic","custom"})do gpu(byte,display)end end
    assert(U.still(game,out.."/h08-"..version.."-"..side.."-"..index.."-"..string.format("%02x",byte)..".png"),"settled source pulse capture")
    check();wait(1)
   end
   for _=1,2000 do if not screen.anim then break end;wait(1)end
   assert(not screen.anim,"full imported animation must finish normally")
   assert(screen.battle.player==player and screen.battle.enemy==enemy,"renderer probe leaves battle identities intact")
  end
  print("PASS H08 actual renderer seam/source script, six GPU palette captures "..version.."; no combat outcome claim")
 end,debug.traceback)
 for _,key in ipairs({"writeSave","writeOptions","persistOptions"})do game[key]=writes[key]end
 game.speedOverride=speed;love.audio.setVolume(volume)
 Palette.setMode(mode);Palette.setCustomRamp(ramp);Palette.setBgp(bgp)
 if not ok then print("FAIL H08 "..tostring(err))end
 love.event.quit(ok and 0 or 1)
 while true do coroutine.yield()end
end
