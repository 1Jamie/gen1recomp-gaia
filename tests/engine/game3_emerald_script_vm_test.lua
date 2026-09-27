package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local prevVersion = GameVersion.get()
GameVersion.set("firered")

local Ctx = require("src.core.game3.scripting.ctx")
local Vm = require("src.core.game3.scripting.vm")
local Ops = require("src.core.game3.scripting.ops_a")
local OpsRse = require("src.core.game3.scripting.ops_rse")
local Opcodes = require("src.core.game3.scripting.opcodes")
local Adapters = require("src.core.game3.scripting.adapters")
local Movement = require("src.core.game3.scripting.movement")
local Flags = require("src.core.game3.scripting.flags")
local Capabilities = require("src.core.game3.capabilities")
local Natives = require("src.core.game3.scripting.natives")
local Tv = require("src.core.game3.rse.tv")
local BerryTrees = require("src.core.game3.rse.berry_trees")
local Rse = require("src.core.game3.rse.init")

print("[test] 1. special var layout and family per game")
eq(Ctx.SPECIAL_LAYOUTS.frlg.family, "frlg", "frlg layout names its family")
eq(Ctx.SPECIAL_LAYOUTS.rse.family, "rse", "rse layout names its family")
eq(Ctx.new({ version = "emerald" }).specialLayout.family, "rse", "an Emerald ctx carries the rse layout")
eq(Ctx.new({ version = "firered" }).specialLayout.family, "frlg", "a FireRed ctx carries the frlg layout")
eq(Ctx.new({ version = "emerald" }).specialVars[0x8012], nil, "Emerald ctx seeds no text colour in VAR_MON_BOX_ID")

print("[test] 2. step callbacks per family")
eq(Ctx.setStepCallback(Ctx.STEP_CB.TRUCK, "FR_X"), nil, "FireRed drops STEP_CB_TRUCK (FR never sets it)")
eq(Ctx.setStepCallback(Ctx.STEP_CB.ICE, "FR_X"), "ice", "FireRed keeps STEP_CB_ICE")
GameVersion.set("emerald")
eq(Ctx.setStepCallback(Ctx.STEP_CB.TRUCK, "EM_INSIDE_OF_TRUCK"), "truck", "Emerald maps STEP_CB_TRUCK to truck")
eq(Ctx.setStepCallback(Ctx.STEP_CB.ICE, "EM_X"), "sootopolisIce", "Emerald STEP_CB 4 is SOOTOPOLIS_ICE")
Ctx.resetStepCallback()
GameVersion.set("firered")

