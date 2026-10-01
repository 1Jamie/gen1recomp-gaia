local K = require("tests.save_compat._codec")
local Diff = require("tests.save_compat._diff")
local Expect = require("tests.save_compat._expect")

local R2 = {}

R2.ROOTS = {
  [1] = { "player", "money", "coins", "currentBox", "playTime", "inventory", "pcItems", "pokedex", "party",
          "boxes", "hallOfFame", "lastHeal", "options", "visited", "pikachuHappiness", "flags", "safari", "daycare",
          "forcedBike", "usedPokecenter", "trashPuzzle", "labFossilMon", "hiddenTaken", "surfingHighScore",
          "flashLit", "onBike", "pikachuMood", "pikachuEmotionModifier" },
  [2] = { "player", "rival", "mom", "party", "boxes", "inventory", "currentBox", "pokedex", "position",
          "playTime", "events", "mapScenes", "engineFlags", "boxNames", "variableSprites" },
  [3] = { "name", "trainerId", "secretId", "gender", "money", "coins", "map", "x", "y", "party", "storage",
          "bag", "roamer", "encryptionKey", "dex" },
}

R2.EXCLUDED = {
  cartExtra = "Gen 3 per-mon carrier of raw cart bytes, regenerated on import",
  cartImport = "Gen 3 marker set by every import",
  rawImport = "Gen 1 template string, dropped on purpose for a templateless export",
  warnings = "decode diagnostics",
}

local function fmt(v)
  if type(v) == "number" and v ~= math.floor(v) then return ("%.4f"):format(v) end
  return tostring(v)
end

local function flatten(v, path, out)
  if type(v) ~= "table" then
    out[path] = fmt(v)
    return
  end
  local any = false
  for k, x in pairs(v) do
    if not (type(k) == "string" and R2.EXCLUDED[k]) then
      any = true
      local seg = type(k) == "number" and ("[" .. k .. "]") or ("." .. tostring(k))
      flatten(x, path .. seg, out)
    end
  end
  if not any then out[path] = "{}" end
end

function R2.project(gen, save)
  local out = {}
  for _, root in ipairs(R2.ROOTS[gen]) do
    if save[root] ~= nil then flatten(save[root], root, out) end
  end
  return out
end

function R2.run(T, gen, cases)
  local track = Expect.new("r2")
  local verbose = os.getenv("SAVE_COMPAT_VERBOSE") == "1"
  for _, c in ipairs(cases) do
    track.case(c.id)
    local want = R2.project(gen, c.save)
    local out, err = K.export(gen, c.version, c.save, false)
    if not out then
      track.fail(c.id, "export", err)
    else
      for _, k in ipairs(K.compatKeys(out, c.version)) do track.fail(c.id, k.key, k.detail) end
      local back, ierr = K.import(gen, c.version, out)
      if not back then
        track.fail(c.id, "reimport", ierr)
      else
        local got = R2.project(gen, back)
        local paths = {}
        for p in pairs(want) do paths[#paths + 1] = p end
        table.sort(paths)
        for _, p in ipairs(paths) do
          if got[p] ~= want[p] then
            local key = "field:" .. p:gsub("%[%d+%]", "[]")
            track.fail(c.id, key, ("%s: %s -> %s"):format(p, want[p], tostring(got[p])))
            if verbose then print(c.id, p, want[p], got[p]) end
          end
        end
        for _, f in ipairs(c.extra and c.extra(back, out) or {}) do track.fail(c.id, f[1], f[2]) end
        local again, aerr = K.export(gen, c.version, back, false)
        if not again then
          track.fail(c.id, "fixedpoint-export", aerr)
        elseif again ~= out then
          local entries = K.r1Diff(gen, c.version, out, again)
          if #entries == 0 then entries = { { name = "derived", count = 0, first = 0, last = 0, sample = {} } } end
          for _, e in ipairs(entries) do track.fail(c.id, "fixedpoint:" .. e.name, Diff.format({ e })) end
        end
      end
    end
  end
  track.finish(T)
end

return R2
