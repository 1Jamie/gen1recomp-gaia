package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local FsIo = require("tests.fs_io")
local Constants = require("src.core.game3.constants")

local NAMES = {}
for _, game in ipairs({ "firered", "emerald" }) do
  for k in pairs(Constants.of(game).songs.byName) do NAMES[k] = true end
end

local CALLS = {
  "playSe", "playFanfare", "playSong", "playMapSong", "fadeOutAndPlay",
  "changeMusicTo", "fadeInBgm", "se", "sfx", "playSE",
}

local SKIP = {
  ["src/core/game3/se_ids.lua"] = true,
}

local ALLOW = {
  ["src/core/game3/battle_bridge.lua"] = 2,
  ["src/core/game3/battle/evo_seq.lua"] = 1,
  ["src/core/game3/battle/exp_seq.lua"] = 1,
  ["src/core/game3/battle/init.lua"] = 1,
  ["src/core/game3/battle/pokedude.lua"] = 2,
  ["src/core/game3/field_effects.lua"] = 3,
  ["src/core/game3/item_use.lua"] = 1,
  ["src/core/game3/scripting/natives_elevator.lua"] = 2,
  ["src/ui/game3/box_storage_ui.lua"] = 48,
  ["src/ui/game3/naming.lua"] = 5,
  ["src/ui/game3/pc_menu.lua"] = 30,
  ["src/ui/game3/shop_menu.lua"] = 22,
  ["src/ui/game3/summary_menu.lua"] = 11,
}

local function relPath(path)
  local i = path:find("src/", 1, true)
  return i and path:sub(i) or path
end

local function scanLine(code)
  for _, f in ipairs(CALLS) do
    local n = code:match("[^%w_%.]" .. f .. "%(%s*(%d+)") or code:match("^" .. f .. "%(%s*(%d+)")
      or code:match("[%.:]" .. f .. "%(%s*(%d+)")
    if n and not (f:find("Song", 1, true) and n == "0") then
      return f .. "(" .. n .. ")"
    end
  end
  for name in code:gmatch("([%u][%u%d_]*)%s*=%s*%d") do
    if NAMES[name] then return name .. " = <number>" end
  end
  if code:match("role%b()%s*or%s*%d") then return "role(...) or <number>" end
  return nil
end

local function scan(path)
  local hits = {}
  local ln = 0
  for line in io.lines(path) do
    ln = ln + 1
    local code = line:gsub("%-%-.*$", "")
    local hit = scanLine(code)
    if hit then hits[#hits + 1] = ln .. ": " .. hit end
  end
  return hits
end

do
  check(scanLine("  se(5)") ~= nil, "gate sees se(5)")
  check(scanLine("Audio.playSe(207)") ~= nil, "gate sees Audio.playSe(207)")
  check(scanLine("local MUS_TITLE = 278") ~= nil, "gate sees a local MUS_ constant")
  check(scanLine("Sim.SE_SELECT = 5") ~= nil, "gate sees a module SE_ field")
  check(scanLine("return Audio.role(\"battleWild\") or 298") ~= nil, "gate sees a numeric role fallback")
  check(scanLine("Audio.playSong(0)") == nil, "playSong(0) is the stop sentinel")
  check(scanLine("se(SE.SE_SELECT)") == nil, "named ids pass")
  check(scanLine("Audio.SE_RAW_MAX_FRAMES = 1500000") == nil, "non-song SE_ names pass")
  check(scanLine("close(5)") == nil, "close(5) is not se(5)")
end

local files = {}
for _, dir in ipairs({ "src/core/game3", "src/ui/game3" }) do
  for _, path in ipairs(FsIo.luaFilesUnder(dir)) do
    local rel = relPath(path)
    if not rel:find("/constants/", 1, true) and not SKIP[rel] then files[#files + 1] = { path, rel } end
  end
end
check(#files > 100, "scanned the game3 sources (" .. #files .. " files)")

local seen = {}
for _, f in ipairs(files) do
  local hits = scan(f[1])
  local allow = ALLOW[f[2]] or 0
  seen[f[2]] = #hits
  check(#hits <= allow, string.format("%s: %d numeric song/SE ids (allowed %d)%s", f[2], #hits, allow,
    #hits > allow and (" " .. table.concat(hits, ", ", 1, math.min(#hits, 6))) or ""))
end
for rel in pairs(ALLOW) do
  check(seen[rel] ~= nil, "allow-listed file exists: " .. rel)
end

T.finish("game3_no_numeric_song_ids_test")
