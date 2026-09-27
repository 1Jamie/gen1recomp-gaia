package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Palette = require("src.core.game3.gba_palette")
local Scanline = require("src.core.game3.scanline_fx")
local Affine = require("src.core.game3.bg_affine")
local Tasks = require("src.core.game3.gba_tasks")
local Sprites = require("src.core.game3.gba_sprites")
local BootModules = require("src.ui.game3.boot_modules")

do
  local p = Palette.new()
  p:load({ 0x001F }, 0, 1)
  eq(p.faded[0], 0x001F, "LoadPalette writes the faded buffer")
  check(p:beginFade(Palette.ALL, 0, 0, 16, Palette.BLACK), "fade starts")
  eq(p.pltt[0], 0x001F, "BeginNormalPaletteFade copies y=0 to hardware")
  eq(p:update(), Palette.STATUS_ACTIVE, "second update blends the OBJ half")
  eq(p:update(), Palette.STATUS_LOADING, "no update before the buffer transfer")
  p:transfer()
  eq(p:update(), Palette.STATUS_ACTIVE, "BG half at y=2")
  eq(p.faded[0], 27, "31 + ((0 - 31) * 2 >> 4) = 27")
  check(not p:beginFade(Palette.ALL, 0, 16, 0, Palette.WHITE), "a second fade is refused while active")
  local calls = 0
  while p:fadeActive() and calls < 100 do
    p:transfer()
    p:update()
    calls = calls + 1
  end
  eq(p.faded[0], 0, "fade reaches black")
  eq(calls, 20, "fade 0->16 finishes after 16 blend updates and 5 finishing updates")
  p:resetFade()
  p:load({ Palette.rgb(10, 20, 30) }, 256, 1)
  p:blendMask(Palette.OBJ, 8, Palette.WHITE)
  eq(p.faded[256], Palette.rgb(20, 25, 30), "BlendPalettes halfway to white")
  p:copyUnfaded(256, 256 + 15 * 16 + 3, 13)
  eq(p.unfaded[256 + 15 * 16 + 3], Palette.rgb(10, 20, 30), "shifted palette copy")
end

do
  local s = Scanline.new()
  s:initWave(0, 160, 4, 4, 1, "BG1HOFS", nil)
  eq(s.buffers[0][0], 0, "wave line 0")
  eq(s.buffers[0][16], 4, "wave peak at theta 64")
  eq(s.buffers[0][48], 65532, "wave trough stored as u16")
  eq(s.buffers[1][16], 4, "second buffer seeded")
  s:vblank({})
  local lines = s:lineValues()
  eq(lines[16], 4, "vblank latches the written buffer")
  eq(s.srcBuffer, 1, "buffers swap each vblank")
  check(s:runWaveTask(), "wave task runs")
  eq(s.buffers[1][16], 4, "first pass keeps the phase")
  eq(s.buffers[1][15], 3, "line 15 is sin(60) * 4 / 256")
  check(s:runWaveTask(), "wave task runs again")
  eq(s.buffers[1][15], 3, "delay interval 1 holds the phase for two passes")
  check(s:runWaveTask(), "wave task runs a third time")
  eq(s.buffers[1][15], 4, "then the wave moves up one line")
  s.state = 3
  local regs = {}
  s:vblank(regs)
  check(s:lineValues() == nil, "state 3 stops the DMA")
  check(not s:runWaveTask(), "and the wave task ends")
end

do
  local r = Affine.panFadeAndZoom(120, 80, 256, 0)
  eq(r.pa, 256, "unit zoom pa")
  eq(r.pb, 0, "unit zoom pb")
  eq(r.pd, 256, "unit zoom pd")
  eq(r.dx, 8 * 256, "tex centre 128 minus screen 120")
  eq(r.dy, 48 * 256, "tex centre 128 minus screen 80")
  local z = Affine.panFadeAndZoom(120, 80, 512, 0)
  eq(z.pa, 512, "2x scale")
  eq(z.dx, (128 - 240) * 256, "2x reference point")
  local x, y = Affine.sample(r, 0, 0, 256, 256, false)
  eq(x, 8, "sample x")
  eq(y, 48, "sample y")
  eq(Affine.convertScaleParam(128), 512, "ConvertScaleParam")
  local m = Affine.objAffineSet(256, 256, 0)
  eq(m.a, 256, "identity OBJ matrix a")
  eq(m.b, 0, "identity OBJ matrix b")
  local q = Affine.objAffineSet(256, 256, 64 * 256)
  eq(q.a, 0, "quarter turn a")
  eq(q.b, -256, "quarter turn b")
  eq(q.c, 256, "quarter turn c")
end

do
  local t = Tasks.new()
  local order = {}
  local a, b
  a = t:create(function(id)
    order[#order + 1] = "a"
    if #order == 1 then t:create(function() order[#order + 1] = "c" end, 0) end
    t:destroy(id)
  end, 0)
  b = t:create(function() order[#order + 1] = "b" end, 0)
  t:create(function() order[#order + 1] = "early" end, 0)
  t:run()
  eq(table.concat(order, ","), "a,b,early,c", "created tasks append and run in the same pass")
  order = {}
  t:run()
  eq(table.concat(order, ","), "b,early,c", "destroyed task is unlinked")
  check(a ~= b, "distinct task ids")
end

do
  local pal = Palette.new()
  local sp = Sprites.new(pal)
  local anims = { { { op = "frame", frame = 0, duration = 2 }, { op = "frame", frame = 1, duration = 2 }, { op = "jump", target = 0 } } }
  local id = sp:create({ w = 16, h = 16, anims = anims }, 50, 60, 0)
  local s = sp:get(id)
  local seen = {}
  for i = 1, 6 do
    sp:animateAll()
    seen[i] = s.frame
  end
  eq(table.concat(seen, ","), "0,0,1,1,0,0", "AnimCmd frame durations")
  sp:buildOam()
  local e = sp.oamBuffer[1]
  eq(e.x, 42, "centre to corner x")
  eq(e.y, 52, "centre to corner y")
  eq(sp:loadPalette(7, { 1, 2, 3 }), 0, "first sprite palette slot")
  sp:setReservedPalettes(8)
  eq(sp:loadPalette(9, { 4 }), 8, "reserved palettes skip low slots")
  eq(pal.unfaded[256 + 8 * 16], 4, "sprite palette lands in OBJ palette RAM")
  local aid = sp:create({ w = 16, h = 16, anims = anims, affineMode = Sprites.AFFINE_DOUBLE,
    affineAnims = { { { op = "frame", xScale = 128, yScale = 128, rotation = 0, duration = 0 }, { op = "end" } } } }, 0, 0, 0)
  local as = sp:get(aid)
  eq(as.centerToCornerVecX, -16, "double-size affine sprites double the corner vector")
  sp:animateAll()
  eq(sp.matrices[as.oam.matrixNum].a, 512, "affine anim frame sets half scale matrix")
end

do
  local fr = BootModules.resolve({ id = "firered" })
  check(fr.custom == false, "profiles without a boot block keep the FireRed boot")
  local em = BootModules["for"](require("src.core.game3.profiles.emerald"))
  check(em.custom == true, "Emerald boot block routes through modules")
  eq(em.intro, "src.ui.game3.rse.intro_emerald", "Emerald intro module")
  eq(em.title, "src.ui.game3.rse.title_rse", "Emerald title module")
  eq(em.params.titleParams.song, "MUS_TITLE", "title song by name")
end

T.finish()
