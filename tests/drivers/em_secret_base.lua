local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_secret_base"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_secret_base failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Party = require("src.core.game3.party")
  local Collision = require("src.core.game3.collision")
  local Objects = require("src.core.game3.objects")
  local Rse = require("src.core.game3.rse.init")
  local DecorInv = require("src.core.game3.rse.decoration_inventory")
  local Decor = require("src.core.game3.rse.decoration")
  local SB = require("src.core.game3.rse.secret_base")
  local UI = require("src.ui.game3.rse.decoration")
  local PcMenu = require("src.ui.game3.pc_menu")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return finish() end
  require("tests.drivers.em_secret_base_hooks").install()

  Party.giveMonToPlayer(session, C:require("species", "SPECIES_ZIGZAGOON"), 20)
  local mon = session.party[1]
  mon.moves[1] = C:require("moves", "MOVE_SECRET_POWER")
  mon.pp = mon.pp or {}
  mon.pp[1] = 20
  local function decor(n) return C:require("decorations", n) end
  local DESK, DOLL, POSTER, DOLL2 = decor("DECOR_HEAVY_DESK"), decor("DECOR_PICHU_DOLL"), decor("DECOR_PIKA_POSTER"),
    decor("DECOR_PIKACHU_DOLL")
  check(DecorInv.add(DESK, session) and DecorInv.add(DOLL, session) and DecorInv.add(POSTER, session)
    and DecorInv.add(DOLL2, session), "desk, two dolls and a poster in the decoration PC")

  local n = 0
  local function shot(name) n = n + 1 U.shot(game, string.format("%s/%02d_%s.png", DIR, n, name)) end
  local function waitFor(pred, frames, pressA)
    for i = 1, frames or 600 do
      if pred() then return true end
      if pressA and i % 12 == 0 then U.tap(game, "a") else U.wait(1) end
    end
    return pred()
  end
  local function msgHas(s)
    if not (Message.isOpen and Message.isOpen()) then return false end
    return table.concat(Message._pages or { Message.currentPage() or "" }, "\n"):find(s, 1, true) ~= nil
  end
  local function vmIdle() return not (Space.vm and Space.vm:isRunning()) end
  local function mapNow() return Runtime.getSession().map end
  local function goTo(mapId, x, y, facing)
    try("Map.load " .. mapId, function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
    local s = Runtime.getSession()
    s.x, s.y, s.facing = x, y, facing
    Player.cellX, Player.cellY, Player.px, Player.py = x, y, x * 16, y * 16
    Player.targetX, Player.targetY, Player.facing = x, y, facing
    U.wait(40)
  end
  local function mid(x, y)
    local l = Collision._mapDef and Collision._mapDef.midLayout
    return l and l:midAt(x, y)
  end
  local function mt(name) return C:require("metatile_labels", name) end
  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local function walk(dir)
    local x0, y0 = Player.cellX, Player.cellY
    for _ = 1, 8 do
      U.hold(game, dir, 2)
      for _ = 1, 20 do
        if Player.cellX ~= x0 or Player.cellY ~= y0 or Player.moving then break end
        U.wait(1)
      end
      if Player.cellX ~= x0 or Player.cellY ~= y0 or Player.moving then break end
    end
    for _ = 1, 40 do
      if not Player.moving then break end
      U.wait(1)
    end
  end
  local blocked = {}
  local function path(tx, ty)
    local seen, queue = { [ty * 1024 + tx] = true }, { { tx, ty } }
    local from = {}
    while #queue > 0 do
      local c = table.remove(queue, 1)
      if c[1] == Player.cellX and c[2] == Player.cellY then
        local out, k = {}, c[2] * 1024 + c[1]
        while from[k] do out[#out + 1] = from[k].dir; k = from[k].k end
        return out
      end
      for dir, d in pairs(DELTA) do
        local nx, ny = c[1] - d[1], c[2] - d[2]
        local key = ny * 1024 + nx
        local start = nx == Player.cellX and ny == Player.cellY
        if not seen[key] and (start or (Collision.isWalkable(nx, ny) and not Objects.at(nx, ny) and not blocked[key])) then
          seen[key] = true
          from[key] = { dir = dir, k = c[2] * 1024 + c[1] }
          queue[#queue + 1] = { nx, ny }
        end
      end
    end
    return nil
  end
  local function walkTo(tx, ty, stopOnMapChange)
    local map0 = mapNow()
    for _ = 1, 80 do
      if Player.cellX == tx and Player.cellY == ty then return true end
      if stopOnMapChange and mapNow() ~= map0 then return true end
      local route = path(tx, ty)
      if not route or #route == 0 then return false end
      local x0, y0 = Player.cellX, Player.cellY
      walk(route[1])
      if Player.cellX == x0 and Player.cellY == y0 and mapNow() == map0 then
        local d = DELTA[route[1]]
        blocked[(y0 + d[2]) * 1024 + x0 + d[1]] = true
      end
    end
    return Player.cellX == tx and Player.cellY == ty
  end
  local function pickChoice(idx)
    if not waitFor(function() return Choice.active end, 600) then return false end
    for _ = 1, 10 do
      if Choice.cursor == idx then break end
      U.tap(game, Choice.cursor < idx and "down" or "up")
      U.wait(3)
    end
    U.tap(game, "a")
    return true
  end
  local function uiState() return UI.isOpen() and UI.state or "closed" end
  local function tapUntil(btn, pred, frames)
    for _ = 1, frames or 60 do
      if pred() then return true end
      U.tap(game, btn)
      U.wait(6)
    end
    return pred()
  end

  -- pokeemerald/data/maps/Route111/map.json
  local EX, EY = 24, 36
  goTo("EM_ROUTE111", EX, EY + 1, "up")
  check(mid(EX, EY) == mt("METATILE_General_YellowCaveIndent"), "Route 111 yellow cave indent in front (" .. tostring(mid(EX, EY)) .. ")")
  shot("route111_indent")

  -- pokeemerald/data/scripts/secret_base.inc:27
  U.tap(game, "a")
  check(waitFor(function() return msgHas("indent in the wall") end, 300), "A on the indent: small indent in the wall")
  check(waitFor(function() return Choice.active and msgHas("Use the SECRET POWER?") end, 300, true),
    "Use the SECRET POWER? YES/NO")
  shot("use_secret_power")
  U.tap(game, "a")
  check(waitFor(function() return msgHas("used SECRET POWER") end, 300, false), "ZIGZAGOON used SECRET POWER")
  waitFor(function() return not Message.isOpen() end, 300, true)
  check(waitFor(function() return mid(EX, EY) == mt("METATILE_General_YellowCaveOpen") end, 600),
    "FLDEFF_USE_SECRET_POWER_CAVE opens the entrance")
  shot("entrance_open")
  check(waitFor(function() return msgHas("Discovered a small cavern") end, 600, false), "Discovered a small cavern!")
  check(waitFor(function() return mapNow() == "EM_SECRET_BASE_YELLOW_CAVE2" end, 900, true), "warped into SECRET_BASE_YELLOW_CAVE2")
  check(SB.base(session, 0).secretBaseId == 131, "SetPlayerSecretBase recorded id 131")
  check(waitFor(function() return msgHas("SECRET BASE here") end, 900), "Want to make your SECRET BASE here?")
  shot("make_base_here")
  local pcX, pcY = SB.findMetatile(SB.fieldGrid(), mt("METATILE_SecretBase_PC"))
  check(pcX and mid(pcX, pcY) == mt("METATILE_SecretBase_Ground"), "the PC is hidden before the base is made")
  waitFor(function() return Choice.active end, 300)
  U.tap(game, "a")
  local e = SB.manifest().entrances[13]
  check(waitFor(function() return vmIdle() and not Message.isOpen() and Player.cellX == e.x and Player.cellY == e.y
      and mid(pcX, pcY) == mt("METATILE_SecretBase_PC") end, 900),
    "EnterNewlyCreatedSecretBase stands the player at the computer with the PC shown (" .. Player.cellX .. "," .. Player.cellY .. ")")
  check(Player.facing == "up", "facing the PC")
  check(Rse.flag("FLAG_RECEIVED_SECRET_POWER"), "FLAG_RECEIVED_SECRET_POWER")
  U.wait(30)
  shot("new_base")

  local function openDecorationMenu()
    U.tap(game, "a")
    if not check(waitFor(function() return msgHas("booted up the PC") end, 300), "PC boots") then return false end
    U.wait(30)
    U.tap(game, "a")
    check(waitFor(function() return Choice.active end, 300), "PC multichoice")
    U.tap(game, "a")
    return check(waitFor(function() return uiState() == "actions" end, 300), "DECORATION opens the decoration menu")
  end

  local function placeFrom(cat, target, label, want)
    for _ = 1, 10 do
      if uiState() == "categories" then break end
      if uiState() == "actions" then UI.actionCursor = 0 U.tap(game, "a") else U.tap(game, "b") end
      U.wait(8)
    end
    tapUntil(UI.catCursor < cat and "down" or "up", function() return UI.catCursor == cat end, 12)
    U.tap(game, "a")
    if not check(waitFor(function() return uiState() == "items" end, 120), label .. ": category list") then return false end
    shot(label .. "_list")
    if want then
      local inv = DecorInv.inventories(session)[cat]
      for _ = 1, 12 do
        if inv[UI.scroll + UI.row + 1] == want then break end
        U.tap(game, "down")
        U.wait(4)
      end
      check(inv[UI.scroll + UI.row + 1] == want, label .. ": cursor on the wanted decoration")
    end
    U.tap(game, "a")
    if not check(waitFor(function() return uiState() == "place" end, 300), label .. ": placement mode") then return false end
    local m = UI.mode
    local tx, ty = target(m)
    if not check(tx ~= nil, label .. ": a legal spot exists (" .. tostring(tx) .. "," .. tostring(ty) .. ")") then
      U.tap(game, "b")
      waitFor(function() return uiState() == "yesno" end, 200)
      U.tap(game, "a")
      waitFor(function() return uiState() == "items" end, 300)
      return false
    end
    for _ = 1, 40 do
      if m.x == tx and m.y == ty then break end
      local dir = (m.x < tx and "right") or (m.x > tx and "left") or (m.y < ty and "down") or "up"
      U.hold(game, dir, 2)
      U.wait(10)
    end
    check(m.x == tx and m.y == ty, label .. ": cursor on the spot")
    shot(label .. "_cursor")
    U.tap(game, "a")
    check(waitFor(function() return uiState() == "yesno" end, 200), label .. ": Place it here?")
    shot(label .. "_confirm")
    U.tap(game, "a")
    return check(waitFor(function() return uiState() == "items" end, 300), label .. ": back to the list after placing")
  end

  local function legal(decorId, pred)
    return function(m)
      local grid = SB.fieldGrid()
      local w, h = grid.size()
      local best, bd
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          if (not pred or pred(x, y))
              and Decor.canPlace(grid, { x = x, y = y, initialX = m.initialX, initialY = m.initialY }, decorId) then
            local d = math.abs(x - m.x) + math.abs(y - m.y)
            if not best or d < bd then best, bd = { x, y }, d end
          end
        end
      end
      if best then return best[1], best[2] end
      return nil
    end
  end

  if openDecorationMenu() then
    shot("decoration_menu")
    placeFrom(Decor.CAT.DESK, legal(DESK, function(x, y) return x + 2 <= Player.cellX - 2 end), "desk")
    local deskX, deskY = Decor.decodePos(SB.base(session, 0).decorationPositions[1])
    check(mid(deskX, deskY) == mt("METATILE_SecretBase_HeavyDesk_BottomLeft"), "HEAVY DESK metatiles on the map")
    check(not Collision.isWalkable(deskX, deskY - 1), "the desk top blocks movement")
    U.tap(game, "b")
    waitFor(function() return uiState() == "categories" end, 60)
    placeFrom(Decor.CAT.DOLL, legal(DOLL, function(x, y) return x >= deskX and x <= deskX + 2 and y >= deskY - 1 and y <= deskY end),
      "doll", DOLL)
    U.tap(game, "b")
    waitFor(function() return uiState() == "categories" end, 60)
    placeFrom(Decor.CAT.POSTER, legal(POSTER), "poster")
    local b = SB.base(session, 0)
    check(b.decorations[1] == DESK and b.decorations[2] == DOLL and b.decorations[3] == POSTER,
      "base decorations desk/doll/poster (" .. b.decorations[1] .. "," .. b.decorations[2] .. "," .. b.decorations[3] .. ")")
    local dx, dy = Decor.decodePos(b.decorationPositions[2])
    local doll = Objects.at(dx, dy)
    check(doll ~= nil and not doll.hidden, "PICHU DOLL object stands on the desk")
    local px, py = Decor.decodePos(b.decorationPositions[3])
    check(mid(px, py) == mt("METATILE_SecretBase_PikaPoster_Left"), "PIKA POSTER on the wall")
    shot("placed_list")
    U.tap(game, "b")
    waitFor(function() return uiState() == "categories" end, 60)
    U.tap(game, "b")
    waitFor(function() return uiState() == "actions" end, 60)
    UI.actionCursor = 3
    U.tap(game, "a")
    check(waitFor(function() return not UI.isOpen() and Choice.active end, 300), "CANCEL returns to the base PC menu")
    pickChoice(3)
    check(waitFor(function() return vmIdle() and not Message.isOpen() end, 300, false), "TURN OFF")
    U.wait(20)
    shot("decorated_base")
  end

  local exitWarp = (game.data.maps[mapNow()].warps or {})[1]
  check(exitWarp ~= nil and walkTo(exitWarp.x, exitWarp.y, true), "walked to the exit mat")
  if mapNow() == "EM_SECRET_BASE_YELLOW_CAVE2" then U.hold(game, "down", 4) end
  check(waitFor(function() return mapNow() == "EM_ROUTE111" and vmIdle() end, 900), "left the base to Route 111")
  U.wait(30)
  check(Player.cellX == EX and Player.cellY == EY + 1, "back in front of the entrance (" .. Player.cellX .. "," .. Player.cellY .. ")")
  check(mid(EX, EY) == mt("METATILE_General_YellowCaveOpen"), "the entrance stays open on reload of Route 111 ("
    .. tostring(mid(EX, EY)) .. ", " .. tostring(Collision._mapDef and Collision._mapDef.id) .. ")")
  shot("route111_open_entrance")

  local okSave = game:saveGame()
  check(okSave ~= false, "saveGame")
  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local okL, raw = pcall(SaveData.load)
  check(okL and raw and raw.version == "emerald", "save reloads")
  if raw then
    local back = Schema.fromSaveTable(raw)
    check(back.secretBases and back.secretBases[1].secretBaseId == 131, "secretBases section in the save")
    require("src.core.game3.options").bind(back, game.options)
    game:adoptSave(back, true)
    game.sessionStartedAt = os.time()
    game:_enterField(back, "continue")
    U.wait(60)
    session = Runtime.getSession()
  end
  check(mapNow() == "EM_ROUTE111", "continue on Route 111")
  check(mid(EX, EY) == mt("METATILE_General_YellowCaveOpen"), "entrance open after continue (" .. tostring(mid(EX, EY)) .. ")")
  check(SB.base(session, 0).decorations[1] == DESK, "decorations survive the reload")

  Player.facing = "up"
  walk("up")
  check(waitFor(function() return mapNow() == "EM_SECRET_BASE_YELLOW_CAVE2" and vmIdle() end, 900),
    "walking into the open entrance re-enters the base")
  U.wait(40)
  local b = SB.base(session, 0)
  local deskX, deskY = Decor.decodePos(b.decorationPositions[1])
  check(mid(deskX, deskY) == mt("METATILE_SecretBase_HeavyDesk_BottomLeft"), "desk metatile after re-entry")
  local px, py = Decor.decodePos(b.decorationPositions[3])
  check(mid(px, py) == mt("METATILE_SecretBase_PikaPoster_Left"), "poster after re-entry")
  local dx, dy = Decor.decodePos(b.decorationPositions[2])
  local doll = Objects.at(dx, dy)
  check(doll ~= nil and not doll.hidden, "doll object respawned by InitDecorations")
  check(b.numTimesEntered >= 1, "numTimesEntered counts (" .. b.numTimesEntered .. ")")
  shot("base_after_reload")

  blocked = {}
  local pcRoute = walkTo(e.x, e.y)
  walk("up")
  check(Player.cellX == e.x and Player.cellY == e.y and Player.facing == "up", "walked back to the PC ("
    .. Player.cellX .. "," .. Player.cellY .. " " .. tostring(Player.facing) .. ", route " .. tostring(pcRoute) .. ")")
  if openDecorationMenu() then
    UI.actionCursor = 1
    U.tap(game, "a")
    check(waitFor(function() return uiState() == "putaway" end, 300), "PUT AWAY enters the put-away cursor")
    local m = UI.mode
    for _ = 1, 40 do
      if m.x == px and m.y == py then break end
      local dir = (m.x < px and "right") or (m.x > px and "left") or (m.y < py and "down") or "up"
      U.hold(game, dir, 2)
      U.wait(10)
    end
    shot("putaway_cursor")
    U.tap(game, "a")
    check(waitFor(function() return uiState() == "yesno" end, 200), "Return this decoration to the PC?")
    shot("putaway_confirm")
    U.tap(game, "a")
    check(waitFor(function() return uiState() == "wait_press" end, 400), "The decoration was returned to the PC.")
    local bb = SB.base(session, 0)
    check(bb.decorations[3] == 0, "poster slot cleared")
    check(mid(px, py) ~= mt("METATILE_SecretBase_PikaPoster_Left"), "poster metatile restored")
    shot("putaway_done")
    U.tap(game, "a")
    waitFor(function() return uiState() == "putaway" end, 60)
    U.tap(game, "b")
    check(waitFor(function() return uiState() == "yesno" end, 200), "Stop putting away decorations?")
    U.tap(game, "a")
    check(waitFor(function() return uiState() == "actions" end, 400), "back to the decoration actions")
    UI.actionCursor = 2
    U.tap(game, "a")
    waitFor(function() return uiState() == "categories" end, 60)
    tapUntil("down", function() return UI.catCursor == Decor.CAT.POSTER end, 12)
    U.tap(game, "a")
    check(waitFor(function() return uiState() == "items" end, 120), "TOSS lists the posters")
    U.tap(game, "a")
    check(waitFor(function() return uiState() == "yesno" end, 300), "This PIKA POSTER will be discarded.")
    shot("toss_confirm")
    U.tap(game, "a")
    check(waitFor(function() return uiState() == "wait_press" end, 400), "The decoration item was thrown away.")
    check(DecorInv.countInCategory(Decor.CAT.POSTER, session) == 0, "the poster left the decoration PC")
    U.tap(game, "a")
    waitFor(function() return uiState() == "items" end, 60)
    U.tap(game, "b")
    waitFor(function() return uiState() == "categories" end, 60)
    U.tap(game, "b")
    waitFor(function() return uiState() == "actions" end, 60)
    U.tap(game, "b")
    check(waitFor(function() return not UI.isOpen() and Choice.active end, 300), "B returns to the base PC menu")
    pickChoice(3)
    waitFor(function() return vmIdle() and not Message.isOpen() end, 300, false)
  end

  goTo("EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", 0, 2, "up")
  U.tap(game, "a")
  check(waitFor(function() return PcMenu.isOpen() and PcMenu.mode == "player_pc" end, 600, true), "bedroom PC")
  local order = require("src.ui.game3.rse.player_pc").topOrder(PcMenu)
  for i, id in ipairs(order) do
    if id == "decoration" then
      for _ = 1, 6 do
        if PcMenu.cursor == i then break end
        U.tap(game, "down")
        U.wait(3)
      end
    end
  end
  U.tap(game, "a")
  check(waitFor(function() return uiState() == "actions" end, 300), "bedroom DECORATION opens the decoration menu")
  local holder = function(x, y)
    local beh = Collision.behavior(x, y)
    return Decor.isBeh(beh, "HOLDS_SMALL_DECORATION") or Decor.isBeh(beh, "HOLDS_LARGE_DECORATION")
  end
  placeFrom(Decor.CAT.DOLL, legal(DOLL2, holder), "bedroom_doll", DOLL2)
  local rp = session.playerRoomDecorations or {}
  check(rp[1] == DOLL2, "PIKACHU DOLL recorded in playerRoomDecorations")
  local bx, by = Decor.decodePos((session.playerRoomDecorationPositions or {})[1])
  local bdoll = Objects.at(bx, by)
  check(bdoll ~= nil and not bdoll.hidden, "bedroom doll object on the map (" .. bx .. "," .. by .. ")")
  shot("bedroom_doll")
  U.tap(game, "b")
  waitFor(function() return uiState() == "categories" end, 60)
  U.tap(game, "b")
  waitFor(function() return uiState() == "actions" end, 60)
  U.tap(game, "b")
  check(waitFor(function() return not UI.isOpen() and PcMenu.isOpen() end, 120), "CANCEL returns to the bedroom PC")
  U.tap(game, "b")
  waitFor(function() return not PcMenu.isOpen() and vmIdle() end, 600, true)
  goTo("EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", 3, 3, "down")
  bdoll = Objects.at(bx, by)
  check(bdoll ~= nil and not bdoll.hidden, "bedroom doll respawns on re-entering the room")
  shot("bedroom_reentry")
  finish()
end
