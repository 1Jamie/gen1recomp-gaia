-- Oak speech scene layer: BG, portrait, platform, scroll, simple fades.

local Display = require("src.core.game3.display")

local OakScene = {}

function OakScene.new(assets)
  assets = assets or {}
  local platformQuads = nil
  if assets.platform and love and love.graphics and love.graphics.newQuad then
    local pw, ph = assets.platform:getDimensions()
    if pw >= 32 and ph >= 96 then
      platformQuads = {}
      for i = 0, 2 do
        platformQuads[i] = love.graphics.newQuad(0, i * 32, 32, 32, pw, ph)
      end
    end
  end
  return {
    bg = assets.oakSpeechBg,
    oak = assets.oakSprite,
    boy = assets.boySprite,
    girl = assets.girlSprite,
    rival = assets.rivalSprite,
    nidoran = assets.nidoranFront,
    ball = assets.ballPoke,
    platform = assets.platform,
    platformQuads = platformQuads,
    portrait = "oak", -- oak | boy | girl | rival | player | none
    gender = 0,
    scrollX = 0,
    nidoranVisible = false,
    nidoranX = 96,
    nidoranY = 96,
    nidoranScale = 1,
    ballVisible = false,
    ballX = 100,
    ballY = 66,
    ballFrame = 0,
    -- Exit shrink (pret Task_OakSpeech_ShrinkPlayerPic): scale around (120,84).
    portraitScale = 1,
    portraitWhite = 0, -- 0..1 blend toward white
    platformVisible = true,
    fade = 0, -- 0 clear .. 1 black
    fadeDir = 0,
  }
end

function OakScene.setPortrait(scene, which)
  scene.portrait = which or "none"
end

function OakScene.setGender(scene, gender)
  scene.gender = tonumber(gender) or 0
end

function OakScene.draw(scene)
  local W, H = Display.W, Display.H
  if scene.bg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(scene.bg, 0, 0)
  else
    love.graphics.setColor(115 / 255, 197 / 255, 164 / 255, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)
  end

  local sx = scene.scrollX or 0
  -- Platform TL at (72/104/136, 96)
  if scene.platformVisible ~= false and scene.platform then
    love.graphics.setColor(1, 1, 1, 1)
    if scene.platformQuads then
      for i = 0, 2 do
        love.graphics.draw(scene.platform, scene.platformQuads[i], 72 + i * 32 + sx, 96)
      end
    else
      love.graphics.draw(scene.platform, 72 + sx, 96)
    end
  end

  local pic = nil
  if scene.portrait == "oak" then pic = scene.oak
  elseif scene.portrait == "boy" then pic = scene.boy
  elseif scene.portrait == "girl" then pic = scene.girl
  elseif scene.portrait == "rival" then pic = scene.rival
  elseif scene.portrait == "player" then
    pic = scene.gender == 1 and scene.girl or scene.boy
  end
  if pic then
    local scale = tonumber(scene.portraitScale) or 1
    local white = math.max(0, math.min(1, tonumber(scene.portraitWhite) or 0))
    -- Pret affine pivot is (120, 84); unscaled pic TL is (88, 16).
    local baseX, baseY = 88 + sx, 16
    local pivX, pivY = 120 + sx, 84
    local ox = pivX - (pivX - baseX) * scale
    local oy = pivY - (pivY - baseY) * scale
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(pic, ox, oy, 0, scale, scale)
    if white > 0 then
      love.graphics.setBlendMode("add")
      love.graphics.setColor(1, 1, 1, white)
      love.graphics.draw(pic, ox, oy, 0, scale, scale)
      love.graphics.setBlendMode("alpha")
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  if scene.nidoranVisible and scene.nidoran then
    love.graphics.setColor(1, 1, 1, 1)
    local sc = scene.nidoranScale or 1
    local ox = (scene.nidoranX or 96) - 32 * sc
    local oy = (scene.nidoranY or 96) - 32 * sc
    love.graphics.draw(scene.nidoran, ox, oy, 0, sc, sc)
  end

  if scene.ballVisible and scene.ball then
    love.graphics.setColor(1, 1, 1, 1)
    local fr = scene.ballFrame or 0
    local q = love.graphics.newQuad and love.graphics.newQuad(0, fr * 16, 16, 16, scene.ball:getDimensions())
    local bx = (scene.ballX or 100) - 8
    local by = (scene.ballY or 66) - 8
    if q then love.graphics.draw(scene.ball, q, bx, by)
    else love.graphics.draw(scene.ball, bx, by) end
  end

  if (scene.fade or 0) > 0 then
    love.graphics.setColor(0, 0, 0, scene.fade)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return OakScene
