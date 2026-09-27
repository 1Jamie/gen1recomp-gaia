package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local PRET = os.getenv("POKEPORT_PRET_EMERALD") or "../pokeemerald"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_contest_ai_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_contest_ai_test: skipped (" .. ROM_PATH .. " is not Emerald)")
  os.exit(0)
end

local rom = { id = "emerald", size = #data }
function rom.get(_, o) return data:byte(o + 1) end
function rom.u16(_, o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
function rom.u32(_, o)
  local a, b, c, d = data:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
function rom.readString(_, o, n) return data:sub(o + 1, o + n) end

local files = {}
local cache = {
  write = function(_, rel, bytes) files[rel] = bytes; return true end,
  read = function(_, rel) return files[rel] end,
}
local ROOT = "data/generated/gba"
local CX = require("src.import.gba.rse.contest_extract")
check(not CX.ready(cache, ROOT), "contest cache not ready before run")
eq(CX.run(rom, cache, { cacheRoot = ROOT }), true, "contest extractor ran")
check(CX.ready(cache, ROOT), "contest cache ready after run")
for _, rel in ipairs(CX.REQUIRED) do check(files[ROOT .. "/" .. rel] ~= nil, rel .. " written") end
local man = assert(load(files[ROOT .. "/" .. CX.SUB .. "/manifest.lua"], "@m", "t", {}))()

local S = require("src.import.gba.syms").of("emerald")
eq(man.opponentCount, S.size("gContestOpponents") / 64, "every gContestOpponents row extracted")
eq(man.opponentCount, 96, "96 contest opponents")
local ranks = { [0] = 0, 0, 0, 0 }
for i = 0, man.opponentCount - 1 do
  local o = man.opponents[i]
  ranks[o.whichRank] = ranks[o.whichRank] + 1
  check(o.species > 0 and o.moves[1] > 0, "opponent " .. i .. " has a species and a move")
end
for r = 0, 3 do check(ranks[r] > 0, "opponents exist for rank " .. r) end
eq(#man.appealResultTexts + 1, 62, "62 appeal result strings (CONTEST_STRING_*)")
eq(man.appealResultTexts[0].name, "gText_BecameMoreConsciousOfOtherMons", "appeal string 0 resolves by name")
eq(man.roundResultTexts[5].name, "gText_MonHasntMadeItsAppeal", "round result 5 resolves by name")
eq(man.excitementTable[0][0], 1, "cool move in a cool contest excites")
eq(man.defaultWinners[0].species ~= 0, true, "default contest hall winner present")

local Disasm = require("src.core.game3.rse.contest_ai_disasm")
local Ai = require("src.core.game3.rse.contest_ai")
local script = Ai.script(man.ai)
local w = Disasm.walk(script.read, (function()
  local l = {}
  for i = 0, 31 do l[#l + 1] = man.ai.entries[i] end
  return l
end)())
eq(#w.order, man.ai.instructions, "walk of the cached blob decodes the same instruction count")
for code = 0, Disasm.COUNT - 1 do
  check(Disasm.OPS[code] ~= nil, string.format("disasm knows op 0x%02X", code))
  check(Ai.HANDLERS[code] ~= nil, string.format("contest ai VM handles op 0x%02X", code))
end

local ALIAS = {
  if_last_appeal = "if_appeal_num_eq", if_not_last_appeal = "if_appeal_num_not_eq",
  if_used_combo_starter = "if_used_combo_starter_eq", if_not_used_combo_starter = "if_used_combo_starter_eq",
}
local h = io.open(PRET .. "/data/contest_ai_scripts.s", "rb")
if h then
  local src = h:read("*a")
  h:close()
  local labels, cur = {}, nil
  local stack = {}
  local function active()
    for _, v in ipairs(stack) do if not v then return false end end
    return true
  end
  for line in src:gmatch("[^\n]+") do
    local lab = line:match("^([%w_]+):")
    local pp = line:match("^#(%a+)")
    if pp == "ifdef" then stack[#stack + 1] = false; lab = nil
    elseif pp == "ifndef" then stack[#stack + 1] = true; lab = nil
    elseif pp == "else" then stack[#stack] = not stack[#stack]; lab = nil
    elseif pp == "endif" then stack[#stack] = nil; lab = nil
    elseif not active() then lab = nil; line = "" end
    if lab then
      cur = { name = lab, ops = {} }
      labels[#labels + 1] = cur
    elseif cur then
      local m = line:match("^%s+([%a_][%w_]*)")
      if m and not m:find("^enum") and m ~= "align" then cur.ops[#cur.ops + 1] = ALIAS[m] or m end
    end
  end
  local compared, bad, reached = 0, 0, 0
  for _, L in ipairs(labels) do
    local key = "contest_ai_scripts.o:" .. L.name
    if not S.has(key) then key = L.name end
    if S.has(key) and #L.ops > 0 then
      local addr = 0x08000000 + S.off(key)
      if addr >= man.ai.base and addr < man.ai.base + man.ai.size then
        reached = reached + 1
        local a = addr
        for _, want in ipairs(L.ops) do
          local ins = Disasm.decode(script.read, a)
          compared = compared + 1
          if not ins or ins.name ~= want then
            bad = bad + 1
            if bad < 5 then print(string.format("  %s: want %s got %s", L.name, want, ins and ins.name or "?")) end
            break
          end
          a = a + ins.size
        end
      end
    end
  end
  check(reached > 50, "pret contest AI labels land inside the cached blob (" .. reached .. ")")
  eq(bad, 0, "every macro in data/contest_ai_scripts.s decodes to the same op at the same size (" .. compared .. " ops)")
else
  print("emerald_contest_ai_test: pret source half skipped (no " .. PRET .. ")")
end

local moves = (function()
  local GV = require("src.core.GameVersion")
  local Versions = require("src.import.gba.versions")
  local Rom = require("src.import.gba.rom")
  GV.set("emerald")
  Versions.select("emerald")
  local sha = GV.VERSIONS.emerald.sha1
  local r = assert(Rom.open({
    info = function() return { size = #data, md5 = sha } end,
    read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
  }, GV.forSha1(sha)))
  return require("src.import.gba.contest_moves_extract").extract(r)
end)()
local Contest = require("src.core.game3.rse.contest")
local D = Contest.buildData(moves, man)

local function lcg(seed)
  local Rng = require("src.core.game3.rng")
  local v = seed
  return function()
    v = (Rng.mulU32(v, 1103515245) + 24691) % 4294967296
    return math.floor(v / 65536)
  end
end

-- pokeemerald/src/contest_ai.c:311
do
  local c = Contest.new({ data = D, category = 0, rank = 0, rng = lcg(1) })
  c.mons[0] = { aiFlags = 0, moves = { [0] = 1, 0, 0, 0 } }
  Ai.reset(c, 0)
  local any = Ai.getActionToUse(c)
  check(any >= 0 and any <= 3 and c.ai.moveScores[any] == 100, "AI with no flags picks any slot at the untouched score")
  c.mons[0] = { aiFlags = 1, moves = { [0] = 1, 0, 0, 0 } }
  Ai.reset(c, 0)
  local pick = Ai.getActionToUse(c)
  eq(pick, 0, "unset move slots score 0 and are never picked")
  eq(c.ai.moveScores[1], 0, "empty slot scored 0")
end

for cat = 0, 4 do
  for rank = 0, 3 do
    local c = Contest.new({ data = D, category = cat, rank = rank, rng = lcg(cat * 7 + rank + 11) })
    c:setContestants({ gameClear = true, player = { species = 1, moves = { 33, 45, 0, 0 } } })
    c:calculateRound1Points()
    c:init()
    local ok, err = pcall(function() c:run({ 0, 1, 0, 1, 0 }) end)
    check(ok, string.format("full contest runs cat %d rank %d %s", cat, rank, ok and "" or tostring(err)))
    if ok then
      local seen = {}
      for i = 0, 3 do seen[c.standings[i]] = true end
      check(seen[0] and seen[1] and seen[2] and seen[3], string.format("cat %d rank %d standings are a permutation", cat, rank))
      for i = 0, 3 do
        eq(c.totals[i], c.round1[i] + 2 * c.appealTotals[i], string.format("cat %d rank %d total[%d] = round1 + 2*appeals", cat, rank, i))
      end
    end
  end
end

T.finish()
