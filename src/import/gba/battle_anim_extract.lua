-- Transpile pret battle_anim_scripts.s → portable IR pack + optional tag sheets.
-- Pointers in createsprite/createvisualtask become named template/task IDs.
-- Writes: data/generated/gba/pokemon/battle_anims/pack.lua (+ tags/*.idx.bin, *.pal)

local Versions = require("src.import.gba.versions")
local AnimTemplates = require("src.core.game3.battle.anim_templates")

local BattleAnimExtract = {}

BattleAnimExtract.FORMAT_VERSION = 2
BattleAnimExtract.CACHE_SUB = "pokemon/battle_anims"

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function pret_scripts_path()
  local env = os.getenv("POKEFIRERED") or os.getenv("POKEFIRE_RED")
  if env and #env > 0 then
    return env .. "/data/battle_anim_scripts.s"
  end
  local candidates = {
    "../pokefirered/data/battle_anim_scripts.s",
    "pokefirered/data/battle_anim_scripts.s",
  }
  for _, p in ipairs(candidates) do
    local f = io.open(p, "rb")
    if f then f:close() return p end
  end
  return nil
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function split_args(s)
  local out = {}
  if not s or s == "" then return out end
  for part in (s .. ","):gmatch("([^,]*),") do
    part = part:match("^%s*(.-)%s*$") or part
    if part ~= "" then
      local num = tonumber(part)
      if num then
        out[#out + 1] = num
      elseif part:match("^ANIM_") then
        local token = part:gsub("^ANIM_", ""):lower()
        if token == "attacker" or token == "target"
          or token == "atk_partner" or token == "def_partner" then
          out[#out + 1] = token
        else
          out[#out + 1] = part
        end
      else
        out[#out + 1] = part
      end
    end
  end
  return out
end

local function pret_sprites_dir()
  local env = os.getenv("POKEFIRERED") or os.getenv("POKEFIRE_RED")
  local bases = {}
  if env and #env > 0 then bases[#bases + 1] = env end
  bases[#bases + 1] = "../pokefirered"
  bases[#bases + 1] = "pokefirered"
  for _, b in ipairs(bases) do
    local p = b .. "/graphics/battle_anims/sprites"
    local f = io.open(p .. "/impact.png", "rb")
    if f then f:close() return p end
  end
  return nil
end

local function parse_tag(name)
  name = tostring(name or ""):gsub("^ANIM_TAG_", "")
  return name
end

--- Parse one script body (lines) into IR ops.
local function parse_ops(lines)
  local ops = {}
  local lastTag = nil
  for _, line in ipairs(lines) do
    line = line:gsub("%s+@.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line == "" or line:sub(1, 1) == "@" or line:sub(1, 1) == "." then
      -- skip
    elseif line:match("^loadspritegfx%s+") then
      local tag = line:match("^loadspritegfx%s+(%S+)")
      lastTag = parse_tag(tag)
      ops[#ops + 1] = { op = "loadspritegfx", tag = lastTag }
    elseif line:match("^unloadspritegfx%s+") then
      local tag = line:match("^unloadspritegfx%s+(%S+)")
      ops[#ops + 1] = { op = "unloadspritegfx", tag = parse_tag(tag) }
    elseif line:match("^createsprite%s+") then
      local rest = line:match("^createsprite%s+(.+)$")
      local args = split_args(rest)
      local template = tostring(args[1] or "Unknown")
      local animBattler = args[2] or "attacker"
      if type(animBattler) == "string" then
        animBattler = animBattler:gsub("^anim_", "")
      end
      local subpri = tonumber(args[3]) or 2
      local sprArgs = {}
      for i = 4, #args do sprArgs[#sprArgs + 1] = args[i] end
      local info = AnimTemplates.get(template)
      local tag = nil
      if not (info and info.noGfx) then
        tag = AnimTemplates.tagFromLoadOrTemplate(lastTag, template)
      end
      ops[#ops + 1] = {
        op = "createsprite",
        template = template,
        animBattler = animBattler,
        subpriority = subpri,
        args = sprArgs,
        tag = tag,
        callback = info and info.callback or nil,
        w = info and info.w or 32,
        h = info and info.h or 32,
        noGfx = info and info.noGfx or nil,
      }
    elseif line:match("^createvisualtask%s+") then
      local rest = line:match("^createvisualtask%s+(.+)$")
      local args = split_args(rest)
      local task = tostring(args[1] or "stub")
      local pri = tonumber(args[2]) or 2
      local targs = {}
      for i = 3, #args do targs[#targs + 1] = args[i] end
      ops[#ops + 1] = {
        op = "createvisualtask",
        task = task,
        priority = pri,
        args = targs,
      }
    elseif line:match("^delay%s+") then
      local n = tonumber(line:match("^delay%s+(%S+)")) or 1
      ops[#ops + 1] = { op = "delay", frames = n }
    elseif line == "waitforvisualfinish" then
      ops[#ops + 1] = { op = "waitforvisualfinish" }
    elseif line == "end" then
      ops[#ops + 1] = { op = "end" }
    elseif line == "blendoff" then
      ops[#ops + 1] = { op = "blendoff" }
    elseif line:match("^monbg%s+") then
      local b = line:match("^monbg%s+(%S+)")
      ops[#ops + 1] = { op = "monbg", battler = (b or "target"):gsub("^ANIM_", ""):lower() }
    elseif line:match("^clearmonbg%s+") then
      local b = line:match("^clearmonbg%s+(%S+)")
      ops[#ops + 1] = { op = "clearmonbg", battler = (b or "target"):gsub("^ANIM_", ""):lower() }
    elseif line:match("^setalpha%s+") then
      local a, b = line:match("^setalpha%s+(%d+)%s*,%s*(%d+)")
      ops[#ops + 1] = { op = "setalpha", eva = tonumber(a) or 12, evb = tonumber(b) or 8 }
    elseif line:match("^playsewithpan%s+") or line:match("^playse%s+") then
      -- pret macros: playsewithpan SE_M_FOO, SOUND_PAN_TARGET
      local se, pan = line:match("playse[%w]*%s+([^,%s]+)%s*,%s*(%S+)")
      if not se then
        se = line:match("playse[%w]*%s+(%S+)")
      end
      if se then
        se = se:gsub(",$", "")
        local op = { op = "playse", se = se }
        if pan then
          -- Parens: gsub returns (str, count); tonumber(str, count) errors (base).
          local panClean = (pan:gsub(",$", ""))
          op.pan = tonumber(panClean) or panClean
        end
        ops[#ops + 1] = op
      end
    elseif line:match("^loopsewithpan%s+") then
      -- pret: loopsewithpan SE, pan, framesBetween, playCount
      local se, pan, wait, plays = line:match(
        "loopsewithpan%s+([^,%s]+)%s*,%s*([^,%s]+)%s*,%s*(%d+)%s*,%s*(%d+)")
      if not se then
        se, pan = line:match("loopsewithpan%s+([^,%s]+)%s*,%s*(%S+)")
      end
      local op = { op = "loopsewithpan" }
      if se then
        op.se = (se:gsub(",$", ""))
        if pan then
          local panClean = (pan:gsub(",$", ""))
          op.pan = tonumber(panClean) or panClean
        end
        op.wait = tonumber(wait) or 10
        op.plays = tonumber(plays) or 1
      end
      ops[#ops + 1] = op
    elseif line:match("^waitplaysewithpan%s+") then
      -- pret: waitplaysewithpan SE, pan, frames
      local se, pan, wait = line:match(
        "waitplaysewithpan%s+([^,%s]+)%s*,%s*([^,%s]+)%s*,%s*(%d+)")
      local op = { op = "waitplaysewithpan" }
      if se then
        op.se = (se:gsub(",$", ""))
        if pan then
          local panClean = (pan:gsub(",$", ""))
          op.pan = tonumber(panClean) or panClean
        end
        op.wait = tonumber(wait) or 0
      end
      ops[#ops + 1] = op
    elseif line:match("^call%s+") then
      local lab = line:match("^call%s+(%S+)")
      ops[#ops + 1] = { op = "call", label = lab }
    elseif line == "return" then
      ops[#ops + 1] = { op = "return" }
    elseif line:match("^goto%s+") then
      local lab = line:match("^goto%s+(%S+)")
      ops[#ops + 1] = { op = "goto", label = lab }
    elseif line:match("^invisible%s+") then
      local b = line:match("^invisible%s+(%S+)")
      ops[#ops + 1] = { op = "invisible", battler = (b or "attacker"):gsub("^ANIM_", ""):lower() }
    elseif line:match("^visible%s+") then
      local b = line:match("^visible%s+(%S+)")
      ops[#ops + 1] = { op = "visible", battler = (b or "attacker"):gsub("^ANIM_", ""):lower() }
    elseif line == "nop" or line == "nop2" then
      ops[#ops + 1] = { op = line }
    end
  end
  if #ops == 0 or ops[#ops].op ~= "end" then
    if not (#ops > 0 and ops[#ops].op == "return") then
      ops[#ops + 1] = { op = "end" }
    end
  end
  return ops
end

local function parse_scripts_file(src)
  local moves = {}
  local status = {}
  local general = {}
  local special = {}
  local labels = {}
  local moveOrder = {} -- from gBattleAnims_Moves table
  local inMovesTable = false

  -- Collect gBattleAnims_Moves pointer order
  for line in (src .. "\n"):gmatch("(.-)\n") do
    local trimmed = line:match("^%s*(.-)%s*$") or line
    if trimmed:find("gBattleAnims_Moves::") then
      inMovesTable = true
    elseif inMovesTable then
      if trimmed:match("^gBattleAnims_") or trimmed:match("^Move_") then
        if not trimmed:match("^%.4byte") then
          inMovesTable = false
        end
      end
      local sym = trimmed:match("^%.4byte%s+(%S+)")
      if sym then
        moveOrder[#moveOrder + 1] = sym
      end
    end
  end

  -- Split into labeled blocks
  local current = nil
  local buf = {}
  local function flush()
    if not current then return end
    local ops = parse_ops(buf)
    labels[current] = ops
    if current:match("^Move_") then
      moves[current] = ops
    elseif current:match("^Status_") or current:match("^gBattleAnims_Status") then
      status[current] = ops
    elseif current:match("^General_") then
      general[current] = ops
    elseif current:match("^Special_") then
      special[current] = ops
    end
    buf = {}
  end

  for line in (src .. "\n"):gmatch("(.-)\n") do
    local label = line:match("^([A-Za-z0-9_]+):")
    if label and not line:match("^gBattleAnims_") then
      flush()
      current = label
    elseif current then
      buf[#buf + 1] = line
    end
  end
  flush()

  -- Index moves by move id (table order; index 0 = MOVE_NONE)
  local byId = {}
  for i, sym in ipairs(moveOrder) do
    local id = i - 1
    byId[id] = labels[sym] or moves[sym]
  end

  return {
    version = BattleAnimExtract.FORMAT_VERSION,
    moves = byId,
    status = status,
    general = general,
    special = special,
    labels = labels,
    moveSymbols = moveOrder,
    tags = {},
  }
end

local function serialize_value(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "nil" then return "nil" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then return tostring(v) end
  if t == "string" then return string.format("%q", v) end
  if t == "table" then
    -- array?
    local n = #v
    local isArray = true
    local count = 0
    for k in pairs(v) do
      count = count + 1
      if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
        isArray = false
      end
    end
    if isArray and n > 0 then
      local parts = { "{" }
      for i = 1, n do
        parts[#parts + 1] = "\n" .. indent .. "  " .. serialize_value(v[i], indent .. "  ") .. ","
      end
      parts[#parts + 1] = "\n" .. indent .. "}"
      return table.concat(parts)
    end
    local parts = { "{" }
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta == tb then
        if ta == "number" then return a < b end
        return tostring(a) < tostring(b)
      end
      return ta < tb
    end)
    for _, k in ipairs(keys) do
      local key
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        key = k
      else
        key = "[" .. serialize_value(k) .. "]"
      end
      parts[#parts + 1] = "\n" .. indent .. "  " .. key .. " = " .. serialize_value(v[k], indent .. "  ") .. ","
    end
    parts[#parts + 1] = "\n" .. indent .. "}"
    return table.concat(parts)
  end
  return "nil"
end

--- Copy pret battle_anims/sprites/*.png into cache as RGBA PNGs with
-- palette index 0 punched to transparent (GBA OBJ convention).
local function extract_tag_pngs(cache, root, spritesDir)
  local tags = {}
  if not spritesDir then return tags end
  local stems = {}
  local p = io.popen('ls -1 "' .. spritesDir .. '"/*.png 2>/dev/null')
  if p then
    for line in p:lines() do
      local stem = line:match("([^/]+)%.png$")
      if stem then stems[#stems + 1] = stem end
    end
    p:close()
  end

  local tmpDir = os.getenv("TMPDIR") or "/tmp"
  local listPath = tmpDir .. "/gba_anim_tags_list.txt"
  local outDir = tmpDir .. "/gba_anim_tags_out"
  os.execute('mkdir -p "' .. outDir .. '"')
  do
    local lf = io.open(listPath, "wb")
    if lf then
      for _, stem in ipairs(stems) do
        lf:write(spritesDir .. "/" .. stem .. ".png\n")
      end
      lf:close()
    end
  end

  -- Convert indexed PNGs → RGBA with GBA index-0 transparent (+ magenta key punch).
  local py = [[
import sys
from PIL import Image
list_path, out_dir = sys.argv[1], sys.argv[2]
n = 0
with open(list_path) as f:
    paths = [ln.strip() for ln in f if ln.strip()]

def is_key(r, g, b):
    return (r, g, b) == (98, 41, 255) or (r > 80 and r < 120 and g < 60 and b > 240)

for src in paths:
    try:
        im = Image.open(src)
    except Exception:
        continue
    stem = src.rsplit('/', 1)[-1].rsplit('.', 1)[0]
    if im.mode == 'P':
        # GBA OBJ: palette index 0 is transparent regardless of color.
        im.info['transparency'] = 0
        im = im.convert('RGBA')
    else:
        im = im.convert('RGBA')
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if is_key(r, g, b):
                px[x, y] = (0, 0, 0, 0)
    out = out_dir + '/' + stem.upper() + '.png'
    im.save(out, 'PNG')
    n += 1
print(n)
]]
  local pyPath = tmpDir .. "/gba_anim_tags_convert.py"
  do
    local pf = io.open(pyPath, "wb")
    if pf then pf:write(py) pf:close() end
  end
  local converted = 0
  local pipe = io.popen('python3 "' .. pyPath .. '" "' .. listPath .. '" "' .. outDir .. '" 2>/dev/null')
  if pipe then
    local line = pipe:read("*l")
    pipe:close()
    converted = tonumber(line) or 0
  end

  local copied = 0
  if converted > 0 then
    local lp = io.popen('ls -1 "' .. outDir .. '"/*.png 2>/dev/null')
    if lp then
      for line in lp:lines() do
        local tag = line:match("([^/]+)%.png$")
        if tag then
          local f = io.open(line, "rb")
          if f then
            local bytes = f:read("*a")
            f:close()
            local rel = root .. "/tags/" .. tag .. ".png"
            if cache and cache.write and bytes then
              cache:write(rel, bytes)
              tags[tag] = {
                file = "tags/" .. tag .. ".png",
                format = "png_rgba",
                transparent = "index0",
              }
              copied = copied + 1
            end
          end
        end
      end
      lp:close()
    end
  else
    -- Fallback: raw copy (runtime will punch magenta)
    for _, stem in ipairs(stems) do
      local srcPath = spritesDir .. "/" .. stem .. ".png"
      local f = io.open(srcPath, "rb")
      if f then
        local bytes = f:read("*a")
        f:close()
        local tag = stem:upper()
        local rel = root .. "/tags/" .. tag .. ".png"
        if cache and cache.write and bytes then
          cache:write(rel, bytes)
          tags[tag] = { file = "tags/" .. tag .. ".png", format = "png", stem = stem }
          copied = copied + 1
        end
      end
    end
  end
  print("[battle_anim_extract] wrote", copied, "tag sheets (transparent index0) from", spritesDir)
  return tags
end

local GENERIC = {
  { op = "loadspritegfx", tag = "IMPACT" },
  { op = "monbg", battler = "target" },
  { op = "createsprite", template = "gHorizontalLungeSpriteTemplate", animBattler = "attacker", subpriority = 2, args = { 4, 4 }, noGfx = true, callback = "HorizontalLunge" },
  { op = "delay", frames = 6 },
  { op = "createsprite", template = "gBasicHitSplatSpriteTemplate", animBattler = "attacker", subpriority = 2, tag = "IMPACT", callback = "HitSplatBasic", w = 32, h = 32, args = { 0, 0, "target", 2 } },
  { op = "createvisualtask", task = "AnimTask_ShakeMon", priority = 2, args = { "target", 3, 0, 6, 1 } },
  { op = "waitforvisualfinish" },
  { op = "clearmonbg", battler = "target" },
  { op = "end" },
}

function BattleAnimExtract.ready(cache, root)
  root = root or BattleAnimExtract.CACHE_SUB
  local path = root .. "/pack.lua"
  if cache and cache.exists then
    return cache:exists(path)
  end
  local f = io.open(path, "rb") or io.open("data/generated/gba/" .. path, "rb")
  if f then f:close() return true end
  return false
end

function BattleAnimExtract.run(opts)
  opts = opts or {}
  local cache = opts.cache
  local root = BattleAnimExtract.CACHE_SUB

  -- Fast path: if already extracted and not forcing re-extract, skip
  if not opts.force and BattleAnimExtract.ready(cache, root) then
    return {
      path = root .. "/pack.lua",
      moveCount = Versions.MOVES_COUNT or 355,
      tagCount = 0,
      version = BattleAnimExtract.FORMAT_VERSION,
      skipped = true,
    }
  end

  local scriptsPath = opts.scriptsPath or pret_scripts_path()
  local pack

  if scriptsPath then
    local src = read_file(scriptsPath)
    if src then
      pack = parse_scripts_file(src)
      print("[battle_anim_extract] parsed", scriptsPath, "moves", pack.moveSymbols and #pack.moveSymbols or 0)
    end
  end

  if not pack then
    pack = {
      version = BattleAnimExtract.FORMAT_VERSION,
      moves = {},
      status = {},
      general = {},
      special = {},
      labels = {},
      tags = {},
    }
    for id = 0, (Versions.MOVES_COUNT or 355) do
      pack.moves[id] = GENERIC
    end
    print("[battle_anim_extract] no pret scripts; wrote generic IR for all moves")
  else
    for id = 0, (Versions.MOVES_COUNT or 355) do
      if not pack.moves[id] then
        pack.moves[id] = GENERIC
      end
    end
  end

  pack.version = BattleAnimExtract.FORMAT_VERSION
  pack.tags = extract_tag_pngs(cache, root, pret_sprites_dir())

  -- Strip label bodies' trailing `end` if they also `return` (call/return)
  -- Already handled in parse_ops for return without forcing end onto return-only... 

  local lua = "return " .. serialize_value(pack) .. "\n"
  local outRel = root .. "/pack.lua"
  if cache and cache.write then
    cache:write(outRel, lua)
  elseif opts.outPath then
    local f = assert(io.open(opts.outPath, "wb"))
    f:write(lua)
    f:close()
  end

  return {
    path = outRel,
    moveCount = pack.moveSymbols and #pack.moveSymbols or (Versions.MOVES_COUNT or 355),
    tagCount = 0,
    version = BattleAnimExtract.FORMAT_VERSION,
  }
end

return BattleAnimExtract
