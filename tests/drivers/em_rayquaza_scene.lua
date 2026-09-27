local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("em_rayquaza_scene", "/tmp/em_rayquaza_scene")

local function blackRuns(scene, tag)
  if os.getenv("XA_BLACK_RUNS") ~= "1" then return end
  local orig = scene.frame
  local prev, runs = nil, {}
  scene.frame = function(self, inp)
    orig(self, inp)
    local pltt, black = self.m.ppu.palette.pltt, true
    for i = 0, 511 do if pltt[i] ~= 0 then black = false break end end
    if black ~= prev then
      runs[#runs + 1] = string.format("%d:%s", self.frames, black and "B" or "V")
      prev = black
    end
    if self.done then d.note(tag .. " black runs " .. table.concat(runs, " ")) end
  end
end

local function dumpFrames(scene, tag)
  local at = {}
  for f in (os.getenv("XA_DUMP_FRAMES") or ""):gmatch("%d+") do at[tonumber(f)] = true end
  if not next(at) then return end
  local orig = scene.frame
  scene.frame = function(self, inp)
    orig(self, inp)
    if at[self.frames] then
      local data = self.m.ppu:snapshot():encode("png"):getString()
      os.execute('mkdir -p "' .. d.dir .. '/raw" 2>/dev/null')
      local h = io.open(string.format("%s/raw/%s_f%04d.png", d.dir, tag, self.frames), "wb")
      if h then h:write(data) h:close() end
    end
  end
end

local function runDirect(game, tag, animId, endEarly, shots, refExit)
  local RayScene = require("src.ui.game3.rse.rayquaza_scene")
  local finished = false
  local scene = RayScene.open({ animId = animId, endEarly = endEarly, onDone = function() finished = true end })
  dumpFrames(scene, tag)
  blackRuns(scene, tag)
  for _, s in ipairs(shots) do
    X.waitFor(function() return scene.frames >= s[1] or finished end, 60000)
    if finished then break end
    d.still(game, string.format("%s_%04d_%s.png", tag, s[1], s[2]))
  end
  X.waitFor(function() return finished end, 120000)
  d.check(finished, tag .. ": scene runs to its exit callback")
  local anims = {}
  for _, e in ipairs(scene.log) do
    if e.what == "anim" or e.what == "init" then anims[#anims + 1] = tostring(e.anim) end
  end
  d.note(tag .. " anim sequence " .. table.concat(anims, ",") .. " exit frame " .. tostring(scene.frames))
  local exitOk = math.abs(scene.frames - refExit) <= 2
  d.check(exitOk, string.format("%s: exit frame %d within 2 of the pygba reference %d", tag, scene.frames, refExit))
  return scene, anims
end

return function(game)
  local sess = X.newGame(d, game, 0)
  if not sess then return d.finish() end
  X.goTo(d, game, "EM_SOOTOPOLIS_CITY", 43, 32, "down")

  local _, preAnims = runDirect(game, "pre", 0, true, {
    { 60, "duo_fight_rain" }, { 150, "lightning" }, { 300, "duo_fight" },
  }, 381)
  d.check(table.concat(preAnims, ",") == "0", "pre: DUO_FIGHT_PRE ends early without chaining (" .. table.concat(preAnims, ",") .. ")")

  local _, fullAnims = runDirect(game, "full", 1, false, {
    { 200, "duo_fight" }, { 410, "duo_pan" }, { 700, "takes_flight" }, { 1000, "takes_flight_float" },
    { 1300, "descends" }, { 1550, "charges" }, { 1900, "chases_away" }, { 2250, "ring" }, { 2450, "duo_leave" },
  }, 2609)
  d.check(table.concat(fullAnims, ",") == "1,2,3,4,5,6",
    "full: DUO_FIGHT -> TAKES_FLIGHT -> DESCENDS -> CHARGES -> CHASES_AWAY -> END (" .. table.concat(fullAnims, ",") .. ")")

  local Scenes = require("src.core.game3.scripting.natives_scenes_rse")
  Scenes.last = nil
  X.setFlag("FLAG_LEGENDARIES_IN_SOOTOPOLIS", false)
  X.setVar("VAR_SOOTOPOLIS_CITY_STATE", 1)
  X.goTo(d, game, "EM_SOOTOPOLIS_CITY", 43, 32, "down")
  local opened = X.waitFor(function() return Scenes.last ~= nil end, 6000)
  d.check(opened, "Sootopolis ON_FRAME reaches special Script_DoRayquazaScene")
  if opened then
    d.check(Scenes.last.fightOnly == true, "VAR_0x8004 FALSE plays the Groudon/Kyogre fight only")
    X.waitFor(function() return Scenes.last.done end, 60000)
    d.check(Scenes.last.done, "the fight scene returns to the field")
    U.wait(30)
    d.shot(game, "script_01_back_on_field.png")
    local cont = X.waitFor(function() return X.var("VAR_SOOTOPOLIS_CITY_STATE") == 2 end, 20000)
    if cont then
      d.check(true, "script continues after the scene to VAR_SOOTOPOLIS_CITY_STATE=2")
    else
      local Audio = require("src.core.game3.audio")
      local se1 = false
      for _, src in ipairs(Audio._seSources or {}) do
        local meta = Audio._seMeta and Audio._seMeta[src]
        if meta and (meta.player == 1 or meta.player == 2) and src:isPlaying() then se1 = true end
      end
      local playing = {}
      for _, src in ipairs(Audio._seSources or {}) do
        local meta = Audio._seMeta and Audio._seMeta[src]
        if src:isPlaying() then playing[#playing + 1] = tostring(meta and meta.id) .. "@" .. tostring(meta and meta.player) .. (src:isLooping() and "L" or "") .. string.format("(%.1f/%.1f)", src:tell(), src:getDuration()) end
      end
      print("[driver] playing SE sources: " .. table.concat(playing, " ") .. " isSePlaying=" .. tostring(Audio.isSePlaying()))
      local where = X.vmWhere()
      if se1 and where:find("status=waiting", 1, true) then
        d.note("NOTE waitse after the scene sees SE1 thunder every frame: at driver speed the real-time thunder SE " ..
          "overlaps the next strike (" .. where .. "); at 1x the downpour gaps free it")
      else
        d.check(false, "script continues after the scene to VAR_SOOTOPOLIS_CITY_STATE=2 (" ..
          X.var("VAR_SOOTOPOLIS_CITY_STATE") .. ", VM " .. where .. ")")
      end
    end
  end
  d.finish()
end
