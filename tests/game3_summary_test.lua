-- Automated tests for Game3 Pokemon Summary Screen
-- Validates:
-- 1. Chrome asset loading from data/generated/gba (game3 launcher scope)
-- 2. Anti-PP swap trap protection (atomic swapMoves)
-- 3. Dynamic trade memo detection (OT Name / ID / SID diff against PlayerState)
-- 4. Page transitions (INFO -> SKILLS -> MOVES -> MOVE_DETAIL)
-- 5. Modal Stack integration with PartyMenu

local Game3 = require("src.core.game3")
local PartyMenu = require("src.ui.game3.party_menu")
local SummaryMenu = require("src.ui.game3.summary_menu")
local SummaryData = require("src.core.game3.summary_data")
local SummaryChrome = require("src.ui.game3.summary_chrome")
local Stack = require("src.ui.game3.stack")

print("=== Running Game3 Summary Screen Tests ===")

-- 1. Asset Chrome
local manifest = SummaryChrome.manifest()
assert(manifest ~= nil, "Manifest must load from data/generated/gba")
assert(manifest.pages.INFO == 0)
assert(manifest.pages.SKILLS == 1)
assert(manifest.pages.MOVES == 2)
assert(manifest.coords and manifest.coords.dexNo and manifest.coords.dexNo.x == 167,
  "INFO dexNo must sit in right pane (pret WIN_INFO_3)")
assert(manifest.coords.atk and manifest.coords.atk.y == 38,
  "SKILLS atk Y must match pret PrintSkillsPage")
assert(manifest.moveSlots and manifest.moveSlots[1].typeX == 123,
  "MOVES type badge X must match pret WIN_MOVES_5")
print("[PASS] Asset Chrome & Manifest verified")

-- 1b. Move names resolve from ROM gMoveNames (not "MOVE 33")
local Pokemon = require("src.core.game3.pokemon")
assert(Pokemon.moveName(33) == "TACKLE", "move 33 must be TACKLE")
assert(Pokemon.moveName(45) == "GROWL", "move 45 must be GROWL")
print("[PASS] Move name lookup verified")

-- 2. Party & Mon Setup
local party = {
  {
    species = 1,
    name = "BULBASAUR",
    level = 5,
    hp = 20,
    maxHp = 20,
    attack = 11,
    defense = 11,
    spAtk = 13,
    spDef = 13,
    speed = 10,
    moves = { 33, 45 }, -- Tackle (35 PP), Growl (40 PP)
    pp = { 35, 40 },
    otName = "RED",
    otId = 12345,
    personality = 0,
  },
  {
    species = 4,
    name = "CHARMANDER",
    level = 5,
    hp = 19,
    maxHp = 19,
    attack = 12,
    defense = 9,
    spAtk = 14,
    spDef = 11,
    speed = 13,
    moves = { 10, 45 }, -- Scratch, Growl
    pp = { 35, 40 },
    otName = "BLUE",
    otId = 54321,
    personality = 25,
  }
}

-- 3. Dynamic Trade Memo Check
local playerState = { playerName = "RED", playerId = 12345, secretId = 0 }
local memoRed = SummaryData.formatTrainerMemo(party[1], playerState)
assert(string.find(memoRed[2], "Met in a trade") == nil, "Original trainer mon should NOT be marked trade")

local memoBlue = SummaryData.formatTrainerMemo(party[2], playerState)
assert(string.find(memoBlue[2], "Met in a trade") ~= nil, "Different OT must be dynamically marked as trade")
print("[PASS] Dynamic Trainer Memo trade detection verified")

-- 4. PartyMenu -> SummaryMenu Navigation
PartyMenu.show(party, nil, {})
assert(PartyMenu.isOpen() == true)
assert(Stack.top().id == "party")

local input = {
  _pressed = { a = true },
  wasPressed = function(self, k) return self._pressed[k] == true end,
  isDown = function() return false end,
}
PartyMenu.handleInput(input) -- list -> action
assert(PartyMenu.mode == "action")
PartyMenu.handleInput(input) -- action -> SUMMARY
assert(SummaryMenu.isOpen() == true, "SummaryMenu must open")
assert(Stack.top().id == "summary", "SummaryMenu must be on top of Stack")
print("[PASS] PartyMenu to SummaryMenu modal Stack navigation verified")

-- 5. Page Navigation & Animated Slide
input._pressed = { right = true }
SummaryMenu.handleInput(input)
assert(SummaryMenu._slide.active == true, "Slide animation starts on page change")
SummaryMenu.update(0.2)
assert(SummaryMenu._slide.active == false, "Slide completes after duration")
assert(SummaryMenu._page == 1, "Should be on SKILLS page")

