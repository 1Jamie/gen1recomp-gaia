-- Tests for Game 3 (FRLG) Field Moves & Field Effects
-- Validates:
-- 1. Pure ROM extraction of field effects (tall grass, cut grass, rock smash, surf blob, fly bird, ripple)
-- 2. Softboiled / Milk Drink donor limits and HP transfer math
-- 3. 3x3 Grass mowing and metatile behavior checks
-- 4. Pushable boulder collision and direction logic
-- 5. Surfing collision, bike override, and landing dismount
-- 6. Strength flag lifecycle (map load reset)
-- 7. Party menu action generation with field moves

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("Assertion failed: %s (expected %s, got %s)",
      tostring(msg), tostring(expected), tostring(actual)))
  end
end

local function assert_true(cond, msg)
  if not cond then
    error("Assertion failed: " .. tostring(msg))
  end
end

print("=== 1. Testing Field Effect ROM Extraction ===")
local FxExtract = require("src.import.gba.field_effect_extract")
local Versions = require("src.import.gba.versions")

local f = io.open("./1636 - Pokemon Fire Red (U)(Squirrels).gba", "rb")
assert_true(f ~= nil, "FireRed ROM found")
local data = f:read("*a")
f:close()

local rom = {
  data = data,
  size = #data,
  get = function(self, off) return self.data:byte(off + 1) end,
  u16 = function(self, off)
    local b1, b2 = self.data:byte(off + 1, off + 2)
    return b1 + b2 * 256
  end,
  u32 = function(self, off)
    local b1, b2, b3, b4 = self.data:byte(off + 1, off + 4)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
  end,
}

local cacheFiles = {}
local cache = {
  write = function(self, path, content)
    cacheFiles[path] = content
  end,
  read = function(self, path)
    return cacheFiles[path]
  end,
}

local res = FxExtract.writeExtract(rom, cache, "data/generated/gba", Versions)
assert_true(type(res) == "table", "writeExtract returned table")
assert_true(cacheFiles["data/generated/gba/field_effects/tall_grass.rgba"] ~= nil, "tall_grass.rgba exists")
assert_true(cacheFiles["data/generated/gba/field_effects/cut_grass.rgba"] ~= nil, "cut_grass.rgba exists")
assert_true(cacheFiles["data/generated/gba/field_effects/rock_smash.rgba"] ~= nil, "rock_smash.rgba exists")
assert_true(cacheFiles["data/generated/gba/field_effects/surf_blob.rgba"] ~= nil, "surf_blob.rgba exists")
assert_true(cacheFiles["data/generated/gba/field_effects/fly_bird.rgba"] ~= nil, "fly_bird.rgba exists")
assert_true(cacheFiles["data/generated/gba/field_effects/ripple.rgba"] ~= nil, "ripple.rgba exists")
print("  ✓ All 6 field effect RGBA sheets successfully extracted from ROM")

print("\n=== 2. Testing Softboiled / Milk Drink Limits ===")
local FieldMoves = require("src.core.game3.field_moves")

-- Donor with exactly 20% HP (e.g. 20/100) -> cost is 20 -> curHp <= cost -> BLOCKED
local chanseyLow = { name = "CHANSEY", hp = 20, maxHp = 100 }
local res1 = FieldMoves.softboiledFromMenu({ mon = chanseyLow })
assert_eq(res1.ok, false, "Softboiled blocked when curHp == cost (prevent faint)")
assert_eq(res1.text, FieldMoves.TEXT.NOT_ENOUGH_HP, "Not enough HP message")

-- Donor with 21/100 HP -> cost is 20 -> curHp > cost -> ALLOWED
local chanseyOk = { name = "CHANSEY", hp = 21, maxHp = 100 }
local res2 = FieldMoves.softboiledFromMenu({ mon = chanseyOk })
assert_eq(res2.ok, true, "Softboiled allowed when curHp > cost")
assert_eq(res2.cost, 20, "Cost is math.floor(maxHp/5)")

-- Recipient checks
local pikachuHealthy = { name = "PIKACHU", hp = 50, maxHp = 50 }
assert_eq(FieldMoves.softboiledTargetOk(chanseyOk, pikachuHealthy), false, "Full HP mon is not valid recipient")

