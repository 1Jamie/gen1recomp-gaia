local U = require("tests.drivers.util")

local S = {}

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPP = { up = "down", down = "up", left = "right", right = "left" }
local CONN_DIR = { north = "up", south = "down", west = "left", east = "right" }

local function mod(name) return require(name) end

function S.new(name, defaultDir)
  local d = {
    name = name,
    dir = os.getenv("POKEPORT_SHOT_DIR") or defaultDir,
    failures = 0,
    passes = 0,
    vmLogs = {},
    started = {},
  }
  S.d = d
  function d.check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if ok then d.passes = d.passes + 1 else d.failures = d.failures + 1 end
    return ok
  end
  function d.note(msg) print("[driver] " .. msg) end
  local function capture(msg)
    msg = tostring(msg)
    if msg:find("skip unknown", 1, true) or msg:find("skip op", 1, true) or msg:find("not ported", 1, true)
        or msg:find("missing script", 1, true) or msg:find("runaway", 1, true) or msg:find("LUA ERROR", 1, true)
        or msg:find("unknown special", 1, true) or msg:find("unhandled special", 1, true) then
      d.vmLogs[#d.vmLogs + 1] = msg
    end
  end
  local origPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    capture(table.concat(parts, "\t"))
    return origPrint(...)
  end
  local Vm = mod("src.core.game3.scripting.vm")
  local origNew = Vm.new
  Vm.new = function(opts)
    local vm = origNew(opts)
    local a = vm.adapters
    if a and a.log and not a._storyWrapped then
      local inner = a.log
      a.log = function(msg) capture(msg) return inner(msg) end
      a._storyWrapped = true
    end
    return vm
  end
  local origStart = Vm.start
  Vm.start = function(self, key, facing)
    d.started[#d.started + 1] = key
    return origStart(self, key, facing)
  end
  function d.ran(label)
    local Space = mod("src.core.game3.scripting.space")
    local key = Space.bundle and Space.bundle.labels and Space.bundle.labels[label]
    for _, k in ipairs(d.started) do
      if k == label or (key and k == key) then return true end
    end
    return false
  end
  function d.finish(label)
    if d.finished then return end
    d.finished = true
    d.check(#d.vmLogs == 0, "no unknown-op / unported-system VM logs" .. (label and (" " .. label) or "") .. " (" .. #d.vmLogs .. ")")
    for i = 1, math.min(#d.vmLogs, 12) do d.note("VM LOG " .. d.vmLogs[i]) end
    print((d.failures == 0 and "PASS" or "FAIL") .. " " .. d.name .. " passes=" .. d.passes .. " failures=" .. d.failures)
    love.event.quit(d.failures == 0 and 0 or 1)
    U.wait(10)
  end
  function d.shot(game, file)
    return U.still(game, d.dir .. "/" .. file .. ".png")
  end
  return d
end

function S.session() return mod("src.core.game3.runtime").getSession() end
function S.mapNow() local s = S.session() return s and s.map end
function S.C() return mod("src.core.game3.constants").of("emerald") end

local function F() return mod("src.core.game3.scripting.flags") end
local function EM() return F().forVersion("emerald") end
local function store() return mod("src.core.game3.scripting.space").store end

function S.flag(name) return F().getFlag(store(), nil, assert(EM().IDS[name], name)) == true end
function S.setFlag(name, on) F().setFlag(store(), nil, assert(EM().IDS[name], name), on ~= false) end
function S.var(name) return tonumber(F().getVar(store(), nil, assert(EM().VAR_IDS[name], name))) or 0 end
function S.setVar(name, v) F().setVar(store(), nil, assert(EM().VAR_IDS[name], name), v) end

function S.trainerBeaten(name)
  local id = S.C():require("trainers", name)
  return F().getFlag(store(), nil, (EM().IDS.TRAINER_FLAGS_START or 0x500) + id) == true
end

function S.item(name) return S.C():require("items", name) end
function S.hasItem(name)
  local s = S.session()
  return s and s.bag and mod("src.core.game3.bag").has(s.bag, S.item(name), 1) or false
end
function S.giveItem(name, n)
  local s = S.session()
  return mod("src.core.game3.bag").add(s.bag, S.item(name), n or 1)
end

function S.species(name) return S.C():require("species", name) end
function S.move(name) return S.C():require("moves", name) end

function S.giveMon(species, level, moves)
  local Party = mod("src.core.game3.party")
  local ok, _, mon = Party.giveMon(S.session(), S.species(species), level, "")
  if ok and moves then S.setMoves(mon, moves) end
  return mon
end

function S.setMoves(mon, moves)
  local Moves = mod("src.core.game3.battle.moves")
  mon.moves, mon.pp, mon.maxPp = {}, {}, {}
  for i, name in ipairs(moves) do
    local id = S.move(name)
    local def = Moves.get(id)
    local pp = def and tonumber(def.pp) or 10
    mon.moves[i], mon.pp[i], mon.maxPp[i] = id, pp, pp
  end
end

function S.setLevel(mon, level, species)
  local Pokemon = mod("src.core.game3.pokemon")
  local SummaryData = mod("src.core.game3.summary_data")
  if species then
    mon.species, mon.speciesId = S.species(species), S.species(species)
    mon.name = Pokemon.name(mon.species)
  end
  mon.level = level
  mon.exp = SummaryData.expForLevel(mon.growthRate or 0, level)
  mon.hp = nil
  Pokemon.applyStats(mon)
  mon.hp = mon.maxHp or mon.hp
  mon.status = nil
end

function S.healParty()
  mod("src.core.game3.party").healAll(S.session().party)
end

local function Player() return mod("src.core.game3.player") end
local function Warp() return mod("src.core.game3.warp") end
local function Message() return mod("src.ui.game3.message") end
local function Choice() return mod("src.ui.game3.choice") end
local function Battle() return mod("src.core.game3.battle") end
local function Field() return mod("src.core.game3.field") end

function S.vmRunning()
  local Space = mod("src.core.game3.scripting.space")
  return Space.vm and Space.vm:isRunning() or false
end

function S.busy()
  local SE = package.loaded["src.core.game3.step_events"]
  return S.vmRunning() or Warp().isBusy() or Message().isOpen() or Field().locked
    or Player().moving or Choice().isOpen() or Battle().isActive()
    or mod("src.ui.game3.rse.pokenav.call_window").isOpen() or (SE and SE.busy and SE.busy()) or false
end

function S.vmWhere()
  local Space = mod("src.core.game3.scripting.space")
  local vm = Space.vm
  if not (vm and vm:isRunning()) then return "idle" end
  local pc = vm.ctx.pc
  local list = pc and vm.scripts[pc.listKey]
  local row = list and list[pc.index]
  return string.format("%s/%s #%s op=%s mode=%s", tostring(vm._scriptKey), tostring(pc and pc.listKey),
    tostring(pc and pc.index), tostring(row and row.op), tostring(vm.ctx.mode))
end

local function pickMove(st, id)
  local Commands = mod("src.core.game3.battle.commands")
  local Moves = mod("src.core.game3.battle.moves")
  local Types = mod("src.core.game3.battle.types")
  local b = st and st.battlers and st.battlers[id]
  local mon = b and b.mon
  if not mon then return nil end
  local foe
  for fid = 1, 3, 2 do
    local f = st.battlers[fid]
    if f and f.mon and (tonumber(f.mon.hp) or 0) > 0 then foe = f break end
  end
  local best, bestScore
  for slot = 1, 4 do
    local mv = mon.moves and mon.moves[slot]
    if mv and mv ~= 0 and Commands.moveUsable(st, slot, id) then
      local def = Moves.get(mv)
      local pow = def and tonumber(def.power) or 0
      local t = def and tonumber(def.type)
      local score = pow
      if foe and t then score = score * Types.effectiveness(t, foe.type1, foe.type2) end
      if t and (t == b.type1 or t == b.type2) then score = score * 1.5 end
      if not best or score > bestScore then best, bestScore = slot, score end
    end
  end
  return best
end

function S.fight(game, opts)
  opts = opts or {}
  local Ui = mod("src.core.game3.battle.ui")
  local Anim = mod("src.core.game3.battle.anim")
  local PartyMenu = mod("src.ui.game3.party_menu")
  local StatGrowth = mod("src.ui.game3.stat_growth")
  local B = Battle()
  local st = B._st
  local guard = 0
  while B.isActive() and guard < (opts.guard or 60000) do
    guard = guard + 1
    st = B._st or st
    if opts.onFrame then opts.onFrame(st, B._phase) end
    if guard % 3000 == 0 and S.d and os.getenv("EM_STORY_DEBUG") then
      S.d.note(string.format("fight loop %d phase=%s mode=%s menu=%s move=%s turn=%s party=%s", guard, tostring(B._phase),
        tostring(Ui._mode), tostring(Ui._menuIndex), tostring(Ui._moveIndex), tostring(st and st.turn),
        tostring(PartyMenu.isOpen and PartyMenu.isOpen())))
      if guard == 3000 and os.getenv("EM_STORY_DEBUG") then U.still(game, S.d.dir .. "/stuck_fight.png") end
    end
    local phase = B._phase
    if PartyMenu.isOpen and PartyMenu.isOpen() then
      local pick
      for i = 1, #(PartyMenu._party or {}) do
        local ok = PartyMenu._validate == nil or PartyMenu._validate(i) == nil
        local mon = PartyMenu._party[i]
        if ok and mon and (tonumber(mon.hp) or 0) > 0 and not mon.isEgg then pick = i break end
      end
      if not pick then U.tap(game, "b") U.wait(10) else
        PartyMenu.cursor = pick
        U.wait(10)
        U.tap(game, "a")
        U.wait(10)
        PartyMenu.actionCursor = 1
        U.tap(game, "a")
        U.wait(10)
      end
    elseif phase == "command" and Ui._mode == "menu" and not Anim.busy() and S.pendingBattleShot and S.d then
      local file = S.pendingBattleShot
      S.pendingBattleShot = nil
      U.wait(10)
      S.d.shot(game, file)
    elseif phase == "command" and Ui._mode == "menu" and not Anim.busy() then
      if os.getenv("EM_STORY_DEBUG") and S.d and st and st.turn ~= S._lastTurnLogged then
        S._lastTurnLogged = st.turn
        local p, e = st.battlers and st.battlers[0], st.battlers and st.battlers[1]
        local function desc(b)
          local m = b and b.mon
          return m and string.format("%s lv%s %s/%s st=%s spd=%s", tostring(m.species), tostring(m.level), tostring(m.hp),
            tostring(m.maxHp), tostring(m.status), tostring(m.speed)) or "-"
        end
        S.d.note("  turn " .. tostring(st.turn) .. " P " .. desc(p) .. " | E " .. desc(e))
      end
      if (Ui._menuIndex or 1) ~= 1 then
        U.tap(game, "up") U.wait(3) U.tap(game, "left") U.wait(3)
      end
      U.tap(game, "a")
      U.wait(6)
    elseif phase == "command" and Ui._mode == "moves" then
      local who = Ui.activeBattler and Ui.activeBattler() or 0
      local slot = pickMove(st, who)
      if os.getenv("EM_STORY_LOGALL") and S.d then
        local b = st.battlers[who]
        local f = st.battlers[1]
        S.d.note(string.format("pick who=%s slot=%s cur=%s moves=%s types=%s/%s foe=%s/%s", tostring(who), tostring(slot),
          tostring(Ui._moveIndex), table.concat(b and b.mon and b.mon.moves or {}, ","), tostring(b and b.type1),
          tostring(b and b.type2), tostring(f and f.type1), tostring(f and f.type2)))
      end
      if slot then
        for _ = 1, 6 do
          local cur = (Ui._moveIndex or 1) - 1
          local want = slot - 1
          if cur == want then break end
          local key = (cur % 2 ~= want % 2) and ((cur % 2 == 0) and "right" or "left")
            or ((cur < want) and "down" or "up")
          U.tap(game, key)
          U.wait(4)
        end
      end
      U.tap(game, "a")
      U.wait(6)
    elseif phase == "command" and (Ui._mode == "selmsg" or Ui._mode == "target") then
      U.tap(game, "a")
      U.wait(6)
    elseif StatGrowth.isOpen() then
      U.tap(game, "a")
      U.wait(4)
    else
      if Ui.choiceActive and Ui.choiceActive() then
        local log = Ui.log and Ui.log() or {}
        local last = log[#log]
        if type(last) == "table" then
          local ok, txt = pcall(mod("src.core.game3.scripting.text_ir").toAscii, last, {})
          last = ok and txt or ""
        end
        if tostring(last):upper():find("STOP", 1, true) then U.tap(game, "a") else U.tap(game, "b") end
        U.wait(4)
      elseif Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
    end
  end
  return st and st.result, st
end

local function answerChoice(game, ans)
  local Ch = Choice()
  local want
  if ans == "no" then want = 2
  elseif ans == "yes" or ans == nil or ans == "a" then want = nil
  elseif type(ans) == "number" then want = ans
  elseif type(ans) == "string" then
    for i, o in ipairs(Ch.options or {}) do
      local txt = type(o) == "table" and (o.text or o.label or o[1]) or o
      if tostring(txt):upper():find(ans:upper(), 1, true) then want = i break end
    end
  end
  if ans == "b" then U.tap(game, "b") U.wait(6) return end
  if want then
    for _ = 1, 12 do
      if Ch.cursor == want then break end
      local cols = Ch.cols or 1
      if cols > 1 and (Ch.cursor - 1) % cols ~= (want - 1) % cols then
        U.tap(game, ((Ch.cursor - 1) % cols < (want - 1) % cols) and "right" or "left")
      else
        U.tap(game, Ch.cursor < want and "down" or "up")
      end
      U.wait(3)
    end
  end
  U.tap(game, "a")
  U.wait(6)
end

S.battles = {}

function S.settle(game, opts)
  opts = opts or {}
  local limit = opts.limit or 3000
  local pred = opts.until_
  local n = 0
  local d = S.d
  for _ = 1, limit do
    if pred and pred() then return true end
    if opts.watch then opts.watch() end
    local B = Battle()
    if B.isActive() then
      local st = B._st
      local foe = st and st.enemy and st.enemy.mon
      local tr = st and (st.trainerId or (st.trainer and st.trainer.id))
      local rec = { map = S.mapNow(), trainer = tr, foe = foe and foe.species, level = foe and foe.level }
      if opts.onBattleStart then opts.onBattleStart(st) end
      if os.getenv("EM_STORY_DEBUG") and d and st and st.player and st.player.mon then
        local pm = st.player.mon
        d.note(string.format("battle start player %s lv%s hp %s/%s atk %s spa %s moves %s", tostring(pm.species), tostring(pm.level),
          tostring(pm.hp), tostring(pm.maxHp), tostring(pm.atk or (pm.stats and pm.stats.atk)), tostring(pm.spa or (pm.stats and pm.stats.spa)),
          table.concat(pm.moves or {}, ",")))
      end
      local result = S.fight(game, { onFrame = opts.onBattleFrame })
      rec.result = result
      if os.getenv("EM_STORY_DEBUG") and d then
        local Ui = mod("src.core.game3.battle.ui")
        if result ~= "win" or os.getenv("EM_STORY_LOGALL") then
          for i, t in ipairs(Ui.log and Ui.log() or {}) do
            if type(t) == "table" then t = select(2, pcall(mod("src.core.game3.scripting.text_ir").toAscii, t, {})) end
            d.note("  log " .. i .. " " .. tostring(t):gsub("\n", " "))
          end
        end
      end
      S.battles[#S.battles + 1] = rec
      if d then d.note(string.format("battle on %s trainer=%s foe=%s lv%s -> %s", tostring(rec.map), tostring(tr),
        tostring(rec.foe), tostring(rec.level), tostring(result))) end
      if opts.onBattleEnd then opts.onBattleEnd(result, st) end
    elseif Choice().isOpen() then
      answerChoice(game, opts.choice and opts.choice(Choice()) or "yes")
    elseif Message().isOpen() then
      n = n + 1
      if Message().isTyping() then Message().skipReveal() end
      if n % 4 == 0 then U.tap(game, "a") else U.wait(1) end
    elseif opts.onIdleUi and opts.onIdleUi() then
    elseif mod("src.ui.game3.rse.pokenav.call_window").isOpen() then
      n = n + 1
      if n % 4 == 0 then U.tap(game, "a") else U.wait(1) end
    else
      U.wait(1)
    end
    if not pred and not S.busy() then
      U.wait(3)
      if not S.busy() then return true end
    end
  end
  if pred then return pred() and true or false end
  return not S.busy()
end

local function passable(game, fx, fy, tx, ty, dir, elev)
  local Collision = mod("src.core.game3.collision")
  if Player().underwater then
    return Collision.canEnter(game, tx, ty, { fromX = fx, fromY = fy, dir = dir, elevation = elev, surfing = true })
  end
  local surfing
  if S.canSurf then
    local fw, tw = Collision.isWater(fx, fy), Collision.isWater(tx, ty)
    surfing = fw or tw
    if tw and not fw then elev = nil end
  end
  local b = Collision.behavior(tx, ty)
  if b and (Collision.isBumpySlope(b) or Collision.isIsolatedVerticalRail(b) or Collision.isIsolatedHorizontalRail(b)
      or Collision.isVerticalRail(b) or Collision.isHorizontalRail(b) or (dir == "up" and Collision.isMuddySlope(b))) then
    return false
  end
  return Collision.canEnter(game, tx, ty, { fromX = fx, fromY = fy, dir = dir, elevation = elev, surfing = surfing })
end

local SLIDE_DIR = {
  PushedSouthByCurrent = "down", PushedNorthByCurrent = "up", PushedWestByCurrent = "left", PushedEastByCurrent = "right",
  WalkSouth = "down", WalkNorth = "up", WalkWest = "left", WalkEast = "right",
}

local function slideEnd(game, x, y, dir, e)
  local Collision = mod("src.core.game3.collision")
  local FM = mod("src.core.game3.forced_movement")
  for _ = 1, 80 do
    local _, row = FM.lookup(Collision.behavior(x, y))
    local sdir = row and (SLIDE_DIR[row.name] or (row.name == "Slip" and dir))
    if not sdir then break end
    local dd = DELTA[sdir]
    if not passable(game, x, y, x + dd[1], y + dd[2], sdir, e) then break end
    x, y, dir = x + dd[1], y + dd[2], sdir
  end
  return x, y
end

function S.mountSurf(game, dir)
  local P = Player()
  S.face(game, dir)
  U.tap(game, "a")
  U.wait(6)
  S.settle(game, { limit = 4000, until_ = function() return P.surfing and not S.busy() end })
  if P.surfing then
    S.surfMounts = (S.surfMounts or 0) + 1
    if S.onSurf then S.onSurf() end
  end
  return P.surfing
end

local function nextElev(px, py, x, y, e)
  local Collision = mod("src.core.game3.collision")
  local z = Collision.elevationAt and Collision.elevationAt(x, y)
  local p = Collision.elevationAt and Collision.elevationAt(px, py)
  if z == nil or z == 15 or p == 15 then return e end
  return z
end

function S.path(game, goal, opts)
  opts = opts or {}
  local P = Player()
  local Collision = mod("src.core.game3.collision")
  local sx, sy = P.cellX, P.cellY
  local se = P.currentElevation
  if opts.from then sx, sy, se = opts.from[1], opts.from[2], opts.from[3] end
  local function skey(x, y, e) return x .. "," .. y .. "," .. tostring(e) end
  local s0 = { sx, sy, se }
  local prev = { [skey(sx, sy, s0[3])] = false }
  local q, head = { s0 }, 1
  local found
  local isGoal = type(goal) == "function" and goal or function(x, y) return x == goal[1] and y == goal[2] end
  local avoid = opts.avoid or {}
  while head <= #q do
    local c = q[head]
    head = head + 1
    if isGoal(c[1], c[2]) and not (c[1] == sx and c[2] == sy and opts.notHere) then found = c break end
    local e = c[3]
    for _, dir in ipairs({ "up", "down", "left", "right" }) do
      local dd = DELTA[dir]
      local nx, ny = c[1] + dd[1], c[2] + dd[2]
      local lx, ly = Collision.ledgeLanding(game, c[1], c[2], dir)
      local land = lx ~= nil
      if land then
        if passable(game, lx - dd[1], ly - dd[2], lx, ly, dir, nil) then nx, ny = lx, ly else land = false nx = nil end
      end
      if nx and not avoid[nx .. "," .. ny] and #q < 30000 then
        local ok = land and true or passable(game, c[1], c[2], nx, ny, dir, e)
        if not ok and opts.goalBlocked and isGoal(nx, ny) then ok = true end
        if ok and not land and S.slides ~= false then nx, ny = slideEnd(game, nx, ny, dir, e) end
        if ok then
          local ne = nextElev(c[1], c[2], nx, ny, e)
          local k = skey(nx, ny, ne)
          if prev[k] == nil then
            prev[k] = { c, dir }
            q[#q + 1] = { nx, ny, ne }
          end
        end
      end
    end
  end
  if not found then return nil, head end
  local out, k = {}, skey(found[1], found[2], found[3])
  while prev[k] do
    local p = prev[k]
    table.insert(out, 1, p[2])
    k = skey(p[1][1], p[1][2], p[1][3])
  end
  return out, found
end

function S.step(game, dir)
  local P = Player()
  local x0, y0, m0 = P.cellX, P.cellY, S.mapNow()
  for _ = 1, 3 do
    for i = 1, 16 do
      if i == 1 then table.insert(game.input.pressQueue, dir) end
      game.input.state[dir] = true
      U.wait(1)
      if P.moving or P.cellX ~= x0 or P.cellY ~= y0 or S.mapNow() ~= m0 or Warp().isBusy() or S.busy() then break end
    end
    game.input.state[dir] = false
    for _ = 1, 90 do
      if not P.moving and not Warp().isBusy() then break end
      U.wait(1)
    end
    if P.cellX ~= x0 or P.cellY ~= y0 or S.mapNow() ~= m0 or S.busy() then break end
  end
  local lx, ly, stable = P.cellX, P.cellY, 0
  for _ = 1, 600 do
    if not P.moving and not Warp().isBusy() then
      if P.cellX == lx and P.cellY == ly then stable = stable + 1 else stable, lx, ly = 0, P.cellX, P.cellY end
      if stable >= 3 then break end
    else
      stable = 0
    end
    U.wait(1)
  end
end

function S.face(game, dir)
  local P = Player()
  if P.facing ~= dir then
    U.tap(game, dir)
    U.wait(12)
    for _ = 1, 60 do
      if not P.moving then break end
      U.wait(1)
    end
  end
end

function S.goTo(game, goal, opts)
  opts = opts or {}
  local P = Player()
  local m0 = S.mapNow()
  local isGoal = type(goal) == "function" and goal or function(x, y) return x == goal[1] and y == goal[2] end
  local misses = 0
  for attempt = 1, opts.tries or 30 do
    if isGoal(P.cellX, P.cellY) then return true end
    if misses >= (opts.maxMisses or 3) then break end
    if S.mapNow() ~= m0 then return false, "map" end
    if S.busy() then S.settle(game, opts.settle) end
    if S.mapNow() ~= m0 then return false, "map" end
    local p, explored = S.path(game, goal, opts)
    if not p then
      misses = misses + 1
      if S.d then
        local Collision = mod("src.core.game3.collision")
        local parts = {}
        for dir, dd in pairs(DELTA) do
          local ok, why = Collision.canEnter(game, P.cellX + dd[1], P.cellY + dd[2],
            { fromX = P.cellX, fromY = P.cellY, dir = dir, elevation = P.currentElevation })
          parts[#parts + 1] = dir .. "=" .. tostring(ok) .. "/" .. tostring(why)
        end
        S.d.note(string.format("no path on %s from %d,%d elev %s (attempt %d, explored %s) %s", tostring(S.mapNow()), P.cellX,
          P.cellY, tostring(P.currentElevation), attempt, tostring(explored), table.concat(parts, " ")))
      end
      U.wait(40)
    else
      misses = 0
      for _, dir in ipairs(p) do
        local bx, by = P.cellX, P.cellY
        local dd = DELTA[dir]
        if S.canSurf and not P.surfing and not P.underwater and mod("src.core.game3.collision").isWater(bx + dd[1], by + dd[2]) then
          S.mountSurf(game, dir)
          break
        end
        S.step(game, dir)
        if S.mapNow() ~= m0 or S.busy() then break end
        if P.cellX == bx and P.cellY == by then
          S._blockCount = (S._lastBlock == bx .. "," .. by .. dir) and (S._blockCount or 0) + 1 or 1
          S._lastBlock = bx .. "," .. by .. dir
          if (os.getenv("EM_STORY_DEBUG") or S._blockCount == 4) and S.d then
            local held = {}
            for k, v in pairs(game.input.state) do if v then held[#held + 1] = tostring(k) end end
            local SE = package.loaded["src.core.game3.step_events"]
            local RT = package.loaded["src.core.game3.runtime"]
            local FD = package.loaded["src.ui.game3.fade"]
            S.d.note(string.format("step %s blocked at %d,%d on %s (path len %d) facing %s held {%s} turn %s/%s se=%s ui=%s fade=%s",
              dir, bx, by, tostring(S.mapNow()), #p, tostring(P.facing), table.concat(held, ","), tostring(P.turnTimer),
              tostring(P.turnArmed), tostring(SE and SE.busy and SE.busy()), tostring(RT and RT.uiBusy and RT.uiBusy()),
              tostring(FD and FD.lockInput)))
            local H = package.loaded["src.ui.game3.hud"]
            local ev = SE and SE._activeEvent
            S.d.note(string.format("  hud menu=%s fade=%s wait=%s msg=%s ev=%s queue=%d call=%s", tostring(H and H.isMenuOpen()),
              tostring(FD and FD.isActive and FD.isActive()), tostring(H and H._waitButton ~= nil), tostring(Message().isOpen()),
              tostring(ev and ev.type), SE and #SE._queue or -1,
              tostring(mod("src.ui.game3.rse.pokenav.call_window").isOpen())))
          end
          U.wait(8)
          break
        end
      end
    end
  end
  return isGoal(P.cellX, P.cellY)
end

function S.adjacentTo(game, tx, ty, opts)
  opts = opts or {}
  local ok = S.goTo(game, function(x, y)
    return math.abs(x - tx) + math.abs(y - ty) == 1
  end, opts)
  if not ok then return false end
  local P = Player()
  local dir
  for dd, v in pairs(DELTA) do
    if P.cellX + v[1] == tx and P.cellY + v[2] == ty then dir = dd end
  end
  S.face(game, dir)
  return true
end

function S.object(localId)
  return mod("src.core.game3.objects").find(localId)
end

function S.objectByScript(label)
  local Objects = mod("src.core.game3.objects")
  local Space = mod("src.core.game3.scripting.space")
  local want = Space.bundle and Space.bundle.labels and Space.bundle.labels[label]
  for _, lid in ipairs(Objects.listActive() or {}) do
    local eo = Objects.find(lid)
    local s = eo and (eo.scriptKey or (eo.def and (eo.def.script or eo.def.scriptKey)))
    if s == label or (want and s == want) then return eo end
  end
  if S.d then
    for _, lid in ipairs(Objects.listActive() or {}) do
      local eo = Objects.find(lid)
      S.d.note(string.format("object %s at %s,%s script=%s def.script=%s", tostring(lid), tostring(eo.cellX), tostring(eo.cellY),
        tostring(eo.scriptKey), tostring(eo.def and eo.def.script)))
    end
  end
  return nil
end

function S.useRepel()
  local s = S.session()
  if (tonumber(s.repelSteps) or 0) > 0 then return true end
  if not S.hasItem("ITEM_MAX_REPEL") then S.giveItem("ITEM_MAX_REPEL", 1) end
  local ok = mod("src.core.game3.item_use").useField(s, s.bag, S.item("ITEM_MAX_REPEL"), nil)
  return ok
end

function S.talkAt(game, tx, ty, opts)
  if not S.adjacentTo(game, tx, ty, opts) then return false end
  U.tap(game, "a")
  U.wait(4)
  return true
end

function S.talkTo(game, eo, opts)
  if not eo then return false end
  local P = Player()
  local Objects = mod("src.core.game3.objects")
  for _ = 1, 16 do
    local tx, ty = eo.cellX, eo.cellY
    if eo.moving and eo.targetX then tx, ty = eo.targetX, eo.targetY end
    if os.getenv("EM_STORY_DEBUG") and S.d then S.d.note(string.format("talkTo lid %s at %d,%d", tostring(eo.localId), tx, ty)) end
    if not S.adjacentTo(game, tx, ty, opts) then U.wait(20) end
    if S.busy() and not P.moving then
      S.settle(game, opts and opts.settle)
    elseif math.abs(P.cellX - tx) + math.abs(P.cellY - ty) == 1 then
      for _ = 1, 180 do
        if Objects.at(tx, ty) == eo and not P.moving then break end
        U.wait(1)
      end
      if Objects.at(tx, ty) == eo then
        U.tap(game, "a")
        for _ = 1, 10 do
          if S.busy() then return true end
          U.wait(1)
        end
      end
    end
  end
  return false
end

function S.partyHealthy()
  for _, m in ipairs(S.session().party or {}) do
    if not m.isEgg and (tonumber(m.hp) or 0) < (tonumber(m.maxHp) or 0) then return false end
  end
  return true
end

function S.needsHeal(threshold)
  for _, m in ipairs(S.session().party or {}) do
    if not m.isEgg then
      local st = m.status
      if (type(st) == "number" and st ~= 0) or (type(st) == "string" and st ~= "") or type(st) == "table" then return true end
      if (tonumber(m.hp) or 0) < (tonumber(m.maxHp) or 0) * (threshold or 0.8) then return true end
    end
  end
  return false
end

function S.healAtCenter(game, cityMap, labelPrefix)
  S.travel(game, { cityMap, cityMap .. "_POKEMON_CENTER_1F" }, { settle = { limit = 20000 } })
  if S.mapNow() ~= cityMap .. "_POKEMON_CENTER_1F" then return false end
  local nurse = S.objectByScript(labelPrefix .. "_PokemonCenter_1F_EventScript_Nurse")
  if not nurse then return false end
  S.goTo(game, { nurse.cellX, nurse.cellY + 2 })
  S.face(game, "up")
  U.tap(game, "a")
  S.settle(game, { limit = 8000 })
  local ok = S.partyHealthy()
  S.travel(game, { cityMap }, { settle = { limit = 8000 } })
  return ok
end

local function currentDef(game)
  return game.data.maps[S.mapNow()]
end

local function exitCandidates(game, nextMap, arrive)
  local def = currentDef(game)
  local out = {}
  local dest = game.data.maps[nextMap]
  for i, w in ipairs(def and def.warps or {}) do
    if w.destMap == nextMap then
      local ok = true
      if arrive then
        local dw = dest and dest.warps and dest.warps[tonumber(w.destWarp) or 0]
        ok = dw ~= nil and math.abs(dw.x - arrive[1]) + math.abs(dw.y - arrive[2]) <= 3
      end
      if ok then out[#out + 1] = { kind = "warp", x = w.x, y = w.y, index = i } end
    end
  end
  if not arrive then
    local Connections = mod("src.core.game3.connections")
    for _, c in ipairs(Connections.each(def)) do
      if c.map == nextMap then
        local dw, dh = Connections.sizeOf(dest)
        local span = (c.dir == "north" or c.dir == "south") and dw or dh
        out[#out + 1] = { kind = "conn", dir = CONN_DIR[c.dir], lo = c.offset, hi = c.offset + span - 1 }
      end
    end
  end
  return out
end

function S.exitTo(game, nextMap, opts)
  opts = opts or {}
  local P = Player()
  local m0 = S.mapNow()
  local cands = exitCandidates(game, nextMap, opts.arrive)
  if #cands == 0 then
    if S.d then S.d.note("no exit from " .. tostring(m0) .. " to " .. tostring(nextMap)) end
    return false
  end
  local Collision = mod("src.core.game3.collision")
  local function edgeW()
    local ox, oy = mod("src.core.game3.connections").sizeOf(currentDef(game))
    return ox, oy
  end
  local reach, other = {}, {}
  for _, c in ipairs(cands) do
    local ok
    if c.kind == "warp" then
      ok = S.path(game, { c.x, c.y }, { goalBlocked = true }) ~= nil
    else
      local w, h = edgeW()
      ok = S.path(game, function(x, y)
        local along = (c.dir == "up" or c.dir == "down") and x or y
        if c.lo and (along < c.lo or along > c.hi) then return false end
        if c.dir == "up" then return y == 0 elseif c.dir == "down" then return y == h - 1
        elseif c.dir == "left" then return x == 0 else return x == w - 1 end
      end) ~= nil
    end
    if ok then reach[#reach + 1] = c else other[#other + 1] = c end
  end
  for _, c in ipairs(other) do reach[#reach + 1] = c end
  cands = reach
  for _ = 1, opts.tries or 6 do
    if S.mapNow() == nextMap then return true end
    if S.mapNow() ~= m0 then return false end
    for _, c in ipairs(cands) do
      if S.mapNow() ~= m0 then break end
      if c.kind == "warp" then
        local wx, wy = c.x, c.y
        if opts.warpXY then wx, wy = opts.warpXY[1], opts.warpXY[2] end
        local avoid
        if opts.avoidWarps then
          avoid = {}
          for _, w in ipairs(currentDef(game).warps or {}) do
            if not (w.x == wx and w.y == wy) then avoid[w.x .. "," .. w.y] = true end
          end
        end
        local reached = S.goTo(game, { wx, wy }, { goalBlocked = true, tries = opts.goToTries or 12, settle = opts.settle,
          avoid = avoid })
        if os.getenv("EM_STORY_DEBUG") and S.d then
          S.d.note(string.format("exit warp %d,%d reached=%s now %s %d,%d", wx, wy, tostring(reached), tostring(S.mapNow()), P.cellX, P.cellY))
        end
        if S.mapNow() == m0 and not reached then
          S.adjacentTo(game, wx, wy, { tries = 6 })
          local dx, dy = wx - P.cellX, wy - P.cellY
          local dir = dx > 0 and "right" or dx < 0 and "left" or dy > 0 and "down" or "up"
          if math.abs(dx) + math.abs(dy) == 1 then S.step(game, dir) end
        end
        if S.mapNow() == m0 and P.cellX == wx and P.cellY == wy then
          local order = {}
          if opts.pushDir then order[1] = opts.pushDir end
          for _, dir in ipairs({ "down", "up", "left", "right" }) do
            local dd = DELTA[dir]
            if not passable(game, wx, wy, wx + dd[1], wy + dd[2], dir, P.currentElevation) then order[#order + 1] = dir end
          end
          for _, dir in ipairs(order) do
            if S.mapNow() ~= m0 or P.cellX ~= wx or P.cellY ~= wy then break end
            S.step(game, dir)
            S.settle(game, { limit = 200 })
          end
        end
      else
        local w, h = Collision._w or (currentDef(game).width * 2), Collision._h or (currentDef(game).height * 2)
        local ox, oy = mod("src.core.game3.connections").sizeOf(currentDef(game))
        w, h = ox > 0 and ox or w, oy > 0 and oy or h
        local edge = function(x, y)
          local along = (c.dir == "up" or c.dir == "down") and x or y
          if c.lo and (along < c.lo or along > c.hi) then return false end
          if c.dir == "up" then return y == 0 elseif c.dir == "down" then return y == h - 1
          elseif c.dir == "left" then return x == 0 else return x == w - 1 end
        end
        local preferX = opts.edgeNear
        local dead = {}
        local goal = function(x, y)
          if not edge(x, y) or dead[x .. "," .. y] then return false end
          if preferX then
            return math.abs((c.dir == "up" or c.dir == "down") and x - preferX or y - preferX) <= (opts.edgeSlack or 3)
          end
          return true
        end
        for _ = 1, 12 do
          if S.mapNow() ~= m0 then break end
          S.goTo(game, goal, { tries = opts.goToTries or 20, settle = opts.settle })
          if S.mapNow() == m0 and edge(P.cellX, P.cellY) then
            local ex, ey = P.cellX, P.cellY
            for _ = 1, 2 do
              if S.mapNow() ~= m0 then break end
              S.step(game, c.dir)
            end
            if S.mapNow() == m0 and not S.busy() then dead[P.cellX .. "," .. P.cellY] = true end
            if S.mapNow() == nextMap and not S.busy() then
              local _, explored = S.path(game, function() return false end)
              if (explored or 0) < 8 then
                S.step(game, OPP[c.dir])
                S.settle(game, { limit = 600 })
                if S.mapNow() == m0 then dead[ex .. "," .. ey] = true end
              end
            end
          elseif S.mapNow() == m0 and not S.busy() then
            break
          end
        end
      end
      if S.mapNow() ~= m0 then break end
    end
    if S.busy() then S.settle(game, opts.settle) end
  end
  if S.busy() then S.settle(game, opts.settle) end
  return S.mapNow() == nextMap
end

function S.travel(game, chain, opts)
  opts = opts or {}
  for _, entry in ipairs(chain) do
    local m, eopts = entry, opts[entry] or opts
    if type(entry) == "table" then
      m = entry[1]
      eopts = setmetatable({ arrive = entry.arrive, pushDir = entry.pushDir }, { __index = opts })
    end
    if S.mapNow() ~= m then
      if opts.repel ~= false then S.useRepel() end
      local ok = S.exitTo(game, m, eopts)
      S.settle(game, opts.settle)
      if not ok and S.mapNow() ~= m then
        if S.d then S.d.note("travel stuck on " .. tostring(S.mapNow()) .. " heading to " .. m .. " at "
          .. Player().cellX .. "," .. Player().cellY .. " vm " .. S.vmWhere()) end
        return false
      end
    end
  end
  return true
end

function S.checkpointPath(name)
  return (os.getenv("EM_STORY_CKPT") or "/tmp/em_story_ckpt") .. "/" .. name .. ".lua"
end

function S.saveCheckpoint(game, name)
  local SaveData = mod("src.core.SaveData")
  local Schema = mod("src.core.game3.save_schema_firered")
  local Space = mod("src.core.game3.scripting.space")
  local s = S.session()
  local P = Player()
  s.x, s.y, s.facing = P.cellX, P.cellY, P.facing
  pcall(function() Space.persistSession(nil, game) end)
  local t = Schema.toSaveTable(s)
  local path = S.checkpointPath(name)
  os.execute('mkdir -p "' .. path:match("^(.*)/") .. '"')
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(SaveData.encode(t))
  f:close()
  return true
end

function S.loadCheckpoint(game, name)
  local SaveData = mod("src.core.SaveData")
  local Schema = mod("src.core.game3.save_schema_firered")
  local f = io.open(S.checkpointPath(name), "rb")
  if not f then return false end
  local raw = f:read("*a")
  f:close()
  local save = SaveData.decode(raw)
  local session = Schema.fromSaveTable(save)
  mod("src.core.game3.options").bind(session, game.options)
  game:adoptSave(session, true)
  game.sessionStartedAt = os.time()
  game:_enterField(session, "continue")
  U.wait(30)
  S.settle(game)
  return true
end

return S
