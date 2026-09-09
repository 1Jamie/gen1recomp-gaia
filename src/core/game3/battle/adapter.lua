-- Owned adapter for game3 battle (api-shaped, no host).

local State = require("src.core.game3.battle.state")
local Rules = require("src.core.game3.battle.rules")

local Adapter = {}

local function norm_status(s)
  if not s then return nil end
  s = tostring(s):upper()
  if s == "BURN" then return "BRN" end
  if s == "POISON" then return "PSN" end
  if s == "TOXIC" then return "TOX" end
  if s == "SLEEP" or s == "SLP" then return "SLP" end
  if s == "PARALYSIS" or s == "PAR" then return "PAR" end
  if s == "FREEZE" or s == "FRZ" then return "FRZ" end
  return s
end

function Adapter.new(battleState, sayFn)
  local a = {
    _st = battleState,
    _say = sayFn or function() end,
  }

  function a:mon(battler) return battler and battler.mon end
  function a:hp(battler) return battler and battler.mon and battler.mon.hp or 0 end
  function a:maxHp(battler) return battler and battler.mon and battler.mon.maxHp or 0 end
  function a:status(battler)
    return battler and norm_status(battler.status or (battler.mon and battler.mon.status))
  end
  function a:hasStatus(battler, ...)
    local cur = self:status(battler)
    if not cur then return false end
    for i = 1, select("#", ...) do
      if cur == norm_status(select(i, ...)) then return true end
    end
    return false
  end
  function a:applyStatus(battler, status, _source, _opts)
    if not battler then return false end
    if self:status(battler) then return false end
    local side = self:ownSide(battler)
    if side and (side.expSafeguardTurns or 0) > 0 then return false end
    status = norm_status(status)
    battler.status = status
    if battler.mon then battler.mon.status = status end
    if status == "TOX" then battler.toxicCounter = 0 end
    return true
  end
  function a:clearStatus(battler)
    if not battler then return end
    battler.status = nil
    battler.toxicCounter = nil
    if battler.mon then battler.mon.status = nil end
  end
  function a:types(battler)
    if not battler then return {} end
    local Types = require("src.core.game3.battle.types")
    local out = { Types.name(battler.type1) }
    if battler.type2 then out[2] = Types.name(battler.type2) end
    return out
  end
  function a:stages(battler) return battler and battler.stages end
  function a:changeStages(battler, changes)
    if not battler or not battler.stages or type(changes) ~= "table" then return end
    for k, d in pairs(changes) do
      local cur = battler.stages[k] or 0
      cur = cur + (tonumber(d) or 0)
      if cur < -6 then cur = -6 elseif cur > 6 then cur = 6 end
      battler.stages[k] = cur
    end
  end
  function a:applyHpLoss(battler, amount)
    if battler and battler.expProtected then
      return 0
    end
    return State.applyHpLoss(battler, amount)
  end
  function a:heal(battler, amount) return State.heal(battler, amount) end
  function a:isFainted(battler) return State.isFainted(battler) end
  function a:emitFaint(battler)
    if battler then
      battler.fainted = true
      if battler.mon then battler.mon.hp = 0 end
      -- Destiny Bond
      if battler.expDestinyBond then
        local foe = self:foeOf(battler)
        if foe and not self:isFainted(foe) then
          self:applyHpLoss(foe, self:hp(foe))
          self:emitFaint(foe)
          self:say(self:displayName(battler) .. " took\n" .. self:displayName(foe) .. " with it!")
        end
      end
    end
  end
  function a:displayName(battler) return State.displayName(battler) end
  function a:say(text, ...)
    if select("#", ...) > 0 then
      text = string.format(tostring(text), ...)
    end
    self._say(tostring(text or ""))
  end
  function a:sayFail() self:say("But it failed!") end
  function a:rng() return self._st.rng or math.random end
  function a:activeBattlers()
    local out = {}
    if self._st.player then out[#out + 1] = self._st.player end
    if self._st.enemy then out[#out + 1] = self._st.enemy end
    return out
  end
  function a:foeOf(battler)
    if not battler then return nil end
    if battler.side == "player" then return self._st.enemy end
    return self._st.player
  end
  function a:ownSide(battler)
    if not battler then return nil end
    if battler.side == "player" then return self._st.playerSide end
    return self._st.enemySide
  end
  function a:foeSide(battler)
    if not battler then return nil end
    if battler.side == "player" then return self._st.enemySide end
    return self._st.playerSide
  end
  function a:findHazard(side, id)
    if not side or not side.hazards then return nil end
    for _, h in ipairs(side.hazards) do
      if h.id == id then return h end
    end
    return nil
  end
  function a:isBattleDecided()
    return self._st.over == true
  end
  function a:hasSubstitute(battler)
    return battler and (battler.substituteHP or 0) > 0
  end
  function a:abilityOf(battler)
    if not battler then return nil end
    if battler.expTracedAbility then return battler.expTracedAbility end
    if battler.expAbilitySuppressed then return nil end
    local id = battler.ability
    if not id and battler.mon then
      id = battler.mon.ability or battler.mon.abilityId
    end
    if type(id) == "string" and id ~= "" then
      return id:upper():gsub("%s+", "_")
    end
    id = tonumber(id)
    if id and id > 0 then
      local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
      if ok and Pokemon and Pokemon.abilityName then
        local n = Pokemon.abilityName(id)
        if n and n ~= "" and not n:match("^ABILITY") then
          return tostring(n):upper():gsub("%s+", "_")
        end
      end
    end
    return nil
  end
  function a:lastMoveOf(battler)
    return battler and (battler.lastMoveId or battler.lastMove)
  end
  function a:partyMons(battler)
    if not battler then return {} end
    if battler.side == "player" then return self._st.playerParty or {} end
    return self._st.foeParty or {}
  end
  function a:applyConfusion(battler, turns, _source)
    if not battler then return false end
    if battler.confusedTurns and battler.confusedTurns > 0 then return false end
    local rng = self:rng()
    local t = turns
    if not t then
      if type(rng) == "function" then
        local ok, v = pcall(rng, 2, 5)
        t = ok and v or math.random(2, 5)
      else
        t = math.random(2, 5)
      end
    end
    battler.confusedTurns = t
    return true
  end
  function a:isConfused(battler)
    return battler and (battler.confusedTurns or 0) > 0
  end
  function a:invokeEffect(id, user, target, opts)
    local Effects = require("src.core.game3.battle.effects")
    opts = opts or {}
    return Effects.run(id, self, user, target, opts.move, opts.moveId)
  end
  function a:useMove(user, moveId, target, opts)
    local Engine = require("src.core.game3.battle.engine")
    return Engine.resolveMove(user, target, moveId, opts and opts.slot, self, self._st, {})
  end
  function a:fieldGet(key) return self._st[key] end
  function a:fieldSet(key, val) self._st[key] = val end

  function a:setWeather(kind, turns)
    self._st.weather = kind
    self._st.weatherTurns = turns or 5
  end

  function a:tickWeather()
    local st = self._st
    if not st.weather then return end
    local turns = st.weatherTurns or 0
    if turns > 0 then
      st.weatherTurns = turns - 1
      local cont = {
        SUNNY = "The sunlight is strong.",
        RAINY = "Rain continues to fall.",
        SANDSTORM = "The sandstorm rages.",
        HAIL = "Hail continues to fall.",
      }
      if st.weatherTurns > 0 then
        self:say(cont[st.weather] or "The weather continues.")
      else
        local endMsg = {
          SUNNY = "The sunlight faded.",
          RAINY = "The rain stopped.",
          SANDSTORM = "The sandstorm subsided.",
          HAIL = "The hail stopped.",
        }
        self:say(endMsg[st.weather] or "The weather cleared.")
        st.weather = nil
        return
      end
    end
    -- Sandstorm / hail chip
    if st.weather == "SANDSTORM" or st.weather == "HAIL" then
      for _, b in ipairs(self:activeBattlers()) do
        if not self:isFainted(b) then
          local types = self:types(b)
          if Rules.weather.hits(types, st.weather) then
            local dmg = Rules.weather.chipAmount(self:maxHp(b))
            self:applyHpLoss(b, dmg)
            self:say(self:displayName(b) .. " is buffeted\nby the " .. st.weather:lower() .. "!")
          end
        end
      end
    end
  end

  return a
end

return Adapter
