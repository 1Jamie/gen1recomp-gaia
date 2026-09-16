package.path = './?.lua;./?/init.lua;' .. package.path
local Help = require('src.ui.game3.help_system')
local Stack = require('src.ui.game3.stack')
local Options = require('src.core.game3.options')
local function press(key) return {wasPressed=function(_, k) return key==k end} end
local pack = {topics={'What?', 'How?', 'Terms', 'About', 'Types', 'EXIT'}, descriptions={}, greetings='Welcome', cancel='CANCEL', contexts={[20]={[1]={1},[2]={1}}}, entries={{{question='Question',answer='Answer'}},{{question='Dex',answer='Use it'}},{},{},{}}, basic={}}
Help.installPack(pack)
local game={phase='field',session={map='FR_ROUTE_1'},input=press('l')}
Stack.push('start', {})
assert(Help.update(game), 'opening help consumes the frame')
assert(Help.isOpen() and Help.level=='welcome')
assert(Stack.top().id=='start', 'help preserves underlying stack')
game.input=press('a'); assert(Help.update(game)); assert(Help.level=='main')
Help.handleInput(press('a')); assert(Help.level=='submenu')
Help.handleInput(press('a')); assert(Help.level=='article')
Help.handleInput(press('b')); assert(Help.level=='submenu' and Help.cursor==1)
Help.handleInput(press('b')); assert(Help.level=='main')
Help.handleInput(press('r')); assert(not Help.isOpen() and Stack.top().id=='start')
for mode=1,2 do
 Options.set(game.session,'buttonMode',mode)
 game.input=press('l'); assert(not Help.update(game) and not Help.isOpen())
end
Options.set(game.session,'buttonMode',0)
Stack.clear(); Stack.push('bag',{})
assert(Help.context(game)==9)
Stack.clear(); game.session.map='FR_PLAYERS_HOUSE_2F'; assert(Help.context(game)==14)
local Rules=require('src.core.game3.help_rules')
assert(not Rules.enabled(2,1,{flags={}}), 'Pokedex help hidden before receiving dex')
local Flags=require('src.core.game3.scripting.flags')
assert(Rules.enabled(2,1,{flags={[Flags.IDS.SYS_POKEDEX_GET]=true}}))
print('game3 help navigation/context/options tests passed')
-- Screen contexts must use the engine's actual identifiers/state shapes.
Stack.clear(); Stack.push('trainer',{side='back'});assert(Help.context(game)==11)
Stack.clear(); Stack.push('summary',{_page=1});assert(Help.context(game)==7)
local Battle=require('src.core.game3.battle')
Battle._active=true;Battle._st={wild=false,double=true}
assert(Help.context(game)==25,'battle context survives opening a summary')
Battle._active=false;Battle._st=nil
Stack.clear()
local Player=require('src.core.game3.player');Player.surfing=true
assert(Help.context(game)==22);Player.surfing=false
assert(Rules.enabled(2,4,{dex={owned={[1]=true,[4]=true}}}), 'switch gate reads session.dex')
Help.reset();game.session.flags={[Flags.IDS.SYS_SAW_HELP_SYSTEM_INTRO]=true}
assert(Help.show(game,20));assert(Help.level=='main','intro flag persists between sessions');Help.close()

-- Help owns the opening/closing frames as well as every frame in between.
local Game3=require('src.core.Game3')
local Runtime=require('src.core.game3.runtime')
local Audio=require('src.core.game3.audio')
local Rng=require('src.core.game3.rng')
local oldUpdate,oldActive=Runtime.update,Runtime.isActive
local oldAudio,oldPump,oldStep=Audio.update,Audio.pumpBgm,Rng.step
local ticks,audioTicks,rngTicks,items=0,0,0,0
Runtime.isActive=function() return true end
Runtime.update=function() ticks=ticks+1 end
Audio.update=function() audioTicks=audioTicks+1 end
Audio.pumpBgm=function() end
Rng.step=function() rngTicks=rngTicks+1 end
local g=Game3.new();g.phase='field';g.session={map='FR_ROUTE_1'}
g._handleRegisteredItem=function() items=items+1 end
for _,key in ipairs({'l','a','down','r'}) do
 g.input=press(key);g:fixedUpdate(1/60)
 assert(ticks==0 and items==0 and rngTicks==0 and audioTicks==0,'Help must pause simulation and audio callbacks')
end
g.input=press('');g:fixedUpdate(1/60)
assert(ticks==1 and items==1 and rngTicks==1 and audioTicks==1,'resume exactly once after closing')
Runtime.update,Runtime.isActive=oldUpdate,oldActive
Audio.update,Audio.pumpBgm,Rng.step=oldAudio,oldPump,oldStep
print('game3 Help pause/resume and persistence tests passed')
local Natives=require('src.core.game3.scripting.natives')
local Ctx=require('src.core.game3.scripting.ctx')
local ctx=Ctx.new();ctx.specialVars[0x8004]=32
Help.reset();Natives.special(ctx,0x17D,{})
assert(Help.context(game)==32)
Natives.special(ctx,0x17E,{})
Help.setContext(20);Natives.special(ctx,0x17F,{})
assert(Help.context(game)==32)
Natives.special(ctx,0x190,{});assert(Help.contextOverride==nil)
Natives.special(ctx,0x198,{})
game.input=press('l');assert(not Help.update(game))
Natives.special(ctx,0x199,{});assert(Help.update(game));Help.close()
assert(not Help.setContext(99))
local Font=require('src.ui.game3.frlg_font')
assert(Font.glyphId('①')==0x10A and Font.glyphId('△')==0x116 and Font.glyphId('✕')==0x117)
local oldSrc,oldCh,oldVol,oldDuck=Audio._bgmSource,Audio._cmdCh,Audio._bgmVolume,Audio._duck
local volume
Audio._bgmSource={setVolume=function(_,v) volume=v end};Audio._cmdCh=nil
Audio._bgmVolume=0.8;Audio._duck=0.5
Audio.setHelpActive(true);assert(volume==0.2)
Audio.setHelpActive(false);assert(volume==0.4)
Audio._bgmSource,Audio._cmdCh,Audio._bgmVolume,Audio._duck=oldSrc,oldCh,oldVol,oldDuck
print('Help script specials, symbols and audio restoration passed')
-- Long submenus scroll, retain cursor, page with left/right, and repeat holds.
local entries,list={},{}
for i=1,20 do entries[i]={question='Term '..i,answer='Definition '..i};list[i]=i end
pack.entries[3]=entries;pack.contexts[20]={[3]=list}
local progress={flags={[Flags.IDS.SYS_POKEMON_GET]=true,[Flags.IDS.WORLD_MAP_VIRIDIAN_FOREST]=true}}
Help.installPack(pack);Help.show({session=progress},20)
Help.handleInput(press('a'));Help.handleInput(press('right'))
assert(Help.cursor==8 and Help.scroll==1,'right pages seven rows')
Help.handleInput(press('a'));Help.handleInput(press('b'))
assert(Help.cursor==8 and Help.scroll==1,'return preserves scroll position')
local held={wasPressed=function() return false end,isDown=function(_,k)return k=='down' end}
for _=1,25 do Help.update({input=held}) end
assert(Help.cursor==10,'held down repeats after delay')
Help.close()
print('Help long-list scrolling, page navigation and held-input tests passed')
