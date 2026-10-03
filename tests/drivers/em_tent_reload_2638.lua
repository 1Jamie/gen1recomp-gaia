local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local phase = os.getenv("EM_TENT_2638_PHASE") or "rest_setup"
  local route, step = phase:match("^(%a+)_(%a+)$")
  local d = S.new("em_tent_reload_2638_" .. phase, "/tmp/em_tent_reload_2638/" .. phase)
  local check = d.check
  local deadline = love.timer.getTime() + 25
  if not check((route == "rest" or route == "direct") and (step == "setup" or step == "resume"), "valid driver phase") then
    return d.finish()
  end
  local identity = os.getenv("POKEPORT_IDENTITY") or ""
  if not check(identity ~= "" and identity ~= "pokemon-love2d", "dedicated identity supplied") then return d.finish() end
  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local Runtime = require("src.core.game3.runtime")
  local D = require("src.core.game3.rse.frontier.trainers")
  local Util = require("src.core.game3.rse.frontier.util")
  local Select = require("src.ui.game3.rse.factory_select")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Choice = require("src.ui.game3.choice")
  local Message = require("src.ui.game3.message")
  local LOBBY = "EM_SLATEPORT_CITY_BATTLE_TENT_LOBBY"
  local CORRIDOR = "EM_SLATEPORT_CITY_BATTLE_TENT_CORRIDOR"
  local witnessFile = "2638_" .. route .. "_expected.lua"
  local saveFile = SaveData.saveFilename("emerald")
  local function readSave()
    local raw = love.filesystem.read(saveFile)
    return type(raw) == "string" and SaveData.decode(raw) or nil
  end
  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
  end
  local function traits(party)
    local out = {}
    local keys = { "species", "speciesId", "speciesNumbering", "personality", "otId", "otSecretId", "otName", "ot",
      "nickname", "ivs", "evs", "moves", "pp", "maxPp", "ppBonusesPacked", "nature", "heldItem", "abilityNum",
      "exp", "level", "friendship", "pokeball", "metLocation", "markings" }
    for i, mon in ipairs(party or {}) do
      out[i] = {}
      for _, key in ipairs(keys) do out[i][key] = copy(mon[key]) end
    end
    return out
  end
  local function fingerprint(party)
    local bytes = SaveData.encode(traits(party))
    return love.data.encode("string", "hex", love.data.hash("sha256", bytes))
  end
  local function sameParty(got, expected, label)
    local a, b = fingerprint(got), fingerprint(expected)
    return check(a == b and #(got or {}) == #(expected or {}), label .. " slots=" .. #(got or {}) .. " sha256=" .. a .. " expected=" .. b)
  end
  local function waitFor(pred, limit)
    for _ = 1, limit or 900 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local capture = d.shot
  function d.shot(game, file)
    local Fade = require("src.ui.game3.fade")
    local Transition = require("src.core.game3.battle_transition")
    local function visible()
      return game.phase == "field" and not Fade.isActive() and (Fade.t or 0) <= 0
        and not Transition.isActive()
    end
    if not check(waitFor(visible, 900), "capture ready " .. file) then
      d.note("capture phase=" .. tostring(game.phase) .. " fadeActive=" .. tostring(Fade.isActive())
        .. " fade=" .. tostring(Fade.t) .. " transition=" .. tostring(Transition.isActive()))
      return false
    end
    U.wait(2)
    if not check(waitFor(visible, 900), "capture remains visible " .. file) then return false end
    return check(capture(game, file), "capture written " .. file)
  end
  if not check(waitFor(function() return game.phase == "boot" and game.boot ~= nil end), "boot reached") then return d.finish() end
  local witness
  if step == "setup" then
    local session = Schema.newGame({ version = "emerald", name = "RELOAD", rngSeed = 0x2638 })
    session.map, session.x, session.y, session.facing = LOBBY, 6, 6, "up"
    require("src.core.game3.options").bind(session, game.options)
    game:adoptSave(session, true)
    game.sessionStartedAt = os.time()
    game:_enterField(session, "continue")
    U.wait(30)
    S.settle(game)
    session = Runtime.getSession()
    if not check(session and session.version == "emerald", "Emerald setup session") then return d.finish() end
    session.party = {}
    local names = { "SPECIES_SWAMPERT", "SPECIES_BLAZIKEN", "SPECIES_SCEPTILE", "SPECIES_METAGROSS", "SPECIES_SALAMENCE", "SPECIES_ZIGZAGOON" }
    for i, name in ipairs(names) do
      local m = D.createMon(S.species(name), 35 + i, 10 + i, 200000 + i * 37, session.trainerId,
        { otName = session.name, moves = {} })
      D.setMoves(m, { S.move("MOVE_TACKLE"), S.move("MOVE_PROTECT") })
      D.setEvs(m, { i * 7, i * 9, i * 11, i * 13, i * 15, i * 17 })
      m.nickname, m.otSecretId, m.heldItem = "KEEP" .. i, session.secretId, S.item("ITEM_ORAN_BERRY")
      m.ivs.hp, m.pp[1], m.friendship, m.markings = i + 4, i + 2, 100 + i, i
      require("src.core.game3.save_mon").normalize(m)
      Schema.ensureMonBall(m)
      session.party[i] = m
    end
    witness = { original = copy(session.party), route = route, seed = tonumber(os.getenv("EM_TENT_2638_SEED")) or 185 }
    require("src.core.game3.encounters").onStep = function() return nil end
    local Rng = require("src.core.game3.rng")
    local Tents = require("src.core.game3.rse.frontier.tents")
    local generateRentals = Tents.generateRentalMons
    Tents.generateRentalMons = function(sess)
      Rng.SeedRng(witness.seed)
      d.note("real rental generator seed=" .. witness.seed)
      return generateRentals(sess)
    end
    Rng.SeedRng(witness.seed)
    local ok, err = pcall(require("src.core.game3.map").load, nil, game, LOBBY, { x = 6, y = 6, facing = "up" })
    if not check(ok, "Slateport lobby loads " .. tostring(err or "")) then return d.finish() end
    U.wait(30)
    S.settle(game)
    d.shot(game, "01_original_party_lobby")
    sameParty(Runtime.getSession().party, witness.original, "2638 original hidden-stat fingerprint")
  else
    local raw = love.filesystem.read(witnessFile)
    witness = type(raw) == "string" and SaveData.decode(raw) or nil
    if not check(witness and witness.route == route and witness.original and witness.rentals, "previous process supplied exact witness") then
      return d.finish()
    end
    local disk = readSave()
    if not check(disk and disk.frontier and disk.frontier.curChallengeBattleNum == 1, "fresh process reads one-battle challenge save") then
      return d.finish()
    end
    sameParty(disk.savedPlayerParty, witness.original, "2638 persisted original hidden-stat fingerprint")
    if route == "rest" then
      sameParty(disk.party, witness.original, "2638 REST disk original fingerprint")
      check(disk.frontier.challengePaused == 1, "REST challenge paused on disk")
      local w = disk.continueGameWarp or {}
      check(w.map == LOBBY and w.x == witness.lobby.x and w.y == witness.lobby.y,
        "REST disk has exact captured lobby coordinates " .. tostring(w.x) .. "," .. tostring(w.y))
      check((tonumber(disk.specialSaveWarpFlags) or 0) % 2 == 1, "REST disk continue flag set")
    else
      sameParty(disk.party, witness.rentals, "2638 direct disk rental hidden-stat fingerprint")
      check(disk.map == CORRIDOR, "direct save retains actual corridor location")
    end
    game:_handleBootAction({ action = "continue" })
    if not check(waitFor(function() return game.phase == "field" and Runtime.getSession() ~= nil end, 1800),
      "fresh process CONTINUE reaches live field") then return d.finish() end
    if route == "rest" then
      check(S.mapNow() == LOBBY, "REST CONTINUE starts in original lobby")
      d.shot(game, "04_resume_lobby")
      sameParty(Runtime.getSession().party, witness.original, "2638 REST continued original fingerprint")
    else
      check(S.mapNow() == CORRIDOR, "direct CONTINUE starts in actual corridor")
      d.shot(game, "04_direct_continue_corridor")
    end
  end
  local session = Runtime.getSession()
  local f = Util.frontier(session)
  local battles, wins, selected = 0, 0, false
  local stopped, savedRest, captured, resumeRentals = false, false, false, false
  local aborted, lastProgress, lastStage = false, U.frame(), nil
  local function timeout(label)
    if aborted then return end
    aborted = true
    check(false, label .. " at " .. S.vmWhere())
  end
  local function driveSelect()
    local st = Select._st
    local function ready(phase)
      return st.phase == phase and (not st.picAnim or st.picAnim.finished)
    end
    local function rentalWait(pred, label, limit)
      if waitFor(pred, limit or 600) then return true end
      d.note("rental UI phase=" .. tostring(st.phase) .. " cursor=" .. tostring(st.cursor)
        .. " selected=" .. tostring(st.selectingState) .. " menu=" .. tostring(st.menuCursor)
        .. " animation=" .. tostring(st.picAnim and st.picAnim.step))
      timeout(label)
      return false
    end
    if not rentalWait(function() return ready("choose") end, "rental UI did not reach actionable selection") then return end
    check(true, "rental UI reaches selection")
    d.shot(game, "02_rental_selection")
    local rank = {}
    local Moves = require("src.core.game3.battle.moves")
    local Types = require("src.core.game3.battle.types")
    local Pokemon = require("src.core.game3.pokemon")
    for i, row in ipairs(st.mons) do
      local m = row.monData
      local types, best, unsafe, names = Pokemon.types(m.species), 0, false, {}
      for _, id in ipairs(m.moves or {}) do
        local move = Moves.get(id)
        names[#names + 1] = tostring(id) .. "/" .. tostring(Pokemon.romMoveName(id))
        if id == 120 or id == 153 then unsafe = true end
        local stab = (move.type == types[1] or move.type == types[2]) and 1.5 or 1
        local stat = Types.isPhysical(move.type) and m.attack or m.spAtk
        best = math.max(best, (move.power or 0) * (stat or 0) * stab / 100)
      end
      local score = unsafe and -1 or best + ((m.maxHp or 0) + (m.defense or 0) + (m.spDef or 0) + (m.speed or 0)) / 5
      rank[i] = { i = i, score = score }
      d.note(string.format("rental %d %s species=%s hp=%s atk=%s spa=%s spe=%s score=%.2f moves=%s", i,
        tostring(m.name), tostring(m.species), tostring(m.maxHp), tostring(m.attack), tostring(m.spAtk), tostring(m.speed),
        score, table.concat(names, ",")))
    end
    table.sort(rank, function(a, b) if a.score == b.score then return a.i < b.i end return a.score > b.score end)
    for _, candidate in ipairs(rank) do
      if st.selectingState > 3 then break end
      if not rentalWait(function() return ready("choose") end, "rental UI did not finish closing previous picture") then return end
      for _ = 1, 6 do if st.cursor == candidate.i then break end U.tap(game, "right") U.wait(3) end
      if not rentalWait(function() return st.cursor == candidate.i end, "rental UI cursor did not reach candidate", 30) then return end
      U.tap(game, "a")
      if not rentalWait(function() return ready("menu") end, "rental UI did not open candidate menu") then return end
      U.tap(game, "down") U.wait(3)
      if not rentalWait(function() return st.menuCursor == 1 end, "rental UI did not highlight RENT", 30) then return end
      d.note("RENT candidate=" .. candidate.i .. " species=" .. tostring(st.mons[candidate.i].monData.species))
      U.tap(game, "a")
      if not rentalWait(function() return ready("choose") or ready("yesno") or st.phase == "invalid" end,
        "rental UI did not complete RENT selection") then return end
      if st.phase == "invalid" then
        U.tap(game, "a")
        if not rentalWait(function() return ready("choose") end, "rental UI did not dismiss invalid species") then return end
      end
    end
    if not rentalWait(function() return ready("yesno") end, "rental UI did not confirm three rentals") then return end
    check(st.selectingState == 4, "three rentals chosen with RENT")
    U.tap(game, "a")
    selected = rentalWait(function() return not Select.isOpen() end, "rental UI did not accept chosen party")
    check(selected, "rental UI confirms chosen party")
  end
  local function readyChoice()
    if not Choice.isOpen() then return false end
    for _, row in ipairs(Choice.options or {}) do
      local text = type(row) == "table" and (row.text or row.label or row[1]) or row
      if tostring(text):upper():find("REST", 1, true) then return true end
    end
    return false
  end
  local function watch()
    session = Runtime.getSession() or session
    f = Util.frontier(session)
    local stage = table.concat({ tostring(S.mapNow()), battles, wins, tostring(selected), tostring(captured), tostring(savedRest), tostring(resumeRentals) }, ":")
    if stage ~= lastStage then lastStage, lastProgress = stage, U.frame() end
    if love.timer.getTime() >= deadline then timeout("driver exceeded 25-second budget")
    elseif U.frame() - lastProgress > 12000 then timeout("driver made no challenge progress for 12000 frames") end
    if aborted then return end
    if step == "setup" and wins == 1 and f.curChallengeBattleNum == 1 and readyChoice() and not captured then
      captured = true
      witness.rentals, witness.rentalMons = copy(session.party), copy(f.rentalMons)
      witness.lobby = copy(session.dynamicWarp)
      check(love.filesystem.write(witnessFile, SaveData.encode(witness)), "write exact restart witness in dedicated identity")
      sameParty(session.savedPlayerParty, witness.original, "2638 before-pause original backup fingerprint")
      sameParty(session.party, witness.rentals, "2638 before-pause rental fingerprint")
      d.shot(game, "03_before_pause")
      if route == "direct" then
        check(game:saveGame() == true, "actual Game3 direct save succeeds during rentals")
        local disk = readSave()
        sameParty(disk and disk.savedPlayerParty, witness.original, "2638 direct save original backup fingerprint")
        sameParty(disk and disk.party, witness.rentals, "2638 direct save rental fingerprint")
        stopped = true
      end
    end
    if step == "setup" and route == "rest" and captured and not savedRest then
      local disk = readSave()
      savedRest = disk and disk.frontier and disk.frontier.challengePaused == 1 and disk.frontier.challengeStatus == 2
        and disk.frontier.curChallengeBattleNum == 1 and (tonumber(disk.specialSaveWarpFlags) or 0) % 2 == 1
      if savedRest then
        sameParty(disk.party, witness.original, "2638 REST written original fingerprint")
        sameParty(disk.savedPlayerParty, witness.original, "2638 REST written backup fingerprint")
      end
    end
    if step == "resume" and route == "rest" and not resumeRentals and S.mapNow() == CORRIDOR and readyChoice() then
      resumeRentals = true
      sameParty(session.party, witness.rentals, "2638 resumed same-rental hidden-stat fingerprint")
      sameParty(session.savedPlayerParty, witness.original, "2638 resumed original-backup hidden-stat fingerprint")
      check(f.curChallengeBattleNum == 1, "REST resume keeps completed battle count")
    end
  end
  local function choice()
    if stopped then return "b" end
    if readyChoice() then return step == "setup" and route == "rest" and "REST" or "GO ON" end
    if Choice.kind == "multi" then
      for _, row in ipairs(Choice.options or {}) do
        local text = type(row) == "table" and (row.text or row.label or row[1]) or row
        local label = tostring(text):upper()
        if label == "CHALLENGE" or label == "ENTER" then
          d.note("select attendant entry " .. label)
          return label
        end
      end
    end
    local page = tostring(Message.currentPage and Message.currentPage() or ""):upper()
    if page:find("SWAP", 1, true) or page:find("RECORD", 1, true) then return "no" end
    return "yes"
  end
  if step == "setup" then
    local attendant = S.objectByScript("SlateportCity_BattleTentLobby_EventScript_Attendant")
    if not check(attendant ~= nil, "real Slateport attendant found") then return d.finish() end
    S.talkTo(game, attendant)
  end
  local done = S.settle(game, {
    limit = 120000,
    until_ = function()
      if aborted then return true end
      if step == "setup" then
        return stopped or (savedRest and game.phase == "boot")
          or (battles > 0 and wins == 0 and S.mapNow() == LOBBY and not S.busy())
      end
      return battles >= 1 and S.mapNow() == LOBBY and not S.busy() and tonumber(f.challengeStatus) == 0
    end,
    choice = choice,
    watch = watch,
    onIdleUi = function()
      if aborted then return true end
      if Select.isOpen() then driveSelect() return true end
      if SaveMenu.isOpen() then U.tap(game, "a") U.wait(8) return true end
      return false
    end,
    onBattleFrame = function(st, phase)
      local Ui = require("src.core.game3.battle.ui")
      if phase == "command" and Ui._mode == "moves" then
        local who = Ui.activeBattler and Ui.activeBattler() or 0
        local p, e = st.battlers and st.battlers[who], st.battlers and st.battlers[1]
        local tag = tostring(st.turn) .. ":" .. tostring(p and p.mon and p.mon.species)
        if tag ~= d.lastBattleTrace then
          d.lastBattleTrace = tag
          d.note("battle turn=" .. tostring(st.turn) .. " player=" .. tostring(p and p.mon and p.mon.species)
            .. " hp=" .. tostring(p and p.mon and p.mon.hp) .. " foe=" .. tostring(e and e.mon and e.mon.species)
            .. " foeHp=" .. tostring(e and e.mon and e.mon.hp))
        end
      end
      if love.timer.getTime() >= deadline then
        timeout("driver exceeded 25-second budget during battle")
        d.finish()
      end
    end,
    onBattleStart = function(st)
      battles = battles + 1
      check(st.kinds and st.kinds.frontier and #session.party == 3, "actual rental Frontier battle " .. battles)
      sameParty(session.savedPlayerParty, witness.original, "2638 battle original-backup fingerprint")
      S.pendingBattleShot = step == "setup" and "02_first_rental_battle" or "05_rental_battle_after_continue"
    end,
    onBattleEnd = function(result)
      if result == "win" then wins = wins + 1 end
      check(result == "win", "actual rental battle won " .. battles .. " result=" .. tostring(result))
      if result ~= "win" then
        local Ui = require("src.core.game3.battle.ui")
        for i, text in ipairs(Ui.log and Ui.log() or {}) do
          if type(text) == "table" then
            local ok, plain = pcall(require("src.core.game3.scripting.text_ir").toAscii, text, {})
            text = ok and plain or tostring(text)
          end
          d.note("battle failure log " .. i .. " " .. tostring(text):gsub("\n", " "))
        end
      end
    end,
  })
  check(done and not aborted, "driver reaches requested phase endpoint")
  if aborted then return d.finish() end
  if step == "setup" then
    check(selected and wins == 1 and captured, "one real rental win precedes save/restart")
    if route == "rest" then check(savedRest and game.phase == "boot", "real REST script saves and resets to boot") end
  else
    session = Runtime.getSession()
    check(battles == 2 and wins == 2, "two remaining real rental battles completed after restart")
    if route == "rest" then check(resumeRentals, "real corridor ResumeChallenge rebuilt saved rentals") end
    check(S.mapNow() == LOBBY and tonumber(Util.frontier(session).challengeStatus) == 0, "challenge completed through real lobby script")
    sameParty(session.party, witness.original, "2638 final exact original-party hidden-stat fingerprint")
    local PartyMenu = require("src.ui.game3.party_menu")
    if not check(waitFor(function()
      local Fade = require("src.ui.game3.fade")
      return not Fade.isActive() and (Fade.t or 0) <= 0
    end, 900), "final lobby fade fully clears before party menu") then return d.finish() end
    PartyMenu.show(session.party, session.move_overlay, { session = session })
    if not check(waitFor(function()
      local top = require("src.ui.game3.stack").top()
      return PartyMenu.isOpen() and top and top.id == "party" and PartyMenu.mode == "list"
        and #PartyMenu._party == 6
    end, 300), "final six-slot party menu is ready") then return d.finish() end
    d.shot(game, "06_final_original_party")
    PartyMenu.close()
    check(game:saveGame() == true, "final original party saves through Game3")
    sameParty(readSave().party, witness.original, "2638 final disk original-party fingerprint")
  end
  return d.finish()
end
