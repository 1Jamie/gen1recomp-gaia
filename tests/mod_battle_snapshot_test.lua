package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local S = require("tests.harness").suite("mod battle snapshot")
local check, eq = S.check, S.eq

check(require("src.battle.BattleState").isBattleState == true,
  "Gen 1 battle states carry the discovery marker")

local TypeChart = require("src.battle.TypeChart")
TypeChart.load({ type_chart = {
  types = { NORMAL = { name = "NORMAL", category = "physical" } },
  matchups = {},
} })

local Damage = require("src.battle.Damage")
local attacker, defender = { stages = {} }, { stages = {} }
eq(Damage.accuracyThreshold({ oneIn256Miss = true }, { accuracy = 100 },
  attacker, defender), 255, "faithful accuracy keeps the 1-in-256 miss")
eq(Damage.accuracyThreshold({ oneIn256Miss = false }, { accuracy = 100 },
  attacker, defender), 256, "clean accuracy exposes a certain hit")
local Catching = require("src.battle.Catching")
eq(Catching.chance("MASTER_BALL", { hp = 1, stats = { hp = 1 } },
  { catchRate = 1 }), 100, "Master Ball preview is certain")
check(Catching.chance("MOD_BALL", { hp = 1, stats = { hp = 1 } },
  { catchRate = 1 }, nil, { ballDef = { attempt = function() end } }) == nil,
  "custom ball logic does not receive a guessed preview")

local mon = { species = "TESTMON", level = 5, hp = 18,
  stats = { hp = 20 }, moves = {} }
local game = {
  data = {
    pokemon = { TESTMON = { name = "TESTMON", catchRate = 255 } },
    moves = { TACKLE = { name = "TACKLE", type = "NORMAL", power = 35,
      accuracy = 95, pp = 35 } },
    items = { POTION = { name = "POTION" },
      POKE_BALL = { name = "POKE BALL" } },
  },
  save = { party = { mon }, inventory = { POTION = 1, POKE_BALL = 1 } },
  stack = { states = {} },
}
local battle = {
  isBattleState = true, phase = "menu", queue = {},
  ruleset = { oneIn256Miss = true },
  player = { mon = mon, curTypes = { "NORMAL" }, stages = {},
    curMoves = { { id = "TACKLE", pp = 35 } } },
  enemy = { mon = { species = "TESTMON", level = 4, hp = 12,
    stats = { hp = 12 }, moves = {} }, curTypes = { "NORMAL" }, stages = {} },
}
function battle:battleKind() return "wild" end
function battle:effectRecord() return { accuracyChecked = true } end
function battle:visibleText() return { "Wild TESTMON appeared!" } end
function battle:catchChance(ball)
  return require("src.battle.Catching").chance(ball, self.enemy.mon,
    game.data.pokemon[self.enemy.mon.species])
end
game.stack.states = { battle }

local api = require("src.battle.BattleAPI").new(game)
local snapshot = api:snapshot()
check(snapshot and snapshot.kind == "wild" and snapshot.prompt == "menu",
  "Gen 1 battle is exposed")
eq(snapshot.player.maxHp, 20, "Gen 1 max HP comes from battle stats")
eq(snapshot.moves[1].name, "TACKLE", "move records are copied")
eq(snapshot.message[1], "Wild TESTMON appeared!", "battle text is copied")
eq(#snapshot.items, 2, "medicine and balls are exposed")
check(type(snapshot.items[1].catchChance) == "number"
    or type(snapshot.items[2].catchChance) == "number",
  "stock catch chance is available")
snapshot.player.hp = 0
snapshot.moves[1].pp = 0
eq(mon.hp, 18, "changing a snapshot cannot change a Pokemon")
eq(battle.player.curMoves[1].pp, 35,
  "changing a snapshot cannot change a move")
local same = api:snapshot()
eq(same.revision, snapshot.revision, "unchanged battle keeps its revision")
battle.enemy.mon.hp = 5
check(api:snapshot().revision > same.revision,
  "observable battle changes advance the revision")
game.stack.states = {}
check(api:snapshot() == nil, "Gen 1 returns nil outside a battle")
game.stack.states = { battle }

local player2 = { species = "CHIKORITA", level = 5, hp = 20,
  maxHp = 21, moves = { { id = "TACKLE", pp = 35, maxPp = 35 } } }
local enemy2 = { species = "RATTATA", level = 3, hp = 12, maxHp = 12,
  moves = {} }
local battle2 = { player = player2, enemy = enemy2, party = { player2 },
  wild = true, turn = 0 }
function battle2:moveDisabled() return false end
local screen2 = { screenId = "Gen2BattleState", battle = battle2,
  phase = "menu", menuIndex = 1, moveIndex = 1 }
local game2 = {
  data = {
    pokemon = { CHIKORITA = { name = "CHIKORITA" },
      RATTATA = { name = "RATTATA" } },
    moves = { TACKLE = { name = "TACKLE", type = "NORMAL",
      power = 35, accuracy = 95, pp = 35 } },
  },
  save = { party = { player2 } }, stack = { states = { screen2 } },
}

local api2 = require("src.battle.gen2.BattleAPI").new(game2)
local snapshot2 = api2:snapshot()
check(snapshot2 and snapshot2.kind == "wild" and snapshot2.prompt == "menu",
  "Gold battle is discovered through its screen id")
eq(snapshot2.player.maxHp, 21, "Gold max HP uses the mon field")
eq(snapshot2.moves[1].name, "TACKLE", "Gold moves are copied")
snapshot2.player.hp = 0
snapshot2.moves[1].pp = 0
eq(player2.hp, 20, "changing a snapshot cannot change a Gold Pokemon")
eq(player2.moves[1].pp, 35,
  "changing a snapshot cannot change a Gold move")
screen2.message = "A wild RATTATA appeared!"
screen2.phase = "resolving"
local message2 = api2:snapshot()
eq(message2.prompt, "advance", "Gold message state is exposed")
check(message2.revision > snapshot2.revision,
  "Gold battle changes advance the revision")
game2.stack.states = {}
check(api2:snapshot() == nil, "Gold returns nil outside a battle")
game2.stack.states = { screen2 }

local Loader = require("src.mods.Loader")
local fs = { read = function() end, getInfo = function() end,
  getDirectoryItems = function() return {} end }
local mod = { path = "mods/snapshot_test", manifest = {
  id = "snapshot_test", version = "1.0.0", permissionSet = {},
} }
local loader1 = Loader.new({ fs = fs, generation = 1 })
loader1.game = game
check(loader1:_api(mod).battle:snapshot().kind == "wild",
  "mod.battle selects the Gen 1 facade")
local loader2 = Loader.new({ fs = fs, generation = 2 })
loader2.game = game2
check(loader2:_api(mod).battle:snapshot().kind == "wild",
  "mod.battle selects the Gen 2 facade")

S.finish()
