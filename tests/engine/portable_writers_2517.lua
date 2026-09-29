package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("portable writers 2517")
local check, eq = S.check, S.eq

local FsIo = require("tests.fs_io")
local SaveData = require("src.core.SaveData")

local WIN = FsIo.isWindows

local function mkdirp(path)
  if WIN then
    os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
  end
end

local function rmrf(path)
  if WIN then
    os.execute('rmdir /s /q "' .. path:gsub("/", "\\") .. '" 2>nul')
  else
    os.execute('chmod -R u+w "' .. path .. '" 2>/dev/null')
    os.execute('rm -rf "' .. path .. '" 2>/dev/null')
  end
end

local function exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local OWNED = {
  "src/core/SaveData.lua",
  "src/import/CacheFs.lua",
  "src/import/RomSources.lua",
  "src/import/RomImporter.lua",
  "src/core/Printer.lua",
  "src/render/ShaderFX.lua",
  "src/core/TouchSkin.lua",
  "src/import/LauncherSettings.lua",
  "src/import/LauncherView.lua",
}

local WRITERS = { "write", "newFile", "createDirectory", "append" }
local REMOVERS = { "remove" }

local SAVEDIR_BRANCH = "non-portable save-dir branch"
local PICKER_TEMP = "picker/export temp file in the save dir"
local STALE_CACHE = "stale save-dir cache cleanup"
local REQUIRED_IMPORT = "required-import staging file in the save dir"

local ALLOW = {
  ["src/import/CacheFs.lua"] = {
    { reason = SAVEDIR_BRANCH, pat = "love%.filesystem%.createDirectory%(curRel%)", n = 1 },
    { reason = SAVEDIR_BRANCH, pat = "love%.filesystem%.createDirectory%(parent%)", n = 1 },
    { reason = SAVEDIR_BRANCH, pat = "love%.filesystem%.write%(rel, data%)", n = 1 },
    { reason = SAVEDIR_BRANCH, pat = "love%.filesystem%.newFile%(rel%)", n = 1 },
    { reason = SAVEDIR_BRANCH, pat = "love%.filesystem%.remove%(rel%)", n = 2 },
    { reason = "legacy save-dir migration", pat = "^%s*local fs = love%.filesystem$", n = 1 },
  },
  ["src/core/Printer.lua"] = {
    { reason = SAVEDIR_BRANCH, pat = 'love%.filesystem%.createDirectory%("prints"%)', n = 1 },
  },
  ["src/render/ShaderFX.lua"] = {
    { reason = "shader download zip stays in the save dir", pat = "remove%(DOWNLOAD_ZIP_REL%)", n = 1 },
  },
  ["src/import/RomImporter.lua"] = {
    { reason = STALE_CACHE, pat = "love%.filesystem%.remove%(prefix %.%. CacheContract%.MARKER_PATH%)", n = 2 },
    { reason = STALE_CACHE, pat = "^%s*love%.filesystem%.remove%(path%)$", n = 4 },
    { reason = REQUIRED_IMPORT, pat = "love%.filesystem%.remove%(RequiredImports%.receiptPath", n = 3 },
    { reason = PICKER_TEMP, pat = "love%.filesystem%.remove%(preferred%)", n = 1 },
    { reason = PICKER_TEMP, pat = "love%.filesystem%.remove%(name%)", n = 1 },
    { reason = PICKER_TEMP, pat = 'love%.filesystem%.remove%("export_done%.flag"%)', n = 1 },
    { reason = PICKER_TEMP, pat = 'love%.filesystem%.remove%("pending_export%.sav"%)', n = 1 },
    { reason = PICKER_TEMP, pat = 'love%.filesystem%.write%("pending_export%.sav"', n = 2 },
    { reason = PICKER_TEMP, pat = 'love%.filesystem%.remove%("pick_error%.flag"%)', n = 1 },
    { reason = PICKER_TEMP, pat = 'love%.filesystem%.remove%("pick_error%.txt"%)', n = 1 },
    { reason = PICKER_TEMP, pat = "love%.filesystem%.remove%(PICK_COMPLETE_FILENAME%)", n = 1 },
    { reason = PICKER_TEMP, pat = "love%.filesystem%.remove%(importerName%)", n = 1 },
    { reason = PICKER_TEMP, pat = "love%.filesystem%.remove%(displayName%)", n = 1 },
    { reason = PICKER_TEMP, pat = "love%.filesystem%.remove%(st%.path%)", n = 1 },
    { reason = PICKER_TEMP, pat = "pcall%(love%.filesystem%.remove, path%)", n = 2 },
    { reason = PICKER_TEMP, pat = "love%.filesystem%.newFile%(path%)", n = 1 },
  },
}

