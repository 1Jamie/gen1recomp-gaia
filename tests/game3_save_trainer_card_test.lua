-- Test game3 TrainerCard and SaveMenu mechanics and state flows.

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("[ok] " .. name)
  else
    print("[FAIL] " .. name .. ": " .. tostring(err))
    error(err)
  end
end

print("[test] 1. Trainer Card lifecycle and fields")
local TrainerCard = require("src.ui.game3.trainer_card")

local session = {
  name = "RED",
  id = 12345,
  money = 3500,
  dex = { caught = { [1] = true, [4] = true, [7] = true } },
  playTimeHours = 2,
  playTimeMinutes = 45,
  badges = { true, true, false, false, false, false, false, false },
  mapName = "PALLET TOWN",
}

local closed = false
TrainerCard.show({
  session = session,
  onClose = function() closed = true end,
})

test("TrainerCard is open", function()
  assert(TrainerCard.isOpen() == true, "TrainerCard should be open")
end)

TrainerCard.close()

test("TrainerCard closed callback called", function()
  assert(TrainerCard.isOpen() == false, "TrainerCard should be closed")
  assert(closed == true, "onClose should have been called")
end)

print("[test] 2. SaveMenu lifecycle and state machine")
local SaveMenu = require("src.ui.game3.save_menu")

local saveClosed = false
SaveMenu.show({
  session = session,
  onClose = function() saveClosed = true end,
})

test("SaveMenu starts in confirm phase", function()
  assert(SaveMenu.isOpen() == true, "SaveMenu should be open")
  assert(SaveMenu._phase == "confirm", "Initial phase should be confirm")
  assert(SaveMenu.cursor == 1, "Cursor should start on YES (1)")
end)

test("SaveMenu cursor movement", function()
  SaveMenu.move(1)
  assert(SaveMenu.cursor == 2, "Cursor should flip to NO (2)")
  SaveMenu.move(1)
  assert(SaveMenu.cursor == 1, "Cursor should flip back to YES (1)")
end)

test("SaveMenu confirm transitions to overwrite then saved", function()
  SaveMenu.confirm()
  assert(SaveMenu._phase == "overwrite", "Selecting YES in confirm should transition to overwrite")
  SaveMenu.confirm()
  assert(SaveMenu._phase == "saved", "Selecting YES in overwrite should transition to saved")
  SaveMenu.confirm()
  assert(SaveMenu.isOpen() == false, "Confirm in saved phase should close menu")
  assert(saveClosed == true, "Save onClose callback should be called")
end)

print("[test] 3. SaveMenu cancellation", function()
  local noClosed = false
  SaveMenu.show({
    session = session,
    onClose = function() noClosed = true end,
  })
  SaveMenu.move(1) -- Move to NO
  SaveMenu.confirm() -- Press A on NO
  assert(SaveMenu.isOpen() == false, "Selecting NO should close SaveMenu")
  assert(noClosed == true, "onClose should be called on cancel")
end)

print("[test] all passed")
