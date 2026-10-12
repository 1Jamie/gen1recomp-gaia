local Compat = require("src.online.xgen.Compat")
local Datasets = require("src.online.xgen.Datasets")
local Messages = require("src.online.xgen.Messages")
local Policy = require("src.online.xgen.Policy")
local Project = require("src.online.xgen.Project")
local Rentals = require("src.online.xgen.Rentals")
local TradeConvert = require("src.online.xgen.TradeConvert")
local Identity = require("src.online.xgen.Identity")
local Recommend = require("src.recommend.Recommend")

local Model = {}
Model.__index = Model

Model.STEPS = { "rules", "problems", "substitute", "moves", "size", "confirm", "waiting", "go", "closed" }

local copy = Project.copy

local TEXT = {
  title_rules = "Union Battle",
  title_problems = "Team Check",
  title_substitute = "Substitutes",
  title_moves = "Moves",
  title_size = "Team Size",
  title_confirm = "Final Check",
  title_waiting = "Ready",
  title_closed = "Union Battle",
  title_changes = "Battle Rules",
  title_rentals = "Rental Pokémon",
  title_mon = "Battle Data",

  vs = "{name} wants to battle.",
  vs_self = "Battle with {name}.",
  plays = "{name} is playing {game}.",
  rules_g3u = "Union rules: Pokémon No. 1 to {dexMax} with Gen {moveGen} moves and types.",
  rules_native = "Link battle with the rules of Gen {gen}.",
  waiting_rules = "Waiting for the rules…",
  temporary = "Nothing is saved. Your Pokémon, items and Exp. stay as they are.",

  blocked_mods = "Gameplay mods are on. Union battles need the original game data. Turn the mods off and try again.",
  blocked_data = "This game's data can't be read. Import it again from the launcher.",
  blocked_proto = "The other game has a different Union Room version. Both players need to update.",
  blocked_policy_mismatch = "The other game has a different Union Room version. Both players need to update.",
  blocked_fingerprint = "Your games' data don't match. Both players need the same game version with no gameplay mods.",
  blocked_missing_import = "A game needs to be imported first. Import it from the launcher.",
  blocked_other = "This battle can't be set up.",
  blocked_no_team = "You have no Pokémon that can battle.",

  problems_none = "Every Pokémon can battle.",
  problems_some = "Some Pokémon need changes.",
  egg_skipped = "Eggs stay out.",

  sub_intro = "Choose who takes its place.",
  sub_owned = "Your {name}, {place}.",
  sub_shares = "Shares a type with {want}.",
  sub_primary = "Same main type as {want}.",
  sub_other = "A different type.",
  sub_level = "Level {level}.",
  rental_tag = "RENTAL",
  rental_info = "A rental Pokémon. It is only for this battle.",
  rentals_loading = "Getting the rental Pokémon…",
  leave_out = "It stays out of this battle.",

  move_pick = "Choose a move for its place.",
  move_same_type = "Same type.",
  move_same_band = "Similar power.",
  move_empty = "The move slot is left empty.",
  move_needs_one = "It needs at least one move.",
  move_type = "Type {type}",
  move_row = "Power {power} PP {pp}",

  size_mine = "You bring {n}.",
  size_theirs = "{name} brings {n}.",
  size_wait = "Waiting for {name}…",
  size_agreed = "Each side uses {n}.",
  size_sit_out = "Choose {n} to sit out.",
  size_they_sit = "{name} chooses who sits out.",
  size_asked = "You asked for {n} each.",
  size_peer_asked = "{name} asks for {n} each.",
  size_pick = "Ask for another team size. Both players must agree.",
  size_out = "{name} sits out.",
  size_in = "{name} battles.",

  confirm_intro = "Your team for this battle.",
  confirm_note = "Check each Pokémon, then confirm.",
  waiting = "Waiting for {name} to confirm…",
  changed = "Something changed. Check your team and confirm again.",
  rules_changed = "The rules changed. Your team is checked again.",
  nack = "That didn't go through. Try again.",

  closed_cancel = "{name} cancelled the battle.",
  closed_self = "The battle was cancelled.",
  closed_timeout = "Nobody did anything for a while, so the battle was cancelled.",
  closed_gone = "The link to {name} was lost.",
  closed_other = "The battle was cancelled.",

  chg_engine = "Everyone battles with Gen 3 rules.",
  chg_types = "Types and moves are the Gen {moveGen} ones.",
  chg_items = "Held items are off.",
  chg_abilities = "Abilities are off.",
  chg_natures = "Natures are neutral.",
  chg_special = "Special counts as both Sp. Atk and Sp. Def.",
  chg_dv = "DVs become IVs: twice the DV, plus one.",
  chg_statexp = "Stat Exp. becomes EVs: its square root, up to 255 each and 510 in all.",
  chg_iv = "IVs and EVs stay as they are.",
  chg_full = "HP and PP are full and status is cleared.",
  chg_native = "The usual link battle rules of your games.",

  mon_stats = "HP {hp} Atk {atk}",
  mon_stats2 = "Def {def} SpA {spa}",
  mon_stats3 = "SpD {spd} Spe {spe}",
  mon_move = "{name} {pp}/{max}",
  mon_types = "Lv{level} {types}",
  mon_level = "{name} Lv{level}",
  mon_ivs = "IV {hp}/{atk}/{def}/{spa}/{spd}/{spe}",
  mon_evs = "EV {hp}/{atk}/{def}/{spa}/{spd}/{spe}",

  item_continue = "Continue",
  item_cancel = "Cancel",
  item_back = "Back",
  item_changes = "Rules",
  item_rentals = "Rentals",
  item_leave = "Leave out",
  item_empty = "Empty",
  item_done = "Done",
  item_size = "Team size",
  item_ready = "Confirm",
  item_ok = "OK",
  item_agree = "Agree to {n}",
  item_size_n = "{n} each",
}
Model.TEXT = TEXT

local function fill(template, args)
  args = args or {}
  return (template:gsub("{(%w+)}", function(key)
    local v = args[key]
    if v == nil then return "" end
    return tostring(v)
  end))
end

local function say(key, args)
  return fill(TEXT[key] or key, args)
end
Model.say = say