local allowCounts = {}

local function allowed(file, line)
  for i, entry in ipairs(ALLOW[file] or {}) do
    if line:find(entry.pat) then
      allowCounts[file] = allowCounts[file] or {}
      allowCounts[file][i] = (allowCounts[file][i] or 0) + 1
      return true
    end
  end
  return false
end

local function callsBypass(line)
  if line:match("^%s*%-%-") then return false end
  if line:match("^%s*local%s+[%w_]+%s*=%s*love%.filesystem%s*$") then return true end
  for _, fn in ipairs(WRITERS) do
    if line:find("love%.filesystem%." .. fn .. "%s*%(")
        or line:find("pcall%(%s*love%.filesystem%." .. fn .. "%s*,") then
      return true
    end
  end
  for _, fn in ipairs(REMOVERS) do
    if line:find("love%.filesystem%." .. fn .. "%s*%(")
        or line:find("pcall%(%s*love%.filesystem%." .. fn .. "%s*,") then
      return true
    end
  end
  return false
end

for _, file in ipairs(OWNED) do
  local body = slurp(file)
  check(body ~= nil, "readable: " .. file)
  local bad = {}
  local n = 0
  for line in (body or ""):gmatch("([^\n]*)\n?") do
    n = n + 1
    if callsBypass(line) and not allowed(file, line) then
      bad[#bad + 1] = n .. ": " .. line:gsub("^%s+", "")
    end
  end
  eq(#bad, 0, file .. " has no love.filesystem writes bypassing persistenceFs"
    .. (#bad > 0 and (" (" .. table.concat(bad, " | ") .. ")") or ""))
  for i, entry in ipairs(ALLOW[file] or {}) do
    eq((allowCounts[file] or {})[i] or 0, entry.n,
      file .. " allow-list [" .. entry.reason .. "] " .. entry.pat .. " matches exactly " .. entry.n)
  end
end

local SHELL_ALLOW = {}

for _, file in ipairs(OWNED) do
  local body = slurp(file) or ""
  local bad = {}
  local n = 0
  for line in body:gmatch("([^\n]*)\n?") do
    n = n + 1
    if not line:match("^%s*%-%-")
        and (line:find("os%.execute") or line:find("io%.popen")) then
      local ok = false
      for _, pat in ipairs(SHELL_ALLOW[file] or {}) do
        if line:find(pat) then ok = true end
      end
      if not ok then bad[#bad + 1] = n .. ": " .. line:gsub("^%s+", "") end
    end
  end
  eq(#bad, 0, file .. " spawns no shell (os.execute / io.popen)"
    .. (#bad > 0 and (" (" .. table.concat(bad, " | ") .. ")") or ""))
end

local SANDBOX = ((os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp")
  :gsub("[/\\]+$", "")) .. ("/pokeport_2517_%d_%d"):format(os.time(), math.random(1, 999999))
local GAME = SANDBOX .. "/g\195\164me f\195\182lder"
local OTHER = SANDBOX .. "/elsewhere"
local SAVEDIR = SANDBOX .. "/appdata"
mkdirp(GAME)
mkdirp(OTHER)
mkdirp(SAVEDIR)

local function writeReal(path, body)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(body)
  f:close()
  return true
end

local savedFs = love.filesystem
local savedSystem = love.system
local savedRomSources = package.loaded["src.import.RomSources"]
local savedCacheFs = package.loaded["src.import.CacheFs"]

local function stubLove(source, sbd)
  local fs = {}
  for k, v in pairs(savedFs) do fs[k] = v end
  fs.getSource = function() return source end
  fs.getSourceBaseDirectory = function() return sbd end
  fs.getSaveDirectory = function() return SAVEDIR end
  love.filesystem = fs
  love.system = { getOS = function() return WIN and "Windows" or "Linux" end }
  SaveData._resetPortableCacheForTests()
end

local function saveDirEntries()
  local n = 0
  local list = FsIo.listDir(SAVEDIR)
  for _ in ipairs(list or {}) do n = n + 1 end
  return n
end

local function run()
  writeReal(GAME .. "/portable.txt", "")
  stubLove(OTHER .. "/x.exe", GAME)

  check(SaveData.isPortable(), "marker under a non-ASCII folder is detected")
  eq(SaveData.portableBaseDir(), GAME, "portable base is the game folder")
  local st = SaveData.portableStatus()
  eq(st.base, GAME, "portableStatus reports the base")
  check(#st.tried >= 1 and st.tried[1].marker == true and st.tried[1].writable == true,
    "portableStatus records marker and writable for the winning candidate")

  package.loaded["src.import.RomSources"] = nil
  local RomSources = require("src.import.RomSources")
  local path = RomSources.keep("red", "ROMBYTES")
  check(path ~= nil, "RomSources.keep succeeds in portable mode")
  eq(slurp(GAME .. "/roms/red.gb"), "ROMBYTES", "kept ROM lands in the game folder")
  check(RomSources.keptExists(path), "kept ROM is visible through the portable fs")
  eq(RomSources.readKept(path), "ROMBYTES", "kept ROM reads back")
  RomSources.removeKept(path)
  check(not exists(GAME .. "/roms/red.gb"), "kept ROM removal reaches the game folder")
  eq(saveDirEntries(), 0, "nothing was written to the OS save directory")

  local pfs = SaveData.portableFs()
  pfs.createDirectory("imports/saves/red")
  eq((pfs.getInfo("imports/saves/red") or {}).type, "directory",
    "portable getInfo reports directories")
  pfs.write("imports/saves/red/a.sav", "12345")
  local info = pfs.getInfo("imports/saves/red/a.sav", "file")
  eq(info and info.size, 5, "portable getInfo reports file size")
  eq(pfs.getInfo("imports/saves/red/a.sav", "directory"), nil,
    "portable getInfo honours the type filter")
  local items = pfs.getDirectoryItems("imports/saves/red")
  eq(#items, 1, "portable getDirectoryItems lists the file")
  eq(items[1], "a.sav", "portable getDirectoryItems names the file")

  local realExecute, realPopen = os.execute, io.popen
  local spawned = 0
  os.execute = function(...) spawned = spawned + 1; return realExecute(...) end
  io.popen = function(...) spawned = spawned + 1; return realPopen(...) end
  local spawnOk, spawnErr = pcall(function()
    local uni = "imports/pok\195\169 \195\188.gb"
    check(pfs.createDirectory("imports/n\195\182n/asc ii/deep") == true,
      "createDirectory builds a nested non-ASCII tree")
    check(pfs.getInfo("imports/n\195\182n/asc ii/deep", "directory") ~= nil,
      "nested non-ASCII directory exists")
    check(pfs.write(uni, "UNI") == true, "portable write to a non-ASCII file name succeeds")
    eq(pfs.read(uni), "UNI", "portable read of a non-ASCII file name round-trips")
    eq(slurp(GAME .. "/" .. uni), "UNI", "non-ASCII write lands in the non-ASCII game folder")
    local listed = pfs.getDirectoryItems("imports")
    local seen = false
    for _, name in ipairs(listed) do
      if name == "pok\195\169 \195\188.gb" then seen = true end
    end
    check(seen, "portable getDirectoryItems returns non-ASCII names as UTF-8")
    for _ = 1, 3 do
      pfs.createDirectory("shaders")
      pfs.getDirectoryItems("shaders")
    end
    pfs.remove(uni)
    check(pfs.getInfo(uni) == nil, "portable remove deletes the non-ASCII file")
    RomSources.keep("blue", "B")
    RomSources.removeKept(RomSources.keptPath("blue"))
    local RI = require("src.import.RomImporter")
    local inst = setmetatable({}, { __index = RI })
    RI.ensureSavesInboxDir(inst)
    RI.ensureImportsDir(inst)
    RI.scanInbox(inst)
    RI.scanInbox(inst)
  end)
  os.execute, io.popen = realExecute, realPopen
  check(spawnOk, "shell-free portable operations ran" .. (spawnOk and "" or (": " .. tostring(spawnErr))))
  eq(spawned, 0, "portable mkdir, list, read, write and inbox scans spawn no shell process")

  local RomImporter = require("src.import.RomImporter")
  check(RomImporter.ensureSavesInboxDir(setmetatable({}, { __index = RomImporter })) == true, "inbox dirs are created in portable mode")
  check(exists(GAME .. "/imports") or FsIo.isDir(GAME .. "/imports"),
    "imports/ lands in the game folder")
  eq(saveDirEntries(), 0, "inbox creation left the OS save directory empty")

  stubLove(OTHER .. "/x.exe", GAME)
  package.loaded["src.import.CacheFs"] = nil
  local CacheFs = require("src.import.CacheFs")
  CacheFs._resetPortableForTests()
  if CacheFs.root() == nil then
    check(CacheFs.portableError() ~= nil, "a failed portable mount records a reason")
    local ok, err = CacheFs.write("data/generated/x.lua", "return 1")
    eq(ok, false, "cache write refuses to fall back to the OS save directory")
    check(type(err) == "string" and err:find("portable"), "cache write error names portable mode")
    eq(saveDirEntries(), 0, "failed portable cache write left the OS save directory empty")
  end

  writeReal(OTHER .. "/portable.txt", "")
  stubLove(OTHER .. "/x.exe", OTHER)
  SaveData._resetPortableCacheForTests()
  check(SaveData.isPortable(), "control: writable folder with marker is portable")

  if not WIN then
    local RO = SANDBOX .. "/readonly"
    mkdirp(RO)
    writeReal(RO .. "/portable.txt", "")
    os.execute('chmod 555 "' .. RO .. '"')
    local probe = io.open(RO .. "/.probe", "wb")
    if probe then
      probe:close()
      os.remove(RO .. "/.probe")
    else
      stubLove(SANDBOX .. "/y.exe", RO)
      check(not SaveData.isPortable(), "marker in a read-only folder is rejected")
      local rs = SaveData.portableStatus()
      eq(rs.tried[1].marker, true, "rejected candidate still records the marker")
      eq(rs.tried[1].writable, false, "rejected candidate records not writable")
      eq(rs.tried[1].reason, "folder not writable", "rejection reason is observable")
    end
    os.execute('chmod 755 "' .. RO .. '"')
  end

  stubLove(SANDBOX .. "/nomarker.exe", SANDBOX .. "/nomarker")
  check(not SaveData.isPortable(), "no marker means not portable")
  eq(SaveData.portableStatus().tried[1].reason, "no portable.txt", "missing marker reason recorded")
end

local ok, err = pcall(run)

love.filesystem = savedFs
love.system = savedSystem
package.loaded["src.import.RomSources"] = savedRomSources
package.loaded["src.import.CacheFs"] = savedCacheFs
SaveData._resetPortableCacheForTests()
rmrf(SANDBOX)

if not ok then check(false, "suite raised: " .. tostring(err)) end

S.finish()
