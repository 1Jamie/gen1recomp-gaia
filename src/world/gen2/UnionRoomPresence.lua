local Avatars = require("src.online.union.Avatars")
local GameVersion = require("src.core.GameVersion")
local Participant = require("src.online.union.Participant")
local Room = require("src.online.union.Room")
local RoomMap = require("src.world.gen2.UnionRoomMap")
local Tag = require("src.ui.gen2.union.Tag")

local P = {}

P.MAP_ID = RoomMap.ID
P.INDEX_BASE = 300
P.CONNECT_SECONDS = 20
P.FADE = 0.35
P.FADE_STEP = 1 / 16
P.TAG_RANGE = 2
P.FOOT = 12

local function now()
  local t = love and love.timer and love.timer.getTime
  return t and t() or os.clock()
end

local function lazy(name)
  return require(name)
end

local Entity = {}
Entity.__index = Entity
P.Entity = Entity

function Entity.new(session, p)
  local x, y, facing = RoomMap.cellFor(p.slot)
  local e = setmetatable({
    session = session, participant = p, unionSlot = p.slot,
    def = { index = P.INDEX_BASE + p.slot, x = x, y = y, unionSlot = p.slot },
    id = ("%s_union_%d"):format(P.MAP_ID, p.slot), mapId = P.MAP_ID,
    cellX = x, cellY = y, homeX = x, homeY = y, px = x * 16, py = y * 16,
    facing = facing, homeFacing = facing, moving = false, progress = 0,
    stepFlip = false, inGrass = false, spawnLatched = true, frozen = false,
    kind = "stand", alpha = session.lost and P.FADE or 0, radiusX = 0, radiusY = 0,
  }, Entity)
  e.avatar = Avatars.resolve(p, { version = GameVersion.get() })
  return e
end

function Entity:setParticipant(p)
  local old = self.participant
  self.participant = p
  if Avatars.key(old) ~= Avatars.key(p) or Avatars.pickKey(old) ~= Avatars.pickKey(p) then
    self.avatar = Avatars.resolve(p, { version = GameVersion.get() })
  end
end

function Entity:covers(cx, cy)
  return self.cellX == cx and self.cellY == cy
end

function Entity:walkPhase() return 0 end

function Entity:inRadius() return false end

function Entity:scriptFace(dir)
  if dir then self.facing = dir end
end

function Entity:facePlayer(player)
  if not player then return end
  local dx, dy = player.cellX - self.cellX, player.cellY - self.cellY
  if math.abs(dx) > math.abs(dy) then
    self.facing = dx > 0 and "right" or "left"
  else
    self.facing = dy > 0 and "down" or "up"
  end
end

function Entity:update() end

function Entity:fade()
  local target = self.session.lost and P.FADE or 1
  if self.alpha < target then
    self.alpha = math.min(target, self.alpha + P.FADE_STEP)
  elseif self.alpha > target then
    self.alpha = math.max(target, self.alpha - P.FADE_STEP)
  end
end

local heights = setmetatable({}, { __mode = "k" })

function P.artHeight(entry)
  if not entry or entry.standin then return Avatars.STANDIN_H end
  local hit = heights[entry]
  if hit then return hit end
  local h = entry.h
  local id = Avatars.imageData(entry)
  local rect = entry.rects and entry.rects[0]
  if id and id.getPixel and rect then
    local gb = entry.layout ~= "gba"
    for y = 0, rect.h - 1 do
      local opaque = false
      for x = 0, rect.w - 1 do
        local r, _, _, a = id:getPixel(rect.x + x, rect.y + y)
        if (gb and r <= 0.83) or (not gb and a > 0) then opaque = true break end
      end
      if opaque then
        h = rect.h - y
        break
      end
    end
  end
  heights[entry] = h
  return h
end

function Entity:height()
  return P.artHeight(self.avatar)
end

function Entity:draw(ox, oy, scale)
  local G = love.graphics
  local s = scale or 1
  local fx = (ox or 0) + (self.px + 8) * s
  local fy = (oy or 0) + (self.py + P.FOOT) * s
  G.setColor(1, 1, 1, self.alpha)
  Avatars.draw(self.avatar, fx, fy, self.facing, 0, false, s)
  G.setColor(1, 1, 1, 1)
  local p = self.participant
  Tag.draw(fx, fy - self:height() * s, p.name, Participant.badgeDigit(p),
    self.session.tagged == self, s)
end

function Entity:onTalk(world)
  return self.session:talk(world, self)
end

local Session = {}
Session.__index = Session
P.Session = Session

function P.new(game, world, opts)
  opts = opts or {}
  local client = opts.client or lazy("src.online.Client")
  return setmetatable({
    game = game, world = world, opts = opts,
    client = client,
    connect = opts.connect,
    room = opts.room or Room.new({ client = client }),
    state = "idle", since = nil, lost = false,
    bySlot = {}, pending = {}, notices = {}, seen = {}, abandoned = {},
    ui = nil, activity = nil, tagged = nil, err = nil,
    spawned = 0, despawned = 0,
  }, Session)
