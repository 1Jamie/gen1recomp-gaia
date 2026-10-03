package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness").suite("Gen2 Fly cancel font H06")
local Version=require("src.core.GameVersion")
local World=require("src.world.gen2.World")
local Stack=require("src.core.StateStack")
local Save=require("src.core.gen2.Save")
local Mon=require("src.battle.gen2.Mon")
for _,edition in ipairs({"gold","silver","crystal"}) do
  Version.set(edition)
  local root=os.getenv("POKEPORT_GEN2_"..edition:upper().."_DATA")
  if not root then print("SKIP H06 actual "..edition.." data") else
    local data={pokemon=assert(loadfile(root.."/pokemon.lua"))()}
    local landmarks=assert(loadfile(root.."/landmarks.lua"))()
    local font=edition=="crystal" and 3 or 6
    for _,n in ipairs({0,1,6}) do
      T.eq(World.flyCancelBlankFrames(n),21+font+3*n,edition.." source cancellation font budget party"..n)
    end
    for _,n in ipairs({1,6}) do
      local save=Save.newGame({trainerId=1234})
      save.engineFlags={};for i=0,500 do save.engineFlags[i]=true end
      save.party={};for i=1,n do save.party[i]=assert(Mon.new(data,"PIDGEY",20)) end
      local edge={}
      local stack=setmetatable({},{__index=Stack});stack:init()
      local game={data=data,save=save,stack=stack,input={wasPressed=function(_,k)return edge[k] end}}
      local world=setmetatable({game=game,landmarks=landmarks,map={def={landmark="LANDMARK_NEW_BARK_TOWN"}}},World)
      game.world=world
      local cancelled=0
      T.check(world:openFlyMap(save.party[1],{onCancel=function()cancelled=cancelled+1 end}),edition.." production FlyMap opens")
      T.eq(stack:top().left,28,edition.." build term unchanged")
      for _=1,28 do stack:update() end
      T.eq(stack:top().screenId,"Gen2Pokegear",edition.." actual picker")
      edge.b=true;stack:update();edge.b=nil
      local blank=stack:top()
      T.eq(blank.screenId,"Gen2BlankScreen",edition.." B enters actual blank consumer")
      T.eq(blank.left,21+font+3*n,edition.." actual cancel reload budget")
      for _=1,21+font+3*n-1 do stack:update() end
      T.check(stack:top()==blank,edition.." blank does not release one tick early")
      stack:update()
      T.eq(stack:top(),nil,edition.." blank releases at source budget")
      T.eq(cancelled,1,edition.." actual cancel callback exactly once")
    end
    T.eq(World.FLY_MAP_BUILD_FRAMES,28,edition.." map build invariant")
    T.eq(World.FLY_EXIT_WHITE_FRAMES,31,edition.." successful exit invariant")
    T.eq(World.MENU_EXIT_WHITE_FRAMES,23,edition.." other menu exit invariant")
  end
end
Version.set("red")
T.eq(World.flyCancelBlankFrames(0),21,"unsupported Gen1 context retains legacy base without claiming Gen2 font timing")
T.finish()
