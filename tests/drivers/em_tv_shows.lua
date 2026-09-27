local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local L = require("tests.drivers.em_battle_loop")

return function(game)
  local d = S.new("em_tv_shows", "/tmp/em_tv_shows")
  local check, note = d.check, d.note
  local function shot(name) d.shot(game, name) end
  local function finish() return d.finish() end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end

  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read("saves/emerald/slot1.lua")
  if not check(type(raw) == "string", "identity has the post-Hall-of-Fame save") then return finish() end
  local session = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(session, game.options)
  game:adoptSave(session, true)
  game.sessionStartedAt = os.time()
  game:_enterField(session, "continue")
  U.wait(30)
  S.settle(game)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Field = require("src.core.game3.field")
  local Collision = require("src.core.game3.collision")
  local Battle = require("src.core.game3.battle")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Naming = require("src.ui.game3.naming")
  local Rtc = require("src.core.game3.rtc")
  local MB = require("src.core.game3.mb")
  local Tv = require("src.core.game3.rse.tv")
  local NativesTv = require("src.core.game3.scripting.natives_tv")
  local Rse = require("src.core.game3.rse.init")
  local C = S.C()

  session = Runtime.getSession()
  check(session and session.version == "emerald" and S.flag("FLAG_SYS_GAME_CLEAR"), "post-game Emerald session ("
    .. tostring(session and session.name) .. ")")
  check(S.flag("FLAG_SYS_TV_START"), "FLAG_SYS_TV_START set by the story")
  Tv.state(session)
  session.gabbyAndTyData.onAir = false
  Tv.clearPokeNews(session)
  for i = 0, Tv.TV_SHOWS_COUNT - 1 do Tv.deleteShow(session.tvShows, i) end
  session.repelSteps = 0

  local function teleport(mapId, x, y, facing)
    S.settle(game)
    local ok, err = pcall(function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
    if not ok then note("Map.load " .. mapId .. ": " .. tostring(err)) end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait(20)
    local ax, ay = Player.cellX, Player.cellY
    S.settle(game)
    if os.getenv("EM_TV_DEBUG") then
      note(string.format("teleport %s want %d,%d after wait %d,%d after settle %d,%d", mapId, x, y, ax, ay,
        Player.cellX, Player.cellY))
    end
    return ok and S.mapNow() == mapId
  end

  local function findBehavior(name)
    local g3 = Runtime._game
    local def = g3 and g3.data and g3.data.maps and g3.data.maps[S.mapNow()]
    local layout = def and def.midLayout
    local want = MB.id(name)
    local out = {}
    for y = 0, (layout and layout.height or 0) - 1 do
      for x = 0, (layout and layout.width or 0) - 1 do
        if Collision.behavior(x, y) == want then out[#out + 1] = { x, y } end
      end
    end
    return out
  end

  local function tvMetatile()
    local tv = findBehavior("TELEVISION")[1]
    if not tv then return nil, nil end
    local o = Field.metatileOverrideAt(S.mapNow(), tv[1], tv[2])
    return o and o.metatile, tv
  end

  local function typeName(text)
    local st = Naming._state
    for _ = 1, 20 do
      if st.name == "" then break end
      U.tap(game, "b")
      U.wait(3)
    end
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      local pi, r, c
      for p, page in ipairs(st.pages or {}) do
        for ri, row in ipairs(page.rows) do
          for ci, cell in ipairs(row) do
            if cell == ch and not pi then pi, r, c = p, ri, ci end
          end
        end
      end
      if not pi then return false end
      for _ = 1, 6 do
        if st.page == pi and st.swapT == nil then break end
        if st.swapT == nil then U.tap(game, "select") end
        U.wait(4)
      end
      for _ = 1, 8 do
        if st.row == r then break end
        U.tap(game, st.row < r and "down" or "up")
        U.wait(3)
      end
      for _ = 1, 12 do
        if st.col == c then break end
        U.tap(game, st.col < c and "right" or "left")
        U.wait(3)
      end
      U.tap(game, "a")
      U.wait(3)
    end
    return st.name == text
  end

  local function watchTV(label)
    local _, tv = tvMetatile()
    local pages = {}
    if not tv then return pages end
    local ok = S.adjacentTo(game, tv[1], tv[2])
    if not ok then note("could not reach the TV at " .. tv[1] .. "," .. tv[2]) return pages end
    NativesTv.lastMessage, NativesTv.lastText = nil, nil
    local last
    U.tap(game, "a")
    for i = 1, 6000 do
      if Message.isOpen() then
        if Message._pages ~= last and Message._pages then
          last = Message._pages
          pages[#pages + 1] = table.concat(Message._pages, " ")
          if #pages == 1 then
            U.wait(30)
            shot(label)
          end
        end
        if Message.isTyping and Message.isTyping() then Message.skipReveal() end
        if i % 4 == 0 then U.tap(game, "a") else U.wait(1) end
      elseif S.busy() then
        U.wait(1)
      else
        U.wait(3)
        if not S.busy() then break end
      end
    end
    if #pages == 0 then
      note(string.format("watchTV %s: no message; player %d,%d facing %s, TV %d,%d, last scripts %s", label, Player.cellX,
        Player.cellY, tostring(Player.facing), tv[1], tv[2], table.concat(d.started, ",", math.max(1, #d.started - 3))))
    end
    return pages
  end

  local function nextDay(days)
    Rtc.advance((days or 1) * 24 * 60)
    local m, x, y, f = S.mapNow(), Player.cellX, Player.cellY, Player.facing
    teleport(m, x, y, f)
  end

  -- pokeemerald/data/maps/SlateportCity_NameRatersHouse/scripts.inc:4
  local lead = session.party[1]
  local oldNick = Tv.nickname(lead)
  check(teleport("EM_SLATEPORT_CITY_NAME_RATERS_HOUSE", 4, 6, "up"), "at the Name Rater's house")
  local rater = S.objectByScript("SlateportCity_NameRatersHouse_EventScript_NameRater")
  if not check(rater ~= nil, "Name Rater is in the house") then return finish() end
  S.talkTo(game, rater)
  local typed, namingSeen = false, false
  S.settle(game, {
    limit = 8000,
    onIdleUi = function()
      if Naming.isOpen() and Naming._state then
        if not namingSeen then
          namingSeen = true
          U.wait(20)
          typed = typeName("TVSTAR")
          U.wait(10)
          shot("01_name_rater_naming")
          U.tap(game, "start")
          U.wait(6)
          U.tap(game, "a")
          U.wait(20)
        else
          U.wait(1)
        end
        return true
      end
      if PartyMenu.isOpen and PartyMenu.isOpen() then
        PartyMenu.cursor = 1
        U.wait(6)
        U.tap(game, "a")
        U.wait(10)
        return true
      end
      return false
    end,
  })
  check(namingSeen and typed, "naming screen typed TVSTAR")
  check(lead.nickname == "TVSTAR", "lead mon renamed (" .. tostring(lead.nickname) .. ", was " .. tostring(oldNick) .. ")")
  local slot
  for i = 0, Tv.NUM_NORMAL_TVSHOW_SLOTS - 1 do
    if session.tvShows[i].kind == Tv.TVSHOW_NAME_RATER_SHOW then slot = i end
  end
  local show = slot and session.tvShows[slot]
  check(show ~= nil and show.active == true, "TryPutNameRaterShowOnTheAir put the Name Rater show on the air (slot "
    .. tostring(slot) .. ")")
  check(show and show.pokemonName == "TVSTAR" and show.trainerName == session.name, "show stores TVSTAR and the player")

  -- pokeemerald/src/tv.c:826
  check(teleport("EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", 4, 3, "up"), "in the bedroom (TV at 4,1)")
  do
    local cells = findBehavior("TELEVISION")
    local parts = {}
    for _, c in ipairs(cells) do
      local o = Field.metatileOverrideAt(S.mapNow(), c[1], c[2])
      parts[#parts + 1] = c[1] .. "," .. c[2] .. "=" .. tostring(o and o.metatile)
    end
    note("TV cells " .. table.concat(parts, " ") .. " player " .. Player.cellX .. "," .. Player.cellY)
  end
  local tvOn = select(1, tvMetatile())
  check(tvOn == C:require("metatile_labels", "METATILE_Building_TV_On"), "UpdateTVScreensOnMap lights the TV (metatile "
    .. tostring(tvOn) .. ")")
  check(not S.flag("FLAG_SYS_TV_WATCH"), "FLAG_SYS_TV_WATCH cleared while a show is on the air")
  shot("02_tv_on")
  local pages = watchTV("03_name_rater_page1")
  local all = table.concat(pages, " | ")
  check(#pages >= 4, "Name Rater show printed " .. #pages .. " pages")
  check(all:find("TVSTAR", 1, true) ~= nil, "pages name TVSTAR")
  check(all:find("NAME RATER", 1, true) ~= nil or all:find("Name Rater", 1, true) ~= nil, "pages are the NAME RATER show")
  note("name rater pages: " .. all:gsub("\n", " "):sub(1, 400))
  check(show and show.active == false, "TVShowDone takes it off the air")
  check(S.flag("FLAG_SYS_TV_WATCH"), "EventScript_TurnOffTV sets FLAG_SYS_TV_WATCH")
  check(select(1, tvMetatile()) == C:require("metatile_labels", "METATILE_Building_TV_Off"), "TurnOffTVScreen")
  shot("04_after_name_rater")

  -- pokeemerald/src/battle_main.c:5126
  local realRandom = Tv.random
  Tv.random = function() return 0 end
  local caught = { playerMon1Species = tonumber(lead.species), caughtMonSpecies = S.species("SPECIES_ZIGZAGOON"),
    caughtMonNick = "ZIGGY", catchAttempts = { [3] = 1 }, lastUsedItem = S.item("ITEM_POKE_BALL"),
    lastOpponentSpecies = S.species("SPECIES_ZIGZAGOON") }
  local _, handled = Rse.call("tv", "onBattleEnd", "TryPutPokemonTodayOnAir", nil, caught, Tv.B_OUTCOME_CAUGHT, {})
  Tv.random = realRandom
  check(handled, "battle-end TV hook reached through the rse system table")
  local outbreak, today
  for i = 0, Tv.LAST_TVSHOW_IDX - 1 do
    local s = session.tvShows[i]
    if s.kind == Tv.TVSHOW_MASS_OUTBREAK then outbreak = s end
    if s.kind == Tv.TVSHOW_POKEMON_TODAY_CAUGHT then today = s end
  end
  check(outbreak ~= nil and outbreak.daysBeforeOutbreak == 1, "post-game catch rolled a mass outbreak show (1 day out)")
  check(outbreak and outbreak.species == S.species("SPECIES_SEEDOT"), "Seedot outbreak from sPokeOutbreakSpeciesList")
  check(today ~= nil and today.active == false and today.nickname == "ZIGGY", "Pokemon Today waits for record mixing")
  check(session.pokeNews[0].kind ~= 0 and session.pokeNews[0].dayCountdown == 4, "PokeNews queued 4 days out")

  nextDay(0)
  pages = watchTV("05_tv_day0")
  all = table.concat(pages, " | ")
  check(all:find("program", 1, true) ~= nil, "day 0: nothing on air -> 'might like this program' (" .. all:gsub("\n", " ") .. ")")

  nextDay(1)
  check(outbreak.daysBeforeOutbreak == 0, "UpdateTVShowsPerDay counted the outbreak down")
  pages = watchTV("06_outbreak_news")
  all = table.concat(pages, " | ")
  note("outbreak pages: " .. all:gsub("\n", " "))
  check(all:find("SEEDOT", 1, true) ~= nil and all:find("ROUTE 102", 1, true) ~= nil, "TV reports SEEDOT swarming ROUTE 102")
  local ob = session.outbreak
  check(ob and ob.map == "EM_ROUTE102" and ob.species == S.species("SPECIES_SEEDOT") and ob.probability == 50,
    "StartMassOutbreak arms the encounter hook")
  check(session.outbreakDaysLeft == 2, "outbreak lasts 2 days")

  -- pokeemerald/src/wild_encounter.c:481
  check(teleport("EM_ROUTE102", 20, 10, "down"), "on Route 102")
  local grass = findBehavior("TALL_GRASS")
  local spot
  for _, g in ipairs(grass) do
    for _, g2 in ipairs(grass) do
      if not spot and math.abs(g[1] - g2[1]) + math.abs(g[2] - g2[2]) == 1 then spot = { g, g2 } end
    end
  end
  check(spot ~= nil, "found a pair of grass cells (" .. #grass .. " grass cells)")
  local seen = {}
  local outbreakMon
  if spot then
    S.goTo(game, spot[1])
    for _ = 1, 300 do
      if outbreakMon or #seen >= 14 then break end
      local P = Player
      local target = (P.cellX == spot[1][1] and P.cellY == spot[1][2]) and spot[2] or spot[1]
      local dir = target[1] > P.cellX and "right" or target[1] < P.cellX and "left" or target[2] > P.cellY and "down" or "up"
      S.step(game, dir)
      for _ = 1, 120 do
        if Battle.isActive() then break end
        U.wait(1)
      end
      if Battle.isActive() then
        for _ = 1, 400 do
          if Battle._st and Battle._st.enemy and Battle._st.enemy.mon then break end
          U.wait(1)
        end
        local st = Battle._st
        local mon = st and ((st.enemy and st.enemy.mon) or (st.battlers and st.battlers[1] and st.battlers[1].mon))
        local moves = mon and mon.moves or {}
        seen[#seen + 1] = string.format("%s lv%s [%s]", tostring(mon and mon.species), tostring(mon and mon.level),
          table.concat(moves, ","))
        if mon and tonumber(mon.species) == S.species("SPECIES_SEEDOT") and tonumber(mon.level) == 3
            and moves[1] == S.move("MOVE_BIDE") and moves[2] == S.move("MOVE_HARDEN") and moves[3] == S.move("MOVE_LEECH_SEED") then
          outbreakMon = mon
          for _ = 1, 1500 do
            if Battle._phase == "command" then break end
            if Message.isOpen() then U.tap(game, "a") end
            U.wait(2)
          end
          U.wait(20)
          shot("07_outbreak_seedot")
        end
        L.run(game, {})
        S.settle(game, { limit = 2000 })
      end
    end
  end
  note("encounters: " .. table.concat(seen, "; "))
  check(outbreakMon ~= nil, "Route 102 grass spawns the outbreak Seedot lv3 with BIDE/HARDEN/LEECH SEED")

  nextDay(1)
  check(session.outbreakDaysLeft == 1, "one outbreak day left")
  nextDay(1)
  check(session.outbreakPokemonSpecies == 0 and session.outbreak == nil, "EndMassOutbreak after two days")

  check(teleport("EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", 4, 3, "up"), "back in the bedroom")
  pages = watchTV("08_pokenews")
  all = table.concat(pages, " | ")
  note("pokenews pages: " .. all:gsub("\n", " "))
  check(#pages >= 1 and NativesTv.lastText and tostring(NativesTv.lastText.group):find("^sPokeNewsTextGroup") ~= nil,
    "PokeNews airs once its countdown is under 3 days (" .. tostring(NativesTv.lastText and NativesTv.lastText.group) .. ")")

  finish()
end
