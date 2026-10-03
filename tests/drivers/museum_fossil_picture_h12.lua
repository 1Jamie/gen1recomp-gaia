local U = require("tests.drivers.util")

return function(game)
  local started = love.timer.getTime()
  local timeout = tonumber(os.getenv("POKEPORT_DRIVER_TIMEOUT")) or 30
  local function waitFor(test, label, frames)
    for _ = 1, frames or 1200 do
      if test() then return end
      assert(love.timer.getTime() - started < timeout, "watchdog: " .. label)
      U.wait(1)
    end
    error("did not settle: " .. label)
  end
  local ok, err = xpcall(function()
    waitFor(function() return game.phase == "boot" and game.boot end, "native boot")
    game:_handleBootAction({ action = "new_game", name = "RED" })
    local Runtime = require("src.core.game3.runtime")
    local Map = require("src.core.game3.map")
    local Space = require("src.core.game3.scripting.space")
    local Catalog = require("src.import.gba.map_catalog")
    local Constants = require("src.core.game3.constants")
    local Message = require("src.ui.game3.message")
    local Fade = require("src.ui.game3.fade")
    local Museum = require("src.ui.game3.museum_fossil_pic")
    local Window = require("src.ui.game3.window")
    local Serializer = require("src.core.SaveSerializer")
    local version = require("src.core.GameVersion").get()
    assert(version == "firered" or version == "leafgreen", "run on FireRed or LeafGreen")
    local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/h12-museum"
    waitFor(function() return Runtime.getSession() ~= nil and game.phase == "field" end, "new field")
    waitFor(function() return not Fade.isActive() and Fade.t == 0 and not Fade.lockInput end, "uncovered new field")
    local target = Catalog.pretToEngine("PewterCity_Museum_1F")
    Map.load(nil, game, target, { x = 9, y = 7, facing = "up" })
    game.session.x, game.session.y, game.session.facing = 9, 7, "up"
    waitFor(function() return Space.vm and Space.mapId == target and not Space.vm:isRunning() end, "museum field")
    local keys = {}
    local openId = Constants.of(version).specials.byName.OpenMuseumFossilPic
    for key, rows in pairs(Space.vm.scripts) do
      local species
      for _, row in ipairs(rows) do
        if row.op == "setvar" and row.var == 0x8004 then species = row.value end
        if row.op == "special" and row.id == openId and (species == 141 or species == 142) then keys[species] = key end
      end
    end
    assert(keys[141] and keys[142], "actual imported exhibit scripts missing")
    local session = Runtime.getSession()
    local preserved = Serializer.encode({ flags = session.flags, dex = session.dex, bag = session.bag,
      money = session.money, modData = session.modData })
    for _, row in ipairs({ {141, "kabutops"}, {142, "aerodactyl"} }) do
      local species, name = row[1], row[2]
      assert(Space.startScript(keys[species]), "actual exhibit script failed to start")
      waitFor(function() return Message.isOpen() and Museum.isActive() end, name .. " picture with description")
      Message.skipReveal()
      waitFor(function() return Message.isWaiting() and Space.vm.ctx.mode == "native" end, name .. " description acknowledgement")
      waitFor(function() return not Fade.isActive() and Fade.t == 0 end, name .. " uncovered description")
      assert(Message.currentPage():lower():find(name, 1, true), "ROM description does not match fossil")
      local state = assert(Space.vm.ctx.museumFossilPic)
      assert(state.species == species and state.x == 10 and state.y == 3, "actual script picture arguments")
      local frame, originalFrame = nil, Window.stdFrame
      Window.stdFrame = function(tpl)
        if tpl.w == 8 and tpl.h == 8 then frame = { tpl.left, tpl.top, tpl.w, tpl.h } end
        return originalFrame(tpl)
      end
      local captured = U.still(game, out .. "/h12-" .. version .. "-" .. name .. "-description.png")
      Window.stdFrame = originalFrame
      assert(captured, "exhibit capture did not reach disk")
      assert(frame and frame[1] == 11 and frame[2] == 4, "source8x8 content frame was not rendered")
      assert(Message.isOpen() and Museum.isActive(), "capture lost coexistence")
      for _ = 1, 180 do
        if not Space.vm:isRunning() then break end
        U.tap(game, "a"); U.wait(2)
        if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
      end
      waitFor(function() return not Space.vm:isRunning() and not Message.isOpen() and not Museum.isActive() end, name .. " acknowledgement closes exhibit")
      waitFor(function() return not Fade.isActive() and Fade.t == 0 end, name .. " uncovered closed exhibit")
      assert(Space.vm.ctx.museumFossilPic == nil, "closed exhibit retained context")
      assert(U.still(game, out .. "/h12-" .. version .. "-" .. name .. "-closed.png"), "closed capture missing")
      assert(Serializer.encode({ flags = session.flags, dex = session.dex, bag = session.bag,
        money = session.money, modData = session.modData }) == preserved, "exhibit mutated saved gameplay state")
      print("PASS H12 " .. version .. " " .. name .. " actual imported script, art, description and close")
    end
  end, debug.traceback)
  if not ok then print("FAIL H12 museum fossil picture: " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
  while true do coroutine.yield() end
end
