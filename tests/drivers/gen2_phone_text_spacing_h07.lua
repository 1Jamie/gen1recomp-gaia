local U = require("tests.drivers.util")
return function(game)
  local deadline = love.timer.getTime() + 25
  local speed, volume = game.speedOverride, love.audio.getVolume()
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
    local Phone=require("src.core.gen2.Phone")
    local world,save=game.world,game.save
    save.engineFlags=save.engineFlags or {};save.engineFlags[2]=true
    Phone.addContact(save,1)
    world:warpToMapId("DARK_CAVE_VIOLET_ENTRANCE",10,8,"down")
    settle(function()return world.map.id=="DARK_CAVE_VIOLET_ENTRANCE" and not world:busy() and not top() end,"actual no-service cave")
    assert(world.map.def.phoneService==false,"imported source no-service map")
    game:openStartMenuItem("pokegear")
    settle(function()return id()=="Gen2Pokegear" end,"actual Pokegear")
    local gear=top()
    for _=1,#gear.cards do if gear:card().id=="phone" then break end;tap("right") end
    assert(gear:card().id=="phone","owned phone card")
    wait(4)
    local function captureText(name,text)
      local expected=require("src.ui.gen2.Chrome").wrap(text,18)
      local rows={};local old=gear.text
      gear.text=function(self,s,x,y,...)
        if x==1 and y>=14 then rows[#rows+1]={s=s,y=y} end
        return old(self,s,x,y,...)
      end
      local captureOk,captureErr=xpcall(function()shot(name)end,debug.traceback)
      gear.text=old;assert(captureOk,captureErr)
      local found={}
      for _,r in ipairs(rows)do if r.s==expected[1] and r.y==14 then found[1]=true end
        if r.s==expected[2] and r.y==16 then found[2]=true end end
      assert(found[1] and found[2],"actual phone renderer two source lines at14/16")
    end
    captureText("01-phone-idle",gear:phoneText("AskWhoCall"))
    tap("a");assert(gear.phoneSubmenu,"real contact submenu")
    tap("a");assert(gear.call and gear.call.kind=="nosignal","normal CALL source no-service branch")
    wait(4);captureText("02-phone-no-service",gear.call.text)
    tap("b");assert(not gear.call and not gear.phoneSubmenu,"normal B hangup preserves card")

  end,debug.traceback)
  game.speedOverride=speed;love.audio.setVolume(volume)
  for _,key in ipairs({"writeSave", "writeOptions", "persistOptions"})do game[key]=writes[key] end
  print(ok and "PASS gen2_phone_text_spacing_h07" or "FAIL gen2_phone_text_spacing_h07 " .. tostring(err))
  love.event.quit(ok and 0 or 1)
  while true do coroutine.yield() end
end
