local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_contest_stage_parity", "/tmp/em_contest_stage_parity")

local function mod(name) return require(name) end

local RESULTS_FNV = "32016F31"

local function rngNext(x)
  return (mod("src.core.game3.rng").mulU32(x, 1103515245) + 24691) % 4294967296
end

local function stream(groups)
  local s = { used = 0, value = 0, split = 0, inSplit = 0, total = 0 }
  function s.begin(k)
    local g = groups[k]
    s.g, s.value, s.used, s.split, s.inSplit, s.total = g, g.seed, 0, 0, 0, 0
    for i = 0, #g.splits do s.total = s.total + (g.splits[i] or 0) end
  end
  function s.draw()
    local g = s.g
    if s.used >= s.total then
      s.value = rngNext(s.value)
      return math.floor(s.value / 65536)
    end
    while s.inSplit >= (g.splits[s.split] or 0) do
      s.split = s.split + 1
      s.inSplit = 0
      s.value = rngNext(s.value)
    end
    s.value = rngNext(s.value)
    s.used = s.used + 1
    s.inSplit = s.inSplit + 1
    return math.floor(s.value / 65536)
  end
  return s
end

local function capture(screen, path)
  local lg = love.graphics
  local cv = lg.newCanvas(240, 160)
  lg.push("all")
  lg.origin()
  lg.setCanvas(cv)
  lg.clear(0, 0, 0, 1)
  screen:draw()
  lg.setCanvas()
  lg.pop()
  os.execute('mkdir -p "' .. d.dir .. '" 2>/dev/null')
  local img = cv:newImageData()
  local fd = img:encode("png")
  local f = io.open(d.dir .. "/" .. path .. ".png", "wb")
  if f then f:write(fd:getString()) f:close() end
  local bit = require("bit")
  local Rng = mod("src.core.game3.rng")
  local h = 0x811C9DC5
  for y = 0, 159 do
    for x = 0, 239 do
      local r, g, b = img:getPixel(x, y)
      for _, v in ipairs({ r, g, b }) do
        h = bit.bxor(h, math.floor(v * 255 + 0.5) / 8 - (math.floor(v * 255 + 0.5) / 8) % 1) % 4294967296
        h = Rng.mulU32(h, 0x01000193)
      end
    end
  end
  return f ~= nil, string.format("%08X", h)
end

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local Contest = mod("src.core.game3.rse.contest")
    local Stage = mod("src.ui.game3.rse.contest")
    local G = dofile("tests/data/emerald_contest/golden_beauty_b.lua")
    local s = stream(G.groups)
    local c = Contest.new({ category = G.category, rank = G.rank, rng = s.draw })
    s.begin(0)
    local p = G.player
    c:setContestants({ gameClear = G.gameClear, player = { species = p.species,
      moves = { p.moves[0], p.moves[1], p.moves[2], p.moves[3] }, cool = p.cool, beauty = p.beauty, cute = p.cute,
      smart = p.smart, tough = p.tough, sheen = p.sheen, personality = p.personality, otId = p.otId } })
    c:calculateRound1Points()
    c.mons[3].nickname, c.mons[3].trainerName = "SALAMENCE", "NICK"
    for i = 0, 2 do d.check(c.opponentIds[i] == G.opponents[i], "golden opponent " .. i .. " picked") end
    s.begin(1)
    local screen = Stage.open({ contest = c, session = session })
    local shot = false
    for _ = 1, 20000 do
      if screen.m.tasks:isActive(screen:func("taskHandleMoveSelectInput")) then
        U.wait(30)
        local hash
        shot, hash = capture(screen, "parity_move_select_r1")
        -- pokeemerald/src/contest.c:1517
        d.check(hash == "BAAEDDB7", "round 1 move select frame matches the pygba capture pixel for pixel (" .. hash .. ")")
        break
      end
      if screen.m.tasks:isActive(screen:func("taskTryShowMoveSelectScreen")) then
        capture(screen, "parity_appeal_prompt_r1")
        U.tap(game, "a")
      end
      U.wait(1)
    end
    d.check(shot, "captured the round 1 move select screen at native 240x160")
    for i = 0, 3 do
      d.check(c.turnOrder[i] == G.groups[1].after.gto[i], "turn order " .. i .. " matches the golden init")
    end
    Stage.reset()

    local s2 = stream(G.groups)
    local c2 = Contest.new({ category = G.category, rank = G.rank, rng = s2.draw })
    local turn = 0
    for k = 0, #G.groups do
      local g = G.groups[k]
      s2.begin(k)
      if g.label == "setup" then
        c2:setContestants({ gameClear = G.gameClear, player = { species = p.species,
          moves = { p.moves[0], p.moves[1], p.moves[2], p.moves[3] }, cool = p.cool, beauty = p.beauty, cute = p.cute,
          smart = p.smart, tough = p.tough, sheen = p.sheen, personality = p.personality, otId = p.otId } })
        c2:calculateRound1Points()
        c2.mons[3].nickname, c2.mons[3].trainerName = "SALAMENCE", "NICK"
      elseif g.label == "init" then
        c2:init()
      elseif g.label == "choose" then
        turn = 0
        local u = g.uninit or {}
        c2.uninit = function(idx) return u[idx] or 0 end
        c2:chooseMoves(g.after.contest.playerMoveChoice)
      elseif g.label == "turn" then
        c2.contest.turnNumber = turn
        c2:completeTurn(c2:startTurn())
        turn = turn + 1
      elseif g.label == "rank" then
        c2:finishRound()
        c2:resetForNextRound()
        c2:nextRound()
      elseif g.label == "final" then
        c2:endAppeals()
      end
    end
    local want = G.groups[#G.groups].after
    local same = true
    for i = 0, 3 do if c2.standings[i] ~= want.stand[i] or c2.totals[i] ~= want.tot[i] then same = false end end
    d.check(same, "golden replay reaches the recorded final standings and totals")
    local Results = mod("src.ui.game3.rse.contest_results")
    local r = Results.open({ contest = c2, session = { gameStats = {}, party = {} }, noFieldHooks = true })
    local rshot = false
    for _ = 1, 4000 do
      if r.m.tasks:isActive(r:func("taskAnnouncePreliminaryResults")) then
        local hash
        rshot, hash = capture(r, "parity_results_announce")
        -- pokeemerald/src/contest_util.c:696
        d.check(hash == RESULTS_FNV, "results screen matches the pygba capture pixel for pixel (" .. hash .. ")")
        break
      end
      U.wait(1)
    end
    d.check(rshot, "captured the results screen as the announcement starts")
    Results.reset()
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
