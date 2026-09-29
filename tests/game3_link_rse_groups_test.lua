#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local active = { version = "firered" }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return active end,
  isActive = function() return false end,
}

local Family = require("src.core.game3.link.family")
local Union = require("src.core.game3.link.union_room")
local Plaza = require("src.core.game3.link.union_plaza_map")
local Status = require("src.core.game3.link.status")
local RseGroups = require("src.core.game3.link.rse_groups")
local Protocol2 = require("src.online.Protocol2")
local Game3Link = require("src.link.Game3Link")

local function as(version, fn)
  local prev = active.version
  active.version = version
  local ok, err = pcall(fn)
  active.version = prev
  if not ok then check(false, version .. ": " .. tostring(err)) end
end

print("[test] activity ids per family")
as("firered", function()
  eq(Union.ACTIVITY.ITEM_TRADE, 14, "FR ITEM_TRADE")
  eq(Union.ACTIVITY.CONTEST_COOL, nil, "FR has no contest activity")
  eq(Union.INTERACT_START_MENU, 10, "FR start menu interact")
  eq(Plaza.MAP_ID, "FR_UNION_ROOM_PLAZA", "FR plaza id")
  eq(#Plaza.EXITS, 1, "FR plaza has one exit")
  eq(Union.COLOSSEUM_SEATS[0].script, "BattleColosseum_2P_EventScript_PlayerSpot0", "FR seat script")
end)
as("emerald", function()
  eq(Union.ACTIVITY.BATTLE_TOWER_OPEN, 14, "EM activity 14 is BATTLE_TOWER_OPEN")
  eq(Union.ACTIVITY.ITEM_TRADE, nil, "EM has no ITEM_TRADE")
  eq(Union.ACTIVITY.CONTEST_TOUGH, 27, "EM CONTEST_TOUGH")
  eq(Union.INTERACT_START_MENU, 11, "EM start menu interact")
  eq(Plaza.MAP_ID, "EM_UNION_ROOM_PLAZA", "EM plaza id")
  eq(Plaza.SOURCE_ID, "EM_UNION_ROOM", "EM plaza source")
  eq(#Plaza.EXITS, 2, "EM plaza keeps both cart exits")
  eq(Union.COLOSSEUM_SEATS[1].script, "EventScript_BattleColosseum_2P_PlayerSpot1", "EM seat script")
end)

print("[test] wire names never carry family-specific numbers")
as("firered", function()
  eq(Union.wireFor(Union.ACTIVITY.BERRY_PICK), "minigame_pick", "FR berry pick wire")
  eq(Union.wireFor(14), nil, "FR item trade has no wire")
  eq(Union.wireFor(15), nil, "FR record corner is not offered")
  eq(Family.activityForWire(nil, "record_corner"), nil, "FR never maps record_corner")
  eq(Family.activityForWire(nil, "contest_cool"), nil, "FR never maps contests")
  eq(Union.memberActivity({ group = { activity = "record_corner" } }), Union.ACTIVITY.NONE + Union.IN_UNION_ROOM,
    "an EM record corner member reads as idle to FR")
  eq(Union.GROUP_ACTIVITY[12], nil, "FR has no link group 12")
end)
as("emerald", function()
  eq(Union.wireFor(15), "record_corner", "EM record corner wire")
  eq(Union.wireFor(16), "berry_blender", "EM blender wire")
  eq(Union.wireFor(14), "battle_tower_open", "EM tower open wire")
  eq(Union.wireFor(28), "battle_tower", "EM tower wire")
  eq(Union.wireFor(23 + 0x40), "contest_cool", "IN_UNION_ROOM bit ignored")
  eq(Union.GROUP_ACTIVITY[12].activity, 15, "EM group 12 is record corner")
  eq(Union.GROUP_ACTIVITY[13].max, 4, "EM blender max 4")
  eq(Union.memberActivity({ group = { activity = "record_corner" } }), 15 + Union.IN_UNION_ROOM,
    "an EM record corner member reads as record corner to EM")
end)
for _, wire in ipairs(Protocol2.LINK_ACTIVITIES) do
  eq(Protocol2.ACTIVITY_RULESET[wire], "g3_link", wire .. " ruleset")
  eq(Protocol2.ACTIVITY_INTENT[wire], "link", wire .. " intent")
  check(Protocol2.GROUP_CAPACITY[wire] ~= nil, wire .. " has a capacity")
end
check(Protocol2.INTENTS.link, "link intent")
check(Protocol2.DIRECT_ACTIVITIES.record_corner and not Protocol2.DIRECT_ACTIVITIES.battle_tower,
  "direct corner offers record_corner, not the tower")

print("[test] link group registry")
local rc = RseGroups.get("record_corner")
check(rc ~= nil and Union.linkTypeOf(rc) == Game3Link.LINKTYPE.RECORD_MIX_BEFORE, "record_corner registered")
check(rc and rc.dest == Union.RECORD_CORNER and rc.service == "RECORD_CORNER", "record_corner warps to the corner")
local bb = RseGroups.get("berry_blender")
check(bb ~= nil and Union.linkTypeOf(bb) == Game3Link.LINKTYPE.BERRY_BLENDER_SETUP, "berry_blender registered")
check(Union.linkTypeOf({ linkType = 0x2288 }) == 0x2288, "numeric linkType passes through")

print("[test] text keys per family")
as("firered", function()
  eq(Family.textKey("gText_UR_TrainerAppearsBusy"), "gText_UR_TrainerAppearsBusy", "FR keeps its key")
end)
as("emerald", function()
  eq(Family.textKey("gText_UR_RegisterMonAtTradingBoard"), "sText_RegisterMonAtTradingBoard", "EM board text")
  eq(Family.textKey("gText_UR_RegistraionCompleted"), "sText_RegistrationCompleted", "EM typo fixed")
  eq(Family.textKey("gTexts_UR_BattleReaction[1][2]"), "sBattleReactionTexts[1][2]", "EM table index kept")
  eq(Family.textKey("sListMenuItems_InviteToActivity[2]"), "sText_Chat2", "EM invite list item")
  eq(Family.textKey("sListMenuItems_TypeNames[1]"), "gTypeNames[10]", "EM type row 1 is FIRE")
  eq(Family.textKey("CableClub_Text_PleaseWaitBCancel"), "gText_PleaseWaitForLink", "EM wait text")
end)

print("[test] link avatars follow CreateLinkPlayerSprite")
as("firered", function()
  eq(select(2, Family.linkPlayerGfx(nil, "leafgreen", 1)), "OBJ_EVENT_GFX_GREEN_NORMAL", "FR sees LG as GREEN")
  eq(select(2, Family.linkPlayerGfx(nil, "emerald", 0)), "OBJ_EVENT_GFX_RS_BRENDAN", "FR sees EM as RS BRENDAN")
end)
as("emerald", function()
  eq(select(2, Family.linkPlayerGfx(nil, "firered", 0)), "OBJ_EVENT_GFX_RED", "EM sees FR as RED")
  eq(select(2, Family.linkPlayerGfx(nil, "leafgreen", 1)), "OBJ_EVENT_GFX_LEAF", "EM sees LG as LEAF")
  eq(select(2, Family.linkPlayerGfx(nil, "emerald", 1)), "OBJ_EVENT_GFX_RIVAL_MAY_NORMAL", "EM sees EM as MAY")
end)

print("[test] status screen table per family")
as("firered", function()
  local c = Status.counts({ { activity = Union.ACTIVITY.RECORD_CORNER, members = 3 },
    { activity = Union.ACTIVITY.BATTLE_SINGLE, members = 2 } })
  eq(c[Status.GROUPTYPE.BATTLE], 2, "FR battle count")
  eq(c[Status.GROUPTYPE.TOTAL], 2, "FR total drops record corner")
end)
as("emerald", function()
  local c = Status.counts({ { activity = 15, members = 3 }, { activity = 28, members = 2 },
    { activity = 23, members = 4 } })
  eq(c[Status.GROUPTYPE.BATTLE], 2, "EM tower counts as battle")
  eq(c[Status.GROUPTYPE.TOTAL], 9, "EM total includes record corner and contests")
end)
local pc = Status.fromPlaza({ trade = 2, battle = 2, union = 3, link = 4 })
eq(pc[Status.GROUPTYPE.TOTAL], 11, "relay link count reaches the total")

if failed > 0 then
  print(("[FAIL] %d check(s) failed"):format(failed))
  os.exit(1)
end
print("[PASS] link rse groups")
