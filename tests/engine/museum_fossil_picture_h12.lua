package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness").suite("H12 museum fossil picture")
local before = os.getenv("H12_BEFORE")
if before then
  package.loaded["src.core.game3.scripting.natives_cutscene"] = assert(loadfile(before .. "/src/core/game3/scripting/natives_cutscene.lua"))()
  package.loaded["src.ui.game3.ui_pass"] = assert(loadfile(before .. "/src/ui/game3/ui_pass.lua"))()
end
local Version = require("src.core.GameVersion")
Version.set("firered")
local Flags = require("src.core.game3.scripting.flags")
local Cutscene = require("src.core.game3.scripting.natives_cutscene")
local Museum = require("src.ui.game3.museum_fossil_pic")
local noCacheCtx = { specialVars = {} }
package.loaded["src.core.game3.scripting.space"] = { store = Flags.newStore() }
Flags.setVar(nil, noCacheCtx, 0x8004, 141)
Flags.setVar(nil, noCacheCtx, 0x8005, 10)
Flags.setVar(nil, noCacheCtx, 0x8006, 3)
T.eq(Cutscene.BY_NAME.OpenMuseumFossilPic(noCacheCtx), false, "detached native remains nonblocking")
T.eq(noCacheCtx.museumFossilPic.species, 141, "detached no-cache state seam remains")
T.eq(Museum.isActive(), false, "detached state creates no visible owner")
Cutscene.BY_NAME.CloseMuseumFossilPic(noCacheCtx)
T.eq(noCacheCtx.museumFossilPic, nil, "detached state clears")
package.loaded["src.core.game3.scripting.space"] = nil

local Cache = require("tests.game3_cache")
local bundle, root = Cache.bundle()
if not root then
  print("[skip] H12 cache-backed controls: " .. tostring(Cache.reason))
  T.finish(); return
end
local actualSpace = require("src.core.game3.scripting.space")
local Dataset = require("src.core.game3.dataset")
local Extract = require("src.import.gba.extract_island1")
local Runtime = require("src.core.game3.runtime")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local Schema = require("src.core.game3.save_schema_firered")
local Natives = require("src.core.game3.scripting.natives")
local Constants = require("src.core.game3.constants")
local Serializer = require("src.core.SaveSerializer")
local Display = require("src.core.game3.display")
local Window = require("src.ui.game3.window")
local Stack = require("src.ui.game3.stack")
local Message = require("src.ui.game3.message")
local MonPic = require("src.ui.game3.mon_pic")
local closed = { isOpen = function() return false end, isVisible = function() return false end,
  isActive = function() return false end, isForestActive = function() return false end,
  draw = function() error("closed UI drawn") end }
for _, name in ipairs({ "choice", "start_menu", "bag_menu", "region_map", "party_menu", "pokedex",
  "option_menu", "save_menu", "trainer_card", "pc_menu", "money_box", "coins_box", "elevator_window",
  "berry_powder_box", "map_preview_screen", "map_name_popup", "naming", "seagallop", "easy_chat" }) do
  package.loaded["src.ui.game3." .. name] = closed
end
package.loaded["src.ui.game3.fade"] = { draw = function() end }
package.loaded["src.ui.game3.wireless_icon"] = { drawField = function() end }
package.loaded["src.core.game3.battle_transition"] = { draw = function() end }

