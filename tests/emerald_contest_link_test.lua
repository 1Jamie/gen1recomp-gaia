package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_contest_link_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_contest_link_test: skipped (" .. ROM_PATH .. " is not Emerald)")
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

local ROOT = "data/generated/gba"
local files = {}
local cache = {
  write = function(_, rel, bytes) files[rel] = bytes; return true end,
  read = function(_, rel) return files[rel] end,
}
package.loaded["src.core.game3.dataset"] = {
  cache = function() return { read = function(_, rel) return files[rel] end, exists = function(_, rel) return files[rel] ~= nil end } end,
  mountExtractRoots = function() end,
}

local CX = require("src.import.gba.rse.contest_extract")
local GX = require("src.import.gba.rse.contest_gfx_extract")
CX.run(rom, cache, { cacheRoot = ROOT, game = "emerald" })
GX.run(rom, cache, { cacheRoot = ROOT, game = "emerald" })
local man = assert(load(files[ROOT .. "/" .. CX.SUB .. "/manifest.lua"], "@m", "t", {}))()
local moves = require("src.import.gba.contest_moves_extract").extract(rom)
local Contest = require("src.core.game3.rse.contest")
local D = Contest.buildData(moves, man)
local CL = require("src.core.game3.link.contest_link")
local Json = require("src.link.Json")

local C = require("src.core.game3.constants").of("emerald")
local function mv(name) return C:require("moves", name) end

local ENTRANTS = {
  { species = C:require("species", "SPECIES_SALAMENCE"), nickname = "SALAMENCE", trainerName = "NICK",
    moves = { mv("MOVE_HEADBUTT"), mv("MOVE_EMBER"), mv("MOVE_DRAGON_BREATH"), mv("MOVE_FLY") },
    cool = 120, beauty = 40, cute = 10, smart = 20, tough = 80, sheen = 30, personality = 12345, otId = 1 },
  { species = C:require("species", "SPECIES_MILOTIC"), nickname = "MILO", trainerName = "ANA",
    moves = { mv("MOVE_SURF"), mv("MOVE_RECOVER"), mv("MOVE_ATTRACT"), mv("MOVE_TWISTER") },
    cool = 60, beauty = 200, cute = 50, smart = 30, tough = 10, sheen = 90, personality = 999, otId = 2,
    scarfCategory = 1 },
  { species = C:require("species", "SPECIES_PIKACHU"), nickname = "PIKA", trainerName = "RED",
    moves = { mv("MOVE_THUNDERBOLT"), mv("MOVE_QUICK_ATTACK"), mv("MOVE_THUNDER_WAVE"), mv("MOVE_CHARM") },
    cool = 90, beauty = 20, cute = 150, smart = 40, tough = 30, sheen = 10, personality = 77, otId = 3 },
  { species = C:require("species", "SPECIES_ALAKAZAM"), nickname = "ZAM", trainerName = "SAGE",
    moves = { mv("MOVE_PSYCHIC"), mv("MOVE_CALM_MIND"), mv("MOVE_RECOVER"), mv("MOVE_FUTURE_SIGHT") },
    cool = 30, beauty = 60, cute = 10, smart = 220, tough = 20, sheen = 50, personality = 4242, otId = 4 },
}

local Wire = require("src.link.Wire")
local function wire(msg)
  if Wire.SCHEMAS[msg.type] then return Wire.sanitize(msg) end
  local out = Wire.plain(msg)
  out.type = msg.type
  return out
end

local function hub(n)
  local inbox, links = {}, {}
  for i = 0, n - 1 do inbox[i] = {} end
  for i = 0, n - 1 do
    local lk = { seat = i, nseats = n, open = true, sent = 0, bytes = 0 }
    function lk:getSeat() return self.seat end
    function lk:seatCount() return n end
    function lk:isOpen() return self.open end
    function lk:send(msg)
      local text = Json.encode(msg)
      self.sent = self.sent + 1
      if #text > self.bytes then self.bytes = #text end
      for j = 0, n - 1 do
        if j ~= i then table.insert(inbox[j], wire(Json.decode(text))) end
      end
      return true
    end
    function lk:take(kind)
      local q = inbox[i]
      for k = 1, #q do
        if q[k].type == kind then return table.remove(q, k) end
      end
      return nil
    end
    links[i] = lk
  end
  return links
