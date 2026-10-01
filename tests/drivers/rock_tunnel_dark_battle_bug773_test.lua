-- Driver: BATTLE BG "world" plus an un-flashed Rock Tunnel put a dark map in
-- the same frame as the battle, and OverworldState:drawWorld's rBGP shift then
-- coloured the battle itself (#773).  On hardware InitBattleCommon
-- (engine/battle/core.asm) pushes wMapPalOffset, InitBattleVariables zeroes it
-- and core.asm pops it back after EndOfBattle, so the battle is lit.
--   POKEPORT_DRIVER=tests/drivers/rock_tunnel_dark_battle_bug773_test.lua \
--     POKEPORT_IDENTITY=bug773 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Probe = dofile("tests/drivers/shot_probe.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"

  local fails = 0
  local function check(ok, msg)
    U.log(ok and "PASS" or "FAIL", msg)
    if not ok then fails = fails + 1 end
    return ok
  end

  game.save.flags.EVENT_GOT_STARTER = true
  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 20))
  end
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  game.save.options.colors = "gbc"
  game.save.options.battleBg = "world"
  PaletteFX.setMode("gbc")

  local CAVE = PaletteFX.pal(game.data, "CAVE")
  local caveDark = PaletteFX.permute(CAVE, PaletteFX.DARK_BGP)

  -- data/maps/objects/RockTunnel1F.asm: the Route 10 entrance warp is 15, 3,
  -- so two cells south of it is floor that does not re-trigger the warp.
  game.save.flashLit = nil
  U.teleport(game, "ROCK_TUNNEL_1F", 15, 5, "down")
  U.wait(20)
  local ow = game.overworld
  check(ow ~= nil and ow.dark == true, "standing in an un-flashed ROCK_TUNNEL_1F")
  U.shot(game, DIR .. "/bug773_1_dark_map.png")
  check(PaletteFX.shadeMap() == PaletteFX.DARK_BGP,
        "the map frame really is drawn with DARK_BGP armed")

  local ok = pcall(function()
    local battle = BattleState.newWild(game, "ZUBAT", 15)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
  end)
  if not ok then
    U.log("FAIL could not force a wild battle; nothing to judge")
    love.event.quit(1)
    while true do coroutine.yield() end
  end

  U.wait(120) -- through the transition wipe and the intro slide-in
  U.shot(game, DIR .. "/bug773_2_battle_world_bg.png")
  check(PaletteFX.shadeMap() == nil,
        "no shade map is armed while the world-bg battle draws (#773)")

  -- The battle keeps its own 160x144 field in the middle of the window; the
  -- dimmed map only fills the surround, so probe the centre.
  local CENTRE = { 0.4, 0.4, 0.6, 0.6 }
  local shot = Probe.grab()
  if shot then
    local c = Probe.count(shot, { litPaper = CAVE[1], darkPaper = caveDark[1] },
                          3, CENTRE)
    check(c.litPaper > 0,
          "the battle screen keeps its paper white -- it is not FadePal2'd")
    local top = Probe.top(shot, 5, 3, CENTRE)
    U.log("battle centre top colours:", Probe.fmt(top))
  else
    U.log("WARN pixel probe unavailable; judge the shots by eye")
  end

  U.log(fails == 0 and "#773 checks passed" or (fails .. " #773 check(s) FAILED"))
  U.log("Look at " .. DIR .. "/bug773_2_battle_world_bg.png: the battle screen")
  U.log("should read exactly like any other battle -- white paper, normal HUD")
  U.log("and pic colours -- with the dimmed tunnel only in the surround.")
  U.log("The separate uniform dim of the world backdrop is #777, not this.")

  local SpriteRenderer = require("src.render.SpriteRenderer")
  local ballGroups = {}
  local realObp = SpriteRenderer.obpImage
  SpriteRenderer.obpImage = function(path, colors, group)
    if path == "assets/generated/battle/balls.png" then ballGroups[#ballGroups + 1] = group end
    return realObp(path, colors, group)
  end

  while #game.save.party < 3 do
    table.insert(game.save.party, Pokemon.new(game.data, "PIDGEY", 10))
  end
  game.save.party[2].status = "PSN"
  game.save.options.colors = "ogred"
  game.save.options.battleBg = nil
  PaletteFX.setMode("ogred")
  U.teleport(game, "ROCK_TUNNEL_1F", 15, 5, "down")
  U.wait(20)
  check(PaletteFX.darkWorld() == true, "ogred: dark-cave OBJ shift armed in ROCK_TUNNEL_1F")
  local _, owGroup = PaletteFX.ogObj()
  check(tostring(owGroup):match("dark$") ~= nil, "ogred: overworld sprites still bake dark (" .. tostring(owGroup) .. ")")

  local battle2
  ok = pcall(function()
    battle2 = BattleState.newWild(game, "ZUBAT", 15)
    battle2.onFinish = function() end
    game.overworld:pushBattle(battle2)
  end)
  check(ok, "ogred: wild battle pushed in the dark tunnel")
  local sawBalls = false
  for _ = 1, 1200 do
    if battle2 and battle2.introBalls then sawBalls = true break end
    U.wait(1)
  end
  for _ = 1, 3000 do
    if #ballGroups > 0 then break end
    U.wait(1)
  end
  check(sawBalls and #ballGroups > 0, "ogred: intro party ball row is on screen")
  U.wait(4)
  U.still(game, DIR .. "/2562_01_rock_tunnel_balls_lit.png")
  local anyDark = false
  for _, g in ipairs(ballGroups) do
    if tostring(g):match("dark$") then anyDark = true end
  end
  U.log("ball bakes:", #ballGroups, tostring(ballGroups[1]), "mode", PaletteFX.mode,
        "usesSpriteObp", tostring(PaletteFX.usesSpriteObp()))
  check(#ballGroups > 0 and not anyDark,
        "ogred: battle ball row bakes without the dark-cave shift (#2562)")
  SpriteRenderer.obpImage = realObp

  U.log(fails == 0 and "#773/#2562 checks passed" or (fails .. " check(s) FAILED"))
  love.event.quit(fails == 0 and 0 or 1)
  while true do coroutine.yield() end
end