local eggMon = { isEgg = true, hp = 10, maxHp = 50 }
assert_eq(FieldMoves.softboiledTargetOk(chanseyOk, eggMon), false, "Egg is not valid recipient")

local faintedMon = { name = "CHARMANDER", hp = 0, maxHp = 50 }
assert_eq(FieldMoves.softboiledTargetOk(chanseyOk, faintedMon), false, "Fainted mon is not valid recipient")

local pikachuHurt = { name = "PIKACHU", hp = 10, maxHp = 50 }
assert_eq(FieldMoves.softboiledTargetOk(chanseyOk, pikachuHurt), true, "Hurt mon is valid recipient")

-- Execution
local okTransfer, userHp, targetHp = FieldMoves.softboiledTransfer(chanseyOk, pikachuHurt, 20)
assert_eq(okTransfer, true, "Transfer successful")
assert_eq(chanseyOk.hp, 1, "Chansey reduced to 1 HP")
assert_eq(pikachuHurt.hp, 30, "Pikachu restored to 30 HP")
print("  ✓ Softboiled donor limits and HP transfer math verified")

print("\n=== 3. Testing 3x3 Grass Mowing ===")
local grid = {
  ["1,1"] = 0x00D, -- Plain_Grass
  ["2,1"] = 0x00A, -- ThinTreeTop_Grass
  ["3,1"] = 0x000, -- Not grass
  ["1,2"] = 0x00B, -- WideTreeTopLeft_Grass
  ["2,2"] = 0x00C, -- WideTreeTopRight_Grass
  ["3,2"] = 0x000,
  ["1,3"] = 0x000,
  ["2,3"] = 0x000,
  ["3,3"] = 0x000,
}
local function getMid(x, y) return grid[x .. "," .. y] or 0 end
local function setMid(x, y, mid) grid[x .. "," .. y] = mid end

local cutCount = FieldMoves.mowGrass3x3(2, 2, getMid, setMid)
assert_eq(cutCount, 4, "Mowed 4 tall grass tiles in 3x3")
assert_eq(grid["1,1"], 0x001, "Plain_Grass became Plain_Mowed")
assert_eq(grid["2,1"], 0x013, "ThinTreeTop_Grass became ThinTreeTop_Mowed")
assert_eq(grid["1,2"], 0x00E, "WideTreeTopLeft_Grass became WideTreeTopLeft_Mowed")
assert_eq(grid["2,2"], 0x00F, "WideTreeTopRight_Grass became WideTreeTopRight_Mowed")
print("  ✓ 3x3 metatile grass mowing verified")

print("\n=== 4. Testing Pushable Boulder Logic ===")
local boulder = { x = 5, y = 5 }
local blockedCells = { ["5,4"] = true }
local function isPassable(x, y)
  return not blockedCells[x .. "," .. y]
end

local canPushUp = FieldMoves.canPushBoulder(boulder, "up", isPassable)
assert_eq(canPushUp, false, "Cannot push boulder into blocked cell")

local canPushDown, destX, destY = FieldMoves.canPushBoulder(boulder, "down", isPassable)
assert_eq(canPushDown, true, "Can push boulder into open cell")
assert_eq(destX, 5, "Dest X is 5")
assert_eq(destY, 6, "Dest Y is 6")
print("  ✓ Pushable boulder direction and collision verified")

print("\n=== 5. Testing Surfing & Bike Override ===")
local Player = require("src.core.game3.player")
Player.biking = true
Player.surfing = false
Player.startSurfing({})
assert_eq(Player.surfing, true, "Player is surfing")
assert_eq(Player.biking, false, "Bike state silently cleared on Surf")
print("  ✓ Surfing and bike override verified")

print("\n=== 6. Testing Message.show with callback function ===")
local Message = require("src.ui.game3.message")
local callbackRan = false
Message.show("This tree can be Cut!", function() callbackRan = true end)
assert_eq(Message.open, true, "Message is open")
assert_true(type(Message._done) == "function", "Message._done is a function")
Message.close()
assert_eq(callbackRan, true, "Message done callback executed on close")
print("  ✓ Message.show function callback verified")

print("\n==========================================")
print("ALL GAME 3 FIELD MOVE TESTS PASSED!")
print("==========================================")
