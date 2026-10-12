-- RED++ tileset-atlas bake worker (love.thread).  Runs AtlasBake over a
-- source ImageData off the main thread, so a map's first TileRenderer build
-- (a per-pixel recolor of the whole atlas: 1.5-7 ms on a desktop, ~10x on an
-- ARM handheld) does not land inside a seam crossing.  Only love.image is
-- used: no PaletteFX, no save state, no GPU objects.
--
-- Protocol -- main thread (src/render/AtlasPrefetch.lua) pushes onto
-- "atlas_cmd" and drains "atlas_out":
--   cmd = "bake" { epoch, key, src (ImageData) | srcPath, perRow, tileColors,
--                  aliases }   (srcPath: the worker decodes the file itself)
--   cmd = "decode" { epoch, key = resolved image path, path = path to open }
--                  (path differs from key under the NX asset overlay)
--                  decode a PNG off the main thread (Assets.image / imageData
--                  hand the result to the GPU / their callers later)
--   cmd = "quit" end the thread
-- out:
--   { key, epoch, data = ImageData }  baked atlas
--   { key, epoch, decode = true, data = ImageData }  decoded file
--   { key, epoch, failed = msg }      bake / decode error (the main thread
--                                     does it sync)
--   { fatal = msg }                   the worker loop errored and exited
--
-- Staleness is decided on the main thread from the echoed epoch; the main
-- thread clears the inbox whenever it bumps the epoch.
--
-- Worker.handle holds all the command handling so tests can drive a round trip
-- in-process by requiring this file.

local Worker = {}

-- handle(cmd, bake, out) -> true when the thread should end.
-- bake: the AtlasBake module.  out: object with :push(msg).
function Worker.handle(cmd, bake, out)
  if cmd.cmd == "bake" then
    local ok, res = pcall(function()
      local src = cmd.src or love.image.newImageData(cmd.srcPath)
      local iw, ih = src:getDimensions()
      local dst = love.image.newImageData(iw, ih)
      return bake.bake(src, dst, cmd.perRow, cmd.tileColors, cmd.aliases)
    end)
    if ok and res then
      out:push({ key = cmd.key, epoch = cmd.epoch, data = res })
    else
      out:push({ key = cmd.key, epoch = cmd.epoch,
                 failed = ok and "no image" or tostring(res) })
    end
  elseif cmd.cmd == "decode" then
    local ok, res = pcall(love.image.newImageData, cmd.path or cmd.key)
    if ok and res then
      out:push({ key = cmd.key, epoch = cmd.epoch, decode = true, data = res })
    else
      out:push({ key = cmd.key, epoch = cmd.epoch, decode = true,
                 failed = ok and "no image" or tostring(res) })
    end
  elseif cmd.cmd == "quit" then
    return true
  end
  return false
end

-- required as a module (tests): hand back the handler instead of running the
-- loop.  A love.thread entry is started with no arguments, so `...` is empty.
if select("#", ...) > 0 then return Worker end

-- Any error must end the loop by RETURNING (a raised thread error would hit
-- love.threaderror on the main thread, which this game does not handle):
-- report it through the out channel and let the main thread fall back to sync.
local function run()
  require("love.thread")
  require("love.timer")
  require("love.image")
  require("love.filesystem")

  -- a fresh thread Lua state does not necessarily carry the package searcher
  local AtlasBake = assert(love.filesystem.load("src/render/AtlasBake.lua"))()

  local cmdCh = love.thread.getChannel("atlas_cmd")
  local outCh = love.thread.getChannel("atlas_out")
  while true do
    local cmd = cmdCh:demand()
    if Worker.handle(cmd, AtlasBake, outCh) then break end
  end
end

local ok, err = pcall(run)
if not ok then
  pcall(function()
    love.thread.getChannel("atlas_out"):push({ fatal = tostring(err) })
  end)
end
