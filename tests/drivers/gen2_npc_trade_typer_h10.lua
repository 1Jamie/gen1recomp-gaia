local U = require("tests.drivers.util")
return function(game)
  local deadline = love.timer.getTime() + 25
  local speed, volume = game.speedOverride, love.audio.getVolume()
  local previousOptions = game.save.options
  local writes = {}
  for _,key in ipairs({"writeSave", "writeOptions", "persistOptions"}) do
    writes[key] = rawget(game,key)
    game[key] = function() error("H UI driver attempted persistent write") end
  end
  local function check() assert(love.timer.getTime() < deadline, "25 second driver deadline") end
  local function wait(n) for _=1,n do check();U.wait(1) end end
  local function settle(predicate,label)
    for _=1,1800 do check();if predicate() then return end;wait(1) end
    error("bounded settle failed: " .. label)
  end
  local function tap(key) check();U.tap(game,key);wait(2) end
  local function top() return game.stack:top() end
  local function id() return top() and top().screenId end
  local out
  local function shot(name) check();assert(U.still(game,out .. "/" .. name .. ".png"),name);check() end
  local ok,err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY")
    assert(identity and identity ~= "pokemon-love2d", "isolated READY identity required")
    out = assert(os.getenv("POKEPORT_SHOT_DIR"), "explicit screenshot directory required")
    local version = require("src.core.GameVersion").get()
    assert(version == "gold" or version == "silver" or version == "crystal", "G/S/C only")
    love.audio.setVolume(0);game.speedOverride=200
    settle(function()return game.world and game.world.map and not top() and not game.world:busy() end,"native field ready")
    local Typer=require("src.ui.gen2.Typer")
    local Npc=require("src.core.gen2.NpcTrade")
    local world,save=game.world,game.save
    save.options={textSpeed="SLOW"}
    local keys={}
    for key,list in pairs(world.vm.scripts)do
      if type(list)=="table" then for _,cmd in ipairs(list)do
        if type(cmd)=="table" and cmd.op=="trade" and cmd.trade==0 then keys[#keys+1]=key;break end
      end end
    end
    table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
    local key=assert(keys[1],"actual imported NPC trade entrypoint")
    save.tradeFlags=save.tradeFlags or {};save.tradeFlags[0]=nil
    game.speedOverride=1
    assert(world.vm:start(key),"full imported trade script starts")
    settle(function()return id()=="Gen2TradeMenu" end,"actual VM/World trade screen")
    local menu=top()
    settle(function()return menu.typer and menu.typer.shown>=8 and Typer.typing(menu) end,"observable partial source typing")
    assert(world.vm:running() and not menu.picking,"VM waits for native trade UI")
    shot("01-trade-source-typing")
    game.speedOverride=200
    for _=1,40 do
      if menu.confirm and menu.confirm.page==#menu.confirm.pages and not Typer.typing(menu) then break end
      settle(function()return not Typer.typing(menu) end,"source page types")
      if menu.confirm and menu.confirm.page<#menu.confirm.pages then tap("a") end
    end
    assert(menu.confirm and menu.confirm.page==#menu.confirm.pages and not Typer.typing(menu),"final source YesNo ready")
    shot("02-trade-yes-no")
    tap("b");assert(menu.message and not menu.confirm,"normal B declines trade")
    settle(function()return not Typer.typing(menu) end,"cancellation text fully types")
    shot("03-trade-cancellation")
    for _=1,60 do
      if not world.vm:running() and not top() then break end
      tap("a");wait(2)
    end
    assert(not world.vm:running() and not top(),"full imported waitbutton/end resumes normally")
    assert(not Npc.done(save,0),"declining does not record trade completion")
    print("H10 " .. version .. " full imported script " .. tostring(key))

  end,debug.traceback)
  game.save.options=previousOptions
  game.speedOverride=speed;love.audio.setVolume(volume)
  for _,key in ipairs({"writeSave", "writeOptions", "persistOptions"})do game[key]=writes[key] end
  print(ok and "PASS gen2_npc_trade_typer_h10" or "FAIL gen2_npc_trade_typer_h10 " .. tostring(err))
  love.event.quit(ok and 0 or 1)
  while true do coroutine.yield() end
end
