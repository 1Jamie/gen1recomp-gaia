-- pokered/scripts/ViridianCity.asm:150
-- pokeyellow/scripts/ViridianCity_2.asm:10
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local GameVersion = require("src.core.GameVersion")
  local version = GameVersion.get()
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local failed = false
  local badges = {
    "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
    "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE",
  }
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", "2632_" .. label)
    if not ok then failed = true end
    return ok
  end
  local function topBox()
    local state = game.stack:top()
    return getmetatable(state) == TextBox and state or nil
  end
  local function flatten(pages)
    local result = {}
    for _, page in ipairs(pages) do result[#result + 1] = table.concat(page, "\n") end
    return table.concat(result, "\f")
  end

  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_POKEDEX = true
  game.save.flags.EVENT_OAK_GOT_PARCEL = true
  game.save.flags.EVENT_VIRIDIAN_GYM_OPEN = true
  game.save.inventory = game.save.inventory or {}

  local function scene(label, count, flagName, textKey)
    for i, badge in ipairs(badges) do game.save.inventory[badge] = i <= count or nil end
    game.save.flags.EVENT_BEAT_GIOVANNI = nil
    game.save.flags.EVENT_BEAT_VIRIDIAN_GYM_GIOVANNI = nil
    if flagName then game.save.flags[flagName] = true end
    U.teleport(game, "VIRIDIAN_CITY", 30, 9, "up")
    local ow = game.overworld
    if not check(label .. "_map", ow and ow.map.id == "VIRIDIAN_CITY") then return end
    local gambler
    for _, npc in ipairs(ow.npcs) do
      if npc.def and npc.def.text == "TEXT_VIRIDIANCITY_GAMBLER1" then
        gambler = npc
        break
      end
    end
    if not check(label .. "_actual_npc", gambler ~= nil) then return end
    gambler.wanders = false
    gambler.moving = false
    gambler.cellX, gambler.cellY = gambler.def.x, gambler.def.y
    gambler.px, gambler.py = gambler.cellX * 16, gambler.cellY * 16
    local p = ow.player
    p.cellX, p.cellY = gambler.cellX, gambler.cellY + 1
    p.px, p.py = p.cellX * 16, p.cellY * 16
    p.facing = "up"
    U.wait(2)
    U.tap(game, "a")
    for _ = 1, 60 do
      if topBox() then break end
      U.wait(1)
    end
    local box = topBox()
    if not check(label .. "_normal_talk", box ~= nil and gambler.frozen) then return end
    local source = game.data.text[textKey]
    if not check(label .. "_rom_text", type(source) == "string") then return end
    local expected = TextBox.paginate(TextBox.substitute(game, source), box.maxCols)
    check(label .. "_dialogue", flatten(box.pages) == flatten(expected))
    U.log("2632_" .. label .. "_pages", flatten(box.pages))
    for _ = 1, 600 do
      if box.done or box.waiting then break end
      U.wait(1)
    end
    if check(label .. "_completed_page", box.done or box.waiting) then
      check(label .. "_screenshot", U.still(game,
        DIR .. "/2632_" .. version .. "_" .. label .. ".png"))
    end
    for _ = 1, 120 do
      if game.stack:top() == ow then break end
      U.tap(game, "a")
      U.wait(3)
    end
    check(label .. "_callback_unfreezes", game.stack:top() == ow and not gambler.frozen)
  end

  scene("closed_before_seven", 6, nil, "_ViridianCityGambler1GymAlwaysClosedText")
  scene("returned_exact_seven", 7, nil, "_ViridianCityGambler1GymLeaderReturnedText")
  scene("returned_after_earth", 8, "EVENT_BEAT_GIOVANNI",
    "_ViridianCityGambler1GymLeaderReturnedText")
  scene("returned_canonical_win", 8, "EVENT_BEAT_VIRIDIAN_GYM_GIOVANNI",
    "_ViridianCityGambler1GymLeaderReturnedText")
  scene("closed_eight_without_win", 8, nil, "_ViridianCityGambler1GymAlwaysClosedText")
  check("all_scenes", not failed)
  love.event.quit(failed and 1 or 0)
end
