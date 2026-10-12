local GameVersion = require("src.core.GameVersion")
local Policy = require("src.online.xgen.Policy")
local Strings = require("src.core.Strings")

local Caps = {}

local NO_MODS = {}

Caps.MODS_TEXT = Strings.source("Mods that change link play are on, so this game can't go online.")

function Caps.gameplayMods(game)
  if type(game) ~= "table" or not game.mods then return false end
  local ok, ArenaData = pcall(require, "src.online.ArenaData")
  if not ok then return true end
  local okB, blockers = pcall(ArenaData.onlineBlockers3, game)
  if not okB or type(blockers) ~= "table" then return true end
  return #blockers > 0
end

function Caps.fingerprint(data, gen)
  if type(data) ~= "table" then return nil end
  local Fingerprint = require("src.link.Fingerprint")
  local ok, fp = pcall(Fingerprint.compute, data, NO_MODS, gen)
  if not ok or type(fp) ~= "string" then return nil end
  return fp:lower()
end

function Caps.compute(ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local version = ctx.version
  local gen = GameVersion.VERSIONS[version or ""] and GameVersion.generation(version) or nil
  local out = { proto = Policy.PROTO, policy = Policy.VERSION, gens = {} }
  if not gen or (ctx.gen ~= nil and ctx.gen ~= gen) then return out end
  local blocked = ctx.gameplayMods
  if blocked == nil then blocked = Caps.gameplayMods(ctx.game) end
  if blocked then return out end
  local fp = ctx.vanillaFingerprint or Caps.fingerprint(ctx.data or (ctx.game and ctx.game.data), gen)
  if type(fp) ~= "string" or not fp:match("^[0-9a-f]+$") or #fp > 64 then return out end
  out.gens[tostring(gen)] = { { version = version, fp = fp } }
  return out
end

function Caps.list(caps, gen)
  if type(caps) ~= "table" or type(caps.gens) ~= "table" then return {} end
  return caps.gens[tostring(gen)] or caps.gens[gen] or {}
end

function Caps.has(caps, gen, version, fp)
  for _, e in ipairs(Caps.list(caps, gen)) do
    if e.version == version and (fp == nil or e.fp == fp) then return true end
  end
  return false
end

function Caps.empty(caps)
  for gen = 1, 3 do
    if #Caps.list(caps, gen) > 0 then return false end
  end
  return true
end

return Caps
