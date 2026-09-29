package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local PRET = os.getenv("POKEPORT_PRET_EMERALD") or "../pokeemerald"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_berry_blender_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_berry_blender_test: skipped (" .. ROM_PATH .. " is not Emerald)")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
local prevVersion = GameVersion.get()
GameVersion.set("emerald")
local imports = {
  info = function(_, id) return { id = id, size = #data, md5 = "emerald", file = "memory" } end,
  read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
}
local rom = assert(require("src.import.gba.rom").open(imports, "emerald"))

local store = {}
local cache = {
  write = function(_, rel, bytes) store[rel] = bytes; return true end,
  read = function(_, rel) return store[rel] end,
  exists = function(_, rel) return store[rel] ~= nil end,
}
local ROOT = "data/generated/gba"

local BX = require("src.import.gba.rse.berry_blender_extract")
check(not BX.ready(cache, ROOT), "blender cache not ready before run")
local ok, man = BX.run(rom, cache, { cacheRoot = ROOT })
eq(ok, true, "blender extractor ran")
check(BX.ready(cache, ROOT), "blender cache ready after run")
for _, rel in ipairs(BX.REQUIRED) do check(store[ROOT .. "/" .. rel] ~= nil, rel .. " written") end
require("src.import.gba.berries_extract").run(rom, cache, { cacheRoot = ROOT })
local pack = assert(loadstring(store[ROOT .. "/berries/berries.lua"]))()
local plan = require("src.import.gba.plans.rse")
local planned = false
for _, m in ipairs(require("src.import.gba.plans.registry").modules(plan)) do
  if m == "src.import.gba.rse.berry_blender_extract" then planned = true end
end
check(planned, "rse import plan runs the blender extractor")

local B = require("src.core.game3.rse.berry_blender")
local Tb = man.tables
local ids = B.itemIds("emerald")

-- pokeemerald/src/berry_blender.c:452
local pretC
do
  local h = io.open(PRET .. "/src/berry_blender.c", "rb")
  if h then pretC = h:read("*a"); h:close() end
end
local function pretNumbers(name)
  if not pretC then return nil end
  local body = pretC:match(name .. "[%[%]%w_ %-]*=%s*(%b{})")
  local out = {}
  for n in (body or ""):gmatch("%d+") do out[#out + 1] = tonumber(n) end
  return out
end
if pretC then
  eq(table.concat(Tb.arrowHitRangeStart, ","), table.concat(pretNumbers("sArrowHitRangeStart"), ","),
    "sArrowHitRangeStart equals pret source")
  eq(table.concat(Tb.numPlayersToSpeedDivisor, ","), table.concat(pretNumbers("sNumPlayersToSpeedDivisor"), ","),
    "sNumPlayersToSpeedDivisor equals pret source")
  eq(table.concat(Tb.arrowStartPosIds, ","), table.concat(pretNumbers("sArrowStartPosIds"), ","),
    "sArrowStartPosIds equals pret source")
  local pos = pretNumbers("sPlayerArrowPos")
  local got = {}
  for _, r in ipairs(Tb.playerArrowPos) do got[#got + 1] = r[1]; got[#got + 1] = r[2] end
  eq(table.concat(got, ","), table.concat(pos, ","), "sPlayerArrowPos equals pret source")
else
  print("emerald_berry_blender_test: pret source not found, source comparisons skipped")
end
eq(table.concat(Tb.arrowStartPos, ","), "0,49152,16384,32768", "sArrowStartPos")
eq(#Tb.opponentBerrySets, 10, "ten NPC berry sets")
eq(#Tb.blackPokeblockFlavorFlags, 10, "ten black flavor sets")
eq(table.concat(man.opponentNames, ","), "MISTER,LADDIE,LASSIE,MASTER,DUDE,MISS", "opponent names")
eq(man.texts.theLevelIs, "The level is ", "sText_TheLevelIs")
check(man.texts.berryBlenderStart:find("Starting up the BERRY BLENDER.", 1, true) ~= nil, "sText_BerryBlenderStart")
eq(man.windows[5].left .. "," .. man.windows[5].top .. "," .. man.windows[5].width, "2,15,27", "message window template")
eq(man.sprites.arrow.frames, 4, "player arrow has 4 frames")
eq(#man.sprites.arrow.anims, 12, "player arrow has 12 anims")
eq(man.berry.frames, 43, "43 berry pics")
eq(#man.palettes.center, 128, "center palette 128 colors")
eq(#man.outerMap, 1024, "outer tilemap 32x32")

local function newGame(opp, item, random, master)
  local g = B.new({ tables = Tb, berries = pack.berries, opponents = opp, playerItem = item, itemIds = ids,
    opponentNames = man.opponentNames, playerName = "NICK", random = random, blendMaster = master })
  g:setPlayerIdMaps()
  return g
end

-- pokeemerald/src/berry_blender.c:1542
local g1 = newGame(1, ids.first)
eq(g1.chosenItemId[1], ids.aspear, "Cheri vs MISTER: MISTER blends an Aspear")
eq(g1.playerNames[1], "MISTER", "one NPC without the blend master is MISTER")
local g3 = newGame(3, ids.first)
eq(g3.chosenItemId[1] .. "," .. g3.chosenItemId[2] .. "," .. g3.chosenItemId[3],
  (ids.first + 4) .. "," .. (ids.first + 3) .. "," .. (ids.first + 2), "Cheri vs 3 NPCs: Aspear, Rawst, Pecha")
eq(g3.playerNames[1] .. "," .. g3.playerNames[2] .. "," .. g3.playerNames[3], "MISS,LADDIE,LASSIE", "3 NPC names")
local gm = newGame(1, ids.first, nil, true)
eq(gm.playerNames[1], "MASTER", "blend master present names MASTER")
eq(gm.chosenItemId[1], ids.first + Tb.berryMasterBerries[1], "blend master counters Cheri with a Spelon")
local gms = newGame(1, ids.spelon, nil, true)
eq(gms.chosenItemId[1], ids.first + Tb.berryMasterBerries[1] - 5, "blend master drops a set for a master berry")
local gE = newGame(1, ids.enigma)
check(gE.chosenItemId[1] >= ids.first and gE.chosenItemId[1] <= ids.aspear, "Enigma picks an NPC berry set")
eq(g3.arrowIdToPlayerId[0] .. "," .. g3.arrowIdToPlayerId[3], "0,3", "4-player arrow map")
eq(g1.playerIdToArrowId[0] .. "," .. g1.playerIdToArrowId[1], "1,2", "2-player: player on arrow 1, NPC on arrow 2")

-- pokeemerald/src/berry_blender.c:1525
g1.arrowPos = (224 + 20 - 24) * 256
eq(g1:arrowProximity(g1.arrowPos, 0), B.PROXIMITY.BEST, "best window start")
g1.arrowPos = (224 + 28 - 24) * 256
eq(g1:arrowProximity(g1.arrowPos, 0), B.PROXIMITY.GOOD, "good after the best window")
g1.arrowPos = (224 - 1 - 24) * 256
eq(g1:arrowProximity(g1.arrowPos, 0), B.PROXIMITY.MISS, "miss before the window")
eq(B.arrowSpeedToRPM(128), 703, "MIN_ARROW_SPEED = 7.03 RPM")

-- pokeemerald/src/berry_blender.c:2387
local function berryOf(item) return B.blenderBerry(item, pack.berries, ids) end
local function calc(items, rpm)
  local list = {}
  for i, it in ipairs(items) do list[i - 1] = berryOf(it) end
  return (B.calculatePokeblock(list, #items, rpm, function() return 0 end, ids, Tb.blackPokeblockFlavorFlags))
end
local red = calc({ ids.first, ids.aspear }, 9887)
eq(red.color .. "," .. red.spicy .. "," .. red.feel, "1,12,23", "Cheri + Aspear at 98.87 RPM = RED lv12 feel 23 (pygba)")
local black = calc({ ids.first, ids.first }, 5000)
eq(black.color, B.COLOR.BLACK, "same berry twice makes a BLACK block")
eq(black.sour .. "," .. black.bitter .. "," .. black.sweet, "2,2,2", "black flavors from sBlackPokeblockFlavorFlags[0]")
local zero = calc({ ids.first }, 0)
eq(zero.color, B.COLOR.RED, "single Cheri is RED")
local C = require("src.core.game3.constants").of("emerald")
local function synth(item, fl)
  return { itemId = item, name = tostring(item), flavors = { [0] = fl[1], fl[2], fl[3], fl[4], fl[5], fl[6] } }
end
local gold = B.calculatePokeblock({ [0] = synth(1, { 60, 0, 0, 0, 0, 20 }), synth(2, { 0, 0, 0, 0, 0, 20 }) }, 2, 0,
  function() return 0 end, ids, Tb.blackPokeblockFlavorFlags)
eq(gold.color .. "," .. gold.spicy .. "," .. gold.feel, "14,59,18", "a flavor above 50 makes GOLD")
local purple = calc({ C:require("items", "ITEM_SPELON_BERRY"), ids.aspear }, 15000)
eq(purple.color .. "," .. purple.spicy .. "," .. purple.dry, "6,41,12", "Spelon + Aspear at 150 RPM = PURPLE")

-- pokeemerald/src/berry_blender.c:3592
eq(B.madeText(red, man.texts, pack.pokeblockNames), "RED POKéBLOCK was made!\nThe level is 12, and the feel is 23.",
  "made text")
eq(B.maxSpeedText(9887, man.texts), "{UNK_SPACER}98.87 RPM", "max speed text")
eq(B.timeText(1664, man.texts), "00 min. 27 sec.", "time text")

local function unhex(s, w, i)
  return tonumber(s:sub((i - 1) * w + 1, i * w), 16)
end
local function signed16(v) if v >= 0x8000 then return v - 0x10000 end return v end

local golden = dofile("tests/data/emerald_blender/golden.lua")
local Rng = require("src.core.game3.rng")
for name, G in pairs(golden) do
  local saved = Rng._value
  Rng._value = G.rng0
  local g = newGame(G.opponents, G.berries[1], Rng.Random)
  for i = 2, #G.berries do eq(g.chosenItemId[i - 1], G.berries[i], name .. " NPC berry " .. (i - 1)) end
  g.arrowPos = g:arrowStartPos()
  g:startPlay()
  local press = {}
  for _, p in ipairs(G.press) do press[p] = true end
  local bad, first = 0, nil
  local ended = false
  for i = 0, G.frames - 1 do
    Rng.Random()
    ended = g:playFrame(press[i] or false)
    local okF = g.speed == signed16(unhex(G.speed, 4, i + 1)) and g.progressBarValue == unhex(G.progress, 3, i + 1)
    if i % 8 == 7 then
      local j = (i - 7) / 8 + 1
      okF = okF and g.arrowPos == unhex(G.arrowPos8, 4, j) and Rng._value == unhex(G.rng8, 8, j)
    end
    if not okF then
      bad = bad + 1
      first = first or i
    end
  end
  eq(bad, 0, name .. ": every frame matches the pygba trace" .. (first and (" (first bad " .. first .. ")") or ""))
  check(ended, name .. ": the game ends on the traced frame")
  local F = G.final
  eq(g.maxRPM, F.maxRPM, name .. ": max RPM")
  eq(g.gameFrameTime, F.frameTime, name .. ": game time")
  eq(Rng._value, F.rng, name .. ": rng state after play")
  local sc = {}
  for p = 0, 3 do for k = 0, 2 do sc[#sc + 1] = g.scores[p][k] end end
  eq(table.concat(sc, ","), table.concat(F.scores, ","), name .. ": scores")
  local b = g:calculate()
  local P = G.pokeblock
  eq(table.concat({ b.color, b.spicy, b.dry, b.sweet, b.bitter, b.sour, b.feel }, ","),
    table.concat({ P.color, P.spicy, P.dry, P.sweet, P.bitter, P.sour, P.feel }, ","), name .. ": pokeblock equals the cart")
  local sess = { berryBlenderRecords = { 11052, 0, 0 } }
  g:tryUpdateRecord(sess)
  eq(table.concat(sess.berryBlenderRecords, ","), table.concat(G.records, ","), name .. ": speed records")
  local e = 0
  while not g:endFrame() do e = e + 1 end
  check(e > 0 and g.speed == 0, name .. ": blender spins down")
  Rng._value = saved
end

-- pokeemerald/src/berry_blender.c:1047
local UI = require("src.ui.game3.rse.berry_blender")
require("src.import.gba.items_extract").run(rom, cache, { cacheRoot = ROOT })
require("src.core.game3.items_data").installPack(assert(loadstring(store[ROOT .. "/items/pack.lua"]))())
for name, G in pairs(golden) do
  local saved = Rng._value
  local Bag = require("src.core.game3.bag")
  local bag = Bag.new()
  Bag.add(bag, G.berries[1], 3)
  local sess = { bag = bag, berryBlenderRecords = { 11052, 0, 0 }, gameStats = {} }
  require("src.core.game3.rse.pokeblock").clearAll(sess)
  local doneCalled = false
  local ui = UI.new({ session = sess, manifest = man, berries = pack, opponents = G.opponents, playerName = "NICK", cache = cache,
    headless = true, vblankRandom = true, random = Rng.Random, itemIds = ids, version = "emerald",
    chooseBerry = function(done) done(G.berries[1]) end, onDone = function() doneCalled = true end })
  local playFrame, seeded = nil, false
  local ynFrames
  local press = {}
  for _, p in ipairs(G.press) do press[p] = true end
  local log = {}
  local frames = 0
  while not ui.done and frames < 20000 do
    frames = frames + 1
    local inp = { new = {}, held = {} }
    if ui.cb == "play" then
      if not seeded then
        Rng._value = G.rng0
        seeded = true
        playFrame = 0
      end
      if press[playFrame] then inp.new.a = true end
      playFrame = playFrame + 1
    elseif ui.cb == "end" and ui.game.gameEndState == 10 then
      ynFrames = (ynFrames or 0) + 1
      if ynFrames == 2 then inp.new.down = true elseif ynFrames == 6 then inp.new.a = true end
    elseif frames % 6 == 0 then
      inp.new.a = true
    end
    local wasCb = ui.cb
    ui:frame(inp)
    if wasCb == "startLocal" and ui.cb == "play" then seeded = false end
    if wasCb ~= ui.cb then log[#log + 1] = ui.cb end
  end
  check(ui.done and doneCalled, name .. ": headless blender screen returns to the field (" .. table.concat(log, ">") .. ")")
  eq(playFrame, G.frames, name .. ": play lasts the traced frame count")
  eq(ui.game.maxRPM, G.final.maxRPM, name .. ": screen max RPM equals the cart")
  local b = sess.pokeblocks[1]
  local P = G.pokeblock
  eq(table.concat({ b.color, b.spicy, b.dry, b.sweet, b.bitter, b.sour, b.feel }, ","),
    table.concat({ P.color, P.spicy, P.dry, P.sweet, P.bitter, P.sour, P.feel }, ","), name .. ": screen adds the cart pokeblock")
  eq(Bag.get(bag, G.berries[1]), 2, name .. ": one berry used")
  eq(sess.gameStats[B.GAME_STAT_POKEBLOCKS], 1, name .. ": GAME_STAT_POKEBLOCKS")
  eq(table.concat(sess.berryBlenderRecords, ","), table.concat(G.records, ","), name .. ": records after the screen")
  local logS = table.concat(ui.sound.log, ",")
  check(logS:find("SE_FALL", 1, true) and logS:find("MUS_LEVEL_UP", 1, true) and logS:find("SE_BERRY_BLENDER", 1, true),
    name .. ": fall SE, blender SE and level-up fanfare played")
  Rng._value = saved
end


local SaveSections = require("src.core.game3.save_sections")
local probe = SaveSections.fields(B.SAVE_FIELDS)
local exported, restored = {}, {}
probe.export({ berryBlenderRecords = { 1, 2, 3 } }, exported)
probe.restore(exported, restored)
eq(table.concat(restored.berryBlenderRecords, ","), "1,2,3", "blender records survive save/restore")
local fresh = {}
B.records(fresh)
eq(table.concat(fresh.berryBlenderRecords, ","), "0,0,0", "records default to zero")
local okReg, listed = pcall(function()
  for _, sec in ipairs(SaveSections.of("emerald")) do
    if sec.name == "berryBlender" then return true end
  end
  return false
end)
check(okReg and listed, "emerald save sections resolve with the blender listed")
check(require("src.core.game3.rse.init").system("berryBlender") == B, "Rse system berryBlender registered")

local BlenderLink = require("src.core.game3.rse.berry_blender_link")
local bus = { queues = { [0] = {}, [1] = {} } }
local function peer(seat)
  local link = { seat = seat, bus = bus, open = true }
  function link:getSeat() return self.seat end
  function link:isOpen() return self.open end
  function link:send(message)
    local target = 1 - self.seat
    local copy = {}
    for key, value in pairs(message) do copy[key] = value end
    copy.seat = self.seat
    self.bus.queues[target][#self.bus.queues[target] + 1] = copy
  end
  function link:take(kind, predicate)
    local q = self.bus.queues[self.seat]
    for i, message in ipairs(q) do
      if message.type == kind and (not predicate or predicate(message)) then
        table.remove(q, i)
        return message
      end
    end
  end
  return link
end
local players = {
  { seat = 0, trainerId = 111, name = "HOST" },
  { seat = 1, trainerId = 222, name = "GUEST" },
}
local hostBlenderLink = BlenderLink.new(peer(0), players)
local guestBlenderLink = BlenderLink.new(peer(1), players)
eq(hostBlenderLink:submitBerry(133), nil, "linked berry waits for the partner choice")
local guestBerries = guestBlenderLink:submitBerry(134)
eq(guestBerries[0], 133, "guest receives host berry by link seat")
local hostBerries = hostBlenderLink:submitBerry(133)
eq(hostBerries[1], 134, "host receives guest berry by link seat")
eq(hostBlenderLink:exchangeFrame(0, B.CMD.BEST), nil, "host frame waits for the guest hit")
local guestFrame = guestBlenderLink:exchangeFrame(0, B.CMD.GOOD)
eq(guestFrame[0], B.CMD.BEST, "linked timing frame carries the host hit")
local hostFrame = hostBlenderLink:exchangeFrame(0, B.CMD.BEST)
eq(hostFrame[1], B.CMD.GOOD, "linked timing frame carries the guest hit")
eq(hostBlenderLink:exchangeContinue(B.PLAY_AGAIN.YES), nil, "continue decision waits for the guest")
eq(guestBlenderLink:exchangeContinue(B.PLAY_AGAIN.CANT_PLAY_NO_BERRIES), nil, "guest waits for leader decision")
local decision = hostBlenderLink:exchangeContinue(B.PLAY_AGAIN.YES)
check(decision and not decision.continue and decision.reason == B.PLAY_AGAIN.CANT_PLAY_NO_BERRIES
  and decision.seat == 1, "leader resolves the partner's no-berries response")
local peerDecision = guestBlenderLink:exchangeContinue(B.PLAY_AGAIN.CANT_PLAY_NO_BERRIES)
check(peerDecision and not peerDecision.continue and peerDecision.seat == 1, "leader decision is broadcast to guest")
eq(hostBlenderLink:exchangeFrame(1, 0), nil, "host frame 1 waits")
check(guestBlenderLink:exchangeFrame(1, B.CMD.GOOD) ~= nil, "guest clears frame 1")
eq(guestBlenderLink:exchangeFrame(2, B.CMD.BEST), nil, "guest runs ahead to frame 2")
check(hostBlenderLink:exchangeFrame(1, 0) ~= nil, "host clears frame 1 with the guest's frame 2 already queued")
local ahead = hostBlenderLink:exchangeFrame(2, 0)
eq(ahead and ahead[1], B.CMD.BEST, "a partner frame that arrives early is kept, not dropped")
check(guestBlenderLink:exchangeFrame(2, B.CMD.BEST) ~= nil, "guest clears frame 2")
hostBlenderLink:abort("test_cancel")
local _, abortReason = guestBlenderLink:exchangeFrame(3, 0)
eq(abortReason, "abort", "peer cancellation releases a waiting timing frame")

bus = { queues = { [0] = {}, [1] = {} } }
local linkHost, linkGuest = peer(0), peer(1)
local playerRows = {
  { seat = 0, trainerId = 111, name = "HOST" },
  { seat = 1, trainerId = 222, name = "GUEST" },
}
local hostSession, guestSession = {}, {}
for _, sess in ipairs({ hostSession, guestSession }) do
  local Bag = require("src.core.game3.bag")
  sess.bag = Bag.new()
  Bag.add(sess.bag, ids.first, 4)
  sess.name = sess == hostSession and "HOST" or "GUEST"
  sess.gameStats = {}
  require("src.core.game3.rse.pokeblock").clearAll(sess)
end
local hostScreen = UI.new({ session = hostSession, manifest = man, berries = pack, opponents = 0,
  playerName = "HOST", playerNames = { "HOST", "GUEST" }, numPlayers = 2, itemIds = ids, version = "emerald",
  cache = cache, headless = true, linkSession = BlenderLink.new(linkHost, playerRows),
  chooseBerry = function(done) done(ids.first) end })
local guestScreen = UI.new({ session = guestSession, manifest = man, berries = pack, opponents = 0,
  playerName = "GUEST", playerNames = { "HOST", "GUEST" }, numPlayers = 2, itemIds = ids, version = "emerald",
  cache = cache, headless = true, linkSession = BlenderLink.new(linkGuest, playerRows),
  chooseBerry = function(done) done(ids.first) end })
local linkedScreens = { hostScreen, guestScreen }
local yesNoTicks = { 0, 0 }
local linkedFrames = 0
while not hostScreen.done or not guestScreen.done do
  linkedFrames = linkedFrames + 1
  if linkedFrames > 30000 then break end
  for index, ui in ipairs(linkedScreens) do
    if not ui.done then
      local inp = { new = {}, held = {} }
      if ui.cb == "play" then
        inp.new.a = ui.game.gameFrameTime % 2 == 0
      elseif ui.cb == "end" and ui.game.gameEndState == 10 then
        yesNoTicks[index] = yesNoTicks[index] + 1
        if yesNoTicks[index] == 2 then inp.new.down = true end
        if yesNoTicks[index] == 6 then inp.new.a = true end
      elseif linkedFrames % 6 == 0 then
        inp.new.a = true
      end
      ui:frame(inp)
    end
  end
end
check(hostScreen.done and guestScreen.done, "linked Blender screens finish together")
check(hostScreen.game and guestScreen.game and hostScreen.game.gameFrameTime == guestScreen.game.gameFrameTime,
  "linked Blender clients advance the same number of frames")
check(hostSession.pokeblocks and guestSession.pokeblocks and hostSession.pokeblocks[1]
  and guestSession.pokeblocks[1], "both linked players receive the same blended Pokeblock")
eq(require("src.core.game3.bag").get(hostSession.bag, ids.first), 3, "host consumes only its selected berry")
eq(require("src.core.game3.bag").get(guestSession.bag, ids.first), 3, "guest consumes only its selected berry")


GameVersion.set(prevVersion)
T.finish("emerald_berry_blender_test")
