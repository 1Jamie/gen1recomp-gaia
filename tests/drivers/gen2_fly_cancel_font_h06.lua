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
    local World=require("src.world.gen2.World")
    local FieldMoves=require("src.world.gen2.FieldMoves")
    local Mon=require("src.battle.gen2.Mon")
    local save,world=game.save,game.world
    save.player.badges=save.player.badges or {};save.player.badges.STORM=true
    save.engineFlags=save.engineFlags or {}
    for _,row in ipairs(FieldMoves.FLYPOINTS)do save.engineFlags[row.flag]=true end
    local flyer=assert(Mon.new(game.data,"PIDGEOTTO",24))
    table.remove(flyer.moves,1);Mon.learnMove(flyer,"FLY",game.data);save.party={flyer}
    world.mapScenes=world.mapScenes or {};world.mapScenes.NEW_BARK_TOWN=1
    world:warpToMapId("NEW_BARK_TOWN",9,8,"down")
    settle(function()return world.map.id=="NEW_BARK_TOWN" and not world:busy() and not top() end,"New Bark field uncovered")
    game:openStartMenuItem("pokemon")
    local opening=top()
    local font=version=="crystal" and 3 or 6
    assert(opening and opening.screenId=="Gen2MenuFade" and opening.white==8+font+3,
      "actual normal party opening includes source font budget")
    print("H06 " .. version .. " normal party opening " .. opening.white .. " white ticks")
    settle(function()return id()=="Gen2PartyMenu" end,"actual party menu")
    local party=top();tap("a");local sub=assert(party.submenu)
    local row
    for n,item in ipairs(sub.items)do if item.id=="FLY" then row=n end end
    assert(row,"actual FLY action")
    for _=1,#sub.items do if sub.index==row then break end;tap("down") end
    tap("a")
    settle(function()return id()=="Gen2Pokegear" and top().fly end,"actual Fly chooser")
    wait(8);shot("01-fly-destination")
    local expected=21+font+3
    local original=World.flyCancelBlankFrames
    local observed
    World.flyCancelBlankFrames=function(n) observed=original(n);return observed end
    local cancelOk,cancelErr=xpcall(function()
      tap("b")
      settle(function()return top()==party end,"cancel reload restores original party screen")
    end,debug.traceback)
    World.flyCancelBlankFrames=original
    assert(cancelOk,cancelErr);assert(observed==expected,"actual cancel producer source font budget")
    assert(World.FLY_MAP_BUILD_FRAMES==28 and World.FLY_EXIT_WHITE_FRAMES==31,"retained build/success terms")
    assert(save.party[1]==flyer and #save.party==1,"party preserved by cancellation")
    wait(8);shot("02-restored-party")
    print("H06 " .. version .. " cancellation reload " .. observed .. " ticks; font " .. font)

  end,debug.traceback)
  game.speedOverride=speed;love.audio.setVolume(volume)
  for _,key in ipairs({"writeSave", "writeOptions", "persistOptions"})do game[key]=writes[key] end
  print(ok and "PASS gen2_fly_cancel_font_h06" or "FAIL gen2_fly_cancel_font_h06 " .. tostring(err))
  love.event.quit(ok and 0 or 1)
  while true do coroutine.yield() end
end