print("[test] 3. Emerald tail opcodes dispatch through ops_rse, FireRed never does")
local EMTAIL = require("src.core.game3.scripting.opcodes_emerald")
local rseOnly = {}
for byte = 0xD3, 0xE1 do
  local name = EMTAIL[byte].name
  rseOnly[#rseOnly + 1] = name
  check(OpsRse.HANDLERS[name] ~= nil, string.format("0x%02X %s has an ops_rse handler", byte, name))
end
eq(EMTAIL[0xE2].name, "bufferitemnameplural", "0xE2 is bufferitemnameplural (same operands as FR)")
for _, name in ipairs({ "initclock", "dotimebasedevents", "gettime", "setberrytree", "getpokenewsactive",
    "choosecontestmon", "startcontest", "showcontestresults", "contestlinktransfer", "adddecoration",
    "removedecoration", "checkdecor", "checkdecorspace", "showcontestpainting" }) do
  check(OpsRse.HANDLERS[name] ~= nil, "changed op " .. name .. " is routed by ops_rse")
end

local function newVm(version, scripts)
  local logs = {}
  local vm = Vm.new({
    version = version,
    scripts = scripts or {},
    adapters = Adapters.stub({}),
  })
  vm.adapters.log = function(m) logs[#logs + 1] = m end
  return vm, logs
end

local seen = {}
local origHandlers = {}
for name, fn in pairs(OpsRse.HANDLERS) do
  origHandlers[name] = fn
  OpsRse.HANDLERS[name] = function(vm, row, H)
    seen[#seen + 1] = name
    return false
  end
end
local frVm, frLogs = newVm("firered")
Ops.dispatch(frVm, { op = "gettime" })
eq(#seen, 0, "a FireRed VM never reaches ops_rse")
eq(frVm.ctx.specialVars[0x8000], 0, "FireRed gettime keeps the zero clock")
local emVm = newVm("emerald")
Ops.dispatch(emVm, { op = "gettime" })
eq(seen[1], "gettime", "an Emerald VM routes gettime through ops_rse")
for name, fn in pairs(origHandlers) do OpsRse.HANDLERS[name] = fn end

print("[test] 4. every Emerald opcode name is handled (no skip op)")
GameVersion.set("emerald")
local set = Opcodes.forGame("emerald")
local skipped = {}
for byte = 0, set.MAX do
  local row = set:get(byte)
  if row then
    local vm, logs = newVm("emerald")
    vm.ctx.status = "running"
    vm.ctx.mode = "bytecode"
    vm.ctx.pc = { listKey = "t", index = 1 }
    local args = { op = row.name }
    for i = 1, #(row.args or {}) do args[i] = 0 end
    pcall(Ops.dispatch, vm, args)
    for _, m in ipairs(logs) do
      if tostring(m):find("skip op", 1, true) then skipped[#skipped + 1] = row.name end
    end
  end
end
eq(#skipped, 0, "no Emerald opcode falls to skip op (" .. table.concat(skipped, ",") .. ")")
GameVersion.set("firered")

print("[test] 5. ops_rse semantics with stub systems")
GameVersion.set("emerald")
local planted
Rse.register("berryTrees", { plant = function(id, berry, stage, allow) planted = { id, berry, stage, allow } end })
local vm5 = newVm("emerald")
Ops.dispatch(vm5, { op = "setberrytree", 3, 7, 5 })
check(planted and planted[1] == 3 and planted[2] == 7 and planted[3] == 5 and planted[4] == false,
  "setberrytree plants through the berryTrees system with growth stopped (scrcmd.c:1924)")
Rse._systems.berryTrees = nil
local vm6, logs6 = newVm("emerald")
Rse.reset()
Rse.register("decorations", nil)
Ops.dispatch(vm6, { op = "checkdecor", 5 })
eq(Flags.getVar(vm6.store, vm6.ctx, 0x800D), 0, "checkdecor without a decoration system leaves VAR_RESULT FALSE")
local logged = false
for _, m in ipairs(logs6) do if tostring(m):find("decorations", 1, true) then logged = true end end
check(logged, "a missing decoration system logs once by name")
local vm7 = newVm("emerald")
vm7.ctx.stringVars = { "", "", "" }
local Trainers = require("src.core.game3.scripting.trainers")
local origGet = Trainers.get
Trainers.get = function(id) return { className = "YOUNGSTER", name = "CALVIN" } end
Ops.dispatch(vm7, { op = "buffertrainerclassname", 0, 5 })
Ops.dispatch(vm7, { op = "buffertrainername", 1, 5 })
Trainers.get = origGet
eq(vm7.ctx.stringVars[1], "YOUNGSTER", "buffertrainerclassname fills STR_VAR_1 (scrcmd.c:2273)")
eq(vm7.ctx.stringVars[2], "CALVIN", "buffertrainername fills STR_VAR_2 (scrcmd.c:2282)")
GameVersion.set("firered")

print("[test] 6. canonical RSE movement actions decode by name")
local MoveEm = require("src.import.gba.movement_emerald")
eq(Movement.decodeAction(MoveEm.canonOf("MOVEMENT_ACTION_EMOTE_HEART")).kind, "emote", "EMOTE_HEART is an emote")
eq(Movement.decodeAction(MoveEm.canonOf("MOVEMENT_ACTION_EMOTE_HEART")).emoteType, "heart", "EMOTE_HEART is a heart")
local diag = Movement.decodeAction(MoveEm.canonOf("MOVEMENT_ACTION_WALK_SLOW_DIAGONAL_UP_LEFT"))
check(diag.kind == "step_diagonal" and diag.dx == -1 and diag.dy == -1 and diag.slow == true,
  "WALK_SLOW_DIAGONAL_UP_LEFT is a slow diagonal step")
eq(Movement.decodeAction(MoveEm.canonOf("MOVEMENT_ACTION_LOCK_ANIM")).kind, "lock_anim", "LOCK_ANIM decodes")
local nopCount = 0
for v = 0x100, 0x116 do
  local a = Movement.decodeAction(v)
  if a.kind == "nop" then nopCount = nopCount + 1 end
end
eq(nopCount, 0, "every canonical 0x100+ action decodes to a real kind")
eq(Movement.decodeAction(0x10).kind, "step", "FR 0x10 WALK_DOWN is unchanged")
eq(Movement.decodeAction(0x10).dir, "down", "FR 0x10 still walks down")

print("[test] 7. TV minimal state (tv.c)")
local sess = {}
eq(Tv.getRandomActiveShowIdx(sess, function() return 3 end), 0xFF, "no show on the air -> 255 (tv.c:775)")
sess.tvShows[2] = { kind = 3, active = true }
eq(Tv.getRandomActiveShowIdx(sess, function() return 4 end), 2, "an active normal show is found walking down")
eq(Tv.selectedShowKind(sess, 2), 3, "GetSelectedTVShow reads the slot kind")
sess.tvShows[4] = { kind = Tv.TVSHOW_MASS_OUTBREAK, active = true, daysBeforeOutbreak = 0 }
sess.outbreakPokemonSpecies = 0
eq(Tv.nextActiveIfMassOutbreak(sess, 4), 4, "an outbreak show without a species keeps its slot")
sess.outbreakPokemonSpecies = 286
eq(Tv.nextActiveIfMassOutbreak(sess, 4), 2, "an active outbreak skips to the first normal show")
eq(Tv.findPokeNewsOnAir({}), 0xFF, "no PokeNews on the air")
check(not Tv.isGabbyAndTyOnAir({}), "Gabby and Ty are off the air on a new game")
local function news(g, n, gender, flags)
  return Tv.checkForPlayersHouseNews({ mapGroup = g, mapNum = n, housesGroup = 1, brendanNum = 0, mayNum = 2,
    gender = gender, flag = function(name) return flags[name] == true end })
end
eq(news(1, 0, 0, {}), Tv.PLAYERS_HOUSE_TV_LATI, "Brendan's 1F before the broadcast flashes (tv.c:3383)")
eq(news(1, 0, 0, { FLAG_SYS_TV_HOME = true }), Tv.PLAYERS_HOUSE_TV_MOVIE, "after the broadcast the TV shows a movie")
eq(news(1, 0, 0, { FLAG_SYS_TV_HOME = true, FLAG_SYS_TV_LATIAS_LATIOS = true }), Tv.PLAYERS_HOUSE_TV_LATI,
  "the Lati news flash wins over the movie")
eq(news(1, 2, 0, {}), Tv.PLAYERS_HOUSE_TV_NONE, "May's house is not the male player's house")
eq(news(1, 2, 1, {}), Tv.PLAYERS_HOUSE_TV_LATI, "May's house is the female player's house")
eq(news(3, 0, 0, {}), Tv.PLAYERS_HOUSE_TV_NONE, "another map group has no house news")
local temp3 = 0
local function momOrDad(g, n, r)
  return Tv.momOrDad({ mapGroup = g, mapNum = n, housesGroup = 1, brendanNum = 0, mayNum = 2, gender = 0,
    random = function() return r end, getTemp3 = function() return temp3 end, setTemp3 = function(v) temp3 = v end })
end
eq(momOrDad(1, 0, 0), "mom", "the player's own house always says MOM")
eq(temp3, 1, "and remembers it in VAR_TEMP_3")
temp3 = 0
eq(momOrDad(5, 5, 0), "dad", "elsewhere an even roll picks DAD (tv.c:3430)")
eq(temp3, 2, "DAD is remembered as 2")
eq(momOrDad(5, 5, 1), "dad", "a remembered choice sticks")
temp3 = 5
eq(momOrDad(5, 5, 0), "dad", "odd VAR_TEMP_3 > 2 says DAD")
local layout = { width = 3, height = 2 }
local set = {}
eq(Tv.setScreens(layout, function(x, y) return (x == 1 and y == 0) and "tv" or "floor" end,
  function(x, y, m) set[#set + 1] = { x, y, m } end, function(b) return b == "tv" end, Tv.METATILE_TV_OFF), 1,
  "SetTVMetatilesOnMap touches only TV behaviours")
check(set[1] and set[1][1] == 1 and set[1][2] == 0 and set[1][3] == 0x002, "TV cell gets METATILE_Building_TV_Off")

print("[test] 8. berry tree planting (berry.c:1116)")
BerryTrees.reset()
local berries = { [0] = { stageDuration = 3, minYield = 2, maxYield = 3 }, [4] = { stageDuration = 6, minYield = 3, maxYield = 5 } }
local origBerries = BerryTrees.berries
BerryTrees.berries = function() return berries end
local bs = {}
BerryTrees.plant(7, 5, 1, false, bs, function() return 0 end)
local tree = bs.berryTrees[7]
eq(tree.berry, 5, "planted berry")
eq(tree.minutesUntilNextStage, 360, "stage duration is stageDuration * 60")
eq(tree.stopGrowth, true, "scripted trees stop growing until seen")
BerryTrees.plant(8, 5, BerryTrees.STAGE_BERRIES, true, bs, function() return 0 end)
eq(bs.berryTrees[8].berryYield, 3, "an unwatered tree in BERRIES yields minYield")
eq(bs.berryTrees[8].minutesUntilNextStage, 1440, "a tree planted with berries waits 4 stages")
eq(bs.berryTrees[8].stopGrowth, false, "allowGrowth keeps the tree growing")
eq(BerryTrees.yieldInternal(5, 3, 4, function() return 0 end), 5, "four waterings reach the max yield band")
BerryTrees.plant(9, 0, 1, true, bs, function() return 0 end)
eq(bs.berryTrees[9].minutesUntilNextStage, 180, "berry 0 reads the first berry (berry.c:988)")
BerryTrees.berries = origBerries

print("[test] 9. RSE natives modules are gated off FireRed")
for _, m in ipairs({ "natives_tv", "natives_field_rse", "natives_clock" }) do
  check(Capabilities.nativeFeature(m) ~= nil, m .. " has a FEATURES row")
  eq(Capabilities.nativeAllowed({ version = "firered" }, m), false, m .. " is filtered on FireRed")
  eq(Capabilities.nativeAllowed({ version = "emerald" }, m), true, m .. " is allowed on Emerald")
end
Natives.bind("firered")
eq(Natives.MODULES.natives_tv, nil, "FireRed never loads natives_tv")
Natives.bind("emerald")
for _, name in ipairs({ "ResetTVShowState", "CheckForPlayersHouseNews", "IsGabbyAndTyShowOnTheAir",
    "GetRandomActiveShowIdx", "GetNextActiveShowIfMassOutbreak", "GetSelectedTVShow", "GetMomOrDadStringForTVMessage",
    "TurnOnTVScreen", "TurnOffTVScreen", "DoTVShow", "DoPokeNews", "DoTVShowInSearchOfTrainers",
    "GetPlayerBigGuyGirlString", "GetRivalSonDaughterString", "ChooseStarter", "InitSecretBaseDecorationSprites",
    "EnableNationalPokedex", "StartWallClock", "DrawWholeMapView", "ShakeCamera", "SpawnCameraObject",
    "RemoveCameraObject" }) do
  check(Natives.BY_NAME[name] ~= nil, "Emerald binds " .. name .. " by name")
end
local EMS = require("src.core.game3.constants").of("emerald").specials
eq(Natives.ALLOW["special:" .. EMS.byName.ChooseStarter], Natives.BY_NAME.ChooseStarter,
  "ChooseStarter binds to its Emerald special id")
Natives.bind("firered")

print("[test] 10. starter choose sprite timing (sprite.c)")
local SC = require("src.ui.game3.rse.starter_choose")
local A = SC._affine
local aff = A.new({ { op = "frame", xScale = 16, duration = 0 }, { op = "frame", xScale = 16, duration = 15 }, { op = "end" } })
local scales = {}
for f = 1, 18 do
  A.step(aff)
  scales[f] = aff.scale
  if aff.ended then break end
end
eq(scales[1], 16, "frame 1 sets the absolute scale")
eq(scales[2], 32, "frame 2 adds the first delta")
eq(scales[16], 256, "the starter reaches full size on frame 16")
eq(#scales, 17, "the affine anim ends on frame 17")
local anim = { { { op = "frame", frame = 0, duration = 30 }, { op = "end" } },
  { { op = "frame", frame = 1, duration = 4 }, { op = "frame", frame = 0, duration = 4 }, { op = "jump", target = 0 } } }
local st = { anims = anim, num = 2, cmd = 1, delay = 0, frame = 0, started = false }
local frames = {}
for f = 1, 10 do
  SC._anim.step(st)
  frames[f] = st.frame
end
eq(table.concat(frames, ""), "1111000011", "a 4-frame ANIMCMD shows 4 frames and the jump loops")

GameVersion.set(prevVersion)
T.finish()
