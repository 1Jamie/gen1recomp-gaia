package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Constants = require("src.core.game3.constants")
local Song = require("src.core.game3.song_ids")
local P = require("src.core.game3.audio_policy_rse")

local EM = Song.forVersion("emerald")
local Cem = Constants.of("emerald")

local HEADERS = {
  LITTLEROOT_TOWN = EM.MUS_LITTLEROOT,
  ROUTE101 = EM.MUS_ROUTE101,
  OLDALE_TOWN = EM.MUS_OLDALE,
  ROUTE118 = EM.MUS_ROUTE118,
  ROUTE111 = EM.MUS_ROUTE120,
  MAUVILLE_CITY = EM.MUS_ROUTE104,
  SOOTOPOLIS_CITY = EM.MUS_SOOTOPOLIS,
  LILYCOVE_CITY = EM.MUS_LILYCOVE,
  EVER_GRANDE_CITY = EM.MUS_EVER_GRANDE,
  ROUTE129 = EM.MUS_ROUTE120,
  ROUTE132 = EM.MUS_ROUTE120,
  MOSSDEEP_CITY_SPACE_CENTER_1F = EM.MUS_POKE_CENTER,
  MOSSDEEP_CITY_SPACE_CENTER_2F = EM.MUS_POKE_CENTER,
  MOSSDEEP_CITY_GYM = EM.MUS_POKE_CENTER,
  ROUTE119_WEATHER_INSTITUTE_1F = EM.MUS_ROUTE120,
  ROUTE119_WEATHER_INSTITUTE_2F = EM.MUS_ROUTE120,
  ROUTE119_WEATHER_INSTITUTE_3F = EM.MUS_ROUTE120,
  POKEMON_CENTER = EM.MUS_POKE_CENTER,
}

local function ctx(o)
  o = o or {}
  local flags, vars = o.flags or {}, o.vars or {}
  return {
    songs = EM,
    location = P.location("EM_" .. (o.map or "LITTLEROOT_TOWN"), o.x or 5, o.y or 5, "EM_"),
    at = function(id, x, y) return P.location("EM_" .. id, x, y, "EM_") end,
    flag = function(n) return flags[n] == true end,
    var = function(n) return vars[n] or 0 end,
    weather = function(n) return Cem.weather.byName[n] end,
    savedWeather = function() return o.weather or 0 end,
    headerMusic = function(loc) return HEADERS[loc.map] or 0 end,
    isIndoor = function(loc) return loc.map == "POKEMON_CENTER" or loc.map == "MOSSDEEP_CITY_GYM" end,
    savedMusic = o.saved,
    currentMusic = o.current or 0,
    surfing = o.surfing == true,
    biking = o.biking == true,
    underwater = o.underwater == true,
  }
end

local function at(c, map, x, y) return c.at(map, x, y) end