local function gameName(version)
  local GameVersion = require("src.core.GameVersion")
  local info = GameVersion.VERSIONS[version or ""]
  return "Pokémon " .. (info and info.label or tostring(version or "?"))
end

function Model.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Model)
  self.version = opts.version
  self.gen = tonumber(opts.gen) or (self.version and require("src.core.GameVersion").generation(self.version)) or 1
  self.data = opts.data
  if self.data == nil and self.version then self.data = Datasets.get(self.version) end
  self.prep = opts.prep
  self.opponent = copy(opts.opponent or {})
  self.opponent.name = self.opponent.name or "?"
  self.gameplayMods = opts.gameplayMods == true
  self.rulesOverride = opts.rules
  self.ownedSource = opts.owned
  self.recommendOpts = opts.recommend
  self.rentalRev = 0
  self.step = "rules"
  self.cursor = 1
  self.view = nil
  self.notice = nil
  self.done = false
  self.outcome = nil
  self.events = {}
  self.final = nil
  self.goInfo = nil
  self.sent = { roster = nil, sizeReq = nil, ready = nil }
  self:reset()
  return self
end

function Model:emit(kind, fields)
  local e = { kind = kind }
  for k, v in pairs(fields or {}) do e[k] = v end
  self.events[#self.events + 1] = e
end

function Model:rules()
  if self.prep and self.prep.rules then return self.prep.rules end
  return self.rulesOverride
end

local function rulesSig(r)
  if type(r) ~= "table" then return "" end
  return TradeConvert.canonical({ r.ruleset, r.gen, r.dexMax, r.moveMax, r.moveGen })
end

local function hasLegacy(r)
  for _, g in ipairs(r.gens or {}) do
    if tonumber(g) and tonumber(g) < 3 then return true end
  end
  return r.ruleset == "g3u"
end

function Model:target()
  local r = self:rules()
  if type(r) ~= "table" then return nil end
  if r.ruleset == "native" then
    return { ruleset = "native", gen = r.gen }
  end
  local moveGen = tonumber(r.moveGen) or 1
  return { ruleset = "g3u-gen" .. moveGen, gen = moveGen, dexMax = r.dexMax, moveMax = r.moveMax,
    legacyPresent = hasLegacy(r) }
end

function Model:isNative()
  local r = self:rules()
  return type(r) == "table" and r.ruleset == "native"
end

local function ownedFrom(source)
  local TeamPick = require("src.online.TeamPick")
  local out = {}
  for _, c in ipairs(TeamPick.candidates(source or {})) do
    out[#out + 1] = { rec = c.mon, ref = { where = c.where, box = c.box, index = c.index }, place = c.source }
  end
  return out
end
Model.ownedFrom = ownedFrom

function Model:reset()
  self.owned = self.ownedSource and (self.ownedSource.list or ownedFrom(self.ownedSource)) or {}
  self.team = {}
  self.eggs = 0
  local data = self.data
  for i, o in ipairs(self.owned) do
    if o.ref.where == "party" then
      local view = type(data) == "table" and Project.read(o.rec, data) or nil
      if view and view.isEgg then
        self.eggs = self.eggs + 1
      else
        self.team[#self.team + 1] = { base = i, moves = {} }
      end
    end
  end
  self.sizeChoice = nil
  self.final = nil
  self.sent = { roster = nil, sizeReq = nil, ready = nil }
  self.sig = rulesSig(self:rules())
  self.memo, self.memoCount, self.pageMemo = nil, nil, nil
  self:rebuildRules()
end

function Model:rebuildRules()
  self:cancelRentals()
  self.unsupported = {}
  self.rentalSet = { rentals = {}, excluded = {} }
  self.rentalRev = self.rentalRev + 1
  local target = self:target()
  if not target or target.ruleset == "native" or type(self.data) ~= "table" then return end
  if self.data.generation == target.gen and self.data.generation <= 2 then
    local Table = require("src.battle.g3u.Table")
    for _, row in ipairs(Table.unsupportedMoves(self.data)) do self.unsupported[#self.unsupported + 1] = row.id end
  end
  local ruleset = Policy.ruleset(target.ruleset)
  local names = Rentals.speciesNames(target.ruleset, self.data)
  if not ruleset or #names == 0 then return self:settleRentals(nil, "unknown_ruleset") end
  self.rentalJob = Recommend.request(ruleset.gen, names, self.recommendOpts)
  self.rentalSet.pending = true
  self:pollRentals()
end

function Model:settleRentals(sets, why)
  local target = self:target()
  self.rentalSet = Rentals.build(target.ruleset, self.data, { unsupported = self.unsupported,
    legacyPresent = target.legacyPresent, sets = sets })
  self.rentalSet.offline = why
  self.rentalRev = self.rentalRev + 1
  self.memo, self.memoCount, self.pageMemo = nil, nil, nil
end

function Model:pollRentals()
  local job = self.rentalJob
  if not job then return end
  local status, result = Recommend.poll(job)
  if status == "pending" then return end
  self.rentalJob = nil
  if status == "ok" then
    self:settleRentals(result, nil)
  else
    self:settleRentals(nil, result or "offline")
  end
end

function Model:cancelRentals()
  if self.rentalJob then Recommend.cancel(self.rentalJob) end
  self.rentalJob = nil
end

function Model:entries()
  local out = {}
  for _, e in ipairs(self.team) do
    if not e.left then out[#out + 1] = e end
  end
  return out
end

function Model:peerSize()
  local p = self.prep
  return p and p.peer and p.peer.roster and p.peer.roster.size or nil
end

function Model:agreedSize()
  return self.prep and self.prep.size or nil
end

function Model:args(withSize)
  local list = self:entries()
  local mons, replace, moves, used, sitOut = {}, {}, {}, {}, {}
  for i, e in ipairs(list) do
    mons[i] = self.owned[e.base].rec
    if e.swap then replace[i] = copy(e.swap) end
    moves[i] = copy(e.moves)
    used[#used + 1] = e.base
    if e.swap and e.swap.owned then used[#used + 1] = e.swap.owned end
    if withSize and e.sitOut then sitOut[#sitOut + 1] = i end
  end
  local adj = { replace = replace, moves = moves }
  local opp = nil
  if withSize then
    adj.sitOut = sitOut
    adj.size = self:agreedSize()
    opp = self:peerSize() or #mons
  end
  return {
    op = "battle", source = { game = self.version, gen = self.gen, data = self.data },
    target = self:target(), mons = mons, owned = self.owned, ownedInTeam = used,
    rentals = self.rentalSet.rentals, adjustments = adj, opponentSize = opp,
    unsupported = self.unsupported, versions = { policy = Policy.VERSION, proto = Policy.PROTO },
  }, list
end

function Model:prepKey()
  local p = self.prep
  if not p then return "" end
  return TradeConvert.canonical({ p.rev, p.size, p.peer.roster and p.peer.roster.size, p.mine.sizeReq,
    p.peer.sizeReq, p.mine.ready and true, p.peer.ready and true, p.state, p.blocked, rulesSig(p.rules),
    p.canReady and p:canReady() })
end

function Model:teamKey()
  local t = {}
  for i, e in ipairs(self.team) do
    t[i] = { e.base, e.swap and e.swap.owned, e.swap and e.swap.rental, e.left, e.sitOut, e.moves }
  end
  return TradeConvert.canonical(t)
end

function Model:report(withSize)
  local key = (withSize and "1" or "0") .. self.rentalRev .. self:teamKey() .. self:prepKey()
  self.memo = self.memo or {}
  local hit = self.memo[key]
  if hit then return hit.r, hit.list end
  local args, list = self:args(withSize)
  local r = Compat.report(args)
  if self.memoCount and self.memoCount > 32 then self.memo, self.memoCount = {}, 0 end
  self.memo[key] = { r = r, list = list }
  self.memoCount = (self.memoCount or 0) + 1
  return r, list
end

function Model:blockReason()
  if self.gameplayMods then return "blocked_mods" end
  if type(self.data) ~= "table" then return "blocked_data" end
  local p = self.prep
  if p and p.blocked then
    local key = "blocked_" .. tostring(p.blocked)
    return TEXT[key] and key or "blocked_other"
  end
  if #self.team == 0 then return "blocked_no_team" end
  return nil
end

function Model:names()
  local data = self.data
  return {
    species = function(n)
      local sp = type(data) == "table" and data.species[tonumber(n) or -1]
      return sp and sp.name or ("No. " .. tostring(n))
    end,
    move = function(id)
      local mv = type(data) == "table" and data.moves[tonumber(id) or -1]
      return mv and mv.name or ("No. " .. tostring(id))
    end,
  }
end

function Model:monName(rec)
  local view = type(self.data) == "table" and Project.read(rec, self.data) or nil
  if not view then return "?" end
  return view.nickname or view.speciesName or "?"
end

function Model:entryRec(e)
  if e.swap and e.swap.owned then return self.owned[e.swap.owned].rec end
  return self.owned[e.base].rec
end

function Model:entryRental(e)
  if e.swap and e.swap.rental then return self.rentalSet.rentals[e.swap.rental] end
  return nil
end

function Model:entryName(e)
  local rental = self:entryRental(e)
  if rental then return rental.name end
  return self:monName(self:entryRec(e))
end

function Model:speciesBlock(rec)
  local target = self:target()
  if not target or target.ruleset == "native" then return nil end
  local view, code, detail = Project.read(rec, self.data)
  if not view then return { code = code, detail = detail } end
  if view.isEgg then return { code = "egg" } end
  local ok, why, info = Compat.speciesEligible(view.national, Compat.resolveRuleset(target))
  if not ok then return { code = why, detail = info, view = view } end
  return nil
end

function Model:subQueue()
  local out = {}
  for _, e in ipairs(self.team) do
    if self:speciesBlock(self.owned[e.base].rec) then out[#out + 1] = e end
  end
  return out
end

function Model:moveQueue()
  local out = {}
  local target = self:target()
  if not target or target.ruleset == "native" then return out end
  local ruleset = Compat.resolveRuleset(target)
  local unsupported = Compat.asSet(self.unsupported)
  for _, e in ipairs(self:entries()) do
    if not self:entryRental(e) then
      local rec = self:entryRec(e)
      if not self:speciesBlock(rec) then
        local view = Project.read(rec, self.data)
        for j, m in ipairs(view.moves) do
          local status = Compat.moveStatus(self.data, view.national, view.level, m.move, ruleset, unsupported)
          if status then
            out[#out + 1] = { entry = e, index = j, move = m.move, code = status, view = view }
          end
        end
      end
    end
  end
  return out
end

function Model:problemLines()
  local lines = {}
  local names = self:names()
  for _, e in ipairs(self.team) do
    local rec = self.owned[e.base].rec
    local sb = self:speciesBlock(rec)
    if sb then
      local detail = copy(sb.detail or {})
      detail.national = detail.national or (sb.view and sb.view.national)
      lines[#lines + 1] = Messages.text(sb.code, detail, names)
    end
  end
  for _, q in ipairs(self:moveQueueForBase()) do
    lines[#lines + 1] = Messages.about(q.name, q.code, { move = q.move, national = q.view.national }, names)
  end
  return lines
end

function Model:moveQueueForBase()
  local out = {}
  local target = self:target()
  if not target or target.ruleset == "native" then return out end
  local ruleset = Compat.resolveRuleset(target)
  local unsupported = Compat.asSet(self.unsupported)
  for _, e in ipairs(self.team) do
    local rec = self.owned[e.base].rec
    if not self:speciesBlock(rec) then
      local view = Project.read(rec, self.data)
      for j, m in ipairs(view.moves) do
        local status = Compat.moveStatus(self.data, view.national, view.level, m.move, ruleset, unsupported)
        if status then
          out[#out + 1] = { entry = e, index = j, move = m.move, code = status, view = view,
            name = view.nickname or view.speciesName }
        end
      end
    end
  end
  return out
end

function Model:replacementOptions(e)
  local target = self:target()
  local ruleset = Compat.resolveRuleset(target)
  local base = self.owned[e.base].rec
  local view = Project.read(base, self.data) or { national = -1, level = 50 }
  local exclude = {}
  for _, other in ipairs(self.team) do
    exclude[other.base] = true
    if other ~= e and not other.left and other.swap and other.swap.owned then exclude[other.swap.owned] = true end
  end
  local owned = Compat.replacements(self.data, view, self.owned, ruleset, exclude, self.unsupported)
  local usedRental = {}
  for _, other in ipairs(self.team) do
    if other ~= e and not other.left and other.swap and other.swap.rental then usedRental[other.swap.rental] = true end
  end
  local rentals = {}
  for _, row in ipairs(Compat.rentalCandidates(self.data, view, self.rentalSet.rentals)) do
    if not usedRental[row.index] then rentals[#rentals + 1] = row end
  end
  return owned, rentals, view
end

function Model:moveOptions(q)
  local target = self:target()
  local ruleset = Compat.resolveRuleset(target)
  local exclude = {}
  for _, m in ipairs(q.view.moves) do exclude[m.move] = true end
  for j, v in pairs(q.entry.moves) do
    if j ~= q.index and tonumber(v) and v ~= 0 then exclude[v] = true end
  end
  return Compat.moveSuggestions(self.data, q.view.national, q.view.level, ruleset, q.move, exclude,
    Compat.asSet(self.unsupported))
end

function Model:canEmpty(q)
  local queue = self:moveQueue()
  local illegal = {}
  for _, other in ipairs(queue) do
    if other.entry == q.entry then illegal[other.index] = other end
  end
  local count = 0
  for j in ipairs(q.view.moves) do
    if not illegal[j] then
      count = count + 1
    elseif j ~= q.index then
      local v = q.entry.moves[j]
      if v == nil or (tonumber(v) and v ~= 0) then count = count + 1 end
    end
  end
  return count > 0
end

function Model:go(step, notice)
  self.step = step
  self.cursor = 1
  self.view = nil
  self.notice = notice
  self.subIndex = self.subIndex or 1
  self.moveIndex = self.moveIndex or 1
  self:emit("step", { step = step })
end

function Model:send(kind, ...)
  local p = self.prep
  if not p then return false end
  if kind == "roster" then return p:roster(...) end
  if kind == "sizeReq" then return p:sizeRequest(...) end
  if kind == "ready" then return p:ready(...) end
  return false
end

function Model:rosterRecords()
  local r = self:report(false)
  if not r.ok then return nil, r end
  return r.result.team, r
end

function Model:syncRoster()
  local team = self:rosterRecords()
  if not team then return false end
  local digest = TradeConvert.digest(team)
  local s = self.sent.roster
  if s and s.digest == digest and s.size == #team then return true end
  self.sent.roster = { digest = digest, size = #team }
  self:send("roster", #team, digest)
  return true
end

function Model:finalReport()
  return self:report(true)
end

function Model:needSitOut()
  local size = self:agreedSize()
  if not size then return 0 end
  local n = #self:entries() - size
  return n > 0 and n or 0
end

function Model:sitOutCount()
  local n = 0
  for _, e in ipairs(self:entries()) do
    if e.sitOut then n = n + 1 end
  end
  return n
end

function Model:sizeSettled()
  if not self:agreedSize() then return false end
  local r = self:finalReport()
  return r.ok
end

function Model:enterSubstitute(fromEnd)
  local q = self:subQueue()
  if #q == 0 then return self:enterMoves(fromEnd) end
  self.subIndex = fromEnd and #q or 1
  self:go("substitute")
end

function Model:enterMoves(fromEnd)
  local q = self:moveQueue()
  if #q == 0 then
    if fromEnd then return self:enterSubstituteBack() end
    return self:enterSize()
  end
  self.moveIndex = fromEnd and #q or 1
  self:go("moves")
end

function Model:enterSubstituteBack()
  local q = self:subQueue()
  if #q == 0 then return self:go("problems") end
  self.subIndex = #q
  self:go("substitute")
end

function Model:enterSize()
  local r = self:report(false)
  if not r.ok then
    self:go("problems", say("changed"))
    return
  end
  self:syncRoster()
  self:go("size")
end

function Model:enterConfirm(notice)
  local r = self:finalReport()
  if not r.ok then
    self:go("size", notice)
    return
  end
  self:go("confirm", notice)
end

function Model:discard()
  self:cancelRentals()
  self.team = {}
  self.owned = {}
  self.final = nil
  self.rentalSet = { rentals = {}, excluded = {} }
  self.view = nil
  self.memo, self.memoCount, self.pageMemo = nil, nil, nil
end

function Model:close(outcome, notice)
  if self.step == "closed" then return end
  self.outcome = outcome
  self:discard()
  self:go("closed", notice)
end

function Model:cancel(why)
  if self.step == "go" or self.step == "closed" then return end
  if self.prep then self.prep:cancel(why or "cancel") end
  self:close("cancel", say("closed_self"))
end

local CLOSED_TEXT = { cancel = "closed_cancel", timeout = "closed_timeout", gone = "closed_gone" }

function Model:handlePrepEvent(e)
  if e.kind == "rules" then
    local sig = rulesSig(self:rules())
    if sig ~= self.sig then
      local had = self.sig ~= ""
      self:reset()
      if had then self:go("rules", say("rules_changed")) end
    end
  elseif e.kind == "closed" then
    local mine = e.seat ~= nil and self.prep and e.seat == self.prep:seat()
    local key = mine and "closed_self" or CLOSED_TEXT[e.why or ""] or "closed_other"
    self:close("closed", say(key, { name = self.opponent.name }))
  elseif e.kind == "nack" then
    if e.of == "xg_roster" then self.sent.roster = nil end
    if e.of == "xg_size_req" then self.sent.sizeReq = nil end
    if e.of == "xg_ready" then
      self.sent.ready = nil
      if self.step == "waiting" then self:enterConfirm(say("nack")) end
    end
  elseif e.kind == "go" then
    if self.step == "waiting" and self.final then
      self.goInfo = copy(e.go)
      self:go("go")
      self.outcome = "go"
      self.done = true
    end
  end
end

function Model:poll()
  self:pollRentals()
  local p = self.prep
  if p then
    for _, e in ipairs(p:poll()) do self:handlePrepEvent(e) end
    if self.step ~= "closed" and self.step ~= "go" then
      if p.state == "closed" then
        self:close("closed", say(CLOSED_TEXT[p.closed and p.closed.why or ""] or "closed_other", { name = self.opponent.name }))
      elseif self.step == "waiting" and not p.mine.ready then
        self.sent.ready = nil
        self.final = nil
        self:enterConfirm(say("changed"))
      elseif self.step == "confirm" and not self:sizeSettled() then
        self:go("size", say("changed"))
      elseif (self.step == "size" or self.step == "confirm") and not self.sent.roster then
        self:syncRoster()
      end
    end
  end
  local out = self.events
  self.events = {}
  return out
end

function Model:style()
  return Messages.style(self.gen)
end

function Model:levelLabel(level)
  return "Lv" .. tostring(level)
end

function Model:changeLines()
  local lines = {}
  local r = self:rules() or {}
  if r.ruleset == "native" then
    lines[#lines + 1] = say("chg_native")
  else
    lines[#lines + 1] = say("chg_engine")
    lines[#lines + 1] = say("chg_types", { moveGen = r.moveGen })
    if hasLegacy(r) then
      lines[#lines + 1] = say("chg_items")
      lines[#lines + 1] = say("chg_abilities")
      lines[#lines + 1] = say("chg_natures")
    end
    if self.gen == 1 then lines[#lines + 1] = say("chg_special") end
    if self.gen <= 2 then
      lines[#lines + 1] = say("chg_dv")
      lines[#lines + 1] = say("chg_statexp")
    else
      lines[#lines + 1] = say("chg_iv")
    end
    lines[#lines + 1] = say("chg_full")
  end
  lines[#lines + 1] = say("temporary")
  return lines
end

function Model:rentalCoverage()
  local target = self:target()
  local out = {}
  if not target or target.ruleset == "native" then return out end
  local types = target.gen == 1 and Identity.GEN1_TYPES or Identity.TYPES
  local byType = {}
  for _, rental in ipairs(self.rentalSet.rentals) do byType[rental.type] = byType[rental.type] or rental end
  for _, t in ipairs(types) do
    out[#out + 1] = { type = t, rental = byType[t] }
  end
  return out
end

function Model:rentalLines(rental)
  local lines = {}
  lines[#lines + 1] = TEXT.rental_tag .. " " .. rental.name
  lines[#lines + 1] = say("mon_types", { level = rental.level, types = table.concat(rental.types, "/") })
  local s = rental.stats
  lines[#lines + 1] = say("mon_stats", { hp = s.hp, atk = s.atk })
  lines[#lines + 1] = say("mon_stats2", { def = s.def, spa = s.spAtk })
  lines[#lines + 1] = say("mon_stats3", { spd = s.spDef, spe = s.speed })
  for _, mv in ipairs(rental.moves) do
    lines[#lines + 1] = say("mon_move", { name = mv.name, pp = mv.pp, max = mv.maxPp })
  end
  lines[#lines + 1] = say("rental_info")
  return lines
end

function Model:displayRec(rec)
  if type(rec) ~= "table" or rec.national ~= nil or type(self.data) ~= "table" then return rec end
  local view = Project.read(rec, self.data)
  if not view then return rec end
  local moves = {}
  for i, m in ipairs(view.moves) do moves[i] = { id = m.move, pp = m.pp } end
  local st = type(rec.stats) == "table" and rec.stats or {}
  return {
    national = view.national, level = view.level, nickname = view.nickname, moves = moves,
    maxHp = rec.maxHp or rec.maxHP or st.hp, atk = rec.atk or rec.attack or st.attack,
    def = rec.def or rec.defense or st.defense, spAtk = rec.spAtk or rec.special or st.spAtk or st.special,
    spDef = rec.spDef or rec.special or st.spDef or st.special, speed = rec.speed or st.speed,
  }
end

function Model:recordLines(rec, changes, short)
  rec = self:displayRec(rec)
  local lines = {}
  local names = self:names()
  local tag = rec.rental and (TEXT.rental_tag .. " ") or ""
  lines[#lines + 1] = tag .. say("mon_level", { name = rec.nickname or names.species(rec.national), level = rec.level })
  lines[#lines + 1] = say("mon_stats", { hp = rec.maxHp, atk = rec.atk })
  lines[#lines + 1] = say("mon_stats2", { def = rec.def, spa = rec.spAtk })
  lines[#lines + 1] = say("mon_stats3", { spd = rec.spDef, spe = rec.speed })
  for _, m in ipairs(rec.moves or {}) do
    lines[#lines + 1] = say("mon_move", { name = names.move(m.id), pp = m.pp, max = m.pp })
  end
  if short then return lines end
  if rec.rental then lines[#lines + 1] = say("rental_info") end
  if type(rec.ivs) == "table" then lines[#lines + 1] = say("mon_ivs", rec.ivs) end
  if type(rec.evs) == "table" then lines[#lines + 1] = say("mon_evs", rec.evs) end
  for _, c in ipairs(changes or {}) do
    if c.field ~= "species" and c.field ~= "moves" then
      lines[#lines + 1] = Messages.change(c, 3)[1]
    end
  end
  return lines
end

local function item(id, label, detail, extra)
  local out = { id = id, label = label, detail = detail }
  for k, v in pairs(extra or {}) do out[k] = v end
  return out
end

function Model:pageRules()
  local lines = {}
  local r = self:rules()
  lines[#lines + 1] = say("vs", { name = self.opponent.name })
  if self.opponent.version then
    lines[#lines + 1] = say("plays", { name = self.opponent.name, game = gameName(self.opponent.version) })
  end
  local why = self:blockReason()
  local items = {}
  if why then
    lines[#lines + 1] = say(why)
    items[#items + 1] = item("cancel", TEXT.item_cancel)
    return { title = TEXT.title_rules, lines = lines, items = items }
  end
  if not r then
    lines[#lines + 1] = say("waiting_rules")
    items[#items + 1] = item("cancel", TEXT.item_cancel)
    return { title = TEXT.title_rules, lines = lines, items = items }
  end
  if r.ruleset == "native" then
    lines[#lines + 1] = say("rules_native", { gen = r.gen })
  else
    lines[#lines + 1] = say("rules_g3u", { dexMax = r.dexMax, moveMax = r.moveMax, moveGen = r.moveGen })
  end
  items[#items + 1] = item("continue", TEXT.item_continue)
  items[#items + 1] = item("changes", TEXT.item_changes)
  if r.ruleset ~= "native" then items[#items + 1] = item("rentals", TEXT.item_rentals) end
  items[#items + 1] = item("cancel", TEXT.item_cancel)
  return { title = TEXT.title_rules, lines = lines, items = items }
end

function Model:pageProblems()
  local lines = self:problemLines()
  if #lines == 0 then
    lines[1] = say("problems_none")
  else
    table.insert(lines, 1, say("problems_some"))
  end
  if self.eggs > 0 then lines[#lines + 1] = say("egg_skipped") end
  return { title = TEXT.title_problems, lines = lines, items = {
    item("continue", TEXT.item_continue), item("back", TEXT.item_back), item("cancel", TEXT.item_cancel) } }
end

function Model:pageSubstitute()
  local q = self:subQueue()
  local e = q[self.subIndex]
  if not e then return self:pageProblems() end
  local base = self.owned[e.base].rec
  local wantName = self:monName(base)
  local names = self:names()
  local sb = self:speciesBlock(base) or {}
  local detail = copy(sb.detail or {})
  detail.national = detail.national or (sb.view and sb.view.national)
  local lines = { Messages.text(sb.code or "bad_record", detail, names), say("sub_intro", { name = wantName }) }
  if self.rentalSet.pending then lines[#lines + 1] = say("rentals_loading") end
  local owned, rentals = self:replacementOptions(e)
  local items = {}
  for _, row in ipairs(owned) do
    local o = self.owned[row.index]
    local why = row.sharesType and say("sub_shares", { want = wantName })
      or row.samePrimary and say("sub_primary", { want = wantName }) or say("sub_other")
    items[#items + 1] = item("swap_owned", row.name .. " " .. self:levelLabel(row.level),
      { say("sub_owned", { name = row.name, place = o.place }), say("sub_level", { level = row.level }), why },
      { arg = row.index, chosen = e.swap and e.swap.owned == row.index })
  end
  for _, row in ipairs(rentals) do
    local rental = self.rentalSet.rentals[row.index]
    local lines2 = self:rentalLines(rental)
    if row.sharesType then table.insert(lines2, 2, say("sub_shares", { want = wantName })) end
    items[#items + 1] = item("swap_rental", TEXT.rental_tag .. " " .. rental.name, lines2,
      { arg = row.index, chosen = e.swap and e.swap.rental == row.index })
  end
  if #self:entries() > 1 or e.left then
    items[#items + 1] = item("leave", TEXT.item_leave, { say("leave_out") }, { chosen = e.left == true })
  end
  items[#items + 1] = item("back", TEXT.item_back)
  return { title = TEXT.title_substitute, lines = lines, items = items,
    progress = { self.subIndex, #q } }
end

function Model:pageMoves()
  local q = self:moveQueue()
  local cur = q[self.moveIndex]
  if not cur then return self:pageProblems() end
  local names = self:names()
  local name = self:entryName(cur.entry)
  local lines = {
    Messages.about(name, cur.code, { move = cur.move, national = cur.view.national }, names),
    say("move_pick"),
  }
  local items = {}
  local chosen = cur.entry.moves[cur.index]
  for _, row in ipairs(self:moveOptions(cur)) do
    local mv = self.data.moves[row.move]
    local d = { say("move_type", { type = mv.type or "?" }), say("move_row", { power = mv.power, pp = Policy.maxPp(mv.pp, 0) }) }
    if row.sameType then d[#d + 1] = say("move_same_type") end
    if row.sameBand then d[#d + 1] = say("move_same_band") end
    items[#items + 1] = item("move", row.name, d, { arg = row.move, chosen = chosen == row.move })
  end
  items[#items + 1] = item("empty", TEXT.item_empty, { say(self:canEmpty(cur) and "move_empty" or "move_needs_one") },
    { disabled = not self:canEmpty(cur), why = say("move_needs_one"), chosen = chosen == 0 })
  items[#items + 1] = item("back", TEXT.item_back)
  return { title = TEXT.title_moves, lines = lines, items = items, progress = { self.moveIndex, #q } }
end

function Model:pageSize()
  local lines = {}
  local list = self:entries()
  lines[#lines + 1] = say("size_mine", { n = #list })
  local peer = self:peerSize()
  local size = self:agreedSize()
  local items = {}
  if not peer or not size then
    lines[#lines + 1] = say("size_wait", { name = self.opponent.name })
  else
    lines[#lines + 1] = say("size_theirs", { name = self.opponent.name, n = peer })
    lines[#lines + 1] = say("size_agreed", { n = size })
  end
  local p = self.prep
  if p and p.mine.sizeReq then lines[#lines + 1] = say("size_asked", { n = p.mine.sizeReq }) end
  local peerReq = p and p.peer.sizeReq
  if peerReq then lines[#lines + 1] = say("size_peer_asked", { name = self.opponent.name, n = peerReq }) end
  local need = self:needSitOut()
  if size and need > 0 then
    lines[#lines + 1] = say("size_sit_out", { n = need })
    for i, e in ipairs(list) do
      local tag = self:entryRental(e) and (TEXT.rental_tag .. " ") or ""
      items[#items + 1] = item("toggle", (e.sitOut and "- " or "") .. tag .. self:entryName(e),
        { say(e.sitOut and "size_out" or "size_in", { name = self:entryName(e) }) }, { arg = i, chosen = e.sitOut == true })
    end
  elseif size and peer and peer > size then
    lines[#lines + 1] = say("size_they_sit", { name = self.opponent.name })
  end
  if size then
    local settled = self:sizeSettled()
    items[#items + 1] = item("continue", need > 0 and TEXT.item_done or TEXT.item_continue, nil,
      { disabled = not settled, why = need > 0 and say("size_sit_out", { n = need }) or nil })
    if peerReq and peerReq ~= size and peerReq <= #list and p.mine.sizeReq ~= peerReq then
      items[#items + 1] = item("agree", say("item_agree", { n = peerReq }), nil, { arg = peerReq })
    end
    if math.min(#list, peer or #list) > 1 then items[#items + 1] = item("size", TEXT.item_size) end
  end
  items[#items + 1] = item("back", TEXT.item_back)
  items[#items + 1] = item("cancel", TEXT.item_cancel)
  return { title = TEXT.title_size, lines = lines, items = items }
end

function Model:pageSizePick()
  local list = self:entries()
  local max = math.min(#list, self:peerSize() or #list)
  local items = {}
  for n = 1, max do items[#items + 1] = item("size_n", say("item_size_n", { n = n }), nil, { arg = n }) end
  items[#items + 1] = item("back", TEXT.item_back)
  return { title = TEXT.title_size, lines = { say("size_pick") }, items = items }
end

function Model:pageConfirm()
  local r = self:finalReport()
  local lines = { say("confirm_intro"), say("confirm_note") }
  local items = {}
  local team = r.ok and r.result.team or {}
  local slots = r.ok and r.result.slots or {}
  local changesBy = {}
  for _, c in ipairs(r.changes or {}) do
    changesBy[c.slot] = changesBy[c.slot] or {}
    table.insert(changesBy[c.slot], c)
  end
  local names = self:names()
  for i, raw in ipairs(team) do
    local rec = self:displayRec(raw)
    local label = (rec.rental and (TEXT.rental_tag .. " ") or "") .. (rec.nickname or names.species(rec.national))
    items[#items + 1] = item("mon", label, self:recordLines(rec, changesBy[slots[i]], true),
      { arg = i, full = self:recordLines(rec, changesBy[slots[i]]) })
  end
  local canReady = r.ok and (not self.prep or self.prep:canReady())
  items[#items + 1] = item("ready", TEXT.item_ready, nil, { disabled = not canReady })
  items[#items + 1] = item("changes", TEXT.item_changes)
  items[#items + 1] = item("back", TEXT.item_back)
  items[#items + 1] = item("cancel", TEXT.item_cancel)
  return { title = TEXT.title_confirm, lines = lines, items = items, keepBody = false }
end

function Model:pageWaiting()
  return { title = TEXT.title_waiting, lines = { say("waiting", { name = self.opponent.name }) },
    items = { item("unready", TEXT.item_back), item("cancel", TEXT.item_cancel) } }
end

function Model:pageClosed()
  return { title = TEXT.title_closed, lines = {}, items = { item("ok", TEXT.item_ok) } }
end

function Model:pageView()
  local v = self.view
  if v.kind == "changes" then
    return { title = TEXT.title_changes, lines = self:changeLines(), items = {}, pager = true }
  elseif v.kind == "rentals" then
    local items = {}
    for _, row in ipairs(self:rentalCoverage()) do
      if row.rental then
        items[#items + 1] = item("info", row.type .. " " .. row.rental.name, self:rentalLines(row.rental))
      end
    end
    items[#items + 1] = item("back", TEXT.item_back)
    return { title = TEXT.title_rentals, lines = self.rentalSet.pending and { say("rentals_loading") } or {}, items = items }
  elseif v.kind == "mon" then
    return { title = TEXT.title_mon, lines = v.lines, items = {}, pager = true }
  elseif v.kind == "size" then
    return self:pageSizePick()
  end
  return { title = "", lines = {}, items = {} }
end

local PAGES = {
  rules = "pageRules", problems = "pageProblems", substitute = "pageSubstitute", moves = "pageMoves",
  size = "pageSize", confirm = "pageConfirm", waiting = "pageWaiting", closed = "pageClosed",
}

function Model:rawPage()
  if self.view then return self:pageView() end
  local fn = PAGES[self.step]
  if not fn then return { title = "", lines = {}, items = {} } end
  return self[fn](self)
end

function Model:page()
  local v = self.view
  local key = TradeConvert.canonical({ self.step, v and v.kind, v and v.lines and #v.lines, self.subIndex,
    self.moveIndex, self.outcome, self.rentalRev }) .. self:teamKey() .. self:prepKey()
  local raw = self.pageMemo and self.pageMemo.key == key and self.pageMemo.page
  if not raw then
    raw = self:rawPage()
    self.pageMemo = { key = key, page = raw }
  end
  local pg = {}
  for k, x in pairs(raw) do pg[k] = x end
  pg.lines = {}
  if self.notice and not self.view then
    pg.lines[1] = self.notice
    pg.notice = true
  end
  for _, line in ipairs(raw.lines or {}) do pg.lines[#pg.lines + 1] = line end
  pg.step = self.view and self.view.kind or self.step
  if #pg.items > 0 then
    if self.cursor > #pg.items then self.cursor = #pg.items end
    if self.cursor < 1 then self.cursor = 1 end
  end
  pg.cursor = self.cursor
  pg.scroll = self.view and self.view.scroll or 0
  local sel = pg.items[self.cursor]
  pg.info = sel and sel.detail or nil
  return pg
end

function Model:openView(kind, extra)
  self.view = { kind = kind, scroll = 0, parentCursor = self.cursor }
  for k, v in pairs(extra or {}) do self.view[k] = v end
  self.cursor = 1
end

function Model:closeView()
  local v = self.view
  self.view = nil
  self.cursor = v and v.parentCursor or 1
end

function Model:choose(it)
  if not it then return end
  if it.disabled then
    if it.why then self.notice = it.why end
    return
  end
  local id = it.id
  if id == "cancel" then return self:cancel("cancel") end
  if self.view then
    if id == "back" then return self:closeView() end
    if self.view.kind == "size" and id == "size_n" then
      self:closeView()
      self.sent.sizeReq = it.arg
      self:send("sizeReq", it.arg)
    end
    return
  end
  local step = self.step
  if step == "closed" then
    self.done = true
    return
  end
  if id == "changes" then return self:openView("changes") end
  if id == "rentals" then return self:openView("rentals") end
  if step == "rules" then
    if id == "continue" then self:go("problems") end
  elseif step == "problems" then
    if id == "continue" then self:enterSubstitute() elseif id == "back" then self:go("rules") end
  elseif step == "substitute" then
    local q = self:subQueue()
    local e = q[self.subIndex]
    if id == "back" then
      if self.subIndex > 1 then
        self.subIndex = self.subIndex - 1
        self.cursor = 1
      else
        self:go("problems")
      end
      return
    end
    if not e then return end
    if id == "swap_owned" then
      e.swap, e.left, e.moves = { owned = it.arg }, nil, {}
    elseif id == "swap_rental" then
      e.swap, e.left, e.moves = { rental = it.arg }, nil, {}
    elseif id == "leave" then
      e.swap, e.left, e.moves = nil, true, {}
    end
    self:clearSent()
    if self.subIndex < #q then
      self.subIndex = self.subIndex + 1
      self.cursor = 1
    else
      self:enterMoves()
    end
  elseif step == "moves" then
    local q = self:moveQueue()
    local cur = q[self.moveIndex]
    if id == "back" then
      if self.moveIndex > 1 then
        self.moveIndex = self.moveIndex - 1
        self.cursor = 1
      else
        self:enterSubstituteBack()
      end
      return
    end
    if not cur then return end
    if id == "move" then
      cur.entry.moves[cur.index] = it.arg
    elseif id == "empty" then
      if not self:canEmpty(cur) then
        self.notice = say("move_needs_one")
        return
      end
      cur.entry.moves[cur.index] = 0
    end
    self:clearSent()
    if self.moveIndex < #q then
      self.moveIndex = self.moveIndex + 1
      self.cursor = 1
    else
      self:enterSize()
    end
  elseif step == "size" then
    if id == "toggle" then
      local e = self:entries()[it.arg]
      if e then e.sitOut = not e.sitOut or nil end
    elseif id == "continue" then
      self:enterConfirm()
    elseif id == "size" then
      self:openView("size")
    elseif id == "agree" then
      self.sent.sizeReq = it.arg
      self:send("sizeReq", it.arg)
    elseif id == "back" then
      self:enterMoves(true)
    end
  elseif step == "confirm" then
    if id == "mon" then
      return self:openView("mon", { lines = it.full or it.detail })
    elseif id == "ready" then
      return self:ready()
    elseif id == "back" then
      self:go("size")
    end
  elseif step == "waiting" then
    if id == "unready" then
      self.final = nil
      self.sent.ready = nil
      self.sent.roster = nil
      self:syncRoster()
      self:go("confirm")
    end
  end
end

function Model:clearSent()
  self.sent.roster = nil
  self.final = nil
end

function Model:partyIndices(slots, list)
  local out = {}
  for _, slot in ipairs(slots or {}) do
    local e = list and list[slot]
    local o = e and self.owned[(e.swap and e.swap.owned) or e.base]
    if o and o.ref and o.ref.where == "party" then out[#out + 1] = o.ref.index end
  end
  return out
end

function Model:ready()
  local r, list = self:finalReport()
  if not r.ok then return false end
  if self.prep and not self.prep:canReady() then return false end
  self.final = { records = copy(r.result.team), size = r.result.size, slots = copy(r.result.slots),
    team = self:partyIndices(r.result.slots, list), digest = TradeConvert.digest(r.result.team) }
  self.sent.ready = self.final.digest
  self:send("ready", self.final.digest)
  self:go("waiting")
  return true
end

function Model:input(key)
  if self.done then return end
  local pg = self:page()
  local n = #pg.items
  if pg.pager then
    if key == "up" then
      self.view.scroll = math.max(0, (self.view.scroll or 0) - 1)
    elseif key == "down" then
      self.view.scroll = math.min(math.max(0, #pg.lines - 1), (self.view.scroll or 0) + 1)
    elseif key == "a" or key == "b" then
      self:closeView()
    end
    return
  end
  if key == "up" and n > 0 then
    self.cursor = self.cursor > 1 and self.cursor - 1 or n
  elseif key == "down" and n > 0 then
    self.cursor = self.cursor < n and self.cursor + 1 or 1
  elseif key == "a" then
    self.notice = nil
    self:choose(pg.items[self.cursor])
  elseif key == "b" then
    self.notice = nil
    if self.view then return self:closeView() end
    if self.step == "closed" then self.done = true return end
    for _, it in ipairs(pg.items) do
      if it.id == "back" or it.id == "unready" then return self:choose(it) end
    end
    for _, it in ipairs(pg.items) do
      if it.id == "cancel" then return self:choose(it) end
    end
  end
end

function Model:result()
  if self.outcome ~= "go" or not self.final then return nil end
  local r = self:rules() or {}
  local go = self.goInfo or {}
  return {
    records = copy(self.final.records),
    size = self.final.size,
    digest = self.final.digest,
    ruleset = { id = r.ruleset, rulesetId = (self:target() or {}).ruleset, gen = r.gen, dexMax = r.dexMax,
      moveMax = r.moveMax, moveGen = r.moveGen, gens = copy(r.gens) },
    seed = go.seed, match = go.match, rev = go.rev, go = copy(go), team = copy(self.final.team or {}),
    version = self.version, gen = self.gen,
  }
end

function Model:formatGroups(lines)
  local out = {}
  for _, line in ipairs(lines or {}) do out[#out + 1] = Messages.format(line, self.gen) end
  return out
end

function Model.fitGroups(body, info, room, opts)
  opts = opts or {}
  local used, showBody, showInfo = 0, {}, {}
  local function take(list, into, from)
    for i = from or 1, #list do
      local g = list[i]
      if used + #g > room then break end
      into[#into + 1] = g
      used = used + #g
    end
  end
  local first = 1
  if opts.notice and body[1] then
    showBody[1] = body[1]
    used = #body[1]
    first = 2
  end
  if opts.keepBody == false then
    take(info, showInfo)
    take(body, showBody, first)
  else
    take(body, showBody, first)
    take(info, showInfo)
  end
  local lines = {}
  for _, g in ipairs(showBody) do for _, l in ipairs(g) do lines[#lines + 1] = l end end
  for _, g in ipairs(showInfo) do for _, l in ipairs(g) do lines[#lines + 1] = l end end
  if #lines == 0 then
    local g = body[1] or info[1] or {}
    for i = 1, math.min(#g, room) do lines[#lines + 1] = g[i] end
  end
  while #lines > room do table.remove(lines) end
  return lines
end

function Model:formatLines(lines)
  local out = {}
  for _, line in ipairs(lines or {}) do
    for _, l in ipairs(Messages.format(line, self.gen)) do out[#out + 1] = l end
  end
  return out
end

function Model:label(text)
  if self:style() == "gb" then return (text or ""):upper() end
  return text or ""
end

return Model
