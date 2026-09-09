-- FRLG volatiles (ported from KR battle/core/effects/volatiles.lua; no KR require).

local H = require("src.core.game3.battle.effects._helpers")

local Volatiles = {}

local ENCORE_BLOCK = {
  [90] = true, -- ENCORE
  [83] = true, -- METRONOME
  [9] = true,  -- MIRROR_MOVE
  [95] = true, -- SKETCH
}

function Volatiles.protect(ctx)
  local user = ctx.user
  local streak = user.expProtectStreak or 0
  if streak > 0 then
    local denom = 2 ^ math.min(streak, 8)
    local rng = ctx.rng or ctx.adapter:rng()
    local roll
    if type(rng) == "function" then
      local ok, v = pcall(rng, 0, denom - 1)
      roll = ok and v or math.random(0, denom - 1)
    else
      roll = math.random(0, denom - 1)
    end
    if roll ~= 0 then
      user.expProtectStreak = 0
      return H.sayFail(ctx)
    end
  end
  user.expProtected = true
  user.expProtectStreak = streak + 1
  ctx.adapter:say(H.displayName(ctx, user) .. "\nprotected itself!")
end

function Volatiles.endure(ctx)
  local user = ctx.user
  local streak = user.expProtectStreak or 0
  if streak > 0 then
    local denom = 2 ^ math.min(streak, 8)
    local rng = ctx.rng or ctx.adapter:rng()
    local roll
    if type(rng) == "function" then
      local ok, v = pcall(rng, 0, denom - 1)
      roll = ok and v or math.random(0, denom - 1)
    else
      roll = math.random(0, denom - 1)
    end
    if roll ~= 0 then
      user.expProtectStreak = 0
      return H.sayFail(ctx)
    end
  end
  user.expEnduring = true
  user.expProtectStreak = streak + 1
  ctx.adapter:say(H.displayName(ctx, user) .. " braced\nitself!")
end

function Volatiles.encore(ctx)
  local target = ctx.target
  local last = H.lastMove(ctx, target)
  if not last then return H.sayFail(ctx) end
  local Moves = require("src.core.game3.battle.moves")
  local lastMove = Moves.get(last)
  if lastMove and ENCORE_BLOCK[tonumber(lastMove.effect) or -1] then
    return H.sayFail(ctx)
  end
  if tostring(last):upper() == "STRUGGLE" then return H.sayFail(ctx) end
  local has = false
  for _, mv in ipairs(H.preparedMoves(ctx, target)) do
    local id = mv.id or mv
    if id == last and (mv.pp or 0) > 0 then has = true break end
  end
  if not has then return H.sayFail(ctx) end
  target.expEncoreMove = last
  local rng = ctx.rng or ctx.adapter:rng()
  local turns
  if type(rng) == "function" then
    local ok, v = pcall(rng, 2, 6)
    turns = ok and v or math.random(2, 6)
  else
    turns = math.random(2, 6)
  end
  target.expEncoreTurns = turns
  ctx.adapter:say(H.displayName(ctx, target) .. "\ngot an ENCORE!")
end

function Volatiles.perishSong(ctx)
  for _, b in ipairs({ ctx.user, ctx.target }) do
    if b and ctx.adapter:mon(b) and not b.expPerishTurns then
      local ab = ctx.adapter:abilityOf(b)
      if ab ~= "SOUNDPROOF" then
        b.expPerishTurns = 4
      end
    end
  end
  ctx.adapter:say("All affected POKEMON\nwill faint in three\nturns!")
end

function Volatiles.attract(ctx)
  local target = ctx.target
  if ctx.adapter:abilityOf(target) == "OBLIVIOUS" then return H.sayFail(ctx) end
  if target.expInfatuated then return H.sayFail(ctx) end
  local userMon = ctx.adapter:mon(ctx.user)
  local targetMon = ctx.adapter:mon(target)
  local ug = userMon and userMon.gender
  local tg = targetMon and targetMon.gender
  if not ug or not tg or ug == "U" or tg == "U" or ug == tg then
    return H.sayFail(ctx)
  end
  target.expInfatuated = true
  ctx.adapter:say(H.displayName(ctx, target) .. " fell in love!")
end

function Volatiles.spite(ctx)
  local target = ctx.target
  local last = H.lastMove(ctx, target)
  if not last then return H.sayFail(ctx) end
  local cut = 0
  local mon = ctx.adapter:mon(target)
  if mon and mon.moves and mon.pp then
    for i = 1, 4 do
      if mon.moves[i] == last and (mon.pp[i] or 0) > 0 then
        local lost = math.min(mon.pp[i], 4)
        mon.pp[i] = mon.pp[i] - lost
        cut = lost
        break
      end
    end
  end
  if cut <= 0 then return H.sayFail(ctx) end
  local Moves = require("src.core.game3.battle.moves")
  ctx.adapter:say(string.format("Reduced %s's\n%s by %d!",
    H.displayName(ctx, target), Moves.displayName(last), cut))
end

function Volatiles.torment(ctx)
  if ctx.target.expTormented then return H.sayFail(ctx) end
  ctx.target.expTormented = true
  ctx.adapter:say(H.displayName(ctx, ctx.target) .. " was\nsubjected to TORMENT!")
end

return Volatiles
