local T = require("tests.harness")
local check, eq = T.check, T.eq

local Audio = require("src.core.game3.audio")
local BattleBridge = require("src.core.game3.battle_bridge")

Audio._savedSong = 0x1234
eq(Audio._savedSong, 0x1234, "savedSong set")
Audio.clearSavedSong()
eq(Audio._savedSong, nil, "clearSavedSong zeroes savedSong (Overworld_ClearSavedMusic parity)")

-- Test BattleBridge finish behavior with firstBattleKind / firstBattle opts
local songRestored = false
local savedSongDuringFinish = nil
Audio._savedSong = 0x9999
local prevRestore = Audio.restoreMapSong
Audio.restoreMapSong = function()
  savedSongDuringFinish = Audio._savedSong
  songRestored = true
end

local fakeSession = { party = { { species = 1, hp = 20, maxHp = 20, moves = { 1 } } } }
local Runtime = require("src.core.game3.runtime")
local prevGetSession = Runtime.getSession
Runtime.getSession = function() return fakeSession end

local opts = { firstBattleKind = "first_battle" }
if opts.firstBattleKind then
  Audio.clearSavedSong()
end
Audio.restoreMapSong()

check(songRestored, "restoreMapSong was called")
eq(savedSongDuringFinish, nil, "Audio._savedSong was cleared before restoreMapSong so field BGM plays")

Audio.restoreMapSong = prevRestore
Runtime.getSession = prevGetSession

T.finish("game3_birch_rescue_bgm_resume_test")