end

local function transfer(n, categories, seed)
  local links = hub(n)
  local jobs, results = {}, {}
  for i = 0, n - 1 do
    local s = CL.newSession(links[i], { flags = CL.FLAG.IS_LINK + CL.FLAG.IS_WIRELESS })
    jobs[i] = CL.beginTransfer({ session = s, category = categories[i + 1], contestant = ENTRANTS[i + 1],
      gameCleared = false, data = D, seed = i == 0 and seed or nil })
  end
  for _ = 1, 50 do
    local pending = false
    for i = 0, n - 1 do
      if results[i] == nil then
        results[i] = jobs[i]:step()
        if results[i] == nil then pending = true end
      end
    end
    if not pending then break end
  end
  return jobs, results, links
end

local function playRound(cs, choice)
  local n = #cs + 1
  local picked, got = {}, {}
  for i = 0, n - 1 do
    local c = cs[i]
    local me = c.playerIndex
    picked[i] = c:isTurnDisabled(me) and 0 or (c.mons[me].moves[choice(i, c.contest.appealNumber)] or 0)
  end
  for _ = 1, 50 do
    local pending = false
    for i = 0, n - 1 do
      if not got[i] then
        got[i] = CL.exchangeMoves(cs[i], picked[i])
        if not got[i] then pending = true end
      end
    end
    if not pending then break end
  end
  for i = 0, n - 1 do
    local c = cs[i]
    c.linkMoves = {}
    for k = 0, c.linkPlayers - 1 do c.linkMoves[k] = got[i][k] end
    c:chooseMoves(0)
    c.linkMoves = nil
    for t = 0, 3 do
      c.contest.turnNumber = t
      c:runTurn()
    end
    c:finishRound()
    c:resetForNextRound()
  end
end

local function runContest(n, seed, choice)
  local cats = {}
  for i = 1, n do cats[i] = 2 end
  local jobs, results, links = transfer(n, cats, seed)
  local cs = {}
  for i = 0, n - 1 do
    eq(results[i], CL.RESULT.OK, string.format("%dP seed %X: seat %d link transfer succeeds", n, seed, i))
    cs[i] = jobs[i].contest
  end
  for i = 0, n - 1 do cs[i]:init() end
  local more = true
  while more do
    playRound(cs, choice)
    more = false
    for i = 0, n - 1 do more = cs[i]:nextRound() end
  end
  for i = 0, n - 1 do cs[i]:endAppeals() end
  local finals = {}
  for _ = 1, 50 do
    local pending = false
    for i = 0, n - 1 do
      if not finals[i] then
        finals[i] = CL.exchangeFinalStandings(cs[i])
        if not finals[i] then pending = true end
      end
    end
    if not pending then break end
  end
  return cs, links
end

print("[test] link contest transfer (pokeemerald/src/contest_link_util.c:33)")
for _, n in ipairs({ 2, 3, 4 }) do
  local jobs, results = transfer(n, { 0, 0, 0, 0 }, 0xC0FFEE + n)
  for i = 0, n - 1 do
    eq(results[i], CL.RESULT.OK, n .. "P transfer: seat " .. i .. " ok")
    eq(jobs[i].contest.playerIndex, i, n .. "P transfer: seat " .. i .. " is contestant " .. i)
  end
  local ref = CL.setupDigest(jobs[0].contest)
  for i = 1, n - 1 do eq(CL.setupDigest(jobs[i].contest), ref, n .. "P transfer: seat " .. i .. " has the leader's lineup") end
  local c = jobs[0].contest
  eq(c.mons[1].species, ENTRANTS[2].species, n .. "P transfer: remote entrant lands in its seat")
  eq(c.mons[1].beauty, math.min(255, ENTRANTS[2].beauty + 20), n .. "P transfer: scarf bonus from the sender (contest.c:2825)")
  if n < 4 then
    check(c.mons[3] and c.mons[3].aiFlags ~= nil and c.opponentIds[3] ~= nil,
      n .. "P transfer: AI contestants fill the empty seats (contest.c:2910)")
  end
  check(c:isLink(), n .. "P transfer: contest runs in link mode")
  eq(jobs[1].session.contestRng.next(), jobs[0].session.contestRng.next(),
    n .. "P transfer: GenerateContestRand streams agree (contest_util.c:2680)")
