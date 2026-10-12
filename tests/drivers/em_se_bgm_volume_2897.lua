local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_se_bgm_volume_2897", "/tmp/em_se_bgm_volume_2897")

return function(game)
  local ok, err = xpcall(function()
    if not M.boot(game, d) then return end
    d.check(M.goTo(game, "EM_ROUTE104", 20, 30, "down"), "Route 104 loaded")
    local Audio = require("src.core.game3.audio")
    for _ = 1, 240 do
      if Audio._bgmSource and Audio._bgmSource:isPlaying() then break end
      U.wait(1)
    end
    U.wait(60)
    local bgm = Audio._bgmSource
    if not d.check(bgm ~= nil, "route BGM source playing") then return end
    local before = bgm:getVolume()
    local SE = require("src.core.game3.se_ids")
    local steady = true
    for _ = 1, 6 do
      Audio.playSe(SE.SE_PUDDLE)
      for _ = 1, 8 do
        U.wait(1)
        if math.abs(Audio._bgmSource:getVolume() - before) > 1e-6 then steady = false end
      end
    end
    d.check(steady, string.format("BGM volume stays %.3f while SE_PUDDLE plays", before))
    Audio.playSe(SE.SE_M_SCRATCH)
    U.wait(4)
    d.check(Audio.isSePlaying(SE.SE_M_SCRATCH)
      and math.abs(Audio._bgmSource:getVolume() - before) < 1e-6,
      "BGM volume unchanged while SE_M_SCRATCH plays")
    Audio.playCry(25, 0)
    U.wait(2)
    local during = Audio._bgmSource:getVolume()
    d.check(math.abs(during - before * 85 / 256) < 1e-3,
      string.format("cry still ducks BGM to 85/256 (%.3f -> %.3f)", before, during))
    for _ = 1, 180 do
      if Audio.isCryFinished() and (Audio._duck or 1) == 1 then break end
      U.wait(1)
    end
    d.check((Audio._duck or 1) == 1, "BGM back to full after the cry")

    local Party = require("src.core.game3.party")
    local Objects = require("src.core.game3.objects")
    local Collision = require("src.core.game3.collision")
    local TrainerSight = require("src.core.game3.trainer_sight")
    local Encounters = require("src.core.game3.encounters")
    local Message = require("src.ui.game3.message")
    local Battle = require("src.core.game3.battle")
    local IntroSeq = require("src.core.game3.battle.intro_seq")
    local C = require("src.core.game3.constants").of("emerald")
    local session = S.session()
    Encounters.onStep = function() return nil end
    session.party = {}
    Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 45, "SWAMPERT")
    Party.giveMon(session, C.species.byName.SPECIES_BLAZIKEN, 45, "BLAZIKEN")
    local tid = C.trainers.byName.TRAINER_GINA_AND_MIA_1
    d.check(M.goTo(game, "EM_ROUTE104", 10, 30, "down"), "Route 104 reloaded for the twins")
    U.wait(40)
    local twins = {}
    for _, lid in ipairs(Objects.listActive()) do
      local eo = Objects.find(lid)
      if eo and TrainerSight.getTrainerId(eo) == tid then twins[#twins + 1] = eo end
    end
    table.sort(twins, function(a, b) return (a.cellX or 0) < (b.cellX or 0) end)
    if not d.check(#twins == 2, "Gina and Mia found") then return end
    local SIDE = { down = { 0, 1, "up" }, left = { -1, 0, "right" }, right = { 1, 0, "left" }, up = { 0, -1, "down" } }
    local sx, sy, face
    for _, dir in ipairs({ "down", "left", "right", "up" }) do
      local o = SIDE[dir]
      local x, y = twins[1].cellX + o[1], twins[1].cellY + o[2]
      if not sx and Collision.canEnter(game, x, y, {}) and not Objects.at(x, y) then
        sx, sy, face = x, y, o[3]
      end
    end
    if not d.check(sx ~= nil, "cell next to the twins") then return end
    M.goTo(game, "EM_ROUTE104", sx, sy, face)
    U.wait(60)
    U.tap(game, "a")
    for _ = 1, 900 do
      if Battle.isActive() then break end
      if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(3)
    end
    if not d.check(Battle.isActive() and Battle._st and Battle._st.double, "double battle started") then return end

    local trace, last = {}, nil
    local shot = false
    for _ = 1, 3600 do
      local v = Audio._duck or 1
      if v ~= last then trace[#trace + 1] = v; last = v end
      if v == 0.5 and not shot then
        shot = true
        d.shot(game, "2897_02_double_release_quiet_bgm")
      end
      if Battle._phase == "command" and not IntroSeq.busy() then break end
      if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(1)
    end
    local parts = {}
    for i, v in ipairs(trace) do parts[i] = string.format("%.3f", v) end
    local seq = table.concat(parts, ",")
    print("[driver] intro BGM volume trace " .. seq)
    local quietThenCry = seq:find("0.500,0.332", 1, true) ~= nil
    d.check(quietThenCry, "double intro release holds BGM at 128 then the second cry drops it to 85")
    local _, pairs2 = seq:gsub("0%.500,0%.332,1%.000", "")
    d.check(pairs2 >= 2, "both sides restore BGM to 256 after their release cries (" .. pairs2 .. ")")
    d.check((Audio._duck or 1) == 1, "BGM at full volume when the command menu opens")

    local Anim = require("src.core.game3.battle.anim")
    d.check(Anim.isQuietBgmMove(47) and Anim.isQuietBgmMove(195) and Anim.isQuietBgmMove(320)
      and not Anim.isQuietBgmMove(10), "cached quiet BGM list is SING, PERISH_SONG, GRASS_WHISTLE")
    for _, move in ipairs({ { 47, true, "SING" }, { 10, false, "SCRATCH" } }) do
      local ended = false
      Anim.launchMove(move[1], { attackerSide = "player", targetSide = "enemy",
        attackerId = 0, targetId = 1, onEnd = function() ended = true end })
      U.wait(6)
      local mid = Audio._duck or 1
      local want = move[2] and 0.5 or 1
      d.check(math.abs(mid - want) < 1e-9,
        string.format("%s anim plays with BGM at %.3f (want %.3f)", move[3], mid, want))
      for _ = 1, 900 do
        if ended then break end
        U.wait(1)
      end
      d.check(ended and (Audio._duck or 1) == 1, move[3] .. " anim end leaves BGM at 256")
    end
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
