package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local P = require("tests.engine._union_prep_pair")
local Model = require("src.online.union.BattlePrepModel")
local Rentals = require("src.online.xgen.Rentals")

local emerald = F.data("emerald")
local red = F.data("red")

local savedDefs = Rentals.DEFINITIONS["g3u-gen1"]
Rentals.DEFINITIONS["g3u-gen1"] = {
  { type = "GRASS", species = 1, moves = { 33, 45 } },
  { type = "ELECTRIC", species = 25, moves = { 84, 45 } },
  { type = "PSYCHIC", species = 150, moves = { 94 } },
}

local function mon3(national, level, moves, extra)
  local m = { species = emerald.nationalToLocal[national], level = level, personality = 7, otId = 1, otSecretId = 0,
    otName = "MAY", ivs = { hp = 1, atk = 1, def = 1, spe = 1, spa = 1, spd = 1 }, evs = {}, moves = moves }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

local function source()
  return {
    generation = 3,
    party = { mon3(252, 20, { 33, 345 }), mon3(25, 20, { 84, 45, 98, 57 }, { ppBonuses = 2 }), mon3(1, 10, { 33 }) },
    boxes = { { mon3(197, 30, { 33 }), mon3(25, 18, { 84 }), mon3(152, 25, { 33 }), mon3(1, 22, { 33 }),
      mon3(2, 21, { 33 }), mon3(150, 60, { 94 }) } },
  }
end