end

do
  local _, results = transfer(3, { 0, 0, 3 }, 0x1111)
  for i = 0, 2 do eq(results[i], CL.RESULT.DIFF_CONTEST, "different categories report case 1 on seat " .. i) end
end

print("[test] lockstep appeals give every peer identical results (pokeemerald/src/contest_link.c:276)")
for _, case in ipairs({
  { n = 2, seed = 0x1234 }, { n = 3, seed = 0xBEEF }, { n = 4, seed = 0x7777 }, { n = 4, seed = 0x2468 },
}) do
  local cs, links = runContest(case.n, case.seed, function(seat, round) return (seat * 3 + round * 2) % 4 end)
  local desync = false
  for i = 0, case.n - 1 do if cs[i].linkDesync then desync = true end end
  check(not desync, string.format("%dP seed %X: per-round hashes never diverge", case.n, case.seed))
  local ref = cs[0]
  for i = 1, case.n - 1 do
    local c = cs[i]
    local same = true
    for k = 0, 3 do
      if c.totals[k] ~= ref.totals[k] or c.standings[k] ~= ref.standings[k] or c.round2[k] ~= ref.round2[k]
          or c.appealTotals[k] ~= ref.appealTotals[k] then
        same = false
      end
    end
    check(same, string.format("%dP seed %X: seat %d final standings match the leader", case.n, case.seed, i))
    eq(CL.hash(c), CL.hash(ref), string.format("%dP seed %X: seat %d end state hash", case.n, case.seed, i))
  end
  local maxBytes = 0
  for i = 0, case.n - 1 do if links[i].bytes > maxBytes then maxBytes = links[i].bytes end end
  check(maxBytes <= 8192, "every game3_contest_* message fits the relay's 8KB cap (" .. maxBytes .. ")")
  local winners = {}
  for i = 0, case.n - 1 do winners[#winners + 1] = cs[i]:winner() end
  eq(table.concat(winners, ","), string.rep(tostring(ref:winner()), case.n, ","), "same winner everywhere")
end

print("[test] a dropped link surfaces as an error instead of hanging")
do
  local jobs, results, links = transfer(2, { 0, 0 }, 0x42)
  eq(results[0], CL.RESULT.OK, "transfer before the drop")
  local c = jobs[0].contest
  c:init()
  links[1].open = false
  links[0].open = false
  local moves, err = CL.exchangeMoves(c, 0)
  eq(moves, nil, "no moves once the link is gone")
  eq(err, "closed", "closed link reported")
end

print("[test] two contest stages over the link finish together (pokeemerald/src/contest.c:1632)")
do
  local Vram = require("src.ui.game3.rse.contest_vram")
  Vram.reset()
  Vram.reader = function(path) return files[path] end
  local Stage = require("src.ui.game3.rse.contest")
  Stage.ir = function(key) return { { t = "text", s = key }, { t = "eos" } } end
  Stage.has = function() return true end
  local Anim = require("src.core.game3.battle.anim")
  local launchMove = Anim.launchMove
  Anim.launchMove = function(_, opts)
    if opts and opts.onEnd then opts.onEnd() end
    return true
  end
  Anim.reset({ headless = true, double = true })
  local jobs, results = transfer(2, { 1, 1 }, 0x5150)
  eq(results[0] == CL.RESULT.OK and results[1] == CL.RESULT.OK, true, "stage peers linked")
  local screens = {}
  local sched = { [0] = { 0, 1, 2, 3, 0 }, [1] = { 3, 2, 1, 0, 1 } }
  for i = 0, 1 do
    screens[i] = Stage.new({ contest = jobs[i].contest, headless = true, moveName = function(m) return "M" .. m end })
  end
  local waited = { [0] = 0, [1] = 0 }
  for _ = 1, 40000 do
    if screens[0].done and screens[1].done then break end
    for i = 0, 1 do
      local s = screens[i]
      if not s.done then
        if s.m.tasks:isActive(s:func("taskHandleMoveSelectInput")) then
          s.c.contest.playerMoveChoice = sched[i][s.c.contest.appealNumber + 1]
        end
        if s.m.tasks:isActive(s:func("taskCommunicateMoveSelections")) then waited[i] = waited[i] + 1 end
        s:frame({ new = { a = true }, held = { a = true }, rep = {} })
      end
    end
  end
  Anim.launchMove = launchMove
  eq(screens[0].done and screens[1].done, true, "both stages reach the end")
  check(waited[0] + waited[1] > 0, "a stage waited on its partner's move at least once")
  local a, b = screens[0].c, screens[1].c
  local same = true
  for k = 0, 3 do if a.totals[k] ~= b.totals[k] or a.standings[k] ~= b.standings[k] then same = false end end
  check(same, "stage peers agree on totals and standings")
  check(not a.linkDesync and not b.linkDesync, "no stage desync")
  eq(a.playerIndex .. "/" .. b.playerIndex, "0/1", "each stage drives its own contestant")
  eq(a.contest.appealNumber .. "/" .. b.contest.appealNumber, "5/5", "all five appeals ran on both stages")
  check(screens[0].frames > 2000, "stage ran " .. screens[0].frames .. " frames")
  local hist = a.contest.moveHistory
  eq(hist[0][0], a.mons[0].moves[0], "seat 0 used its own round-1 pick")
  eq(hist[0][1], a.mons[1].moves[3], "seat 1's pick arrived over the link for round 1")
  eq(b.contest.moveHistory[1][0], b.mons[0].moves[1], "seat 1 saw seat 0's round-2 pick")

  local Results = require("src.ui.game3.rse.contest_results")
  local okN, NC = pcall(require, "src.core.game3.scripting.natives_contest")
  local onShown = okN and NC.onResultsShown
  if okN then NC.onResultsShown = function() end end
  local sessions = { [0] = { gameStats = {}, party = {} }, [1] = { gameStats = {}, party = {} } }
  local rs = {}
  for i = 0, 1 do
    rs[i] = Results.new({ contest = screens[i].c, session = sessions[i], headless = true, noFieldHooks = true })
  end
  for _ = 1, 40000 do
    if rs[0].done and rs[1].done then break end
    for i = 0, 1 do
      if not rs[i].done then rs[i]:frame({ new = { a = true }, held = { a = true }, rep = {} }) end
    end
  end
  if okN then NC.onResultsShown = onShown end
  eq(rs[0].done and rs[1].done, true, "both results screens reach the end")
  for i = 0, 1 do
    local c = screens[i].c
    local place = c.standings[c.playerIndex]
    eq(sessions[i].contestLinkResults[2][place + 1], 1, "seat " .. i .. " link results count its place (contest.c:3635)")
    eq(sessions[i].gameStats[36], nil, "seat " .. i .. " link contest leaves GAME_STAT_ENTERED_CONTEST alone")
    eq(sessions[i].gameStats[35] or 0, place == 0 and 1 or 0, "seat " .. i .. " GAME_STAT_WON_LINK_CONTEST")
    eq(c.link, nil, "seat " .. i .. " dropped the contest link after results (contest_util.c:1005)")
  end
end

T.finish()
