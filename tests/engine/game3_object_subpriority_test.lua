-- Producer contract for seam-7 set/resetobjectsubpriority (rse-seams e10
-- spec 5.8): the script op freezes an object's draw-order pair on the
-- EventObject record { fixedPriority, subpriority, fixedClass }; the field_view
-- half (Refactor lane) consumes it, and the freeze points mirror pret:
--   pret src/event_object_movement.c:2089-2101 SetObjectSubpriority
--     (objectEvent->fixedPriority = TRUE; sprite->subpriority = subpriority)
--   pret src/event_object_movement.c:2104-2116 ResetObjectSubpriority
--     (fixedPriority = FALSE — re-enables the dynamic path, does NOT restore
--      a previous value; all three fields drop)
--   pret src/scrcmd.c:1122-1130 (+83 bias) / :1133-1140
--   guard: TryGetObjectEventIdByLocalIdAndMap (mapGroup/mapNum must resolve
--     to the active map or the command does nothing)
--   lua: luajit tests/engine/game3_object_subpriority_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Objects = require("src.core.game3.objects")
local Catalog = require("src.import.gba.map_catalog")

local here = Catalog.mapIdFor(0, 1)
local other = Catalog.mapIdFor(0, 2)
check(here and other and here ~= other, "the catalog resolves two distinct maps")

local savedMap = Objects._mapId
local savedById = Objects._byId
Objects._mapId = here
Objects._byId = { [7] = { localId = 7 } }

-- 1. set freezes the pair with the +83 bias applied by the script op and
--    nils any stale fixedClass (spec 5.8 record).
local ok = Objects.setSubpriority(7, 0, 1, 5 + 83)
eq(ok, true, "set succeeds for the current map")
eq(Objects._byId[7].fixedPriority, true, "fixedPriority is frozen")
eq(Objects._byId[7].subpriority, 88, "subpriority stores priority + 83")
Objects._byId[7].fixedClass = 1 -- stale class from an earlier freeze
Objects.setSubpriority(7, 0, 1, 10 + 83)
eq(Objects._byId[7].fixedClass, nil, "set nils a stale fixedClass before first observation")

-- 2. cross-map refusal (pret TryGetObjectEventIdByLocalIdAndMap).
local refused = Objects.setSubpriority(7, 0, 2, 7 + 83)
eq(refused, false, "a different (mapGroup, mapNum) is refused")
eq(Objects._byId[7].subpriority, 93, "the refused call left the record alone")

-- 3. unknown localId is a silent no-op (pret lookup failure).
eq(Objects.setSubpriority(99, 0, 1, 1), false, "unknown localId: set is a no-op")
eq(Objects.resetSubpriority(99, 0, 1), false, "unknown localId: reset is a no-op")

-- 4. reset drops all three fields and restores the dynamic path (no old
--    value is restored — pret event_object_movement.c:2104-2116).
Objects._byId[7].fixedClass = 2
eq(Objects.resetSubpriority(7, 0, 1), true, "reset succeeds for the current map")
eq(Objects._byId[7].fixedPriority, nil, "fixedPriority dropped")
eq(Objects._byId[7].subpriority, nil, "subpriority dropped")
eq(Objects._byId[7].fixedClass, nil, "fixedClass dropped (all three per spec 5.8)")

-- 5. no active map / no object: still safe.
Objects._byId = {}
eq(Objects.setSubpriority(7, 0, 1, 1), false, "no object after clear: no-op")

Objects._mapId = savedMap
Objects._byId = savedById

T.finish("game3_object_subpriority_test")
