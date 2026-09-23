#!/usr/bin/env luajit
-- pokefirered/data/scripts/pc.inc:1

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

local events = {}
package.loaded["src.ui.game3.stack"] = {
  push = function() end,
  pop = function() end,
  busy = function() return false end,
  drawOrder = function() return {} end,
}
package.loaded["src.core.game3.audio"] = {
  playSe = function(id) events[#events + 1] = "se" .. tostring(id) end,
  playCry = function() end,
}

local function input(key)
  return { wasPressed = function(_, k) return k == key end, isDown = function() return false end }
end

local function seOnly()
  local out = {}
  for _, e in ipairs(events) do
    if e:sub(1, 2) == "se" then out[#out + 1] = e end
  end
  return table.concat(out, ",")
end

local Player = require("src.core.game3.player")
Player.cellX, Player.cellY, Player.facing = 5, 10, "up"
local PcAnim = require("src.core.game3.pc_anim")
PcAnim.setter(function() end)
local realTurnOn = PcAnim.turnOn
PcAnim.turnOn = function(...)
  events[#events + 1] = "anim_on"
  return realTurnOn(...)
end

local Std = require("src.core.game3.scripting.stdscripts")
local PcMenu = require("src.ui.game3.pc_menu")
local Bag = require("src.core.game3.bag")
local Storage = require("src.core.game3.storage")
local function session() return { bag = Bag.new(), storage = Storage.new(), name = "RED" } end

print("[test] 1. EventScript_PC carries playse SE_PC_ON right after AnimatePcTurnOn")
local rows = Std.SCRIPTS.EventScript_PC
local onIdx, animIdx
for i, r in ipairs(rows) do
  if r.op == "special" and r.id == Std.SPECIAL.AnimatePcTurnOn then animIdx = i end
  if r.op == "playse" and r[1] == 4 then onIdx = i end
end
check(animIdx ~= nil and onIdx == animIdx + 1, "playse 4 follows AnimatePcTurnOn")

print("[test] 2. Center PC flow: ON, message, menu, storage LOGIN, LOG OFF")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local vm = Vm.new({
  scripts = Std.SCRIPTS,
  text = Std.TEXT,
  adapters = Adapters.stub({
    onMessage = function() events[#events + 1] = "msg" end,
    openPc = function(done)
      events[#events + 1] = "menu"
      PcMenu.show({ session = session() })
      PcMenu.handleInput(input("a"))
      PcMenu.close()
      done()
    end,
  }),
})
check(vm:start("EventScript_PC") == true, "vm started EventScript_PC")
local steps = 0
while vm:isRunning() and steps < 80 do vm:step(); steps = steps + 1 end
check(not vm:isRunning(), "EventScript_PC completed")
local seq = table.concat(events, ",")
check(seq == "anim_on,se4,msg,menu,se5,se2,se3",
  "ordered events anim_on,se4,msg,menu,se5,se2,se3 (got " .. seq .. ")")

local function flagged(dex, clear)
  local s = session()
  s.flags = {}
  local Space = package.loaded["src.core.game3.scripting.space"]
  local stores = { s }
  if Space and Space.store then Space.store.flags = Space.store.flags or {}; stores[2] = Space.store end
  for _, st in ipairs(stores) do
    st.flags[0x829] = dex or nil
    st.flags[0x82C] = clear or nil
  end
  return s
end

local function rowIds()
  local ids = {}
  for _, r in ipairs(PcMenu._rootEntries()) do ids[#ids + 1] = r.id end
  return table.concat(ids, ",")
end

print("[test] 3. root rows gate on POKEDEX_GET / GAME_CLEAR (script_menu.c:1006)")
for _, c in ipairs({
  { false, false, "storage,player,quit" },
  { true, false, "storage,player,oak,quit" },
  { true, true, "storage,player,oak,hall,quit" },
  { false, true, "storage,player,oak,hall,quit" },
}) do
  PcMenu.show({ session = flagged(c[1], c[2]) })
  local got = rowIds()
  check(got == c[3], string.format("dex=%s clear=%s rows %s (got %s)", tostring(c[1]), tostring(c[2]), c[3], got))
  PcMenu.close()
end

print("[test] 4. root menu open plays nothing; each access row plays SELECT then LOGIN")
for i, id in ipairs({ "storage", "player", "oak", "hall" }) do
  local s = flagged(true, true)
  events = {}
  PcMenu.show({ session = s })
  check(seOnly() == "", id .. ": root open plays no SE")
  PcMenu.cursor = i
  check(PcMenu._rootEntries()[i].id == id, id .. " is root row " .. i)
  PcMenu.handleInput(input("a"))
  check(seOnly() == "se5,se2", id .. ": A plays se5,se2 (got " .. seOnly() .. ")")
  PcMenu.close()
end

print("[test] 5. LOG OFF and B play SE_SELECT then SE_PC_OFF")
for _, c in ipairs({ { false, false, 3 }, { true, false, 4 }, { true, true, 5 } }) do
  events = {}
  PcMenu.show({ session = flagged(c[1], c[2]) })
  PcMenu.cursor = c[3]
  check(PcMenu._rootEntries()[c[3]].id == "quit", "LOG OFF is row " .. c[3])
  PcMenu.handleInput(input("a"))
  check(seOnly() == "se5,se3", "LOG OFF row " .. c[3] .. " plays se5,se3 (got " .. seOnly() .. ")")
end
events = {}
PcMenu.show({ session = flagged(false, false) })
PcMenu.handleInput(input("b"))
check(seOnly() == "se5,se3", "B plays se5,se3 (got " .. seOnly() .. ")")

print("[test] 6. bedroom player_pc open plays nothing")
events = {}
PcMenu.show({ session = session(), startMode = "player_pc", closeOnExit = true })
check(seOnly() == "", "bedroom open plays no SE")
events = {}
PcMenu.handleInput(input("b"))
check(seOnly() == "se5,se3", "bedroom TURN OFF plays se5,se3 once (got " .. seOnly() .. ")")

print("[test] 7. Hud.openPc boots with SE_PC_ON")
local okHud, Hud = pcall(require, "src.ui.game3.hud")
check(okHud, "hud loads (" .. tostring(okHud and "" or Hud) .. ")")
if okHud then
  events = {}
  Hud.openPc(nil, session())
  check(seOnly() == "se4", "Hud.openPc plays se4 (got " .. seOnly() .. ")")
  PcMenu.close()
end

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[ok] all checks passed")