local bytes, scripts = {}, {}
for species, name in pairs({ [141] = "kabutops", [142] = "aerodactyl" }) do
  local f = assert(io.open(root .. "/museum/" .. name .. ".rgba", "rb"))
  bytes[species] = f:read("*a"); f:close()
  T.eq(#bytes[species], 16384, name .. " required actual imported art size")
end
T.check(bytes[141] ~= bytes[142], "both exhibits have distinct imported fossil art")
for key, rows in pairs(bundle.scripts) do
  local species
  for _, row in ipairs(rows) do
    if row.op == "setvar" and row.var == 0x8004 then species = row.value end
    if row.op == "special" and row.id == Constants.of("firered").specials.byName.OpenMuseumFossilPic then
      if species == 141 or species == 142 then scripts[species] = key end
    end
  end
end
T.check(scripts[141] ~= nil and scripts[142] ~= nil, "both actual imported exhibit scripts resolve by native id")

local events, frames, draws, allocations = {}, {}, {}, {}
local newData, newImage, oldFrame, oldMessageDraw = love.image.newImageData, love.graphics.newImage, Window.stdFrame, Message.draw
love.image.newImageData = function(w,h,fmt,rgba)
  local data = newData(w,h,fmt,rgba); data._rgba = rgba; return data
end
love.graphics.newImage = function(data, ...)
  local img = newImage(data, ...)
  if type(data) == "table" and data._rgba then
    img._rgba, img.w, img.h = data._rgba, data.w, data.h
    img.release = function(self) self.released = true end
    allocations[#allocations + 1] = img
  end
  return img
end
love.graphics.draw = function(img, ...)
  draws[#draws + 1] = { image = img, args = { ... } }
  if img._rgba == bytes[141] or img._rgba == bytes[142] then events[#events + 1] = "fossil" end
end
Window.stdFrame = function(tpl) frames[#frames + 1] = tpl; return oldFrame(tpl) end
Message.draw = function() events[#events + 1] = "message"; return oldMessageDraw() end
local function draw()
  events, draws, frames = {}, {}, {}
  Display.drawUiPass()
  local fossil = {}
  for _, row in ipairs(draws) do
    if row.image._rgba == bytes[141] or row.image._rgba == bytes[142] then fossil[#fossil + 1] = row end
  end
  return fossil
end

local vm, ctx, session
local function setup()
  if ctx then Cutscene.BY_NAME.CloseMuseumFossilPic(ctx) end
  Stack.clear(); Message.close(); MonPic.hide()
  session = Schema.newGame({ version = "firered", name = "RED" })
  Runtime.session = session
  vm = Vm.new({ store = Flags.newStore() }); ctx = vm.ctx; ctx.status = "waiting"
  actualSpace.vm, actualSpace.mapId, actualSpace.store = vm, "FR_PEWTER_MUSEUM_1F", vm.store
  return ctx
end
local function open(species, x, y)
  Flags.setVar(nil, ctx, 0x8004, species)
  Flags.setVar(nil, ctx, 0x8005, x or 10); Flags.setVar(nil, ctx, 0x8006, y or 3)
  return Cutscene.BY_NAME.OpenMuseumFossilPic(ctx)
end

for _, species in ipairs({ 141, 142 }) do
  setup()
  local saved = Serializer.encode(session)
  local cries, fronts = 0, 0
  local Audio, Pokemon = require("src.core.game3.audio"), require("src.core.game3.pokemon")
  local oldCry, oldFront = Audio.playCry, Pokemon.frontPic
  Audio.playCry = function() cries = cries + 1 end
  Pokemon.frontPic = function() fronts = fronts + 1; error("fossil must not use Pokemon front") end
  T.eq(open(species), false, species .. " actual handler remains nonblocking")
  T.eq(ctx.museumFossilPic.species, species, species .. " context seam preserved")
  Message.show("exhibit description", { speed = 0, stay = true })
  local images = draw()
  T.eq(#images, 1, species .. " native reaches actual Display UI image draw")
  if images[1] then
    T.eq(images[1].image._rgba, bytes[species], species .. " uses exact imported RGBA rather than Pokemon art")
    T.eq(images[1].image.w, 64, species .. " image width")
    T.eq(images[1].image.h, 64, species .. " image height")
    T.eq(images[1].args[1], 88, species .. " source sprite left from center120")
    T.eq(images[1].args[2], 32, species .. " source sprite top from center64")
    local f = frames[#frames]
    T.eq(f.left, 11, species .. " source window content left")
    T.eq(f.top, 4, species .. " source window content top")
    T.eq(f.w, 8, species .. " source window width")
    T.eq(f.h, 8, species .. " source window height")
    T.eq(events[1], "fossil", species .. " fossil draws before description")
    T.eq(events[2], "message", species .. " description stays visible above fossil")
  else T.check(false, species .. " fossil frame and art required") end
  T.eq(cries, 0, species .. " no cry")
  T.eq(fronts, 0, species .. " no ordinary Pokemon picture")
  T.eq(Serializer.encode(session), saved, species .. " no save/dex mutation")
  local firstState, n = ctx.museumFossilPic, #allocations
  open(species == 141 and 142 or 141, 2, 7)
  T.check(ctx.museumFossilPic == firstState, species .. " duplicate open retains original state")
  T.eq(#allocations, n, species .. " duplicate does not allocate another sprite")
  open(25)
  T.check(ctx.museumFossilPic == firstState, species .. " invalid species does not replace an exhibit")
  Cutscene.BY_NAME.CloseMuseumFossilPic(ctx)
  T.eq(ctx.museumFossilPic, nil, species .. " close clears context")
  T.eq(#draw(), 0, species .. " close retires visible fossil")
  if images[1] then T.eq(images[1].image.released, true, species .. " close releases loaded art") end
  open(species, 4, 2)
  local reopened = draw()
  T.eq(#reopened, 1, species .. " exhibit can reopen after close")
  if reopened[1] then
    T.eq(reopened[1].args[1], 40, species .. " reopened nondefault source x")
    T.eq(reopened[1].args[2], 24, species .. " reopened nondefault source y")
  end
  Cutscene.BY_NAME.CloseMuseumFossilPic({})
  T.eq(#draw(), 1, species .. " another context cannot close the owning exhibit")
  Cutscene.BY_NAME.CloseMuseumFossilPic(ctx)
  Audio.playCry, Pokemon.frontPic = oldCry, oldFront
end

for _, species in ipairs({ 141, 142 }) do
  setup()
  local acknowledged
  local adapters = Adapters.stub({})
  adapters.openMessageStay = function(text) Message.showStay(text, { speed = 0 }) end
  adapters.openMessageAsync = adapters.openMessageStay
  adapters.closeMessage = Message.close
  adapters.armWaitButton = function(cb) acknowledged = cb end
  vm = Vm.new({ store = vm.store, scripts = bundle.scripts, text = bundle.text,
    movements = bundle.movements, adapters = adapters })
  ctx = vm.ctx; actualSpace.vm = vm
  local beforeSave = Serializer.encode(session)
  T.check(vm:start(scripts[species]), species .. " imported exhibit starts in actual VM")
  Message.skipReveal(); vm:tick(); vm:tick()
  T.check(Message.isOpen(), species .. " actual imported description is open")
  T.check(Message.currentPage():lower():find(species == 141 and "kabutops" or "aerodactyl", 1, true) ~= nil,
    species .. " actual ROM description matches exhibit")
  T.check(vm:isRunning(), species .. " acknowledgement retains VM wait")
  T.eq(#draw(), 1, species .. " actual imported script retains fossil alongside message")
  T.check(type(acknowledged) == "function", species .. " description owns acknowledgement")
  if acknowledged then acknowledged(); vm:tick() end
  T.eq(vm:isRunning(), false, species .. " acknowledgement completes actual script")
  T.eq(ctx.museumFossilPic, nil, species .. " actual CloseMuseumFossilPic retires state")
  T.eq(#draw(), 0, species .. " completed exhibit leaves no art")
  T.eq(Serializer.encode(session), beforeSave, species .. " imported exhibit never changes saved state")
end

for _, mutate in ipairs({
  { "VM teardown", function() actualSpace.vm = nil end },
  { "VM replacement", function() actualSpace.vm = Vm.new() end },
  { "map retarget", function() actualSpace.mapId = "FR_PEWTER_CITY" end },
  { "VM halt", function() vm:halt(true) end },
  { "session replacement", function() Runtime.session = {} end },
  { "edition rebind", function() Version.set("leafgreen") end },
  { "root rebind", function() Extract.CACHE_ROOT = root .. "/other" end },
  { "override rebind", function() Dataset.cacheRootOverride = root .. "/other" end },
}) do
  Version.set("firered"); Extract.CACHE_ROOT = root; Dataset.cacheRootOverride = root
  setup(); open(141)
  local images = draw(); T.eq(#images, 1, mutate[1] .. " starts with loaded exhibit")
  mutate[2]()
  T.eq(#draw(), 0, mutate[1] .. " retires art")
  T.eq(ctx.museumFossilPic, nil, mutate[1] .. " clears stale owning context")
  if images[1] then T.eq(images[1].image.released, true, mutate[1] .. " releases old art") end
end
Version.set("firered"); Extract.CACHE_ROOT = root; Dataset.cacheRootOverride = root
local Game3 = require("src.core.Game3")
local clearFieldScreens
for i = 1, 100 do
  local name, fn = debug.getupvalue(Game3.returnToTitle, i)
  if not name then break end
  if name == "clearFieldScreens" then clearFieldScreens = fn; break end
end
T.check(type(clearFieldScreens) == "function", "actual title transition exposes screen teardown")
setup(); open(141)
local resetImage = draw()[1]
T.check(resetImage ~= nil, "title reset starts with loaded exhibit")
if clearFieldScreens then clearFieldScreens() end
T.eq(ctx.museumFossilPic, nil, "actual screen teardown clears owning context without field polling")
if resetImage then T.eq(resetImage.image.released, true, "actual screen teardown synchronously releases fossil image") end
T.eq(#draw(), 0, "title teardown leaves no fossil art")
setup(); open(141)
Stack.push("test_fullscreen", { draw = function() end }, { hideBelow = false, fullscreen = true })
T.eq(#draw(), 0, "unrelated fullscreen layer suppresses fossil")
Stack.clear(); T.eq(#draw(), 1, "returning to field restores still-owned fossil")
Stack.push("test_dialog", { draw = function() end }, { hideBelow = true })
T.eq(#draw(), 0, "hideBelow dialog suppresses fossil")
Stack.clear(); T.eq(#draw(), 1, "layer pop restores fossil without reopening")

local Pokemon = require("src.core.game3.pokemon")
local ordinary = love.graphics.newImage("ordinary-mon-positive-control")
Pokemon.frontPic = function() return { image = ordinary, w = 64, h = 64 } end
MonPic.show(25, 10, 3, { noCry = true })
Cutscene.BY_NAME.CloseMuseumFossilPic(ctx); draw()
local ordinaryDraws = 0; for _, row in ipairs(draws) do if row.image == ordinary then ordinaryDraws = ordinaryDraws + 1 end end
T.eq(ordinaryDraws, 1, "closing museum leaves ordinary MonPic visible")
T.eq(MonPic.active, true, "closing museum never hides ordinary picture")
MonPic.hide(); T.eq(#draw(), 0, "ordinary and fossil lifetimes are independent")

local read = Dataset.cache().read
for _, failure in ipairs({
  { "missing art", function(rel) if rel:find("kabutops.rgba", 1, true) then return false end end },
  { "missing manifest", function(rel) if rel:find("manifest.lua", 1, true) then return false end end },
  { "short art", function(rel) return rel:find("kabutops.rgba", 1, true) and bytes[141]:sub(1, -2) end },
  { "malformed manifest", function(rel) return rel:find("manifest.lua", 1, true) and "invalid" end },
  { "wrong dimensions", function(rel) return rel:find("manifest.lua", 1, true) and 'return {format_version=1,width=8,height=64,species={kabutops=141,aerodactyl=142}}' end },
}) do
  setup()
  Dataset.cache().read = function(self, rel)
    local value = failure[2](rel)
    if value == false then return nil end
    return value or read(self, rel)
  end
  local ok, err = pcall(open, 141)
  T.eq(ok, false, failure[1] .. " fails strict bound native display")
  T.check(tostring(err):find("[game3/museum]", 1, true) ~= nil, failure[1] .. " identifies required cache art failure")
  T.eq(ctx.museumFossilPic, nil, failure[1] .. " manufactures no placeholder state")
  T.eq(#draw(), 0, failure[1] .. " manufactures no placeholder draw")
  Dataset.cache().read = read
end

Cutscene.BY_NAME.CloseMuseumFossilPic(ctx)
T.finish()