local function labels(pg)
  local out = {}
  for _, it in ipairs(pg.items) do out[#out + 1] = it.label end
  return out
end

local function find(pg, id, label)
  for i, it in ipairs(pg.items) do
    if it.id == id and (label == nil or it.label:find(label, 1, true)) then return i, it end
  end
  return nil
end

local function pick(m, id, label)
  local pg = m:page()
  local i = find(pg, id, label)
  assert(i, "no item " .. id .. " " .. tostring(label) .. " on " .. tostring(pg.step) .. ": " .. table.concat(labels(pg), ","))
  m.cursor = i
  m:input("a")
end

local function joined(lines)
  return table.concat(lines or {}, " | ")
end

local function pumpBoth(w, ma, pb)
  for _ = 1, 3 do
    w:pump()
    ma:poll()
    if pb then pb:poll() end
  end
end

do
  local w, pa, pb = P.pair("emerald", "red")
  local src = source()
  local before = F.copy(src)
  local m = Model.new({ version = "emerald", gen = 3, data = emerald, prep = pa, owned = src,
    opponent = { name = "BOB", version = "red", gen = 1 } })
  pumpBoth(w, m, pb)
  T.eq(m.step, "rules", "the prep opens on the opponent and rules")
  local pg = m:page()
  T.check(joined(pg.lines):find("BOB wants to battle", 1, true) ~= nil, "the rules page names the opponent")
  T.check(joined(pg.lines):find("Pokémon Red", 1, true) ~= nil, "the rules page names the opponent's game")
  T.check(joined(pg.lines):find("No. 1 to 151", 1, true) ~= nil, "the rules page shows the dex limit")
  T.check(find(pg, "changes") ~= nil and find(pg, "rentals") ~= nil, "rules and rentals can be opened")

  pick(m, "changes")
  local chg = joined(m:page().lines)
  T.check(chg:find("Held items are off", 1, true) and chg:find("Abilities are off", 1, true)
    and chg:find("Natures are neutral", 1, true) and chg:find("Gen 1 ones", 1, true)
    and chg:find("IVs and EVs stay", 1, true), "the rules view lists items, abilities, natures, typing and IV policy")
  m:input("b")
  T.eq(m.view, nil, "B closes the rules view")

  pick(m, "rentals")
  local rp = m:page()
  T.eq(#rp.items, 4, "three valid rentals plus back")
  T.check(rp.items[1].label:find("GRASS BULBASAUR", 1, true) ~= nil, "rentals are listed by type")
  local rinfo = joined(rp.info)
  T.check(rinfo:find("RENTAL", 1, true) and rinfo:find("Lv50", 1, true) and rinfo:find("HP ", 1, true)
    and rinfo:find("TACKLE 35/35", 1, true), "a rental discloses its tag, level, stats and moves")
  m:input("b")

  pick(m, "continue")
  T.eq(m.step, "problems", "continue moves to team compatibility")
  local probs = joined(m:page().lines)
  T.check(probs:find("TREECKO can't join this battle. Only No. 1 to 151 can.", 1, true) ~= nil, "Treecko's block is explained")
  T.check(probs:find("PIKACHU can't learn SURF", 1, true) ~= nil, "Pikachu's Surf is explained as not learnable")

  pick(m, "continue")
  T.eq(m.step, "substitute", "the substitution step follows")
  local sp = m:page()
  T.check(sp.items[1].label:find("IVYSAUR", 1, true) and sp.items[2].label:find("BULBASAUR", 1, true),
    "owned grass types rank first, closest level first (" .. joined(labels(sp)) .. ")")
  local again = m:page()
  T.eq(joined(labels(again)), joined(labels(sp)), "the ranking is stable across rebuilds")
  T.check(joined(sp.items[1].info or sp.items[1].detail):find("Shares a type", 1, true) ~= nil, "the ranking reason is shown")
  local sawChikorita = false
  for _, it in ipairs(sp.items) do if it.label:find("CHIKORITA", 1, true) then sawChikorita = true end end
  T.check(not sawChikorita, "species outside the dex are never offered")
  T.check(find(sp, "swap_rental", "RENTAL BULBASAUR") ~= nil, "rentals are offered next to owned Pokemon")
  T.check(find(sp, "leave") ~= nil, "a slot can be left out")
  pick(m, "swap_rental", "RENTAL BULBASAUR")

  T.eq(m.step, "moves", "move adjustments follow substitutions")
  local mp = m:page()
  T.check(joined(mp.lines):find("PIKACHU can't learn SURF", 1, true) ~= nil, "the move problem is explained by itself")
  T.check(joined(mp.lines):find("PIKACHU: PIKACHU", 1, true) == nil, "the name is not repeated")
  T.eq(mp.items[1].label, "THUNDERBOLT", "a similar legal move is suggested first")
  for _, it in ipairs(mp.items) do
    T.check(it.arg ~= 84 and it.arg ~= 45 and it.arg ~= 98, "a move the mon already knows is not suggested: " .. it.label)
  end
  local _, empty = find(mp, "empty")
  T.check(empty and not empty.disabled, "an empty slot is allowed when other legal moves remain")
  pick(m, "move", "THUNDERBOLT")

  T.eq(m.step, "size", "team size follows moves")
  pumpBoth(w, m, pb)
  T.eq(pa.mine.roster and pa.mine.roster.size, 3, "the roster size reaches the relay")
  pb:roster(2, "00000000000000b2")
  pumpBoth(w, m, pb)
  T.eq(pa.size, 2, "the relay agrees the smaller size")
  local zp = m:page()
  local _, cont = find(zp, "continue")
  T.check(cont and cont.disabled, "the larger roster must choose who sits out before continuing")
  T.check(joined(zp.lines):find("Choose 1 to sit out", 1, true) ~= nil, "the sit-out count is shown")
  T.check(joined(zp.lines):find("BOB brings 2", 1, true) ~= nil, "the opponent's size is shown")
  m.cursor = find(zp, "continue")
  m:input("a")
  T.eq(m.step, "size", "a disabled continue does nothing")
  local toggles = 0
  for _, it in ipairs(zp.items) do if it.id == "toggle" then toggles = toggles + 1 end end
  T.eq(toggles, 3, "every battler can be chosen to sit out")
  pick(m, "toggle", "PIKACHU")
  pick(m, "continue")
  T.eq(m.step, "confirm", "final confirmation follows the size")
  local cp = m:page()
  T.eq(#cp.items, 6, "two battlers, confirm, rules, back, cancel")
  T.check(cp.items[1].label:find("RENTAL BULBASAUR", 1, true) ~= nil, "a rental is clearly marked")
  local ready = select(2, find(cp, "ready"))
  T.check(ready and not ready.disabled, "confirm is available")
  pick(m, "ready")
  T.eq(m.step, "waiting", "confirm waits for the opponent")
  T.check(pa.mine.ready ~= nil, "ready is sent to the relay")
  pumpBoth(w, m, pb)

  pb:roster(2, "00000000000000c3")
  pumpBoth(w, m, pb)
  T.eq(m.step, "confirm", "a later roster change sends the player back to confirm")
  T.check(joined(m:page().lines):find("Something changed", 1, true) ~= nil, "the invalidation is explained")
  T.eq(pa.mine.ready, nil, "readiness is cleared")
  pick(m, "ready")
  pumpBoth(w, m, pb)
  pb:ready("00000000000000c3")
  pumpBoth(w, m, pb)
  T.check(m.done and m.outcome == "go", "both confirmations start the battle")
  local res = m:result()
  T.eq(res and #res.records, 2, "the result carries the chosen team")
  T.eq(res.size, 2, "the result carries the size")
  T.eq(res.ruleset.id, "g3u", "the result carries the ruleset")
  T.eq(res.ruleset.rulesetId, "g3u-gen1", "the result names the policy ruleset")
  T.eq(res.seed, pa.go.seed, "the result carries the relay seed")
  T.check(res.records[1].rental == true and res.records[1].species == 1, "the rental stays flagged in the result")
  T.eq(res.records[2].species, 1, "Bulbasaur fills the second place in party order")
  T.check(F.deepEqual(src, before), "the active save's party and PC are untouched")
  local nick = false
  local function walk(t, seen)
    if type(t) ~= "table" or seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
      if k ~= "prep" and k ~= "data" then
        if v == "ZAPZAP" then nick = true end
        walk(v, seen)
      end
    end
  end
  walk(m, {})
  T.check(not nick, "no opponent record is ever in the model")
  for k in pairs(pa.peer) do
    T.check(k == "roster" or k == "sizeReq" or k == "ready" or k == "caps" or k == "capsSent" or k == "counter",
      "the peer view holds sizes and flags only: " .. tostring(k))
  end
end

do
  local w, pa, pb = P.pair("emerald", "red")
  local src = source()
  local m = Model.new({ version = "emerald", gen = 3, data = emerald, prep = pa, owned = src,
    opponent = { name = "BOB", version = "red", gen = 1 } })
  pumpBoth(w, m, pb)
  pick(m, "continue")
  pick(m, "continue")
  pick(m, "swap_owned", "IVYSAUR")
  pick(m, "empty")
  T.eq(m.step, "size", "an emptied slot with other legal moves passes")
  pumpBoth(w, m, pb)
  pb:roster(3, "00000000000000b2")
  pumpBoth(w, m, pb)
  T.eq(pa.size, 3, "equal rosters agree on 3")
  pb:sizeRequest(1)
  pumpBoth(w, m, pb)
  local zp = m:page()
  T.check(joined(zp.lines):find("BOB asks for 1 each", 1, true) ~= nil, "the opponent's size request is shown")
  T.eq(pa.size, 3, "one request alone does not change the size")
  pick(m, "agree")
  pumpBoth(w, m, pb)
  T.eq(pa.size, 1, "both requests agree on another equal size")
  T.check(joined(m:page().lines):find("Choose 2 to sit out", 1, true) ~= nil, "the agreed size asks for two to sit out")
  pick(m, "toggle", "PIKACHU")
  pick(m, "toggle", "BULBASAUR")
  pick(m, "continue")
  T.eq(m.step, "confirm", "the agreed size reaches confirm")
  local cp = m:page()
  T.check(cp.items[1].label:find("IVYSAUR", 1, true) ~= nil, "the substitute battles alone")
  local detail = joined(cp.items[1].full)
  T.check(detail:find("TACKLE 35/35", 1, true) ~= nil, "the battler's moves and PP are shown")
  T.check(detail:find("IV ", 1, true) and detail:find("EV ", 1, true), "IVs and EVs are disclosed")
  pick(m, "cancel")
  T.eq(m.step, "closed", "cancel closes the prep")
  T.eq(#m.team, 0, "cancel discards the temporary team")
  T.eq(m:result(), nil, "a cancelled prep has no result")
  pumpBoth(w, m, pb)
  T.eq(pb.state, "closed", "the opponent's prep closes")
  m:input("a")
  T.check(m.done and m.outcome == "cancel", "OK finishes a closed prep")
end

do
  local w, pa, pb = P.pair("emerald", "red")
  local src = source()
  src.party[2] = mon3(25, 20, { 84, 45, 98, 57 }, { ppBonuses = 2 })
  src.party[3] = mon3(1, 10, { 345 })
  local m = Model.new({ version = "emerald", gen = 3, data = emerald, prep = pa, owned = src,
    opponent = { name = "BOB" } })
  pumpBoth(w, m, pb)
  pick(m, "continue")
  local probs = joined(m:page().lines)
  T.check(probs:find("MAGICAL LEAF isn't used in this battle", 1, true) ~= nil, "a move outside the ruleset is told apart")
  T.check(probs:find("can't learn SURF", 1, true) ~= nil, "from a move the species can't learn")
  pick(m, "continue")
  pick(m, "leave")
  T.eq(m.step, "moves", "leaving Treecko out goes to moves")
  pick(m, "move", "THUNDERBOLT")
  local mp = m:page()
  T.check(joined(mp.lines):find("BULBASAUR: MAGICAL LEAF", 1, true) ~= nil, "each illegal move gets its own screen")
  local _, empty = find(mp, "empty")
  T.check(empty and empty.disabled, "the only move can't be emptied")
  m.cursor = find(mp, "empty")
  m:input("a")
  T.eq(m.step, "moves", "an empty choice that leaves no move is refused")
  T.check(joined(m:page().lines):find("needs at least one move", 1, true) ~= nil, "the refusal is explained")
  local legal = {}
  for _, it in ipairs(mp.items) do if it.id == "move" then legal[#legal + 1] = it.arg end end
  for _, id in ipairs(legal) do
    T.check(id == 33 or id == 45 or id == 22 or id == 34 or id == 92 or id == 75, "replacement is legal for Bulbasaur at 10: " .. id)
  end
  pick(m, "move", "TACKLE")
  T.eq(m.step, "size", "all moves resolved")
  pumpBoth(w, m, pb)
  pb:roster(2, "00000000000000b2")
  pumpBoth(w, m, pb)
  pick(m, "continue")
  T.eq(m.step, "confirm", "equal sizes need no sit-out")
  local r = m:finalReport()
  T.check(r.ok, "the final team is legal")
  local pika = r.result.team[1]
  T.eq(pika.moves[1].ppUps, 2, "kept moves keep their PP Ups")
  T.eq(pika.moves[1].pp, 42, "kept move PP includes PP Ups (30 + 2 x 6)")
  T.eq(pika.moves[4].id, 85, "the replacement stays in the slot it replaced")
  T.eq(pika.moves[4].pp, 15, "the replacement starts at its full base PP")
  T.eq(pika.moves[4].ppUps, 0, "the replacement has no PP Ups")
  T.eq(#r.result.team[2].moves, 1, "Bulbasaur has its one legal move")
end

do
  local w, pa, pb = P.pair("red", "emerald")
  local party = {
    { species = "PIKACHU", level = 20, dvs = { attack = 9, defense = 8, speed = 7, special = 6 },
      statExp = { hp = 100, attack = 400, defense = 0, speed = 0, special = 900 },
      moves = { { id = "THUNDERSHOCK", pp = 30 }, { id = "GROWL", pp = 40 } } },
  }
  local m = Model.new({ version = "red", gen = 1, data = red, prep = pa, owned = { party = party, generation = 1 },
    opponent = { name = "BOB" } })
  pumpBoth(w, m, pb)
  pick(m, "changes")
  local chg = joined(m:page().lines)
  T.check(chg:find("Special counts as both", 1, true) and chg:find("DVs become IVs", 1, true)
    and chg:find("Stat Exp. becomes EVs", 1, true), "a Gen 1 player sees the Special, DV and Stat Exp. policy")
  m:input("b")
  local gb = m:formatLines({ "Every Pokémon can battle." })
  T.eq(gb[1], "EVERY POKéMON CAN", "Gen 1 text is upper case and wrapped to 18")
end

do
  local m = Model.new({ version = "emerald", gen = 3, data = emerald, owned = source(), gameplayMods = true,
    rules = { ruleset = "g3u", dexMax = 151, moveMax = 165, moveGen = 1, gens = { 1, 3 } } })
  local pg = m:page()
  T.check(joined(pg.lines):find("Gameplay mods are on", 1, true) ~= nil, "gameplay mods refuse g3u with an explanation")
  T.eq(#pg.items, 1, "only cancel is offered")
  m:input("b")
  T.eq(m.step, "closed", "B on a cancel-only page cancels")
  local n = Model.new({ version = "emerald", gen = 3, data = emerald, owned = source(), gameplayMods = true,
    rules = { ruleset = "native", gen = 3, gens = { 3, 3 } } })
  T.check(joined(n:page().lines):find("Gameplay mods are on", 1, true) ~= nil, "gameplay mods refuse native battles too")
  local d = Model.new({ version = "emerald", gen = 3, data = false, owned = source(),
    rules = { ruleset = "g3u", dexMax = 151, moveMax = 165, moveGen = 1, gens = { 1, 3 } } })
  T.check(joined(d:page().lines):find("Import it again", 1, true) ~= nil, "a missing dataset gives actionable text")
end

do
  local w, pa, pb = P.pair("red", "red")
  local m = Model.new({ version = "red", gen = 1, data = red, prep = pa, owned = { party = {
    { species = "PIKACHU", level = 20, dvs = { attack = 9, defense = 8, speed = 7, special = 6 }, statExp = {},
      moves = { { id = "THUNDERSHOCK", pp = 30 } } } }, generation = 1 }, opponent = { name = "BOB" } })
  pumpBoth(w, m, pb)
  local pg = m:page()
  T.check(joined(pg.lines):find("rules of Gen 1", 1, true) ~= nil, "same-gen pairs use the native rules")
  T.eq(find(pg, "rentals"), nil, "native battles have no rentals")
  pick(m, "continue")
  pick(m, "continue")
  T.eq(m.step, "size", "a native team needs no substitutions or moves")
end

do
  local w, pa, pb = P.pair("emerald", "red")
  pb:cancel("bye")
  local m = Model.new({ version = "emerald", gen = 3, data = emerald, prep = pa, owned = source(),
    opponent = { name = "BOB" } })
  pumpBoth(w, m, pb)
  T.eq(m.step, "closed", "a peer cancel closes the prep")
  T.check(joined(m:page().lines):find("BOB cancelled", 1, true) ~= nil, "the close names the opponent")
  T.eq(#m.team, 0, "the temporary team is discarded")
end

do
  local w, pa, pb = P.pair("emerald", "gold")
  local gold = F.data("gold")
  local party = { { species = "CHIKORITA", level = 12, dvs = { attack = 9, defense = 8, speed = 7, special = 6 },
    statExp = {}, moves = { { id = "TACKLE", pp = 35 } } } }
  local mb = Model.new({ version = "gold", gen = 2, data = gold, prep = pb, owned = { party = party, generation = 2 },
    opponent = { name = "ALICE" } })
  local m = Model.new({ version = "emerald", gen = 3, data = emerald, prep = pa, owned = source(),
    opponent = { name = "BOB" } })
  pumpBoth(w, m, nil)
  mb:poll()
  T.eq(pa.rules.dexMax, 251, "Gen 2 vs Gen 3 starts at dex 251")
  pick(m, "continue")
  pick(m, "continue")
  T.eq(m.step, "substitute", "Treecko (No. 252) is outside dex 251")
  pb:counter(1)
  pumpBoth(w, m, nil)
  mb:poll()
  T.eq(pa.rules.dexMax, 151, "the counter narrows the rules")
  T.eq(m.step, "rules", "a rules change sends the player back to the rules")
  T.check(joined(m:page().lines):find("The rules changed", 1, true) ~= nil, "the rules change is explained")
  T.eq(mb.step, "rules", "the proposing side restarts too")
  pick(mb, "continue")
  T.check(joined(mb:page().lines):find("CHIKORITA can't join", 1, true) ~= nil, "the new rules re-check the team")
end

Rentals.DEFINITIONS["g3u-gen1"] = savedDefs
T.finish()
