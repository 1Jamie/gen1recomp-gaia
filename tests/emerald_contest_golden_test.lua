package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_contest_golden_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_contest_golden_test: skipped (" .. ROM_PATH .. " is not Emerald)")
  os.exit(0)
end

local GV = require("src.core.GameVersion")
local Rom = require("src.import.gba.rom")
local Versions = require("src.import.gba.versions")
GV.set("emerald")
Versions.select("emerald")
local sha = GV.VERSIONS.emerald.sha1
local rom = assert(Rom.open({
  info = function() return { size = #data, md5 = sha } end,
  read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
}, GV.forSha1(sha)))

local files = {}
local cache = {
  write = function(_, rel, bytes) files[rel] = bytes; return true end,
  read = function(_, rel) return files[rel] end,
}
local ROOT = "data/generated/gba"
local CX = require("src.import.gba.rse.contest_extract")
local ok = CX.run(rom, cache, { cacheRoot = ROOT, game = "emerald" })
eq(ok, true, "contest extractor ran")
local manifest = assert(load(files[ROOT .. "/" .. CX.SUB .. "/manifest.lua"], "@m", "t", {}))()
local moves = require("src.import.gba.contest_moves_extract").extract(rom)

local Contest = require("src.core.game3.rse.contest")
local D = Contest.buildData(moves, manifest)

local function rngNext(x)
  local Rng = require("src.core.game3.rng")
  return (Rng.mulU32(x, 1103515245) + 24691) % 4294967296
end

local function stream(groups)
  local s = { k = -1, used = 0, value = 0, split = 0, inSplit = 0, total = 0 }
  function s.begin(k)
    local g = groups[k]
    s.k, s.g, s.value, s.used, s.split, s.inSplit, s.total = k, g, g.seed, 0, 0, 0, 0
    for i = 0, #g.splits do s.total = s.total + (g.splits[i] or 0) end
  end
  function s.draw()
    local g = assert(s.g, "rng drawn outside a golden group")
    if s.used >= s.total then
      s.over = (s.over or 0) + 1
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

local mismatchBudget = 40
local function cmp(what, want, got, errs)
  if want ~= got then
    errs[#errs + 1] = string.format("%s want %s got %s", what, tostring(want), tostring(got))
  end
end

local function compareState(c, st, fields, label, opts)
  local errs = {}
  opts = opts or {}
  for i = 0, 3 do
    if st.r1 then cmp("r1[" .. i .. "]", st.r1[i], c.round1[i], errs) end
    if st.gto and not opts.skipGto then cmp("gto[" .. i .. "]", st.gto[i], c.turnOrder[i], errs) end
    if st.app then cmp("app[" .. i .. "]", st.app[i], c.appealTotals[i], errs) end
    if st.r2 then cmp("r2[" .. i .. "]", st.r2[i], c.round2[i], errs) end
    if st.tot then cmp("tot[" .. i .. "]", st.tot[i], c.totals[i], errs) end
    if st.stand and opts.standings then cmp("stand[" .. i .. "]", st.stand[i], c.standings[i], errs) end
  end
  if st.status then
    for i = 0, 3 do
      local row = st.status[i]
      for k, name in ipairs(fields) do
        if not (opts.skipFields and opts.skipFields[name]) then
          cmp(string.format("status[%d].%s", i, name), row[k - 1], c.status[i][name], errs)
        end
      end
    end
    local gc = st.contest
    for _, k in ipairs({ "appealNumber", "applauseLevel", "currentContestant", "playerMoveChoice" }) do
      if gc[k] ~= nil then cmp(k, gc[k], c.contest[k], errs) end
    end
    if gc.prevTurnOrder then
      for i = 0, 3 do cmp("prevTurnOrder[" .. i .. "]", gc.prevTurnOrder[i], c.contest.prevTurnOrder[i], errs) end
    end
    if gc.moveHistory then
      for r = 0, 4 do
        for i = 0, 3 do
          cmp(string.format("moveHistory[%d][%d]", r, i), gc.moveHistory[r][i], c.contest.moveHistory[r][i], errs)
          cmp(string.format("excitementHistory[%d][%d]", r, i), gc.excitementHistory[r][i], c.contest.excitementHistory[r][i], errs)
        end
      end
    end
    local gr = st.results
    if gr then
      for i = 0, 3 do
        cmp("results.turnOrder[" .. i .. "]", gr.turnOrder[i], c.results.turnOrder[i], errs)
        cmp("results.unnervedPokes[" .. i .. "]", gr.unnervedPokes[i], c.results.unnervedPokes[i], errs)
      end
      cmp("results.jam", gr.jam, c.results.jam, errs)
      cmp("results.jam2", gr.jam2, c.results.jam2, errs)
      cmp("results.contestant", gr.contestant, c.results.contestant, errs)
    end
    local gx = st.excitement
    if gx then
      for _, k in ipairs({ "moveExcitement", "frozen", "freezer", "excitementAppealBonus" }) do
        cmp("excitement." .. k, gx[k], c.excitement[k], errs)
      end
    end
  end
  eq(#errs, 0, label .. " matches the pygba golden")
  for i = 1, math.min(#errs, 6) do
    if mismatchBudget > 0 then
      print("    " .. label .. ": " .. errs[i])
      mismatchBudget = mismatchBudget - 1
    end
  end
end

local function runGolden(path)
  local G = dofile(path)
  local name = path:match("([^/]+)%.lua$")
  local fields = G.statusFields
  local s = stream(G.groups)
  local c = Contest.new({ data = D, category = G.category, rank = G.rank, rng = s.draw })
  local round, turn = 0, 0
  local ng = #G.groups
  for k = 0, ng do
    local g = G.groups[k]
    local label = string.format("%s group %d (%s, frame %d)", name, k, g.label, g.frame)
    s.begin(k)
    if g.label == "setup" then
      local p = G.player
      c:setContestants({
        gameClear = G.gameClear,
        player = { species = p.species, moves = { p.moves[0], p.moves[1], p.moves[2], p.moves[3] },
          cool = p.cool, beauty = p.beauty, cute = p.cute, smart = p.smart, tough = p.tough, sheen = p.sheen,
          personality = p.personality, otId = p.otId },
      })
      for i = 0, 2 do eq(c.opponentIds[i], G.opponents[i], name .. " opponent " .. i .. " matches the golden pick") end
      c:calculateRound1Points()
      compareState(c, g.after, fields, label)
    elseif g.label == "init" then
      c:init()
      compareState(c, g.after, fields, label)
    elseif g.label == "choose" then
      turn = 0
      local u = g.uninit or {}
      c.uninit = nil
      local modelBad = 0
      for idx, v in pairs(u) do
        if c:uninitVar(idx) ~= v then modelBad = modelBad + 1 end
      end
      eq(modelBad, 0, label .. " heap model gives the recorded out-of-range AI vars")
      c.uninit = function(idx) return u[idx] or 0 end
      c:chooseMoves(g.after.contest.playerMoveChoice)
      compareState(c, g.after, fields, label)
    elseif g.label == "turn" then
      c.contest.turnNumber = turn
      local who = c:startTurn()
      compareState(c, g.after, fields, label)
      c:completeTurn(who)
      turn = turn + 1
      compareState(c, g.settled, fields, label .. " settled")
    elseif g.label == "rank" then
      c:finishRound()
      compareState(c, g.after, fields, label)
      c:resetForNextRound()
      c:nextRound()
      round = round + 1
      if k + 1 <= ng and G.groups[k + 1].label ~= "final" then
        compareState(c, g.settled, fields, label .. " settled")
      end
    elseif g.label == "final" then
      c:endAppeals()
      compareState(c, g.after, fields, label, { standings = true })
    end
    eq(s.used, s.total, label .. " consumed exactly the recorded draws")
    eq(s.over or 0, 0, label .. " drew no extra random numbers")
  end
  eq(round, 5, name .. " ran five appeal rounds")
end

local dir = "tests/data/emerald_contest"
local list = {}
local p = io.popen("ls " .. dir .. "/golden_*.lua 2>/dev/null")
if p then
  for line in p:lines() do list[#list + 1] = line end
  p:close()
end
check(#list > 0, "contest golden files present")
for _, path in ipairs(list) do runGolden(path) end

T.finish()
