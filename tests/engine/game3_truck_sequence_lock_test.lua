local T = require("tests.harness")
local check, eq = T.check, T.eq

local Field = require("src.core.game3.field")
Field.stop()
eq(Field.isLocked(), false, "field unlocked initially")
eq(Field.locked, false, "field.locked property reads false")

-- Tag-based lock
Field.lock("truck")
eq(Field.isLocked(), true, "field locked by truck")
eq(Field.locked, true, "field.locked property reads true")

-- Concurrent on_frame lock
Field.lock("on_frame")
eq(Field.isLocked(), true, "field locked by truck + on_frame")

-- on_frame script finishes and attempts unlock
Field.unlock("on_frame")
eq(Field.isLocked(), true, "truck lock still holds after on_frame unlock")
eq(Field.locked, true, "field.locked still true")

-- Legacy direct assign attempt to unlock
Field.locked = false
eq(Field.isLocked(), true, "truck lock cannot be cleared by raw Field.locked = false assignment")

-- Truck finishes sequence
Field.unlock("truck")
eq(Field.isLocked(), false, "field completely unlocked when all tags cleared")
eq(Field.locked, false, "field.locked property reads false")

-- Verify Truck default host lock/unlock integration
local Truck = require("src.core.game3.truck_sequence")
local host = Truck.defaultHost()
host.lock(true)
eq(Field.isLocked(), true, "host.lock(true) locks truck")
host.lock(false)
eq(Field.isLocked(), false, "host.lock(false) unlocks truck")

-- Verify Truck.step end sequence unlocks Field
Truck.reset()
eq(Field.isLocked(), false, "field unlocked after reset")
local seq = Truck.new(host)
seq.state = 5
seq.timer = 119
Truck.step(seq)
check(seq.done, "truck sequence completes on frame 120 of state 5")
eq(Field.isLocked(), false, "movement is unlocked after truck sequence completes")

T.finish("game3_truck_sequence_lock_test")