-- pokeemerald/src/overworld.c:1082
local LOCATION_CASES = {
  { "plain header", {}, "LITTLEROOT_TOWN", EM.MUS_LITTLEROOT },
  { "Sootopolis silent while Sky Pillar state 1", { vars = { VAR_SKY_PILLAR_STATE = 1 } }, "SOOTOPOLIS_CITY", EM.MUS_NONE },
  { "Sootopolis silence beats the abnormal weather", { vars = { VAR_SKY_PILLAR_STATE = 1 }, flags = { FLAG_SYS_WEATHER_CTRL = true } }, "SOOTOPOLIS_CITY", EM.MUS_NONE },
  { "Sootopolis header at Sky Pillar state 0", {}, "SOOTOPOLIS_CITY", EM.MUS_SOOTOPOLIS },
  { "Sootopolis header at Sky Pillar state 2", { vars = { VAR_SKY_PILLAR_STATE = 2 } }, "SOOTOPOLIS_CITY", EM.MUS_SOOTOPOLIS },
  { "Sky Pillar state 1 leaves Lilycove alone", { vars = { VAR_SKY_PILLAR_STATE = 1 } }, "LILYCOVE_CITY", EM.MUS_LILYCOVE },
  { "abnormal weather in Lilycove", { flags = { FLAG_SYS_WEATHER_CTRL = true } }, "LILYCOVE_CITY", EM.MUS_ABNORMAL_WEATHER },
  { "abnormal weather in Ever Grande", { flags = { FLAG_SYS_WEATHER_CTRL = true } }, "EVER_GRANDE_CITY", EM.MUS_ABNORMAL_WEATHER },
  { "no weather control, Lilycove header", {}, "LILYCOVE_CITY", EM.MUS_LILYCOVE },
  { "Route 129 needs Sootopolis state 4", { flags = { FLAG_SYS_WEATHER_CTRL = true }, vars = { VAR_SOOTOPOLIS_CITY_STATE = 3 } }, "ROUTE129", EM.MUS_ROUTE120 },
  { "Route 129 abnormal at Sootopolis state 4", { flags = { FLAG_SYS_WEATHER_CTRL = true }, vars = { VAR_SOOTOPOLIS_CITY_STATE = 4 } }, "ROUTE129", EM.MUS_ABNORMAL_WEATHER },
  { "Route 132 never abnormal", { flags = { FLAG_SYS_WEATHER_CTRL = true }, vars = { VAR_SOOTOPOLIS_CITY_STATE = 4 } }, "ROUTE132", EM.MUS_ROUTE120 },
  { "Space Center before the invasion", {}, "MOSSDEEP_CITY_SPACE_CENTER_1F", EM.MUS_POKE_CENTER },
  { "Space Center 1F infiltrated (state 1)", { vars = { VAR_MOSSDEEP_CITY_STATE = 1 } }, "MOSSDEEP_CITY_SPACE_CENTER_1F", EM.MUS_ENCOUNTER_MAGMA },
  { "Space Center 2F infiltrated (state 2)", { vars = { VAR_MOSSDEEP_CITY_STATE = 2 } }, "MOSSDEEP_CITY_SPACE_CENTER_2F", EM.MUS_ENCOUNTER_MAGMA },
  { "Space Center after the invasion (state 3)", { vars = { VAR_MOSSDEEP_CITY_STATE = 3 } }, "MOSSDEEP_CITY_SPACE_CENTER_1F", EM.MUS_POKE_CENTER },
  { "Mossdeep state 1 only touches the Space Center", { vars = { VAR_MOSSDEEP_CITY_STATE = 1 } }, "MOSSDEEP_CITY_GYM", EM.MUS_POKE_CENTER },
  { "Weather Institute 1F infiltrated", {}, "ROUTE119_WEATHER_INSTITUTE_1F", EM.MUS_MT_CHIMNEY },
  { "Weather Institute 2F infiltrated", {}, "ROUTE119_WEATHER_INSTITUTE_2F", EM.MUS_MT_CHIMNEY },
  { "Weather Institute 3F keeps its header", {}, "ROUTE119_WEATHER_INSTITUTE_3F", EM.MUS_ROUTE120 },
  { "Weather Institute cleared", { vars = { VAR_WEATHER_INSTITUTE_STATE = 1 } }, "ROUTE119_WEATHER_INSTITUTE_1F", EM.MUS_ROUTE120 },
}
for _, row in ipairs(LOCATION_CASES) do
  local c = ctx(row[2])
  eq(P.locationMusic(c, at(c, row[3])), row[4], "GetLocationMusic: " .. row[1])
end

-- pokeemerald/src/overworld.c:1096
local DEFAULT_CASES = {
  { "Route 111 sandstorm plays the desert", { map = "ROUTE111", weather = Cem.weather.byName.WEATHER_SANDSTORM }, EM.MUS_DESERT },
  { "Route 111 without sandstorm", { map = "ROUTE111", weather = Cem.weather.byName.WEATHER_SUNNY }, EM.MUS_ROUTE120 },
  { "sandstorm elsewhere is ignored", { map = "LITTLEROOT_TOWN", weather = Cem.weather.byName.WEATHER_SANDSTORM }, EM.MUS_LITTLEROOT },
  { "Route 118 west half (x 23)", { map = "ROUTE118", x = 23 }, EM.MUS_ROUTE110 },
  { "Route 118 east half (x 24)", { map = "ROUTE118", x = 24 }, EM.MUS_ROUTE119 },
  { "Route 118 x 0", { map = "ROUTE118", x = 0 }, EM.MUS_ROUTE110 },
  { "Route 118 x 60", { map = "ROUTE118", x = 60 }, EM.MUS_ROUTE119 },
}
for _, row in ipairs(DEFAULT_CASES) do
  eq(P.currLocationDefaultMusic(ctx(row[2])), row[3], "GetCurrLocationDefaultMusic: " .. row[1])
