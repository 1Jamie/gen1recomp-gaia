-- pokecrystal/engine/pokegear/radio.asm:1425
local U = require("tests.drivers.util")
local Buena = require("src.core.gen2.Buena")
local BuenaScreen = require("src.ui.gen2.BuenaPassword")
local Music = require("src.core.Music")
local Save = require("src.core.gen2.Save")
local Apricorns = require("src.core.gen2.Apricorns")

return function(game)
  local ok, err = xpcall(function()
    U.wait(45)
    local world, save = assert(game.world), assert(game.save)
    assert(world.map, "Gen2 world did not boot")
    local version = save.version
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"))
    local function ready(map)
      for _ = 1, 800 do
        if world.map.id == map and not game.stack:top() and world:acceptsMenuInput() then return end
        U.wait(1)
      end
      error("warp did not become ready: " .. map)
    end
    local function shot(name)
      assert(U.still(game, out .. "/2639-" .. version .. "-" .. name .. ".png"), "capture failed")
    end
    world.clockHour = 21
    world:warpToMapId("GOLDENROD_CITY", 12, 20, "down"); ready("GOLDENROD_CITY")
    local radioCard = world:engineFlagId("ENGINE_RADIO_CARD", 0)
    world:setEngineFlag(radioCard, true)
    assert(world:engineFlag(radioCard), "Radio Card fixture not seeded")
    world:setEngineFlag(world:engineFlagId("ENGINE_ROCKETS_IN_RADIO_TOWER", 18), false)
    game:openStartMenuItem("pokegear")
    local gear
    for _ = 1, 300 do
      local top = game.stack:top()
      if top and top.screenId == "Gen2Pokegear" then gear = top; break end
      U.wait(1)
    end
    assert(gear, "Pokegear did not open")
    for index, card in ipairs(gear.cards) do if card.id == "radio" then gear.cardIndex = index end end
    assert(gear:card().id == "radio", "Radio Card not available")
    gear.mode, gear.tuningKnob = "card", 40
    gear:tuneRadio()
    if version ~= "crystal" then
      assert(version == "gold" or version == "silver", "run on Gen2")
      assert(not gear.radio and not gear:currentStation().station, "Buena leaked into Gold/Silver")
      assert(#gear:stations() == 8 and not game.data.gen2EventTables.buenaPassword, "Gold/Silver data leaked")
      shot("no-buena-10.5")
      gear.tuningKnob = 16; gear:tuneRadio(); U.wait(12)
      assert(gear.radioSong == "Music_ProfOaksPokemonTalk" and Music.current(), "ordinary station failed")
      shot("ordinary-04.5")
      print("PASS 2639 " .. version .. " negative and ordinary-radio controls")
      return
    end
    local metadata = assert(Buena.metadata(game.data))
    assert(#metadata.categories == 11 and metadata.stationName == "BUENA'S PASSWORD", "fresh ROM metadata missing")
    Buena.dailyReset(save, world:engineFlagResolver())
    gear:tuneRadio(); U.wait(415)
    assert(gear.radioShow == "BUENAS_PASSWORD" and gear.radioSong == "Music_BuenasPassword", "broadcast missing")
    assert(Music.current(), "native music did not start")
    local category, choice, word = Buena.captured(save, game.data)
    assert(category and world:engineFlag(world:engineFlagId("ENGINE_BUENAS_PASSWORD", 95)), "listening state not captured")
    local spoken = Buena.word(game.data, category, choice) .. "!"
    assert(gear.radio.log[4] == spoken and gear.radio.stationName == metadata.stationName, "ROM-fed name/password absent")
    shot("on-air-password")
    gear:tuneRadio(); U.wait(415)
    assert(save.crystal.buenaPassword.word == word and gear.radio.log[4] == spoken, "retuning rerolled word")
    assert(game:writeSave() ~= false, "native save failed")
    local restored = assert(Save.load(version))
    assert(restored.crystal.buenaPassword.word == word and restored.engineFlags[95], "native reload lost listening state")
    print("PASS 2639 broadcast, native music, retune and native save/reload")
    world.clockHour = 23
    U.wait(10)
    world.clockHour = 0
    for _ = 1, 2400 do
      if gear.radio.cur == "BUENAS_PASSWORD_21" then break end
      U.wait(1)
    end
    assert(gear.radio.cur == "BUENAS_PASSWORD_21" and gear.radioSong == false, "midnight outro did not finish")
    assert(gear.radio.stationName == "" and not world:engineFlag(95) and save.crystal.buenaPassword.day == nil,
      "off-air name/listening state not cleared")
    assert(not Music.current(), "native off-air music did not stop")
    shot("midnight-off-air")
    world.clockHour = 18
    U.wait(550)
    assert(gear.radioSong == "Music_BuenasPassword" and world:engineFlag(95), "off-air polling did not restart without retune")
    shot("next-broadcast")
    gear:stopRadio(); game.stack:pop(); U.wait(8)
    world:warpToMapId("RADIO_TOWER_2F", 13, 5, "right"); ready("RADIO_TOWER_2F")
    save.inventory.BLUE_CARD = 1
    save.crystal.buenaPassword.balance = 7
    world:setEngineFlag(world:engineFlagId("ENGINE_BUENAS_PASSWORD_2", 96), false)
    local object
    for _, row in ipairs(world.map.def.objects) do
      if row.x == 14 and row.y == 5 then object = row end
    end
    assert(object and object.scriptKey, "actual Buena map script missing")
    local metFlag
    for _, command in ipairs(assert(world.vm.scripts[object.scriptKey])) do
      if command.op == "checkevent" then metFlag = command.event; break end
    end
    assert(type(metFlag) == "number", "actual Buena introduction gate missing")
    world.events:set(metFlag, true)
    assert(world.events:get(metFlag), "Buena introduction fixture not seeded")
    local function answerScript(expectMenu)
      assert(world.vm:start(object.scriptKey), "Buena map script did not start")
      local sawMenu = false
      for _ = 1, 1800 do
        if not world.vm:running() and not game.stack:top() and not world:busy() then break end
        local top = game.stack:top()
        if getmetatable(top) == BuenaScreen then
          sawMenu = true
          local _, picked = Buena.captured(save, game.data)
          top.index = picked + 1
          shot("npc-captured-password")
        end
        if top then U.tap(game, "a") else U.wait(1) end
        U.wait(3)
      end
      assert(not world.vm:running(), "Buena script did not complete")
      assert(sawMenu == expectMenu, "NPC password-menu eligibility mismatch")
    end
    answerScript(true)
    assert(save.crystal.buenaPassword.balance == 8 and world:engineFlag(96), "actual map script did not award one point")
    answerScript(false)
    assert(save.crystal.buenaPassword.balance == 8, "second attempt awarded twice")
    game:openStartMenuItem("pack")
    local pack
    for _ = 1, 300 do
      local top = game.stack:top()
      if top and top.screenId == "Gen2PackMenu" then pack = top; break end
      U.wait(1)
    end
    assert(pack, "Blue Card pack did not open")
    for _ = 1, 4 do
      if pack:pocket().id == "KEY_ITEM" then break end
      pack:switchPocket(1)
    end
    local cardIndex
    for index, row in ipairs(pack.rows) do
      if row.id == "BLUE_CARD" then cardIndex = index; break end
    end
    assert(cardIndex, "Blue Card fixture missing from actual key-items pocket")
    pack.index = cardIndex
    pack:ensureVisible()
    pack:useSelected()
    assert(pack.message and table.concat(pack.message, "\n"):find("8 points.", 1, true),
      "actual Blue Card message did not expose awarded balance")
    shot("npc-blue-card-eight-points")
    game.stack:clear()
    Apricorns.dailyReset(save, world:engineFlagResolver())
    assert(not world:engineFlag(95) and not world:engineFlag(96) and save.crystal.buenaPassword.day == nil,
      "daily reset did not clear both source flags")
    assert(save.crystal.buenaPassword.balance == 8, "daily reset changed points")
    print("PASS 2639 dynamic midnight/off-air/restart, actual NPC single-point and daily-reset chain")
  end, debug.traceback)
  if not ok then print("FAIL 2639 " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