end

function Session:connectModule()
  return self.connect or lazy("src.online.Connect")
end

function Session:ctx()
  local o = self.opts.ctx
  if o then return o end
  local game, world = self.game, self.world
  local save = game and game.save or {}
  local player = save.player or {}
  local version = GameVersion.get()
  local gender = 0
  if version == "crystal" and world and world.playerGender then
    gender = lazy("src.world.gen2.FieldMoves").isFemale(world:playerGender()) and 1 or 0
  end
  return { version = version, game = game, name = player.name, trainerId = player.id,
           gender = gender, style = Participant.DEFAULT_STYLE }
end

function Session:start()
  if self.state ~= "idle" then return end
  local cs = self.client.state()
  if cs == "online" then return self:join() end
  self.state = "connecting"
  self.since = now()
  if cs == "connecting" or cs == "reconnecting" then return end
  local ctx = self:ctx()
  local profile = Room.buildProfile(ctx)
  if not profile then return self:fail("profile") end
  local Connect = self:connectModule()
  local okCall, ok = pcall(Connect.start, {
    source = "game", version = ctx.version,
    trainerName = ctx.name, profiles = { profile },
    presence = { where = "game", status = "idle", version = ctx.version },
  })
  if not (okCall and ok) then return self:fail("offline") end
  self:notice({ kind = "connecting" })
end

function Session:join()
  local ok, err = self.room:join(self:ctx())
  if not ok then return self:fail(err and err.error or "profile") end
  self.state = "joined"
end

function Session:fail(code)
  self:clear()
  if self.room.state ~= "idle" and self.room.state ~= "left" then self.room:leave() end
  self.state = "offline"
  self.err = code
  self.lost = false
  self:notice({ kind = "error", code = code })
end