end
check(EM.MUS_ROUTE118 == 0x7FFF, "MUS_ROUTE118 is the 0x7FFF sentinel")

-- pokeemerald/src/overworld.c:1120
do
  local c = ctx({ map = "MAUVILLE_CITY" })
  eq(P.warpDestinationMusic(c, at(c, "ROUTE118", 60, 5)), EM.MUS_ROUTE110, "Route 118 from Mauville is the Route 110 theme")
  c = ctx({ map = "ROUTE119" })
  eq(P.warpDestinationMusic(c, at(c, "ROUTE118", 5, 5)), EM.MUS_ROUTE119, "Route 118 from anywhere else is the Route 119 theme")
  c = ctx({ map = "LITTLEROOT_TOWN" })
  eq(P.warpDestinationMusic(c, at(c, "ROUTE101")), EM.MUS_ROUTE101, "plain destination header")
end

-- pokeemerald/src/overworld.c:1142
local SPECIAL_CASES = {
  { "default map music", {}, EM.MUS_LITTLEROOT },
  { "saved music wins", { saved = EM.MUS_CYCLING, surfing = true }, EM.MUS_CYCLING },
  { "saved MUS_DUMMY is no saved music", { saved = 0 }, EM.MUS_LITTLEROOT },
  { "underwater map type", { underwater = true, surfing = true }, EM.MUS_UNDERWATER },
  { "saved music beats underwater", { underwater = true, saved = EM.MUS_CYCLING }, EM.MUS_CYCLING },
  { "surfing", { surfing = true }, EM.MUS_SURF },
  { "biking alone does not pick cycling", { biking = true }, EM.MUS_LITTLEROOT },
  { "abnormal weather ignores surf and saved", { map = "LILYCOVE_CITY", flags = { FLAG_SYS_WEATHER_CTRL = true }, surfing = true, saved = EM.MUS_CYCLING }, EM.MUS_ABNORMAL_WEATHER },
  { "Sootopolis silence ignores surf", { map = "SOOTOPOLIS_CITY", vars = { VAR_SKY_PILLAR_STATE = 1 }, surfing = true }, EM.MUS_NONE },
  { "surfing on Route 118 east", { map = "ROUTE118", x = 40, surfing = true }, EM.MUS_SURF },
  { "walking on Route 118 east", { map = "ROUTE118", x = 40 }, EM.MUS_ROUTE119 },
}
for _, row in ipairs(SPECIAL_CASES) do
  eq(P.specialMapMusic(ctx(row[2])), row[3], "Overworld_PlaySpecialMapMusic: " .. row[1])
end
eq(P.playSpecialMapMusic(ctx({ current = EM.MUS_LITTLEROOT })), nil, "same music keeps playing")
eq(P.playSpecialMapMusic(ctx({ current = EM.MUS_ROUTE101 })), EM.MUS_LITTLEROOT, "different music starts")

-- pokeemerald/src/overworld.c:1170
do
  local c = ctx({ map = "LITTLEROOT_TOWN", current = EM.MUS_LITTLEROOT })
  local t = P.transitionMapMusic(c, at(c, "ROUTE101"))
  eq(t and t.song, EM.MUS_ROUTE101, "connection to Route 101 switches music")
  eq(t and t.fadeOut, 8, "walking: FadeOutAndPlayNewMapMusic(8)")
  eq(t and t.fadeIn, nil, "walking: no fade in")
  c = ctx({ map = "LITTLEROOT_TOWN", current = EM.MUS_LITTLEROOT, biking = true })
  t = P.transitionMapMusic(c, at(c, "ROUTE101"))
  eq(t and t.fadeOut, 4, "biking: fade out 4")
  eq(t and t.fadeIn, 4, "biking: fade in 4")
  c = ctx({ map = "ROUTE101", current = EM.MUS_ROUTE101 })
  eq(P.transitionMapMusic(c, at(c, "ROUTE101")), nil, "same music: no change")
  c = ctx({ current = EM.MUS_LITTLEROOT, flags = { FLAG_DONT_TRANSITION_MUSIC = true } })
  eq(P.transitionMapMusic(c, at(c, "ROUTE101")), nil, "FLAG_DONT_TRANSITION_MUSIC blocks the change")
  c = ctx({ map = "ROUTE132", current = EM.MUS_SURF, surfing = true })
  eq(P.transitionMapMusic(c, at(c, "ROUTE101")), nil, "surf music keeps playing across connections")
  c = ctx({ map = "ROUTE132", current = EM.MUS_UNDERWATER })
  eq(P.transitionMapMusic(c, at(c, "ROUTE101")), nil, "underwater music keeps playing across connections")
  c = ctx({ map = "ROUTE132", current = EM.MUS_ROUTE120, surfing = true })
  t = P.transitionMapMusic(c, at(c, "ROUTE101"))
  eq(t and t.song, EM.MUS_SURF, "surfing into a map switches to surf music")
  c = ctx({ map = "ROUTE132", current = EM.MUS_SURF, surfing = true, flags = { FLAG_SYS_WEATHER_CTRL = true } })
  t = P.transitionMapMusic(c, at(c, "LILYCOVE_CITY"))
  eq(t and t.song, EM.MUS_ABNORMAL_WEATHER, "abnormal weather replaces surf music")
  c = ctx({ map = "MAUVILLE_CITY", current = EM.MUS_ROUTE104 })
  t = P.transitionMapMusic(c, at(c, "ROUTE118", 0, 10))
  eq(t and t.song, EM.MUS_ROUTE110, "Mauville -> Route 118 plays the Route 110 theme")
