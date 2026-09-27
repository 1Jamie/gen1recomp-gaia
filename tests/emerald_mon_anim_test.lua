package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_mon_anim_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()

local SHA = "f3ae088181bf583e55daf962a92bb46f4f1d07b7"
local rom = assert(require("src.import.gba.rom").open({
  info = function() return { size = #data, md5 = SHA } end,
  read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
}, "emerald"))
require("src.core.GameVersion").set("emerald")

local files = {}
local cache = {
  write = function(_, rel, b) files[rel] = b; return true end,
  read = function(_, rel) return files[rel] end,
  exists = function(_, rel) return files[rel] ~= nil end,
}
require("src.import.gba.mon_anim_extract").run(rom, cache, { cacheRoot = "data/generated/gba" })

local Data = require("src.core.game3.mon_anim_data")
Data.useCache({ read = function() return nil end })
check(not Data.available(), "no front_anims pack means mon anims are off (FireRed caches)")
Data.useCache(cache)
check(Data.available(), "Emerald cache enables mon anims")
local M = require("src.core.game3.mon_anim")
eq(Data.functionCount(), 151, "sMonAnimFunctions has 151 entries")
local ported = 0
for id = 0, 150 do
  if pcall(M.animFunction, id) then ported = ported + 1 end
end
eq(ported, 151, "every sMonAnimFunctions entry has a port")

local C = require("src.core.game3.constants").of("emerald")
local EGG = C:require("species", "SPECIES_EGG")
eq(Data.functionName(Data.frontAnimId(EGG)), Data.functionName(Data.get().front.animDelays[1]),
  "egg reads sMonFrontAnimIdsTable past its end into sMonAnimationDelayTable")
eq(Data.delay(EGG), 3, "egg delay reads gPPUpGetMask[0]")

local function run(sprite, tasksFirst)
  local n = 0
  while not M.done(sprite) and n < 2000 do
    M.step(sprite, tasksFirst)
    n = n + 1
  end
  return n
end

local stuck, moved = {}, {}
for sp = 1, EGG do
  local s = M.newSprite(sp, { data = { [0] = 1, [2] = sp } })
  M.battleFront(s, sp, false, 1, { cry = function() end })
  if run(s) >= 2000 or s.data[2] ~= sp or s.data[0] ~= 1 or not s.animEnded then stuck[#stuck + 1] = "front " .. sp end
  for flip = 0, 1 do
    local q = M.newSprite(sp, { affineMode = "off", hFlip = flip == 0, data = { [0] = sp } })
    q.callback = function(x) x.data[1] = flip; M.summary(x, sp, sp == EGG) end
    q.summary = true
    if run(q, true) >= 2000 or q.affineMode ~= "off" and q.affineMode ~= "normal" then
      stuck[#stuck + 1] = "summary " .. sp .. "/" .. flip
    end
  end
  if s.x2 ~= 0 then moved[#moved + 1] = sp end
end
for set = 0, 24 do
  for nature = 0, 24 do
    local s = M.newSprite(1, { data = { [0] = 0, [2] = 1 } })
    for sp = 1, 411 do
      if Data.backAnimSet(sp) == set then s = M.newSprite(sp, { data = { [0] = 0, [2] = sp } }) break end
    end
    M.battleBack(s, s.species, nature)
    if run(s) >= 2000 then stuck[#stuck + 1] = "back " .. set .. "/" .. nature end
  end
end
eq(#stuck, 0, "every front, summary and back anim ends (" .. table.concat(stuck, ",") .. ")")
eq(M.oob, 0, "no gSineTable read outside its 320 entries")
check(#moved == 2, "only the RapidHorizontalHops species keep x2 = 1 after the anim (" .. table.concat(moved, ",") .. ")")

local skip = M.newSprite(25, { data = { [2] = 25 } })
M.battleFront(skip, 25, true, 1, { noAnimations = true })
check(M.done(skip), "battle scene off skips the front anim")

local modes = { off = 0, normal = 1, double = 3 }
local function trunc(x) if x >= 0 then return math.floor(x) end return -math.floor(-x) end
local function mat(m)
  local sx, sy = m.xScale / 256, m.yScale / 256
  local th = math.floor(m.rotation / 256) / 128 * math.pi
  local c, s = math.cos(th), math.sin(th)
  return trunc(c * sx * 256), trunc(-s * sx * 256), trunc(s * sy * 256), trunc(c * sy * 256)
end
local golden = dofile("tests/data/emerald_mon_anim/golden.lua")
for _, g in ipairs(golden) do
  local s, tasksFirst
  if g.kind == "front" then
    s = M.newSprite(g.species, { data = { [0] = 1, [2] = g.species } })
    s.callback = function(x) M.battleFront(x, g.species, false, 1, { cry = function() end }) end
  elseif g.kind == "back" then
    s = M.newSprite(g.species, { data = { [0] = 0, [2] = g.species } })
    s.callback = function(x) M.battleBack(x, g.species, g.nature) end
  else
    s = M.newSprite(g.species, { affineMode = "off", hFlip = g.hflip == 1, data = { [0] = g.species } })
    s.callback = function(x) x.data[1] = g.noFlip; M.summary(x, g.species, false) end
    tasksFirst = true
  end
  local bad
  for i, r in ipairs(g.rows) do
    M.step(s, tasksFirst)
    local a, b, c, d = mat(s.matrix)
    local ok = s.x2 == r[1] and s.y2 == r[2] and modes[s.affineMode] == r[3] and s.frame == r[8]
      and M.callbackName(s) == r[9]
    if r[3] ~= 0 then
      ok = ok and math.abs(a - r[4]) <= 1 and math.abs(b - r[5]) <= 1 and math.abs(c - r[6]) <= 1
        and math.abs(d - r[7]) <= 1
    end
    if not ok then
      bad = string.format("frame %d: x2 %d/%d y2 %d/%d cb %s/%s", i, s.x2, r[1], s.y2, r[2], M.callbackName(s), r[9])
      break
    end
  end
  check(bad == nil, string.format("%s species %d matches the mGBA trace for %d frames%s", g.kind, g.species, #g.rows,
    bad and (" (" .. bad .. ")") or ""))
end

T.finish("emerald_mon_anim_test")
