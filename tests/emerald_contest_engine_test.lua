package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_contest_engine_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_contest_engine_test: skipped (" .. ROM_PATH .. " is not Emerald)")
  os.exit(0)
end

local GV = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Rom = require("src.import.gba.rom")
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
local CX = require("src.import.gba.rse.contest_extract")
CX.run(rom, cache, { cacheRoot = "gba", game = "emerald" })
local man = assert(load(files["gba/" .. CX.SUB .. "/manifest.lua"], "@m", "t", {}))()
local moves = require("src.import.gba.contest_moves_extract").extract(rom)
local Contest = require("src.core.game3.rse.contest")
local Util = require("src.core.game3.rse.contest_util")
local D = Contest.buildData(moves, man)
local E = Contest.EFFECT

local function lcg(seed)
  local Rng = require("src.core.game3.rng")
  local v = seed
  return function()
    v = (Rng.mulU32(v, 1103515245) + 24691) % 4294967296
    return math.floor(v / 65536)
  end
end

local function moveWith(effect, opts)
  opts = opts or {}
  for id = 1, moves.count - 1 do
    local m = moves.moves[id]
    if m.effect == effect and (opts.allowCombo or m.comboStarterId == 0) and (opts.category == nil or m.category == opts.category)
      and (opts.notCategory == nil or m.category ~= opts.notCategory) then
      local combos = m.comboMoves
      if opts.allowCombo or (combos[1] == 0 and combos[2] == 0 and combos[3] == 0 and combos[4] == 0) then return id end
    end
  end
  error("no plain move with contest effect " .. effect)
end

local function newContest(category, list)
  local c = Contest.new({ data = D, category = category, rank = 0, rng = lcg(77) })
  for i = 0, 3 do
    c.mons[i] = { species = 1, aiFlags = 0, moves = { [0] = list[i], 0, 0, 0 }, cool = 0, beauty = 0, cute = 0,
      smart = 0, tough = 0, sheen = 0 }
  end
  c:calculateRound1Points()
  c:init()
  return c
end

local function play(c, list)
  for i = 0, 3 do c.status[i].currMove = c:isTurnDisabled(i) and 0 or list[i] end
  local events = {}
  for t = 0, 3 do
    c.contest.turnNumber = t
    local who = c:startTurn()
    events[who] = c:completeTurn(who)
  end
  c:finishRound()
  local appeals = {}
  for i = 0, 3 do appeals[i] = c.status[i].appeal end
  c:resetForNextRound()
  c:nextRound()
  return appeals, events
end

local function byOrder(c, turn)
  for i = 0, 3 do if c.results.turnOrder[i] == turn then return i end end
end

-- pokeemerald/src/contest.c:4425
do
  local plain = moveWith(E.HIGHLY_APPEALING)
  local cat = moves.moves[plain].category
  local c = newContest(cat, { [0] = plain, plain, plain, plain })
  local list = { [0] = plain, plain, plain, plain }
  local a = play(c, list)
  for i = 0, 3 do eq(a[i], 40 + 10, "highly appealing move in its own category appeals 40 + 10 excitement") end
  eq(c.contest.applauseLevel, 4, "four same-category appeals fill the meter to 4")
  local a2 = play(c, list)
  for i = 0, 3 do eq(a2[i], 40 - 20, "repeated move loses 20 and earns no excitement") end
  eq(c.contest.applauseLevel, 4, "repeats leave the meter alone")
end

-- pokeemerald/src/contest_effect.c:522
do
  local m = moveWith(E.BETTER_IF_FIRST)
  local cat = (moves.moves[m].category + 2) % 5
  local plain = moveWith(E.HIGHLY_APPEALING, { notCategory = cat, allowCombo = true })
  local c = newContest(cat, { [0] = m, m, m, m })
  local first = byOrder(c, 0)
  local list = { [0] = plain, plain, plain, plain }
  list[first] = m
  local excite = c:moveExcitement(m)
  local a = play(c, list)
  local base = D.effects[E.BETTER_IF_FIRST].appeal
  eq(a[first], base * 3 + (excite > 0 and 10 or 0), "better-if-first move appealing first triples its base")
end

-- pokeemerald/src/contest_effect.c:93
do
  local boom = moveWith(E.GREAT_APPEAL_BUT_NO_MORE_MOVES)
  local cat = moves.moves[boom].category
  local plain = moveWith(E.HIGHLY_APPEALING, { notCategory = cat, allowCombo = true })
  local c = newContest(cat, { [0] = boom, plain, plain, plain })
  play(c, { [0] = boom, plain, plain, plain })
  eq(c.status[0].noMoreTurns, 1, "great-appeal move sets noMoreTurns at round end")
  check(c:isTurnDisabled(0), "exploded contestant cannot appeal again")
  local a, events = play(c, { [0] = boom, plain, plain, plain })
  eq(a[0], 0, "exploded contestant appeals 0 next round")
  eq(events[0][2].text, "gText_MonWasWatchingOthers", "exploded contestant watches the others")
end