end

-- pokeemerald/src/overworld.c:1193
do
  eq(P.changeMusicToDefault(ctx({ current = EM.MUS_LITTLEROOT })), nil, "ChangeMusicToDefault: already default")
  local t = P.changeMusicToDefault(ctx({ current = EM.MUS_SURF }))
  eq(t and t.song, EM.MUS_LITTLEROOT, "ChangeMusicToDefault: back to the map music")
  eq(t and t.fadeOut, 8, "ChangeMusicToDefault fades at 8")
  t = P.changeMusicToDefault(ctx({ map = "ROUTE118", x = 30, current = EM.MUS_SURF }))
  eq(t and t.song, EM.MUS_ROUTE119, "ChangeMusicToDefault resolves the Route 118 split")
  t = P.changeMusicTo(ctx({ current = EM.MUS_LITTLEROOT }), EM.MUS_SURF)
  eq(t and t.song, EM.MUS_SURF, "ChangeMusicTo: new song")
  eq(P.changeMusicTo(ctx({ current = EM.MUS_SURF }), EM.MUS_SURF), nil, "ChangeMusicTo: same song")
  eq(P.changeMusicTo(ctx({ current = EM.MUS_ABNORMAL_WEATHER }), EM.MUS_SURF), nil, "ChangeMusicTo: abnormal weather is never replaced")
end

-- pokeemerald/src/overworld.c:1207
do
  local c = ctx({ current = EM.MUS_LITTLEROOT })
  eq(P.mapMusicFadeoutSpeed(c, at(c, "POKEMON_CENTER")), 2, "indoor destination fades at 2")
  eq(P.mapMusicFadeoutSpeed(c, at(c, "ROUTE101")), 4, "outdoor destination fades at 4")
  eq(P.tryFadeOutOldMapMusic(c, at(c, "ROUTE101")), 4, "different warp music fades out")
  eq(P.tryFadeOutOldMapMusic(c, at(c, "POKEMON_CENTER")), 2, "indoor warp fades out at 2")
  c = ctx({ current = EM.MUS_POKE_CENTER })
  eq(P.tryFadeOutOldMapMusic(c, at(c, "POKEMON_CENTER")), nil, "same warp music keeps playing")
  c = ctx({ current = EM.MUS_LITTLEROOT, flags = { FLAG_DONT_TRANSITION_MUSIC = true } })
  eq(P.tryFadeOutOldMapMusic(c, at(c, "ROUTE101")), nil, "FLAG_DONT_TRANSITION_MUSIC keeps the music")
  c = ctx({ map = "SOOTOPOLIS_CITY", current = EM.MUS_SURF, vars = { VAR_SKY_PILLAR_STATE = 2 } })
  eq(P.tryFadeOutOldMapMusic(c, at(c, "SOOTOPOLIS_CITY", 29, 53)), nil, "Sootopolis (29,53) surf warp keeps the music")
  eq(P.tryFadeOutOldMapMusic(c, at(c, "SOOTOPOLIS_CITY", 29, 52)), 4, "other Sootopolis warps fade")
  c = ctx({ map = "SOOTOPOLIS_CITY", current = EM.MUS_SURF, vars = { VAR_SKY_PILLAR_STATE = 3 } })
  eq(P.tryFadeOutOldMapMusic(c, at(c, "SOOTOPOLIS_CITY", 29, 53)), 4, "the Sootopolis exception needs Sky Pillar state 2")
