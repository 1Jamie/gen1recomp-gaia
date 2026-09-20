local M = {}

local function readable(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function push(list, seen, path)
  if path and path ~= "" and not seen[path] then
    seen[path] = true
    list[#list + 1] = path
  end
end

local function candidates()
  local list, seen = {}, {}
  push(list, seen, os.getenv("POKEPORT_GBA_CACHE"))
  push(list, seen, "data/generated/gba")

  local home = os.getenv("HOME")
  if not home then return list end

  local saveRoots = {
    home .. "/Library/Application Support/LOVE",
    home .. "/.local/share/love",
  }
  local bases = {}
  local identity = os.getenv("POKEPORT_IDENTITY")
  if identity and identity ~= "" then bases[#bases + 1] = identity end
  bases[#bases + 1] = "pokemon-love2d"

  for _, saveRoot in ipairs(saveRoots) do
    for _, base in ipairs(bases) do
      push(list, seen, saveRoot .. "/" .. base .. "/firered/data/generated/gba")
    end
    local pipe = io.popen('ls -1t "' .. saveRoot .. '" 2>/dev/null')
    if pipe then
      for line in pipe:lines() do
        if line:find("firered", 1, true) then
          push(list, seen, saveRoot .. "/" .. line .. "/firered/data/generated/gba")
        end
      end
      pipe:close()
    end
  end
  return list
end

M._roots = {}

function M.root(marker)
  marker = marker or "meta.json"
  local memo = M._roots[marker]
  if memo ~= nil then
    if memo == false then return nil end
    return memo
  end
  for _, root in ipairs(candidates()) do
    if readable(root .. "/" .. marker) then
      M._roots[marker] = root
      return root
    end
  end
  M._roots[marker] = false
  return nil
end

function M.cache()
  return {
    read = function(_, rel)
      local f = io.open(rel, "rb")
      if not f then return nil end
      local data = f:read("*a")
      f:close()
      if type(data) == "string" and #data > 0 then return data end
      return nil
    end,
    exists = function(_, rel)
      return readable(rel)
    end,
  }
end

function M.mount(marker)
  local root = M.root(marker)
  if not root then return nil end
  local Dataset = require("src.core.game3.dataset")
  Dataset.cacheRootOverride = root
  Dataset.mountExtractRoots()
  return root
end

function M.mountOrSkip(label, marker)
  local root = M.mount(marker)
  if not root then
    print("[skip] " .. tostring(label) .. ": no imported FireRed cache found")
    os.exit(0)
  end
  print("[info] FireRed cache at " .. root)
  return root
end

function M.bundle(marker)
  local root = M.mount(marker)
  if not root then return nil end
  local ExtractScripts = require("src.import.gba.extract_scripts")
  local Space = require("src.core.game3.scripting.space")
  local bundle = ExtractScripts.loadBundle(M.cache(), root, { allowIncomplete = true })
  Space.bundle = bundle
  return bundle, root
end

return M
