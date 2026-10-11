-- ram/wram.asm:1749, ram/wram.asm:1780, ram/wram.asm:2219
-- run save, then continue (a fresh boot) on the same identity:
--   FLASH2863_PHASE=save     tools/run_driver.sh red 2863-red tests/drivers/flash_save_continue_2863.lua /tmp/shots2863
--   FLASH2863_PHASE=continue tools/run_driver.sh red 2863-red tests/drivers/flash_save_continue_2863.lua /tmp/shots2863
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Probe = dofile("tests/drivers/shot_probe.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local Pokemon = require("src.pokemon.Pokemon")
  local GameVersion = require("src.core.GameVersion")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots2863"
  local PHASE = os.getenv("FLASH2863_PHASE") or "save"
  local V = GameVersion.get()
  local MAP = "ROCK_TUNNEL_1F"

  local fails = 0
  local function check(ok, msg)
    print((ok and "PASS " or "FAIL ") .. V .. " " .. PHASE .. ": " .. msg)
    if not ok then fails = fails + 1 end
    return ok
  end

  local CAVE = PaletteFX.pal(game.data, "CAVE")
  local caveDark = PaletteFX.permute(CAVE, PaletteFX.DARK_BGP)
  local CORNER = { 0.02, 0.02, 0.28, 0.28 }

  local function forceGbc()
    game.save.options = game.save.options or {}
    game.save.options.colors = "gbc"
    PaletteFX.setMode("gbc")
  end

  local function settle()
    for _ = 1, 600 do
      if game.stack:top() == game.overworld and not game.overworld.transitioning then break end
      U.wait(1)
    end
    U.wait(30)
  end

  local function lightState(label, shot, wantLit)
    local ow = game.overworld
    check(ow and ow.map and ow.map.id:match("^ROCK_TUNNEL"),
          label .. ": standing in " .. tostring(ow and ow.map and ow.map.id))
    check(game.save.flashLit == (wantLit or nil),
          label .. ": save.flashLit=" .. tostring(game.save.flashLit))
    check(ow and ow.dark == not wantLit, label .. ": overworld.dark=" .. tostring(ow and ow.dark))
    check(PaletteFX.darkWorld() == not wantLit,
          label .. ": PaletteFX.darkWorld=" .. tostring(PaletteFX.darkWorld()))
    local path = DIR .. "/" .. shot
    local grab
    if U.still(game, path) then
      local f = io.open(path, "rb")
      local bytes = f and f:read("*a")
      if f then f:close() end
      if bytes then
        grab = love.image.newImageData(love.filesystem.newFileData(bytes, shot))
      end
    end
    if grab then
      local c, total = Probe.count(grab, { litPaper = CAVE[1], litMid = CAVE[2],
                                           darkPaper = caveDark[1] }, 3, CORNER)
      print(("[driver] %s corner %d px litPaper=%d litMid=%d darkPaper=%d")
            :format(label, total, c.litPaper, c.litMid, c.darkPaper))
      if wantLit then
        check(c.litPaper > 0 or c.litMid > 0, label .. ": corner pixels are lit CAVE colours")
      else
        check(c.litPaper == 0 and c.litMid == 0 and c.darkPaper > 0,
              label .. ": corner pixels are FadePal2-darkened")
      end
    else
      print("[driver] WARN no frame capture for " .. label)
    end
    check(not wantLit == (PaletteFX.shadeMap() == PaletteFX.DARK_BGP),
          label .. ": last frame armed DARK_BGP=" .. tostring(PaletteFX.shadeMap() == PaletteFX.DARK_BGP))
  end

  local function topIs(mt) local t = game.stack:top() return t and getmetatable(t) == mt end

  local function pickStart(label)
    U.tap(game, "start")
    U.wait(20)
    local menu = game.stack:top()
    local want
    for i, it in ipairs(menu and menu.items or {}) do
      if it.label == label then want = i end
    end
    if not want then check(false, "START menu has " .. label) return false end
    for _ = 1, 12 do
      if menu.index == want then break end
      U.tap(game, "down")
      U.wait(3)
    end
    U.tap(game, "a")
    U.wait(20)
    return true
  end

  local function useFlash()
    local PartyMenu = require("src.ui.PartyMenu")
    if not pickStart(require("src.core.Strings")("POKéMON")) then return end
    check(topIs(PartyMenu), "party menu open")
    local pm = game.stack:top()
    U.tap(game, "a")
    U.wait(10)
    local want
    for i, it in ipairs(pm.subItems or {}) do
      if it.action == "flash" then want = i end
    end
    check(want ~= nil, "FLASH listed in the party submenu")
    for _ = 1, 8 do
      if pm.subIndex == want then break end
      U.tap(game, "down")
      U.wait(3)
    end
    U.tap(game, "a")
    for _ = 1, 400 do
      if game.stack:top() == game.overworld then break end
      U.tap(game, "a")
      U.wait(4)
    end
    settle()
  end

  local function saveViaMenu()
    if not pickStart(require("src.core.Strings")("SAVE")) then return end
    for _ = 1, 20 do
      U.wait(10)
      local t = game.stack:top()
      if t and t.openPrompt then break end
    end
    U.wait(20)
    U.tap(game, "a")
    U.wait(10)
    U.tap(game, "a")
    for _ = 1, 600 do
      if game.stack:top() == game.overworld then break end
      U.wait(2)
    end
    settle()
    local SaveData = require("src.core.SaveData")
    local onDisk = SaveData.load(V)
    check(onDisk and onDisk.player.map == MAP, "save file holds " .. MAP)
    check(onDisk and onDisk.flashLit == true, "save file holds flashLit=true")
  end

  local function quitToTitle()
    if not pickStart(require("src.core.Strings")("QUIT")) then return end
    U.wait(20)
    U.tap(game, "up")
    U.wait(5)
    U.tap(game, "a")
    U.wait(30)
  end

  local function wildBattle(label)
    local BattleState = require("src.battle.BattleState")
    local battle = BattleState.newWild(game, "ZUBAT", 15)
    game.overworld:pushBattle(battle)
    for _ = 1, 600 do
      if game.stack:top() == battle then break end
      U.wait(1)
    end
    U.wait(60)
    battle.result = "run"
    battle.playerRan = true
    battle:finish()
    settle()
    lightState(label, ("2863_%s_%s.png"):format(V, label:gsub("%W", "_")), true)
  end

  if PHASE == "save" then
    U.newGame(game)
    forceGbc()
    game.save.flags.EVENT_GOT_STARTER = true
    game.save.inventory.BOULDERBADGE = true
    local mon = Pokemon.new(game.data, "PIKACHU", 30)
    mon.moves = { { id = "FLASH", pp = 20 }, { id = "THUNDERSHOCK", pp = 30 } }
    table.insert(game.save.party, 1, mon)
    while #game.save.party > 6 do table.remove(game.save.party) end
    game.save.flashLit = nil
    U.teleport(game, MAP, 15, 5, "down")
    settle()
    lightState("dark on arrival", "2863_" .. V .. "_1_dark_arrival.png", false)
    useFlash()
    lightState("after FLASH", "2863_" .. V .. "_2_after_flash.png", true)
    saveViaMenu()
    lightState("after SAVE", "2863_" .. V .. "_3_after_save.png", true)
    quitToTitle()
    U.newGame(game)
    forceGbc()
    settle()
    lightState("soft reset CONTINUE", "2863_" .. V .. "_4_softreset_continue.png", true)
    wildBattle("battle after soft reset")
  else
    U.newGame(game)
    forceGbc()
    settle()
    lightState("cold boot CONTINUE", "2863_" .. V .. "_5_coldboot_continue.png", true)
    wildBattle("battle after cold boot")
    U.teleport(game, "ROCK_TUNNEL_B1F", 3, 3, "down")
    settle()
    lightState("warped to B1F", "2863_" .. V .. "_6_b1f.png", true)
  end

  print((fails == 0 and "PASS " or "FAIL ") .. V .. " " .. PHASE .. ": " .. fails .. " failure(s)")
  love.event.quit(fails == 0 and 0 or 1)
end