-- pokeemerald/src/contest_effect.c:307
do
  local jam = moveWith(E.JAMS_OTHERS_BUT_MISS_ONE_TURN)
  local cat = moves.moves[jam].category
  local plain = moveWith(E.HIGHLY_APPEALING, { notCategory = cat, allowCombo = true })
  local c = newContest(cat, { [0] = jam, plain, plain, plain })
  local last = byOrder(c, 3)
  local list = { [0] = plain, plain, plain, plain }
  list[last] = jam
  play(c, list)
  eq(c.status[last].numTurnsSkipped, 1, "jam-and-rest move skips the next turn")
  play(c, list)
  eq(c.status[last].numTurnsSkipped, 0, "skip counter runs out after one round")
end

-- pokeemerald/src/contest_effect.c:754
do
  local early = moveWith(E.NEXT_APPEAL_EARLIER)
  local cat = moves.moves[early].category
  local plain = moveWith(E.HIGHLY_APPEALING, { notCategory = cat, allowCombo = true })
  local c = newContest(cat, { [0] = plain, plain, plain, plain })
  local last = byOrder(c, 3)
  local list = { [0] = plain, plain, plain, plain }
  list[last] = early
  play(c, list)
  eq(c.results.turnOrder[last], 0, "move-up-in-line appeals first next round")
end

-- pokeemerald/src/contest_effect.c:964
do
  local freeze = moveWith(E.DONT_EXCITE_AUDIENCE)
  local cat = moves.moves[freeze].category
  local same, sameBase
  for _, e in ipairs({ E.HIGHLY_APPEALING, E.USER_LESS_EASILY_STARTLED, E.AVOID_STARTLE, E.AVOID_STARTLE_ONCE,
    E.AVOID_STARTLE_SLIGHTLY, E.USER_MORE_EASILY_STARTLED }) do
    local ok, id = pcall(moveWith, e, { category = cat, allowCombo = true })
    if ok then same, sameBase = id, D.effects[e].appeal; break end
  end
  local c = newContest(cat, { [0] = same, same, same, same })
  local first = byOrder(c, 0)
  local list = { [0] = same, same, same, same }
  list[first] = freeze
  local a, events = play(c, list)
  eq(c.contest.applauseLevel, 1, "only the freezer's appeal moved the meter")
  for i = 0, 3 do
    if i ~= first then
      eq(a[i], sameBase, "appeals after a crowd freeze get no excitement bonus")
      local ignored = false
      for _, e in ipairs(events[i]) do if e.text == "gText_MonsMoveIsIgnored" then ignored = true end end
      check(ignored, "crowd ignores appeals after a freeze")
    end
  end
end

-- pokeemerald/src/contest_util.c:1470
do
  local c = { round1 = { [0] = 63, 0, 1, 700 }, round2 = { [0] = 80, -80, 1, -1 } }
  eq(Util.preliminaryStars(c, 0, true), 1, "63 condition points = 1 star")
  eq(Util.preliminaryStars(c, 1, true), 0, "0 points = 0 stars")
  eq(Util.preliminaryStars(c, 2, true), 1, "any condition shows at least one star")
  eq(Util.preliminaryStars(c, 3, true), 10, "stars cap at 10")
  eq(Util.round2Hearts(c, 0, true), 1, "80 round-2 points = 1 heart")
  eq(Util.round2Hearts(c, 1, true), -1, "negative round-2 points = negative hearts")
  eq(Util.round2Hearts(c, 3, true), -1, "any negative round-2 points shows one lost heart")
end

-- pokeemerald/src/contest.c:5594
do
  local session = {}
  Util.clearAllWinners(session, D)
  eq(#session.contestWinners, 13, "13 contest winner slots after new game")
  eq(session.contestWinners[1].species, man.defaultWinners[0].species, "hall winner 1 is the ROM default")
  eq(session.contestWinners[9].species, 0, "museum slots start empty")
  eq(Util.countPlayerMuseumPaintings(session), 0, "no museum paintings at new game")
  local plain = moveWith(E.HIGHLY_APPEALING)
  local c = newContest(0, { [0] = plain, plain, plain, plain })
  c.standings = { [0] = 1, 2, 3, 0 }
  c.mons[3].species = 25
  c.mons[3].personality = 1234
  eq(Util.saveContestWinner(session, 0, c), true, "hall winner saved")
  eq(session.contestWinners[1].species, 25, "newest hall winner goes to slot 1")
  eq(session.contestWinners[2].species, man.defaultWinners[0].species, "older hall winners shift down")
  eq(Util.saveContestWinner(session, Util.SAVE_FOR_MUSEUM, c), true, "player winner saved for the museum")
  eq(session.contestWinners[9].species, 25, "cool museum painting slot 9")
  check(session.contestWinners[9].contestCategory < 3, "museum caption id stays in the cool band")
  eq(Util.countPlayerMuseumPaintings(session), 1, "one museum painting")
  c.standings = { [0] = 0, 2, 3, 1 }
  eq(Util.saveContestWinner(session, Util.SAVE_FOR_MUSEUM, c), false, "an NPC winner is never saved to the museum")
end

T.finish()
