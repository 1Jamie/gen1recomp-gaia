package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local T = require('tests.harness').suite('Route22 facing phases #2644')
local Version = require('src.core.GameVersion')
local Game = require('src.core.Game')
local OW = require('src.world.OverworldController')
local Runner = require('src.script.ScriptRunner')
local Map = require('src.world.Map')
local Player = require('src.world.Player')
local NPC = require('src.world.NPC')
local MapScripts = require('src.script.MapScripts')
local Music = require('src.core.Music')
local TextBox = require('src.render.TextBox')
local Font = require('src.render.Font')
local Data = require('src.core.Data')
local previous={version=Version.get(),data=Game.data,save=Game.save,stack=Game.stack,map_scripts=Data.map_scripts}
local bindings, fontBindings = {},{}
local resetFontCaches
for i=1,100 do
  local name,value=debug.getupvalue(OW.onStepComplete,i)
  if not name then break end
  if name=='Game' or name=='mapScripts' then
    bindings[#bindings+1]={index=i,value=value}
    debug.setupvalue(OW.onStepComplete,i,name=='Game' and Game or MapScripts)
  end
end
for i=1,100 do
  local name,value=debug.getupvalue(Font.load,i)
  if not name then break end
  if name=='state' or name=='loadedFrom' then fontBindings[#fontBindings+1]={index=i,value=value} end
  if name=='resetTextCaches' then resetFontCaches=value end
end
local base
for i=1,100 do
  local name,value=debug.getupvalue(MapScripts.attachBase,i)
  if not name then break end
  if name=='base' then base=value;break end
end
local previousBase=assert(base).ROUTE_22
base.ROUTE_22=nil
Data.map_scripts=nil
local story = require('data.scripts.story5')
local oldMusic,oldMapMusic = Music.play,Music.playMap
Music.play = function() end;Music.playMap=Music.play
local observed = {}
local success,problem=xpcall(function()
for _, version in ipairs({'red','blue','yellow'}) do
  Version.set(version)
  local root = os.getenv('ROUTE22_' .. version:upper() .. '_CACHE')
  local cartridgeRoot=os.getenv('GEN1_' .. version:upper() .. '_CACHE')
  if not root and cartridgeRoot then root=cartridgeRoot .. '/data/generated' end
  if root then
  local data = {}
  for _, key in ipairs({'maps','tilesets','text','sprites','field','constants','font'}) do
    data[key] = assert(loadfile(root .. '/' .. key .. '.lua'))()
  end
  Game.data = data
  Font.load(data)
  local map = Map.new(data.maps.ROUTE_22, data.tilesets[data.maps.ROUTE_22.tileset])
  T.eq(map.id, 'ROUTE_22', version .. ' actual imported map ID')
  MapScripts.attachBase('ROUTE_22', story.ROUTE_22)
  for _, n in ipairs({1,2}) do for _, y in ipairs({4,5}) do for _,outcome in ipairs({'win','lose'}) do
    local tag = version .. ' rival' .. n .. ' y' .. y .. ' ' .. outcome
    Game.save = {version=version,generation=1,player={name='RED',rival='BLUE'},flags=n==1 and
      {EVENT_GOT_POKEDEX=true} or {EVENT_BEAT_BROCK=true,EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE=true,EVENT_BEAT_GIOVANNI=true}}
    local pushed = {}
    Game.stack = {push=function(_, box) pushed[#pushed+1]=box end}
    local player = Player.new(data,29,y,'left')
    local ow = setmetatable({map=map,player=player,npcs={},entities={player},scriptMoves={}}, {__index=OW})
    local finished=0
    ow.afterBattle=function(_,result) T.eq(result,outcome,tag .. ' battle completion callback result');finished=finished+1 end
    ow.runner = Runner.new(Game,ow)
    ow:onStepComplete()
    T.check(ow.runner:isRunning(),tag .. ' actual completed-step dispatch triggers base hook')
    local npc = assert(ow:npcByIndex(n))
    T.eq(npc.def.x,25,tag .. ' actual ROM spawn x')
    T.eq(npc.def.y,5,tag .. ' actual ROM spawn y')
    T.eq(npc.cellX,25,tag .. ' movement is pending on trigger')
    T.eq(ow.runner.pc,2,tag .. ' actual runner waits at approach')
    T.eq(#pushed,0,tag .. ' no text before movement')
    T.eq(player.facing,'left',tag .. ' source trigger facing LEFT')
    local frames, wrong, beforeEnd = 0,0,0
    local trace = {}
    while #pushed==0 and frames<160 do
      ow:updateScriptMoves()
      if #pushed==0 then
        if player.facing~='left' then wrong=wrong+1 end
        T.eq(npc.facing,'right',tag .. ' approach NPC faces RIGHT frame' .. frames)
      end
      if npc.moving then NPC.update(npc,map,ow.entities) end
      frames=frames+1
      if #pushed==0 and npc.cellX~=(y==4 and 29 or 28) then beforeEnd=beforeEnd+1 end
      trace[#trace+1]={frame=frames,x=npc.cellX,y=npc.cellY,progress=npc.progress,moving=npc.moving,
        playerFacing=player.facing,rivalFacing=npc.facing,text=#pushed>0}
    end
    T.check(frames<160,tag .. ' real movement reaches dialogue under bound')
    T.check(beforeEnd>0,tag .. ' tested while rival not at destination')
    T.eq(wrong,0,tag .. ' source LEFT throughout approach')
    T.eq(npc.cellX,y==4 and 29 or 28,tag .. ' actual movement target x')
    T.eq(npc.cellY,5,tag .. ' actual movement target y')
    T.eq(npc.moving,false,tag .. ' no moving NPC when text opens')
    T.eq(npc.facing,y==4 and 'up' or 'right',tag .. ' rival final direction')
    T.eq(player.facing,y==4 and 'down' or 'left',tag .. ' player final direction')
    T.eq(getmetatable(pushed[1]),TextBox,tag .. ' actual TextBox owns prebattle dialogue')
    local label='_Route22RivalBeforeBattleText' .. n
    T.check(type(data.text[label])=='string' and #data.text[label]>0,tag .. ' imported required dialogue exists')
    T.eq(ow.runner.script[ow.runner.pc][1],'show_text',tag .. ' yielded before battle')
    T.eq(ow.runner.script[ow.runner.pc][2],label,tag .. ' exact prebattle dialogue')
    T.eq(Game.save.flags['EVENT_BEAT_ROUTE22_RIVAL_' .. (n==1 and '1ST' or '2ND') .. '_BATTLE'],nil,
      tag .. ' no battle progression prematurely committed')
    observed[#observed+1]={version=version,n=n,y=y,frames=frames,wrongFacingFrames=wrong,trace=trace}
    ow.runner.ctx.resumeBattle={result=outcome,battle={}}
    pushed[1].onDone()
    local beat='EVENT_BEAT_ROUTE22_RIVAL_' .. (n==1 and '1ST' or '2ND') .. '_BATTLE'
    if outcome=='win' then
      T.eq(Game.save.flags[beat],true,tag .. ' victory commits only matching story flag')
      T.eq(#pushed,2,tag .. ' actual resumed battle success opens postbattle text')
      T.eq(finished,0,tag .. ' afterBattle waits for script walkoff')
      pushed[2].onDone()
      local exitFrames=0
      while ow.runner:isRunning() and exitFrames<400 do
        ow:updateScriptMoves()
        T.check(map:isWalkableCell(npc.cellX,npc.cellY),tag .. ' exit remains on actual walkable ground')
        T.check(npc.cellX~=29 or npc.cellY~=y,tag .. ' exit avoids parked player')
        if npc.moving then NPC.update(npc,map,ow.entities) end
        exitFrames=exitFrames+1
      end
      T.check(exitFrames<400,tag .. ' real exit finishes under bound')
      T.eq(npc.cellX,n==1 and 31 or 25,tag .. ' source exit end x')
      T.eq(npc.cellY,n==1 and 10 or 5,tag .. ' source exit end y')
    else
      T.eq(Game.save.flags[beat],nil,tag .. ' loss does not commit story flag')
      T.eq(#pushed,1,tag .. ' loss skips victory text')
      T.eq(#ow.scriptMoves,0,tag .. ' loss skips walkoff')
    end
    T.eq(finished,1,tag .. ' actual completion continuation runs once')
    T.eq(ow.runner:isRunning(),false,tag .. ' script finishes')
    T.eq(ow:npcByIndex(n),nil,tag .. ' hide_object removes live rival')
    T.eq(Game.save.objectToggles.ROUTE_22['ROUTE22_RIVAL'..n],false,tag .. ' final toggle preserved')
  end end end
  local function gate(flags,x,y,busy)
    local ran=0
    local ow={player={facing='right'},runner={isRunning=function()return busy end,run=function()ran=ran+1 end}}
    local game={data=data,save={flags=flags}}
    T.eq(story.ROUTE_22.onStep(game,ow,x,y),false,version .. ' negative trigger')
    T.eq(ran,0,version .. ' negative trigger queues nothing')
    T.eq(ow.player.facing,'right',version .. ' negative trigger preserves direction')
  end
  gate({},29,4,false)
  gate({EVENT_GOT_POKEDEX=true,EVENT_BEAT_BROCK=true},29,4,false)
  gate({EVENT_BEAT_GIOVANNI=true,EVENT_BEAT_ROUTE22_RIVAL_2ND_BATTLE=true},29,4,false)
  gate({EVENT_BEAT_GIOVANNI=true},28,4,false)
  gate({EVENT_BEAT_GIOVANNI=true},29,4,true)
  local ow={player={facing='left'},runner={isRunning=function()return false end,run=function()end}}
  T.eq(story.CERULEAN_CITY.onStep({data=data,save={flags={}}},ow,20,6),true,version .. ' Cerulean still triggers')
  T.eq(ow.player.facing,'up',version .. ' generic ambush retains immediate UP control')
  else print('SKIP #2644 actual '..version..' phase/movement/continuation gate: set ROUTE22_'..version:upper()..'_CACHE or GEN1_'..version:upper()..'_CACHE') end
end
end,debug.traceback)
Music.play,Music.playMap=oldMusic,oldMapMusic
Game.data,Game.save,Game.stack=previous.data,previous.save,previous.stack
Data.map_scripts=previous.map_scripts;base.ROUTE_22=previousBase
for _,binding in ipairs(bindings) do debug.setupvalue(OW.onStepComplete,binding.index,binding.value) end
for _,binding in ipairs(fontBindings) do debug.setupvalue(Font.load,binding.index,binding.value) end
if resetFontCaches then resetFontCaches() end
Version.set(previous.version)
assert(success,problem)
if os.getenv('ROUTE22_OBSERVATIONS') then
  local f=assert(io.open(os.getenv('ROUTE22_OBSERVATIONS'),'wb'))
  f:write(require('src.link.Json').encode(observed));f:close()
end
T.finish()
