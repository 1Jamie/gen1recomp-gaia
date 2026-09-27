local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_intro_frames"
local LAST = tonumber(os.getenv("EM_INTRO_LAST")) or 3800
local EVERY = os.getenv("EM_INTRO_EVERY") == "1"
local FROM = tonumber(os.getenv("EM_INTRO_FROM")) or 0
local PRESS = {}
for n in (os.getenv("EM_INTRO_PRESS") or ""):gmatch("%d+") do PRESS[tonumber(n)] = true end

local LANDMARKS = {
  { 2, "copyright_fadein" }, { 140, "copyright_hold_end" }, { 200, "scene1_fadein" },
  { 330, "gf_logo" }, { 470, "gf_blend_out" }, { 800, "sparkles_pan" }, { 1060, "flygon_silhouette" },
  { 1300, "scene2_start" }, { 1700, "scene2_mid" }, { 2100, "scene2_torchic" }, { 2290, "scene3_pokeball" },
  { 2440, "scene3_groudon" }, { 2560, "scene3_kyogre" }, { 2870, "scene3_clouds" }, { 3140, "scene3_rayquaza" },
  { 3300, "title_logo" }, { 3700, "title_settle" },
}

return function(game)
  local ok = true
  local function check(c, label)
    print((c and "PASS " or "FAIL ") .. label)
    if not c then ok = false end
  end
  os.execute('mkdir -p "' .. DIR .. '"')
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil and game.boot.custom ~= nil, "rse boot modules active")
  if not (game.boot and game.boot.custom) then
    love.event.quit(1)
    return
  end
  local BootModules = require("src.ui.game3.boot_modules")
  local want = {}
  for _, l in ipairs(LANDMARKS) do want[l[1]] = l[2] end
  local frame = 0
  local sceneAt, gender, lastTag = {}, nil, nil
  local function dump(name)
    local obj = BootModules.active(game.boot)
    if not (obj and obj.snapshot) then return end
    local data = obj:snapshot()
    local f = io.open(string.format("%s/%s.png", DIR, name), "wb")
    if f then
      f:write(data:encode("png"):getString())
      f:close()
    end
  end
  while frame < LAST do
    if PRESS[frame + 1] then
      U.tap(game, "a")
    else
      U.wait(1)
    end
    frame = frame + 1
    local c = game.boot and game.boot.custom
    local obj = c and BootModules.active(game.boot)
    local tag = c and (c.intro and ("intro:" .. tostring(c.intro.scene)) or c.title and ("title:" .. tostring(c.title.phase)) or "other")
    if tag and tag ~= lastTag then
      sceneAt[tag] = sceneAt[tag] or frame
      print(string.format("[timeline] f=%d %s", frame, tag))
      lastTag = tag
    end
    if c and c.intro and gender == nil and c.intro.scene == "scene1" then
      gender = c.intro.gender
      print("[timeline] intro gender " .. tostring(gender))
    end
    if EVERY and frame >= FROM then dump(string.format("f%05d", frame)) end
    if want[frame] then dump(string.format("f%05d_%s", frame, want[frame])) end
  end
  for _, obj in ipairs({ game.boot.custom.intro, game.boot.custom.title }) do
    for _, e in ipairs(obj and obj.log or {}) do
      print(string.format("[log] %s f=%s %s", obj == game.boot.custom.intro and "intro" or "title", tostring(e.frame), tostring(e.what)))
    end
  end
  check(sceneAt["intro:scene1"] ~= nil, "intro reached scene 1")
  check(sceneAt["intro:scene2"] ~= nil, "intro reached scene 2")
  check(sceneAt["intro:scene3"] ~= nil, "intro reached scene 3")
  check(sceneAt["title:phase1"] ~= nil, "title reached phase 1")
  check(gender == 1, "cold boot intro rider is May (gender " .. tostring(gender) .. ")")
  love.event.quit(ok and 0 or 1)
end
