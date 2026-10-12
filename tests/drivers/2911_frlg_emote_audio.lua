local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/2911_frlg_emote_audio"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " 2911_frlg_emote_audio failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local OAK = 4

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Objects = require("src.core.game3.objects")
  local FieldEffects = require("src.core.game3.field_effects")
  local Message = require("src.ui.game3.message")
  local Audio = require("src.core.game3.audio")
  local Songs = require("src.core.game3.song_ids").forVersion("firered")
  local F = Flags.forVersion("firered")
  if not check(Runtime.getSession() ~= nil, "new game reached the field") then return finish() end

  local function setup()
    Flags.setFlag(Space.store, Space.vm.ctx, F.IDS.FLAG_HIDE_OAK_IN_HIS_LAB, false)
    Flags.setFlag(Space.store, Space.vm.ctx, F.IDS.FLAG_HIDE_RIVAL_IN_LAB, true)
    Flags.setFlag(Space.store, Space.vm.ctx, F.IDS.FLAG_HIDE_POKEDEX, false)
    Flags.setVar(Space.store, Space.vm.ctx, F.VAR_IDS.VAR_MAP_SCENE_PALLET_TOWN_PROFESSOR_OAKS_LAB, 5)
    Flags.setVar(Space.store, Space.vm.ctx, F.VAR_IDS.VAR_MAP_SCENE_VIRIDIAN_CITY_MART, 1)
  end
  Map.load(nil, game, "FR_OAKS_LAB", { x = 6, y = 4, facing = "up" })
  U.wait(30)
  if not check(Space.vm ~= nil and Space.store ~= nil, "script VM active in FR_OAKS_LAB") then return finish() end
  setup()
  Map.load(nil, game, "FR_OAKS_LAB", { x = 6, y = 4, facing = "up" })
  local s = Runtime.getSession()
  s.x, s.y, s.facing = 6, 4, "up"
  U.wait(60)
  setup()
  local oak = Objects.find(OAK)
  if not check(oak ~= nil and oak.cellX == 6 and oak.cellY == 3, "Oak stands at (6,3)") then return finish() end

  local frame = 0
  local emoteAt, emoteDoneAt, textAt, emoteTrack
  local fadeState
  local origEmote = FieldEffects.startEmote
  FieldEffects.startEmote = function(obj, kind, cb)
    if obj == oak and not emoteAt then
      emoteAt = frame
      emoteTrack = Objects._tracks[OAK]
    end
    return origEmote(obj, kind, cb)
  end
  local origFade = Audio.fadeDefaultBgm
  Audio.fadeDefaultBgm = function(...)
    local before = Audio._currentSong and Audio._currentSong.id
    local r = origFade(...)
    if not fadeState then
      fadeState = {
        before = before,
        after = Audio._currentSong and Audio._currentSong.id,
        fading = Audio._fadeOut ~= nil,
        nextSong = Audio._fadeOut and Audio._fadeOut.nextSong,
        logical = Audio.currentMapMusic(),
        hasSource = Audio._bgmSource ~= nil,
      }
    end
    return r
  end

  U.tap(game, "a")
  for _ = 1, 30 do
    if Space.vm:isRunning() then break end
    U.wait(1)
  end
  if not check(Space.vm:isRunning(), "talking to Oak starts his script") then return finish() end

  local wasOpen = false
  local shotEmote = false
  for _ = 1, 6000 do
    frame = frame + 1
    local open = Message.isOpen and Message.isOpen()
    if emoteAt and not emoteDoneAt then
      if not emoteTrack or emoteTrack.done or Objects._tracks[OAK] ~= emoteTrack then emoteDoneAt = frame end
    end
    if emoteAt and not shotEmote and frame - emoteAt == 20 then
      shotEmote = U.still(game, DIR .. "/2911_01_oak_exclamation.png")
    end
    if emoteAt and open and not wasOpen and not textAt then
      textAt = frame
      break
    end
    wasOpen = open
    if not emoteAt and open and frame % 6 == 0 then
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  FieldEffects.startEmote = origEmote
  Audio.fadeDefaultBgm = origFade

  check(fadeState ~= nil, "fadedefaultbgm ran after the rival walked in")
  if fadeState then
    print(string.format("audio before=%s after=%s fading=%s next=%s logical=%s source=%s",
      tostring(fadeState.before), tostring(fadeState.after), tostring(fadeState.fading),
      tostring(fadeState.nextSong), tostring(fadeState.logical), tostring(fadeState.hasSource)))
    check(fadeState.before == Songs.MUS_ENCOUNTER_RIVAL, "rival encounter music playing before fadedefaultbgm")
    if fadeState.hasSource then
      check(fadeState.after == Songs.MUS_ENCOUNTER_RIVAL and fadeState.fading,
        "fadedefaultbgm fades the rival music out instead of cutting it")
      check(fadeState.nextSong == Songs.MUS_OAK_LAB, "MUS_OAK_LAB queued behind the fade")
    end
    check(fadeState.logical == Songs.MUS_OAK_LAB, "current map music reads MUS_OAK_LAB after fadedefaultbgm")
  end
  check(emoteAt ~= nil, "Oak exclamation emote started")
  if emoteAt then
    local moveFrames = emoteDoneAt and (emoteDoneAt - emoteAt) or -1
    local toText = textAt and (textAt - emoteAt) or -1
    print(string.format("emote movement frames=%d emote->Oak text frames=%d", moveFrames, toText))
    check(moveFrames >= 0 and moveFrames <= 3, "emote_exclamation_mark movement finishes within 3 frames (got " .. moveFrames .. ")")
    check(toText > 0 and toText <= 70, "Oak's next text opens within 70 frames of the emote (got " .. toText .. ")")
  end
  return finish()
end
