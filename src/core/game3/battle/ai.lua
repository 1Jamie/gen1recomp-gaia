-- FireRed 1:1 battle AI — BattleAI_ChooseMoveOrAction scoring loop.

local AiVm = require("src.core.game3.battle.ai_vm")

local Ai = {}

Ai._pack = nil
Ai._packTried = false

local function pack_paths()
  local rel = "data/generated/gba/battle_ai/pack.lua"
  local paths = {}
  local home = os.getenv("HOME")
  if home then
    paths[#paths + 1] = home .. "/.local/share/love/pokemon-love2d/firered/" .. rel
  end
  paths[#paths + 1] = rel
  paths[#paths + 1] = "firered/" .. rel
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local sd = love.filesystem.getSaveDirectory()
    if type(sd) == "string" and sd ~= "" then
      paths[#paths + 1] = sd .. "/" .. rel
      local parent = sd:match("^(.*)/[^/]+$")
      if parent then
        paths[#paths + 1] = parent .. "/pokemon-love2d/firered/" .. rel
      end
    end
  end
  return paths, rel
end

local function load_lua_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  if not src then return nil end
  local chunk, err = load(src, "@" .. path, "t", {})
  if not chunk then return nil, err end
  local ok, t = pcall(chunk)
  if ok then return t end
  return nil, t
end

function Ai.loadPack(opts)
  opts = opts or {}
  if Ai._pack and not opts.force then return Ai._pack end
  Ai._packTried = true

  local paths, rel = pack_paths()

  -- love filesystem
  if love and love.filesystem and love.filesystem.read then
    local src = love.filesystem.read(rel)
    if src then
      local chunk = load(src, "@" .. rel, "t", {})
      if chunk then
        local ok, t = pcall(chunk)
        if ok and t then
          Ai._pack = t
          return t
        end
      end
    end
  end

  -- Dataset cache
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local cache = Dataset.cache()
    if cache and cache.read then
      local src = cache:read(rel)
      if src then
        local chunk = load(src, "@" .. rel, "t", {})
        if chunk then
          local ok, t = pcall(chunk)
          if ok and t then
            Ai._pack = t
            return t
          end
        end
      end
    end
  end

  for _, p in ipairs(paths) do
    local t = load_lua_file(p)
    if t then
      Ai._pack = t
      return t
    end
  end

  -- Try extract on demand
  if opts.extract ~= false then
    local okE, Extract = pcall(require, "src.import.gba.battle_ai_extract")
    if okE and Extract and Extract.run then
      local FileIO = require("src.import.gba.file_io")
      local home = os.getenv("HOME")
      local outRoot = home and (home .. "/.local/share/love/pokemon-love2d/firered") or "."
      local cache = FileIO.makeCache(outRoot)
      local detail = Extract.run({
        cache = cache,
        cacheRoot = "data/generated/gba",
        pretRoot = os.getenv("POKEFIRERED"),
      })
      if detail then
        local t = load_lua_file(outRoot .. "/" .. (detail.path or rel))
        if not t and detail.path then t = load_lua_file(detail.path) end
        if t then
          Ai._pack = t
          return t
        end
        -- re-read via cache
        local src = cache:read(rel)
        if src then
          local chunk = load(src, "@" .. rel, "t", {})
          if chunk then
            local ok, pack = pcall(chunk)
            if ok and pack then
              Ai._pack = pack
              return pack
            end
          end
        end
      end
    end
  end

  return nil
end

local function rng_fn(st, opts)
  if opts and opts.rng then return opts.rng end
  if st and type(st.rng) == "function" then return st.rng end
  return math.random
end

local function roll(rng, lo, hi)
  local ok, v = pcall(rng, lo, hi)
  if ok and type(v) == "number" then return v end
  ok, v = pcall(rng)
  if ok and type(v) == "number" then
    return lo + (math.floor(v) % (hi - lo + 1))
  end
  return math.random(lo, hi)
end

local function first_usable(mon)
  if not mon or not mon.moves then return nil end
  for i = 1, 4 do
    local mv = mon.moves[i]
    local p = mon.pp and mon.pp[i]
    if mv and mv ~= 0 and mv ~= "" and (p == nil or tonumber(p) > 0) then
      return { kind = "move", move = mv, slot = i, user = "enemy" }
    end
  end
  return { kind = "move", move = "STRUGGLE", slot = nil, user = "enemy" }
end

local function random_usable(mon, rng)
  local usable = {}
  if mon and mon.moves then
    for i = 1, 4 do
      local mv = mon.moves[i]
      local p = mon.pp and mon.pp[i]
      if mv and mv ~= 0 and mv ~= "" and (p == nil or tonumber(p) > 0) then
        usable[#usable + 1] = { move = mv, slot = i }
      end
    end
  end
  if #usable == 0 then
    return { kind = "move", move = "STRUGGLE", slot = nil, user = "enemy" }
  end
  local pick = usable[roll(rng, 1, #usable)]
  return { kind = "move", move = pick.move, slot = pick.slot, user = "enemy" }
end

local function bit_and_flags(a, b)
  a = math.floor(a or 0)
  b = math.floor(b or 0)
  local r, bitv = 0, 1
  for _ = 1, 32 do
    if (a % 2) > 0 and (b % 2) > 0 then r = r + bitv end
    a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
  end
  return r
end

--- Choose enemy move via pret AI scripts.
-- @return { kind="move", move=..., slot=i, user="enemy", scores=... }
function Ai.chooseMove(st, opts)
  opts = opts or {}
  local mon = st and st.enemy and st.enemy.mon
  local rng = rng_fn(st, opts)

  local aiFlags = opts.aiFlags
  if aiFlags == nil then
    if st and st.aiFlags ~= nil then
      aiFlags = st.aiFlags
    elseif st and st.wild then
      aiFlags = 0
    else
      aiFlags = st and st.aiFlags or 0
    end
  end
  aiFlags = tonumber(aiFlags) or 0

  if aiFlags == 0 then
    -- Wild / no scripts: match prior fallback (first usable). Random also acceptable.
    local act = first_usable(mon)
    act.scores = { 0, 0, 0, 0 }
    return act
  end

  local pack = opts.pack or Ai.loadPack()
  if not pack or not pack.table or not pack.scripts then
    return first_usable(mon)
  end

  local scores = { 100, 100, 100, 100 }
  local simulatedRNG = {}
  for i = 1, 4 do
    local mv = mon and mon.moves and mon.moves[i]
    local pp = mon and mon.pp and mon.pp[i]
    if not mv or mv == 0 or mv == "" or (pp ~= nil and tonumber(pp) <= 0) then
      scores[i] = 0
    end
    simulatedRNG[i] = 100 - (roll(rng, 0, 15))
  end

  local logicId = 0
  local flags = aiFlags
  while flags ~= 0 do
    if bit_and_flags(flags, 1) ~= 0 then
      local scriptName = pack.table[logicId + 1] -- Lua 1-based; pret index 0
      if scriptName and pack.scripts[scriptName] then
        for movesetIndex = 1, 4 do
          if scores[movesetIndex] ~= 0 or true then
            -- Still run; empty/no-PP moves get score 0 inside VM
            local vm = AiVm.new({
              pack = pack,
              st = st,
              user = st.enemy,
              target = st.player,
              userSide = st.enemySide,
              targetSide = st.playerSide,
              scores = scores,
              simulatedRNG = simulatedRNG,
              movesetIndex = movesetIndex,
              rng = rng,
            })
            AiVm.run(vm, scriptName)
            if vm.aiAction and vm.aiAction ~= 0 then
              -- flee/watch: ignore for MVP move choice
            end
          end
        end
      end
    end
    flags = math.floor(flags / 2)
    logicId = logicId + 1
    if logicId > 31 then break end
  end

  -- Pick max score; ties → Random() % numBest
  local best = scores[1] or 0
  local considered = { 1 }
  for i = 2, 4 do
    local s = scores[i] or 0
    if s > best then
      best = s
      considered = { i }
    elseif s == best then
      considered[#considered + 1] = i
    end
  end
  local pickSlot = considered[roll(rng, 1, #considered)]
  local mv = mon and mon.moves and mon.moves[pickSlot]
  if not mv or mv == 0 or mv == "" or best <= 0 then
    local fallback = first_usable(mon)
    fallback.scores = scores
    return fallback
  end
  return {
    kind = "move",
    move = mv,
    slot = pickSlot,
    user = "enemy",
    scores = scores,
  }
end

return Ai