function Session:notice(n)
  for i = #self.notices, 1, -1 do
    local k = self.notices[i].kind
    if k == "connecting" or k == "lost" then table.remove(self.notices, i) end
  end
  self.notices[#self.notices + 1] = n
end

function Session:idle()
  local game, world = self.game, self.world
  if self.ui or self.activity then return false end
  if game and game.stack and game.stack:top() then return false end
  if world and world.busy and world:busy() then return false end
  local p = world and world.player
  if p and p.moving then return false end
  return true
end

local function removeFrom(list, item)
  if type(list) ~= "table" then return end
  for i = #list, 1, -1 do
    if list[i] == item then table.remove(list, i) end
  end
end

function Session:blocked(x, y)
  local p = self.world and self.world.player
  if not p then return false end
  if p.cellX == x and p.cellY == y then return true end
  return p.moving and p.targetX == x and p.targetY == y
end

function Session:spawn(p)
  local x, y = RoomMap.cellFor(p.slot)
  if not x then return nil end
  self:despawn(p.slot)
  if self:blocked(x, y) then
    self.pending[p.slot] = p
    return nil
  end
  self.pending[p.slot] = nil
  local e = Entity.new(self, p)
  local world = self.world
  world.npcs = world.npcs or {}
  world.entities = world.entities or {}
  table.insert(world.npcs, e)
  table.insert(world.entities, e)
  self.bySlot[p.slot] = e
  self.spawned = self.spawned + 1
  return e
end

function Session:despawn(slot)
  self.pending[slot] = nil
  local e = self.bySlot[slot]
  if not e then return end
  removeFrom(self.world.npcs, e)
  removeFrom(self.world.entities, e)
  if self.tagged == e then self.tagged = nil end
  self.bySlot[slot] = nil
  self.despawned = self.despawned + 1
end

function Session:clear()
  for slot in pairs(self.bySlot) do self:despawn(slot) end
  self.pending = {}
end

function Session:apply(diff)
  for _, p in ipairs(diff.left or {}) do
    local e = self.bySlot[p.slot]
    if (e and e.participant.id == p.id) or (self.pending[p.slot] and self.pending[p.slot].id == p.id) then
      self:despawn(p.slot)
    end
  end
  for _, p in ipairs(diff.joined or {}) do self:spawn(p) end
  for _, p in ipairs(diff.changed or {}) do
    local e = self.bySlot[p.slot]
    if e then
      e:setParticipant(p)
    elseif self.pending[p.slot] then
      self.pending[p.slot] = p
    end
  end
end

function Session:retryPending()
  for slot, p in pairs(self.pending) do
    local x, y = RoomMap.cellFor(slot)
    if not self:blocked(x, y) then self:spawn(p) end
  end
end

function Session:entity(slot)
  return self.bySlot[slot]
end

function Session:entities()
  local out = {}
  for _, e in pairs(self.bySlot) do out[#out + 1] = e end
  table.sort(out, function(a, b) return a.unionSlot < b.unionSlot end)
  return out
end

function Session:pickTagged()
  local p = self.world and self.world.player
  if not p then self.tagged = nil return end
  local best, bestD
  local d = ({ up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } })[p.facing or "down"]
  local faced = d and self.world.npcAt and self.world:npcAt(p.cellX + d[1], p.cellY + d[2])
  if faced and faced.session == self then self.tagged = faced return end
  for _, e in pairs(self.bySlot) do
    local dist = math.abs(e.cellX - p.cellX) + math.abs(e.cellY - p.cellY)
    if dist <= P.TAG_RANGE and (not bestD or dist < bestD
        or (dist == bestD and e.unionSlot < best.unionSlot)) then
      best, bestD = e, dist
    end
  end
  self.tagged = best
end

function Session:watchLink()
  local cs = self.client.state()
  if cs == "online" then
    if self.lost then self.lost = false end
  elseif cs == "reconnecting" or cs == "connecting" then
    if not self.lost then
      self.lost = true
      self:notice({ kind = "lost" })
    end
  else
    self:fail("lost")
  end
end

function Session:watchActivity()
  local xr = self.room:xgRoom()
  if self.activity then
    if self.activity.done then
      self.activity = nil
      self.room:dropPrep()
    end
    return
  end
  if not xr or self.ui then return end
  for handle in pairs(self.abandoned) do
    if handle.room and handle.room == xr.room then
      self.abandoned[handle] = nil
      local prep = self.room:prep()
      if prep then
        prep:cancel("cancel")
        prep:leave()
      end
      self.room:dropPrep()
      return
    end
  end
  if self.closedRoom == xr.room then return end
  local Activity = lazy("src.ui.gen2.union.Activity")
  self.activity = Activity.begin(self.game, self.room, xr.mode or (xr.xg and xr.xg.mode), { session = self })
  self.closedRoom = xr.room
end

function Session:watchInvites()
  if not self:idle() then return end
  for _, inv in ipairs(self.room:incoming()) do
    if not self.seen[inv.id] then
      self.seen[inv.id] = true
      lazy("src.ui.gen2.union.Talk").prompt(self, inv)
      return
    end
  end
end

function Session:pumpNotices()
  while #self.notices > 0 do
    local n = self.notices[1]
    if n.kind == "lost" and not self.lost then
      table.remove(self.notices, 1)
    elseif n.kind == "connecting" and self.state ~= "connecting" then
      table.remove(self.notices, 1)
    else
      break
    end
  end
  local n = self.notices[1]
  if not n or not self:idle() then return end
  table.remove(self.notices, 1)
  lazy("src.ui.gen2.union.Talk").notice(self, n)
end

function Session:update()
  if self.state == "idle" then self:start() end
  if self.state == "connecting" then
    local cs = self.client.state()
    if cs == "online" then
      self:join()
    elseif cs == "error" or now() - (self.since or now()) > P.CONNECT_SECONDS then
      self:fail("offline")
    end
  end
  if self.state == "joined" then
    self:watchLink()
  end
  if self.state == "joined" then
    local diff = self.room:poll()
    self:apply(diff)
    if diff.error then
      self:fail(diff.error.error)
    else
      self:retryPending()
      self:watchActivity()
      self:watchInvites()
    end
  end
  for _, e in pairs(self.bySlot) do e:fade() end
  self:pickTagged()
  self:pumpNotices()
end

function Session:talk(world, e)
  if self.ui or self.activity then return true end
  e:facePlayer(world and world.player)
  lazy("src.ui.gen2.union.Talk").open(self, e)
  return true
end

function Session:uiOpen(kind)
  self.ui = kind or true
end

function Session:uiDone()
  self.ui = nil
  for _, e in pairs(self.bySlot) do e.facing = e.homeFacing end
end

function Session:close()
  if self.activity and self.activity.abort then self.activity:abort("left") end
  self.activity = nil
  self:clear()
  if self.boardEntry then
    self.boardEntry = nil
    self.room:setBoard(false)
  end
  if self.room.state ~= "idle" and self.room.state ~= "left" then self.room:leave() end
  self.state = "closed"
end

local current = nil

function P.tick(game)
  local world = game and game.world
  local onRoom = world and world.map and world.map.id == P.MAP_ID
  if current and (not onRoom or current.world ~= world) then
    current:close()
    current = nil
  end
  if onRoom and not current then current = P.new(game, world, P.defaults) end
  if current then current:update() end
  return current
end

function P.active()
  return current
end

function P.talkBoard(world, kind)
  local s = current
  if not (s and s.world == world) or s.ui or s.activity then return true end
  lazy("src.ui.gen2.union.Board")[kind](s)
  return true
end

function P.reset()
  if current then current:close() end
  current = nil
end

return P