end

do
  local Sample = require("src.core.game3.m4a_sample")
  local EmAudio = require("src.core.game3.profiles.emerald.audio")
  eq(Sample.cryParams(6).volume, 90, "FRLG CRY_MODE_ECHO_END volume 90")
  eq(Sample.cryParams(6, nil, EmAudio.cryModeOverrides).volume, 70, "Emerald CRY_MODE_ECHO_END volume 70")
  eq(Sample.cryParams(6, nil, EmAudio.cryModeOverrides).pitch, 15555, "override keeps the other fields")
  eq(Sample.cryParams(2, nil, EmAudio.cryModeOverrides).volume, 90, "Emerald encounter cry stays 90")
  eq(Sample.cryParams(0, 125, EmAudio.cryModeOverrides).volume, 125, "caller volume still applies to normal cries")
end

do
  local prev = GameVersion.get()
  local Audio = require("src.core.game3.audio")
  GameVersion.set("firered")
  eq(Audio.mapMusicPolicy(), "frlg", "FireRed map music policy")
  eq(Audio.MUS_SURF, 305, "FireRed MUS_SURF")
  eq(Audio.MUS_CYCLING, 282, "FireRed MUS_CYCLING")
  eq(Audio.legendaryBattleSong(150), 340, "FireRed Mewtwo theme")
  eq(Audio.legendaryBattleSong(410), 339, "FireRed Deoxys theme")
  eq(Audio.legendaryBattleSong(386), nil, "FireRed species 386 is Volbeat")
  check(Audio.questLogGating(), "FireRed gates sounds during quest log playback")
  GameVersion.set("emerald")
  eq(Audio.mapMusicPolicy(), "rse", "Emerald map music policy")
  eq(Audio.MUS_SURF, EM.MUS_SURF, "Emerald MUS_SURF by name")
  eq(Audio.MUS_CYCLING, EM.MUS_CYCLING, "Emerald MUS_CYCLING by name")
  eq(Audio.MUS_UNDERWATER, EM.MUS_UNDERWATER, "Emerald MUS_UNDERWATER by name")
  check(Audio.canOverrideMapMusic(Audio.MUS_SURF, 97), "Emerald has no no-ride map sections")
  check(not Audio.questLogGating(), "Emerald has no quest log gating")
  local sp = Cem.species.byName
  eq(Audio.legendaryBattleSong(sp.SPECIES_GROUDON), EM.MUS_VS_KYOGRE_GROUDON, "Groudon theme")
  eq(Audio.legendaryBattleSong(sp.SPECIES_KYOGRE), EM.MUS_VS_KYOGRE_GROUDON, "Kyogre theme")
  eq(Audio.legendaryBattleSong(sp.SPECIES_RAYQUAZA), EM.MUS_VS_RAYQUAZA, "Rayquaza theme")
  eq(Audio.legendaryBattleSong(sp.SPECIES_DEOXYS), EM.MUS_RG_VS_DEOXYS, "Deoxys theme")
  eq(Audio.legendaryBattleSong(sp.SPECIES_HO_OH), EM.MUS_RG_VS_LEGEND, "Ho-Oh theme")
  eq(Audio.legendaryBattleSong(sp.SPECIES_MEW), EM.MUS_VS_MEW, "Mew theme")
  eq(Audio.legendaryBattleSong(sp.SPECIES_MEWTWO), nil, "no Emerald entry for Mewtwo")
  eq(Audio.legendaryBattleSong(sp.SPECIES_LATIAS, { legendary = true }), EM.MUS_VS_KYOGRE_GROUDON,
    "StartLegendaryBattle default case")
  eq(Audio.resolveSong("MUS_LEVEL_UP"), EM.MUS_LEVEL_UP, "song names resolve per game")
  eq(Audio.resolveSong(5), 5, "numbers pass through")
  GameVersion.set(prev)
end

T.finish("game3_audio_policy_rse_test")
