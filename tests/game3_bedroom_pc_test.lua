#!/usr/bin/env luajit
-- pokefirered/src/player_pc.c:151 BedroomPC, pokefirered/src/player_pc.c:100 gNewGamePCItems

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

package.loaded["src.ui.game3.stack"] = {
  push = function() end,
  pop = function() end,
  busy = function() return false end,
  drawOrder = function() return {} end,
}
package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playCry = function() end,
}

print("[test] 1. BedroomPC special id + handler")
local Std = require("src.core.game3.scripting.stdscripts")
check(Std.SPECIAL.BedroomPC == 249, "BedroomPC = 249 (got " .. tostring(Std.SPECIAL.BedroomPC) .. ")")
local Natives = require("src.core.game3.scripting.natives")
check(Natives.ALLOW["special:249"] ~= nil, "special:249 handler registered")

print("[test] 2. special 249 yields into openPc with bedroom opts")
local gotOpts, gotDone
local ctx = { mode = "bytecode", status = "running" }
local adapters = {
  openPc = function(done, opts)
    gotDone = done
    gotOpts = opts
  end,
  log = function() end,
}
local yielded = Natives.special(ctx, 249, adapters)
check(yielded == true, "special 249 yields")
check(type(gotOpts) == "table" and gotOpts.bedroom == true, "openPc got bedroom=true")
check(ctx.nativePoll and ctx.nativePoll() == false, "native wait pending while PC open")
if gotDone then gotDone() end
check(ctx.nativePoll and ctx.nativePoll() == true, "native wait finishes on close")

print("[test] 3. host openPc routes bedroom into player_pc with closeOnExit")
do
  local shown
  local realPc = package.loaded["src.ui.game3.pc_menu"]
  local realRt = package.loaded["src.core.game3.runtime"]
  package.loaded["src.ui.game3.pc_menu"] = { show = function(o) shown = o end }
  package.loaded["src.core.game3.runtime"] = {
    isActive = function() return true end,
    getSession = function() return {} end,
  }
  local okA, Adapters = pcall(require, "src.core.game3.scripting.adapters")
  local okH, host = false, nil
  if okA then
    okH, host = pcall(Adapters.host, nil, {}, nil)
  end
  check(okH and host and host.openPc, "Adapters.host builds openPc")
  if okH and host and host.openPc then
    host.openPc(function() end, { bedroom = true })
    check(shown and shown.startMode == "player_pc" and shown.closeOnExit == true,
      "bedroom -> startMode player_pc, closeOnExit")
    shown = nil
    host.openPc(function() end)
    check(shown and shown.startMode == nil and not shown.closeOnExit, "no opts -> root hub")
  end
  package.loaded["src.ui.game3.pc_menu"] = realPc
  package.loaded["src.core.game3.runtime"] = realRt
end

print("[test] 4. PcMenu bedroom mode: starts in player_pc, B and LOG OFF close")
local PcMenu = require("src.ui.game3.pc_menu")
local function input(btn)
  return { wasPressed = function(_, b) return b == btn end }
end

local closed = 0
PcMenu.show({ session = {}, onClose = function() closed = closed + 1 end,
  startMode = "player_pc", closeOnExit = true })
check(PcMenu.mode == "player_pc", "starts in player_pc (got " .. tostring(PcMenu.mode) .. ")")
check(PcMenu._status == "What would you like to do?", "status What would you like to do?")
PcMenu.handleInput(input("b"))
check(not PcMenu.isOpen() and closed == 1, "B closes bedroom PC and fires onClose")

PcMenu.show({ session = {}, onClose = function() closed = closed + 1 end,
  startMode = "player_pc", closeOnExit = true })
PcMenu.handleInput(input("up"))
check(PcMenu.cursor == 4, "cursor on LOG OFF")
PcMenu.handleInput(input("a"))
check(not PcMenu.isOpen() and closed == 2, "LOG OFF closes bedroom PC")

PcMenu.show({ session = {}, onClose = function() closed = closed + 1 end })
check(PcMenu.mode == "root", "default show opens root hub")
PcMenu.cursor = 2
PcMenu.handleInput(input("a"))
check(PcMenu.mode == "player_pc", "hub -> player_pc")
PcMenu.handleInput(input("b"))
check(PcMenu.isOpen() and PcMenu.mode == "root" and closed == 2, "hub player_pc B returns to root")
PcMenu.close()

print("[test] 5. New game seeds PC POTION; withdraw moves it to bag; save round-trip")
local Schema = require("src.core.game3.save_schema_firered")
local Bag = require("src.core.game3.bag")
local Storage = require("src.core.game3.storage")
local session = Schema.newGame({ rngSeed = 1 })
local it = session.storage and session.storage.items and session.storage.items[1]
check(it and it.id == 13 and it.qty == 1, "newGame storage.items[1] = POTION x1")
check(session.storage and #session.storage.items == 1, "exactly one PC item")

local saved = Schema.toSaveTable(session)
check(type(saved.storage) == "table" and saved.storage.items[1] and saved.storage.items[1].id == 13,
  "toSaveTable writes storage")
local restored = Schema.fromSaveTable(saved)
check(restored.storage and restored.storage.items[1] and restored.storage.items[1].id == 13,
  "fromSaveTable restores storage")
local legacy = Schema.fromSaveTable({ map = "FR_PALLET_TOWN", x = 1, y = 1 })
check(legacy.storage == nil, "legacy save without storage gets no seeded POTION")

check(Storage.withdrawItem(session, 1, 1) == true, "withdrawItem POTION ok")
check(Bag.has(session.bag, 13, 1), "bag has POTION")
check(#session.storage.items == 0, "PC storage empty after withdraw")

if failed == 0 then
  print("\nAll game3 bedroom PC tests passed.")
  os.exit(0)
else
  print("\n" .. failed .. " bedroom PC test(s) failed.")
  os.exit(1)
end
