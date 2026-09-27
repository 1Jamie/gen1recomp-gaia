local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_lilycove_lady", "/tmp/em_lilycove_lady")

local MAP = "EM_LILYCOVE_CITY_POKEMON_CENTER_1F"
local LABEL = "LilycoveCity_PokemonCenter_1F_EventScript_LilycoveLady"

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local Lady = require("src.core.game3.rse.lilycove_lady")
    local NativesLady = require("src.core.game3.scripting.natives_lilycove_lady")
    local Town = require("src.core.game3.rse.town_common")
    local Party = require("src.core.game3.party")
    local Bag = require("src.core.game3.bag")
    local C = S.C()
    Party.giveMonToPlayer(session, S.species("SPECIES_TORCHIC"), 20)

    local function lady(tid)
      session.trainerId = tid
      Lady.init(session)
      d.check(M.goTo(game, MAP, 4, 5, "left"), "entered Lilycove Pokemon Center 1F (lady " .. session.lilycoveLady.id .. ")")
    end

    -- pokeemerald/data/scripts/lilycove_lady.inc:120
    lady(0)
    d.check(S.var("VAR_OBJ_GFX_ID_0") == C:require("event_objects", "OBJ_EVENT_GFX_WOMAN_4"), "SetLilycoveLadyGfx: quiz lady gfx")
    d.shot(game, "01_quiz_lady")
    local q = Lady.quiz(session)
    local answer = q.correctAnswer
    local prize = q.prize
    local prize0 = Bag.get(session.bag, prize) or 0
    local potion = C:require("items", "ITEM_POTION")
    Bag.add(session.bag, potion, 1)
    local shownQuestion = false
    local mark = #M.msgs
    local myQuestion = {}
    local done = M.talk(game, LABEL, {
      answers = { "yes", "yes", 0 },
      onFrame = function()
        if not shownQuestion and M.saw(Town.word(q.question[1]), mark) then
          shownQuestion = true
          d.shot(game, "02_quiz_question")
        end
      end,
      easyChat = function(st)
        if st.type == 15 then
          d.check(st.count == 1, "quiz answer screen takes one word")
          d.shot(game, "03_quiz_answer_screen")
          return { answer }
        elseif st.type == 17 then
          d.check(st.count >= 8, "quiz question screen has the question slots (" .. tostring(st.count) .. ")")
          local w = {}
          for i = 1, st.count do w[i] = q.question[i] or Town.EC_EMPTY_WORD end
          w[1] = answer
          myQuestion = w
          return w
        elseif st.type == 18 then
          return { answer }
        end
      end,
    })
    d.check(done, "quiz lady script finished")
    d.check(shownQuestion, "quiz question shown before answering")
    d.check(M.saw("You got it right", mark) or M.saw("right", mark), "correct answer accepted")
    d.check((Bag.get(session.bag, prize) or 0) == prize0 + 1 or prize == potion, "quiz prize " .. Town.itemName(prize) .. " received")
    d.check(q.waitingForChallenger == true and q.prize == potion, "player quiz recorded with POTION as prize")
    d.check(q.playerName == Town.playerName(session), "quiz author is the player")
    d.shot(game, "04_quiz_made")
    mark = #M.msgs
    M.talk(game, LABEL, {})
    d.check(M.saw("waiting", mark) or M.saw("challenger", mark), "lady waits for someone to take the player's quiz")

    -- pokeemerald/data/scripts/lilycove_lady.inc:9
    lady(2)
    d.check(S.var("VAR_OBJ_GFX_ID_0") == C:require("event_objects", "OBJ_EVENT_GFX_WOMAN_2"), "SetLilycoveLadyGfx: favor lady gfx")
    local f = Lady.favor(session)
    Bag.add(session.bag, f.bestItem, 1)
    local idx = 0
    for i, id in ipairs(NativesLady.giftableItems(session)) do if id == f.bestItem then idx = i - 1 end end
    local favorPrize = Town.data().lady.favorPrizes[f.favorId + 1]
    local request = require("src.core.game3.rom_text").plain(Lady.favorRequest(session))
    local fp0 = Bag.get(session.bag, favorPrize) or 0
    mark = #M.msgs
    done = M.talk(game, LABEL, {
      answers = { "yes", idx },
      onList = function() d.shot(game, "05_favor_item_list") end,
    })
    d.check(done, "favor lady script finished")
    d.check(M.saw(request, mark), "favor lady asks for " .. request .. " things")
    d.check((Bag.get(session.bag, favorPrize) or 0) == fp0 + 1, "best item earned the prize " .. Town.itemName(favorPrize))
    d.check(Lady.favorState(session) == Lady.STATE_COMPLETED, "SetFavorLadyState_Complete")
    d.shot(game, "06_favor_done")

    -- pokeemerald/data/scripts/lilycove_lady.inc:320
    lady(4)
    local c = Lady.contest(session)
    d.check(S.var("VAR_OBJ_GFX_ID_1") == Town.data().lady.contestMonGfx[c.category + 1], "contest lady mon gfx follows the category")
    d.shot(game, "07_contest_lady")
    local okP, Pokeblock = pcall(require, "src.core.game3.rse.pokeblock")
    if okP and Pokeblock.add then
      local key = ({ [0] = "spicy", "dry", "sweet", "bitter", "sour" })[c.category]
      local block = Pokeblock.new({ color = 1, [key] = 20, feel = 20 })
      Pokeblock.add(session, block)
      S.giveItem("ITEM_POKEBLOCK_CASE", 1)
      mark = #M.msgs
      done = M.talk(game, LABEL, { answers = { "yes" }, onCase = function()
        if not d._caseShot then d._caseShot = true d.shot(game, "08_pokeblock_case") end
      end })
      d.check(done, "contest lady script finished")
      if not d.check(c.givenPokeblock == true and c.numGoodPokeblocksGiven == 1, "pokeblock of the right flavor given") then
        for i = mark + 1, #M.msgs do d.note("msg " .. i .. ": " .. M.msgs[i]:gsub("\n", "/")) end
      end
      d.check(M.saw(require("src.core.game3.rom_text").plain(string.format("sContestLadyMonNames[%d]", c.category)), mark),
        "lady names her POKeMON")
    else
      d.note("pokeblock module unavailable: " .. tostring(Pokeblock))
    end
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
