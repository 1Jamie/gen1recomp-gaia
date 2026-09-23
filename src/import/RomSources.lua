local GameVersion = require("src.core.GameVersion")
local SaveData = require("src.core.SaveData")

local RomSources = {}

RomSources.KEEP_DIR = "roms"

local function records(opts)
  local t = type(opts) == "table" and opts.romSources or nil
  return type(t) == "table" and t or {}
end

local function sha1(data)
  local digest = love.data.hash("sha1", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest)
end

function RomSources.promptsAllowed()
  if os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER") then
    return false
  end
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then return false end
  if os.getenv("POKEPORT_IMPORT_ROM") then return false end
  return true
end

function RomSources.isAbsolute(path)
  if type(path) ~= "string" or path == "" then return false end
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
    or path:sub(1, 2) == "\\\\"
end

function RomSources.absolute(path)
  if type(path) ~= "string" or path == "" then return nil end
  if RomSources.isAbsolute(path) then return path end
  local cwd = love.filesystem.getWorkingDirectory
    and love.filesystem.getWorkingDirectory()
  if type(cwd) ~= "string" or cwd == "" then return nil end
  return cwd:gsub("[/\\]$", "") .. "/" .. path:gsub("^%./", "")
end

function RomSources.shortPath(path)
  if type(path) ~= "string" then return "" end
  local parts = {}
  for part in path:gmatch("[^/\\]+") do parts[#parts + 1] = part end
  if #parts <= 2 then return path end
  return parts[#parts - 1] .. "/" .. parts[#parts]
end

function RomSources.keptPath(version)
  local gen = GameVersion.generation(version)
  local ext = ".gb"
  if gen == 3 then
    ext = ".gba"
  elseif version == "yellow" or gen == 2 then
    ext = ".gbc"
  end
  return RomSources.KEEP_DIR .. "/" .. version .. ext
end

function RomSources.get(version, opts)
  local rec = records(opts or SaveData.loadOptions())[version]
  return type(rec) == "table" and rec or nil
end

function RomSources.remember(version, rec)
  local all = {}
  for k, v in pairs(records(SaveData.loadOptions())) do all[k] = v end
  all[version] = rec
  return SaveData.saveOptions({ romSources = all })
end

function RomSources.keep(version, data)
  local path = RomSources.keptPath(version)
  love.filesystem.createDirectory(RomSources.KEEP_DIR)
  local ok = love.filesystem.write(path, data)
  if not ok then return nil end
  return path
end

function RomSources.autoReimport(opts)
  opts = opts or SaveData.loadOptions()
  return type(opts) == "table" and opts.autoReimport == true
end

function RomSources.setAutoReimport(on)
  return SaveData.saveOptions({ autoReimport = on == true })
end

function RomSources.forgetAll(opts)
  for _, rec in pairs(records(opts)) do
    if type(rec) == "table" and rec.kept and type(rec.path) == "string" then
      love.filesystem.remove(rec.path)
    end
  end
  if love.filesystem.getInfo(RomSources.KEEP_DIR, "directory") then
    for _, name in ipairs(love.filesystem.getDirectoryItems(RomSources.KEEP_DIR)) do
      love.filesystem.remove(RomSources.KEEP_DIR .. "/" .. name)
    end
    love.filesystem.remove(RomSources.KEEP_DIR)
  end
  opts.romSources = nil
end

function RomSources.count(opts)
  local n = 0
  for _, rec in pairs(records(opts)) do
    if type(rec) == "table" then n = n + 1 end
  end
  return n
end

local function readSource(rec)
  if rec.kept then
    local data = love.filesystem.read(rec.path)
    return type(data) == "string" and data or nil
  end
  local file = io.open(rec.path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

function RomSources.candidate(version, mobile, opts)
  local rec = RomSources.get(version, opts)
  if not rec or type(rec.sha1) ~= "string" then return nil end
  if type(rec.path) ~= "string" then
    if mobile then return { pick = true } end
    return nil
  end
  local ok, data = pcall(readSource, rec)
  if not ok or not data then return nil end
  local okHash, digest = pcall(sha1, data)
  if not okHash or digest ~= rec.sha1 then return nil end
  return { path = rec.path, kept = rec.kept == true }
end

return RomSources
