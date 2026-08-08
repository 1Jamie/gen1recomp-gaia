-- mod.world:startWildBattle.  What regresses is the handoff, not the battle:
-- a mod that pushes its own BattleState still fights and still levels, it just
-- loses onFinish -> afterBattle (evolutions, blackout-on-loss) and pushBattle
-- (entry wipe, battle theme), silently.  Shipped mods have hit exactly this.
--
-- T3, not the ROM-free tier: the handoff only exists once a real map is up
-- (OverworldState:enter binds the module-local Game and MapLoader needs real
-- tilesets), and the fixture dataset carries neither.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local S = require("tests.harness").suite("parity world startWildBattle")
local check = S.check

local Game = require("src.core.Game")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local Pokemon = require("src.pokemon.Pokemon")
local WorldAPI = require("src.world.WorldAPI")
local OverworldState = require("src.world.OverworldController")
require("src.render.Font").load(Data)

-- data/generated/audio.lua only exists after an in-app ROM import; the Python
-- developer builder has no audio stage, so Music's entry points can be absent.
-- setMap plays map music on the way in, which is incidental to the handoff
-- under test -- no-op whatever is missing rather than depend on the dataset.
-- run_tests.lua dofiles every suite into one process, so this is restored at
-- the end: leaving it patched makes later suites pass that otherwise fail.
local Music = require("src.core.Music")
local musicSaved = {}
for _, fn in ipairs({ "playMap", "setSurfing", "playBattle" }) do
  -- `or false` so a genuinely-absent entry point is still recorded and gets
  -- restored to nil; storing the nil directly would drop the key entirely
  musicSaved[fn] = Music[fn] or false
  Music[fn] = Music[fn] or function() end
end
local function restoreMusic()
  for fn, orig in pairs(musicSaved) do Music[fn] = orig or nil end
end

local function freshWorld()
  Game.data = Data
  Game.save = SaveData.newGame()
  Game.stack = StateStack; StateStack:init()
  Game.renderer = { worldViewSize = function() return 160, 144 end }
  Game.overworld = OverworldState
  OverworldState:enter("ROUTE_1", 5, 5, "down")
  return WorldAPI.new(Game, "testmod")
end

-- The assertions run under pcall so the Music patch is handed back even when
-- one of them throws: run_tests.lua dofiles the later suites into this same
-- process, and a Music left stubbed lets their own music checks pass.
local function body()
  -- ----- argument handling: every failure is a nil + reason, never a throw

  local world = WorldAPI.new({ data = Data }, "testmod")
  local ok, err = world:startWildBattle("PIDGEY", 5)
  check(ok == nil, "no overworld up refuses")
  check(err == "no overworld", "and says so")

  world = freshWorld()
  Game.save.party = { Pokemon.new(Data, "CATERPIE", 6) }

  ok, err = world:startWildBattle("NOT_A_MON", 5)
  check(ok == nil, "an unknown species refuses")
  check(err and err:find("unknown species", 1, true), "and names the species")

  -- 5.5 too: Pokemon.new writes the level through into the stat calc and the
  -- exp curve verbatim, so a fraction has to be refused, not rounded
  for _, lv in ipairs({ 0, 101, "nope", 5.5 }) do
    check(world:startWildBattle("PIDGEY", lv) == nil,
      "level " .. tostring(lv) .. " refuses")
  end

  -- ----- the handoff: a level-up evolution is offered after the win

  world = freshWorld()
  local caterpie = Pokemon.new(Data, "CATERPIE", 6)
  Game.save.party = { caterpie }

  check(world:startWildBattle("PIDGEY", 25) == true, "a wild battle starts")

  -- pushBattle pushes the transition, which pushes the battle from its
  -- callback.  awardExp is the BattleState marker the drain loop below
  -- identifies it by; screenId would NOT work here -- only Screens.push
  -- stamps that, and pushBattle pushes the battle straight onto the stack,
  -- so `screenId ~= "BattleState"` holds even with the transition skipped.
  local top = Game.stack:top()
  check(top ~= nil, "something was pushed")
  check(top.awardExp == nil, "the entry transition goes on first")

  -- overworld() resolves the world from under the battle, so a second call
  -- while one is up has to refuse rather than stack another
  check(world:startWildBattle("PIDGEY", 5) == nil,
    "a battle already running refuses")

  local battle
  for _ = 1, 400 do
    local t = Game.stack:top()
    if t and t.awardExp then battle = t break end
    if t and t.update then t:update(1 / 60) else break end
  end
  check(battle ~= nil, "the transition hands off to the battle")

  battle.participants = { [caterpie] = true }
  battle:awardExp()
  check(caterpie.level >= 7, "the mon levels past its evolution threshold")
  check(battle.leveledUp and battle.leveledUp[caterpie],
    "awardExp records the level-up for EvolveAfterBattle")

  Game.stack:pop()
  battle.onFinish("win")
  for _ = 1, 12 do
    local t = Game.stack:top()
    if not t or t.screenId == "EvolutionState" then break end
    Game.stack:pop()
    if t.onDone then t.onDone() end
  end
  check(Game.stack:top() and Game.stack:top().screenId == "EvolutionState",
    "the win reaches the evolution screen")
end

local ran, runErr = pcall(body)
restoreMusic()
if not ran then error(runErr, 0) end
S.finish()