input._pressed = { right = true }
SummaryMenu.handleInput(input)
SummaryMenu.update(0.2)
assert(SummaryMenu._page == 2, "Should be on MOVES page")
print("[PASS] Page navigation and animated sliding verified")

-- 6. Move Detail & Atomic Move Swapping
input._pressed = { a = true }
SummaryMenu.handleInput(input)
assert(SummaryMenu._page == 3, "Should enter MOVE DETAIL mode")

input._pressed = { a = true } -- pick slot 1
SummaryMenu.handleInput(input)
assert(SummaryMenu._swapSlot == 1, "Slot 1 selected for swap")

input._pressed = { down = true }
SummaryMenu.handleInput(input)
assert(SummaryMenu._moveCursor == 2, "Cursor moved to slot 2")

input._pressed = { a = true } -- execute atomic swap
SummaryMenu.handleInput(input)
assert(SummaryMenu._swapSlot == nil, "Swap slot cleared after swap")
assert(party[1].moves[1] == 45 and party[1].moves[2] == 33, "Move IDs swapped")
assert(party[1].pp[1] == 40 and party[1].pp[2] == 35, "PP swapped atomically with move IDs")
print("[PASS] Atomic move swap and anti-PP swap trap verified")

-- 7. Returning to PartyMenu
input._pressed = { b = true }
SummaryMenu.handleInput(input) -- detail -> moves
assert(SummaryMenu._page == 2)

input._pressed = { b = true }
SummaryMenu.handleInput(input) -- close summary
assert(SummaryMenu.isOpen() == false)
assert(Stack.top().id == "party", "Top layer should return to PartyMenu")
print("[PASS] Summary exit cleanly returns to PartyMenu")

-- 8. Top Bar Progress Indicator Verification
local function read_top_bar_pixel(pageName, x, y)
  local f = io.open("data/generated/gba/pokemon/summary/" .. pageName .. ".rgba", "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local idx = (y * 240 + x) * 4 + 1
  return data:byte(idx), data:byte(idx + 1), data:byte(idx + 2)
end

-- Slot 1 (X=112), Slot 2 (X=128), Slot 3 (X=144) at Y=8
local function is_yellow_bg(r, g, b)
  return r > 200 and g > 200 and b < 180
end
local function is_cyan_bg(r, g, b)
  return r < 150 and g > 170 and b > 180
end

local r1, g1, b1 = read_top_bar_pixel("page_info", 112, 8)
local r2, g2, b2 = read_top_bar_pixel("page_info", 128, 8)
local r3, g3, b3 = read_top_bar_pixel("page_info", 144, 8)
assert(is_yellow_bg(r1, g1, b1), "Page INFO slot 1 is active (yellow tab)")
assert(is_cyan_bg(r2, g2, b2), "Page INFO slot 2 is inactive (cyan)")
assert(is_cyan_bg(r3, g3, b3), "Page INFO slot 3 is inactive (cyan)")

local sr1, sg1, sb1 = read_top_bar_pixel("page_skills", 112, 8)
local sr2, sg2, sb2 = read_top_bar_pixel("page_skills", 128, 8)
local sr3, sg3, sb3 = read_top_bar_pixel("page_skills", 144, 8)
assert(is_yellow_bg(sr1, sg1, sb1), "Page SKILLS slot 1 is yellow tab")
assert(is_yellow_bg(sr2, sg2, sb2), "Page SKILLS slot 2 is active (yellow tab)")
assert(is_cyan_bg(sr3, sg3, sb3), "Page SKILLS slot 3 is inactive (cyan)")

local mr1, mg1, mb1 = read_top_bar_pixel("page_moves", 112, 8)
local mr2, mg2, mb2 = read_top_bar_pixel("page_moves", 128, 8)
local mr3, mg3, mb3 = read_top_bar_pixel("page_moves", 144, 8)
assert(is_yellow_bg(mr1, mg1, mb1), "Page MOVES slot 1 is yellow tab")
assert(is_yellow_bg(mr2, mg2, mb2), "Page MOVES slot 2 is yellow tab")
assert(is_yellow_bg(mr3, mg3, mb3), "Page MOVES slot 3 is active (yellow tab)")
print("[PASS] Top bar page progress indicators across all pages verified")

print("=== ALL TESTS PASSED SUCCESSFULLY! ===")
