local Caps = require("src.online.union.Caps")
local UnionCenters = require("src.world.gen1.UnionCenters")
local UnionRoomMap = require("src.world.gen1.UnionRoomMap")
local Origin = require("src.online.union.Origin")
local Presence = require("src.world.gen1.UnionRoomPresence")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")

local GATE = UnionCenters.GATE_2F
local STAIRS = UnionCenters.STAIRS_2F

local WELCOME = Strings("This is the UNION\nROOM. TRAINERS\vfrom near and far\vmeet up inside.\fWould you like to\ngo in?")
local ENJOY = Strings("Step right in!\nHave fun!")
-- pokefirered/data/scripts/cable_club.inc:1492
local NEED_TWO = Strings("To enter the UNION\nROOM, you must\vhave at least two\vPOKéMON.")

local function say(game, text, after, opts)
  game.stack:push(TextBox.new(game, text, after, opts))
end

local function gateIds(game)
  local r = UnionCenters.forData(game.data)
  return r and r.gateClosed, r and r.gateOpen
end

local function walkIn(game)
  local _, open = gateIds(game)
  local ex, ey, facing = UnionRoomMap.entry()
  return {
    { "replace_block", GATE.bx, GATE.by, open },
    { "play_sound", "Switch" },
    { "wait", 20 },
    { "move_player", "left", 1 },
    { "move_player", "up", 3 },
    { "warp", UnionCenters.UNION_ROOM, ex, ey, facing },
  }
end

local function walkOut(game)
  local closed = gateIds(game)
  return {
    { "move_player", "down", 3 },
    { "replace_block", GATE.bx, GATE.by, closed },
    { "play_sound", "Switch" },
    { "face_player_dir", "right" },
    { "face_object", UnionCenters.UNION_RECEPTIONIST, "left" },
    { "show_text", "_CableClubNPCPleaseComeAgainText" },
    { "face_object", UnionCenters.UNION_RECEPTIONIST, "down" },
  }
end

local function unionReceptionist(game, ow, npc, done)
  local t = game.data.text
  if not game.save.flags.EVENT_GOT_POKEDEX then
    say(game, t._CableClubNPCMakingPreparationsText, done)
    return
  end
  local function decline() say(game, t._CableClubNPCPleaseComeAgainText, done) end
  -- pokefirered/data/scripts/cable_club.inc:747
  if Caps.gameplayMods(game) then
    say(game, Strings(Caps.MODS_TEXT), decline)
    return
  end
  say(game, WELCOME, nil, { choice = function(yes)
    if not yes then decline() return end
    -- pokefirered/data/scripts/cable_club.inc:803
    if #(game.save.party or {}) < 2 then
      say(game, NEED_TWO, decline)
      return
    end
    say(game, t._WouldYouLikeToSaveText, nil, { choice = function(save)
      if not save then decline() return end
      game:writeSave()
      say(game, t._GameSavedText, function()
        say(game, ENJOY, function()
          ow.runner:run(walkIn(game), { npc = npc, onDone = done })
        end)
      end, { auto = {
        sound = function() return require("src.core.Sound").play(game.data, "Save") end,
        delay = 30,
      } })
    end })
  end })
end

local function recordOrigin(game, fromMapId)
  local plan = UnionCenters.planFor(game.data, fromMapId)
  if not plan then return end
  Origin.record(game.save, {
    gen = 1, version = require("src.core.GameVersion").get(),
    map = plan.map, warp = plan.warp, x = plan.stairs.x, y = plan.stairs.y,
    facing = "down",
  })
end

local function returnDown(game, ow, x, y)
  local o = Origin.get(game.save)
  local plan = o and o.gen == 1 and UnionCenters.planFor(game.data, o.map)
  Origin.clear(game.save)
  if plan and plan.warp == o.warp then
    ow:takeWarp({ x = x, y = y, destMap = plan.map, destWarp = plan.warp })
  else
    ow:warpToHealPoint()
  end
end

return {
  [UnionCenters.FLOOR_2F] = {
    onEnter = function(game, ow, fromMapId)
      local closed, open = gateIds(game)
      if fromMapId == UnionCenters.UNION_ROOM then
        ow:replaceBlock(GATE.bx, GATE.by, open)
        ow:queueScript(walkOut(game))
        return
      end
      if ow.map:blockAt(GATE.bx, GATE.by) ~= closed then
        ow:replaceBlock(GATE.bx, GATE.by, closed)
      end
      recordOrigin(game, fromMapId)
    end,
    onStep = function(game, ow, x, y)
      if x ~= STAIRS.x or y ~= STAIRS.y then return false end
      returnDown(game, ow, x, y)
      return true
    end,
    talk = {
      [UnionCenters.TEXT_UNION] = unionReceptionist,
    },
  },
  [UnionCenters.UNION_ROOM] = {
    onEnter = function(game, ow) Presence.enter(game, ow) end,
    talk = {
      [Presence.TEXT] = Presence.talk,
      [UnionRoomMap.TEXT_ATTENDANT] = Presence.attendant,
      [UnionRoomMap.TEXT_BOARD] = Presence.board,
    },
  },
}
