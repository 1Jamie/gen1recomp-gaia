-- In-process launcher session teardown: Game:reset, Renderer canvas release,
-- Runtime/Assets/LegacyCompat cleanup, and editor package.loaded discovery flush.
--   luajit tests/engine/launcher_session_teardown_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Runtime = require("src.mods.Runtime")
local Assets = require("src.render.Assets")
local LegacyCompat = require("src.mods.LegacyCompat")
local Game = require("src.core.Game")
local Renderer = require("src.render.Renderer")
local StateStack = require("src.core.StateStack")

-- ---- Game:reset drops instance state, keeps methods ----------------------
do
  StateStack:init()
  StateStack:push({ name = "stale" })
  Game.mods = { id = "orphan" }
  Game.save = { money = 1 }
  Game.network = { live = true } -- future field: must not need a whitelist
  Game.stack = StateStack
  Game.renderer = Renderer
  Renderer.canvas = love.graphics.newCanvas(8, 8)

  Game:reset()

  check(type(Game.load) == "function", "Game:reset keeps methods")
  check(type(Game.reset) == "function", "Game:reset keeps itself")
  check(Game.mods == nil, "Game:reset clears mods")
  check(Game.save == nil, "Game:reset clears save")
  check(Game.network == nil, "Game:reset clears arbitrary future fields")
  check(Game.stack == nil, "Game:reset clears stack reference")
  check(Game.renderer == nil, "Game:reset clears renderer reference")
  check(StateStack:top() == nil, "Game:reset cleared the shared StateStack")
end

-- ---- Renderer:init releases prior canvases before realloc ----------------
do
  local first = love.graphics.newCanvas(16, 16)
  Renderer.canvas = first
  Renderer.battleHUDCanvas = love.graphics.newCanvas(16, 16)
  Renderer.worldCanvas = love.graphics.newCanvas(16, 16)
  Renderer.uprightCanvas = love.graphics.newCanvas(16, 16)
  Renderer:init()
  check(first.released == true,
    "Renderer:init Object:release()s the previous primary canvas")
  check(Renderer.canvas ~= nil and Renderer.canvas ~= first,
    "Renderer:init allocates a fresh primary canvas")
  check(Renderer.canvas.released ~= true,
    "the new primary canvas is not released")
  -- second init also releases the one just created
  local second = Renderer.canvas
  Renderer:init()
  check(second.released == true,
    "a second Renderer:init releases the canvas from the prior init")
end

-- ---- Shared singleton teardown contract (closeEditor / returnToLauncher)
do
  Runtime.install({ emit = function() end }, { call = function() end }, { "e" })
  Assets.installLoader({
    overrideOrder = function() return {} end,
    derivedPath = function() return nil end,
  })
  LegacyCompat.reports = { some_mod = { order = {} } }

  -- Mirrors main.lua teardownMountedSession without mounting CacheFs.
  require("src.core.Data"):unloadGenerated()
  Runtime.reset()
  Assets.installLoader(nil)
  LegacyCompat.reset()

  check(Runtime.errors == nil, "teardown clears Runtime.errors")
  check(Assets.loader == nil, "teardown clears Assets.loader")
  eq(next(LegacyCompat.reports), nil, "teardown clears LegacyCompat.reports")
end

-- ---- Editor package.loaded discovery flush (no panel whitelist) ---------
do
  love.filesystem.write("tools/save-editor/App.lua", "return {}")
  love.filesystem.write("tools/save-editor/panels/NewPanel.lua", "return {}")
  package.loaded["App"] = { stale = true }
  package.loaded["NewPanel"] = { stale = true }
  package.loaded["src.core.Data"] = package.loaded["src.core.Data"] -- keep

  local function isEditorFlat(name)
    if name:find("[./]") then return false end
    return love.filesystem.getInfo("tools/save-editor/" .. name .. ".lua") ~= nil
      or love.filesystem.getInfo("tools/save-editor/panels/" .. name .. ".lua") ~= nil
  end
  for k in pairs(package.loaded) do
    if type(k) == "string"
        and (k:find("save%-editor", 1, false) or isEditorFlat(k)) then
      package.loaded[k] = nil
    end
  end

  check(package.loaded["App"] == nil, "discovery flush drops flat App")
  check(package.loaded["NewPanel"] == nil,
    "discovery flush drops a new panel without a hardcoded list")
  check(package.loaded["src.core.Data"] ~= nil,
    "discovery flush leaves engine modules alone")
  love.filesystem.remove("tools/save-editor/App.lua")
  love.filesystem.remove("tools/save-editor/panels/NewPanel.lua")
end

T.finish("launcher_session_teardown_test")
