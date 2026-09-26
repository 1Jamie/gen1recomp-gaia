-- Test game3 OAM draw ordering for tall grass and trainers (NPCs).
-- Ensures grass cover on tile cy is drawn after the actor on tile cy,
-- but BEFORE any actor on tile cy + 1 (so the lower actor's head is not covered by grass).

local Objects = require("src.core.game3.objects")
local FieldEffects = require("src.core.game3.field_effects")
local FieldView = require("src.core.game3.field_view")
local Collision = require("src.core.game3.collision")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local CELL = 16

-- Mock love graphics image/quad for tall_grass if love is stubbed
FieldEffects._sheets["tall_grass"] = {
  image = {},
  quads = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} },
  quadsFront = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} },
  fw = 16,
  fh = 16,
  frames = 5,
}

print("[test] 1. Player in grass above NPC trainer: grass cover must sort between Player and Trainer")
do
  -- Player at cell (4, 4) -> px = 64, py = 64
  local Player = require("src.core.game3.player")
  Player.cellX = 4
  Player.cellY = 4
  Player.px = 4 * CELL
  Player.py = 4 * CELL
  Player.elevation = 3
  Player.moving = false

  -- Trainer NPC at cell (4, 5) -> px = 64, py = 80
  local trainer = {
    localId = 1,
    def = { x = 4, y = 5, elevation = 3 },
    cellX = 4, cellY = 5,
    px = 4 * CELL, py = 5 * CELL,
    elevation = 3,
  }
  Objects._byId = { [1] = trainer }
  Objects.forDraw = function() return { trainer } end

  -- Activate player grass rustle/cover at (4, 4)
  FieldEffects.tallGrassAt(4, 4, true)

  local actors = {}
  -- Player actor
  actors[#actors + 1] = {
    kind = "player",
    elevation = 3,
    x = Player.px,
    y = Player.py,
    sortY = Player.py,
  }
  -- Trainer actor
  actors[#actors + 1] = {
    kind = "npc",
    i = 1,
    obj = trainer.def,
    eventObject = trainer,
    elevation = 3,
    x = trainer.px,
    y = trainer.py,
    sortY = trainer.py,
  }

  -- Collect field effect actors
  FieldEffects.collectActors(actors)

  check(#actors >= 3, "collected Player, Trainer, and Grass Cover actors")

  local under, over = FieldView.applyDrawOrder(actors)
  check(#under >= 3, "all actors at elevation 3 land in underActors")

  -- Find positions of player, grass cover, and trainer in sorted order
  local playerIdx, grassIdx, trainerIdx
  for idx, a in ipairs(under) do
    if a.kind == "player" then playerIdx = idx end
    if a.kind == "field_effect_grass" then grassIdx = idx end
    if a.kind == "npc" and a.i == 1 then trainerIdx = idx end
  end

  check(playerIdx ~= nil, "player present in draw list")
  check(grassIdx ~= nil, "player grass cover present in draw list")
  check(trainerIdx ~= nil, "trainer present in draw list")

  check(playerIdx < grassIdx, "Player (Y=64) drawn before player's grass cover (Y=64.5)")
  check(grassIdx < trainerIdx, "Player's grass cover (Y=64.5) drawn before Trainer below (Y=80)")
end

print("[test] 2. Trainer NPC on grass tile also gets grass cover sorted after trainer")
do
  -- Mock Collision.isGrass to return true for cell (4, 5)
  local origIsGrass = Collision.isGrass
  Collision.isGrass = function(cx, cy)
    return (cx == 4 and cy == 4) or (cx == 4 and cy == 5)
  end

  local Player = require("src.core.game3.player")
  Player.cellX = 4
  Player.cellY = 4
  Player.px = 4 * CELL
  Player.py = 4 * CELL
  Player.elevation = 3
  Player.moving = false

  local trainer = {
    localId = 1,
    def = { x = 4, y = 5, elevation = 3 },
    cellX = 4, cellY = 5,
    px = 4 * CELL, py = 5 * CELL,
    elevation = 3,
  }
  Objects.forDraw = function() return { trainer } end
  FieldEffects.tallGrassAt(4, 4, true)

  local actors = {}
  actors[#actors + 1] = {
    kind = "player",
    elevation = 3,
    x = Player.px,
    y = Player.py,
    sortY = Player.py,
  }
  actors[#actors + 1] = {
    kind = "npc",
    i = 1,
    obj = trainer.def,
    eventObject = trainer,
    elevation = 3,
    x = trainer.px,
    y = trainer.py,
    sortY = trainer.py,
  }

  FieldEffects.collectActors(actors)

  local under, over = FieldView.applyDrawOrder(actors)
  local playerIdx, playerGrassIdx, trainerIdx, trainerGrassIdx
  for idx, a in ipairs(under) do
    if a.kind == "player" then playerIdx = idx end
    if a.kind == "field_effect_grass" then playerGrassIdx = idx end
    if a.kind == "npc" and a.i == 1 then trainerIdx = idx end
    if a.kind == "field_effect_npc_grass" then trainerGrassIdx = idx end
  end

  check(playerIdx < playerGrassIdx, "1. Player drawn first")
  check(playerGrassIdx < trainerIdx, "2. Player grass cover drawn second (before trainer)")
  check(trainerIdx < trainerGrassIdx, "3. Trainer drawn third (head covers player's grass tile)")
  check(trainerGrassIdx > trainerIdx, "4. Trainer grass cover drawn fourth (covers trainer's feet)")

  Collision.isGrass = origIsGrass
end

done()
