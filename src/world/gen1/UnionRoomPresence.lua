local Avatars = require("src.online.union.Avatars")
local FieldDefaults = require("src.world.FieldDefaults")
local GameVersion = require("src.core.GameVersion")
local Participant = require("src.online.union.Participant")
local Room = require("src.online.union.Room")
local UnionRoomMap = require("src.world.gen1.UnionRoomMap")

local Presence = {}
Presence.__index = Presence

Presence.MAP_ID = UnionRoomMap.MAP_ID
Presence.TEXT = "TEXT_UNION_ROOM_MEMBER"
Presence.INDEX_BASE = 1000
Presence.CONNECT_SECONDS = 15
Presence.LOST_SHOW_FRAMES = 60
Presence.LOST_GIVE_UP_SECONDS = 30
Presence.FOCUS_RANGE = 2

Presence.seams = { newRoom = nil, connect = nil }

local LIVE = { online = true }
local DOWN = { error = true, offline = true }

local function now()
  return love.timer.getTime()
end

local function ui(name)
  return require("src.ui.union.gen1." .. name)
end

local function defaultConnect(opts)
  return require("src.online.Connect").start(opts)
end

function Presence.cellFor(slot)
  local x, y, facing = UnionRoomMap.cellFor(slot)
  if not x then return nil end
  return { x = x, y = y, facing = facing or "down" }
end

local Member = {}
Member.__index = Member
Presence.Member = Member

function Member.new(presence, p, cell)
  local self = setmetatable({}, Member)
  self.presence = presence
  self.p = p
  self.unionMember = true
  self.id = Presence.MAP_ID .. "_union_" .. p.slot
  self.def = { index = Presence.INDEX_BASE + p.slot, text = Presence.TEXT,
               name = "UNION_MEMBER_" .. p.slot, union = true }
  self.cellX, self.cellY = cell.x, cell.y
  self.px, self.py = cell.x * 16, cell.y * 16
  self.home = cell.facing
  self.facing = self.home
  self.moving = false
  self.frozen = false
  self:setParticipant(p)
  return self
end

function Member:setParticipant(p)
  local key = Avatars.key(p) .. "#" .. Avatars.pickKey(p)
  if key ~= self.avatarKey then
    self.avatarKey = key
    self.entry = Avatars.resolve(p, { version = GameVersion.get() })
  end
  self.p = p
  self.name = ui("Text").clean(p.name)
  self.digit = Participant.badgeDigit(p)
end

function Member:update()
  if not self.frozen and not self.presence.busy and self.facing ~= self.home then
    self.facing = self.home
  end
end

function Member:facePlayer(player)
  local dx = player.cellX - self.cellX
  local dy = player.cellY - self.cellY
  if math.abs(dx) > math.abs(dy) then
    self.facing = dx > 0 and "right" or "left"
  else
    self.facing = dy > 0 and "down" or "up"
  end
end

function Member:resetToSpawn() end

function Member:walkPhase() return 0 end

function Member:pose()
  return nil, self.px, self.py, self.facing, 0, false, false
end

function Member:foot(camX, camY)
  return math.floor(self.px - camX) + 8, math.floor(self.py - camY) + 12
end

function Member:draw(camX, camY)
  local fx, fy = self:foot(camX, camY)
  local Look = ui("Look")
  Look.draw(self.entry, fx, fy, self.facing, self.presence.lookOpts)
  if self.presence.focus ~= self and self.digit then
    ui("Tag").draw(fx, fy - Look.height(self.entry), self.name, self.digit, false)
  end
end

local Overlay = {}
Overlay.__index = Overlay
Overlay.passable = true
Overlay.unionOverlay = true

function Overlay:draw(camX, camY)
  local m = self.presence.focus
  if not m then return end
  local fx, fy = m:foot(camX, camY)
  local top = fy - ui("Look").height(m.entry)
  local ow = self.presence:ow()
  local pl = ow and ow.player
  if pl and pl.cellX == m.cellX and pl.cellY == m.cellY - 1 then
    top = math.min(top, math.floor(pl.py - camY) + 12 - 16)
  end
  ui("Tag").draw(fx, top, m.name, m.digit, true)
end

function Overlay:update() end

function Presence.new(game, opts)
  opts = opts or {}
  local self = setmetatable({
    game = game,
    state = "idle",
    members = {},
    pending = {},
    notices = {},
    seenInvites = {},
    tracked = {},
    abandoned = {},
    frames = 0,
    busy = false,
    statusSent = nil,
    focus = nil,
    boundNpcs = nil,
    boundEntities = nil,
    closed = false,
  }, Presence)
  self.overlay = setmetatable({ presence = self, px = 0, py = -1 }, Overlay)
  local walk = FieldDefaults.fieldValue(game.data, "playerSprites", "walk")
  self.lookOpts = { playerDef = game.data.sprites and game.data.sprites[walk], seed = "union" }
  self.room = opts.room or (Presence.seams.newRoom and Presence.seams.newRoom(game)) or Room.new()
  self.client = self.room.client
  self.connect = opts.connect or Presence.seams.connect or defaultConnect
  self.ctxExtra = opts.ctx or Presence.seams.ctx
  return self
end

function Presence.current(game)
  local p = game and game.unionPresence
  if p and not p.closed then return p end
  return nil
end

function Presence:ctx()
  local save = self.game.save
  local player = save and save.player or {}
  local ctx = {
    version = GameVersion.get(), game = self.game, data = self.game.data,
    name = player.name, trainerId = player.id, gender = 0, style = "player",
  }
  for k, v in pairs(self.ctxExtra or {}) do ctx[k] = v end
  return ctx
end

function Presence:connectOptions(profile)
  local version = GameVersion.get()
  local player = self.game.save and self.game.save.player or {}
  return {
    source = "game", version = version, trainerName = player.name,
    profiles = { profile },
    presence = { where = "game", status = "idle", version = version },
  }
end

function Presence:clientState()
  return self.client and self.client.state and self.client.state() or "offline"
end

function Presence:start()
  if LIVE[self:clientState()] then
    self:join()
    return
  end
  local profile, why = Room.buildProfile(self:ctx())
  if not profile then
    self:goOffline("profile", why)
    return
  end
  local ok, err = self.connect(self:connectOptions(profile))
  if not ok then
    self:goOffline("offline", err)
    return
  end
  self.state = "connecting"
  self.since = now()
end

function Presence:join()
  local ok, err = self.room:join(self:ctx())
  if not ok then
    self:goOffline(err and err.error or "profile")
    return
  end
  self.state = "joining"
  self.statusSent = "idle"
  self.since = now()
end

function Presence:goOffline(code, detail)
  if self.state == "offline" then return end
  self.state = "offline"
  self.offlineCode = code
  self.offlineDetail = detail
  self:clearMembers()
  if self.room.state == "joining" or self.room.state == "joined" or self.room.state == "error" then
    self.room:leave()
  end
  self:notify(ui("Text").error(code))
end

function Presence:notify(text)
  self.notices[#self.notices + 1] = text
end

function Presence:ow()
  return self.game.overworld
end

local function removeFrom(list, item)
  if not list then return end
  for i = #list, 1, -1 do
    if list[i] == item then table.remove(list, i) end
  end
end

local function contains(list, item)
  for i = 1, #list do
    if list[i] == item then return true end
  end
  return false
end

function Presence:bind(ow)
  if not (ow and ow.npcs and ow.entities) then return end
  if self.boundNpcs == ow.npcs and self.boundEntities == ow.entities then return end
  self.boundNpcs, self.boundEntities = ow.npcs, ow.entities
  for _, m in pairs(self.members) do
    if not contains(ow.npcs, m) then ow.npcs[#ow.npcs + 1] = m end
    if not contains(ow.entities, m) then ow.entities[#ow.entities + 1] = m end
  end
  if not contains(ow.entities, self.overlay) then ow.entities[#ow.entities + 1] = self.overlay end
end

function Presence:unbind()
  local npcs, entities = self.boundNpcs, self.boundEntities
  for _, m in pairs(self.members) do
    removeFrom(npcs, m)
    removeFrom(entities, m)
  end
  removeFrom(entities, self.overlay)
  self.boundNpcs, self.boundEntities = nil, nil
end

local function occupies(e, x, y)
  return e ~= nil and ((e.cellX == x and e.cellY == y) or (e.targetX == x and e.targetY == y))
end

function Presence:cellBlocked(cell)
  local ow = self:ow()
  if not ow then return false end
  if occupies(ow.player, cell.x, cell.y) then return true end
  local follower = require("src.world.PikachuFollower").current(ow)
  if occupies(follower, cell.x, cell.y) then return true end
  return false
end

function Presence:spawn(p)
  local cell = Presence.cellFor(p.slot)
  if not cell then return nil end
  if self:cellBlocked(cell) then
    self.pending[p.slot] = p
    return nil
  end
  self.pending[p.slot] = nil
  local m = Member.new(self, p, cell)
  self.members[p.slot] = m
  if self.boundNpcs then
    self.boundNpcs[#self.boundNpcs + 1] = m
    self.boundEntities[#self.boundEntities + 1] = m
  end
  return m
end

function Presence:despawn(slot)
  self.pending[slot] = nil
  local m = self.members[slot]
  if not m then return end
  self.members[slot] = nil
  removeFrom(self.boundNpcs, m)
  removeFrom(self.boundEntities, m)
  if self.focus == m then self.focus = nil end
end

function Presence:clearMembers()
  for slot in pairs(self.members) do self:despawn(slot) end
  self.pending = {}
  self.focus = nil
end

function Presence:apply(diff)
  for _, p in ipairs(diff.left or {}) do
    local m = self.members[p.slot]
    if (m and m.p.id == p.id) or (self.pending[p.slot] and self.pending[p.slot].id == p.id) then
      self:despawn(p.slot)
    end
  end
  for _, p in ipairs(diff.joined or {}) do
    if self.members[p.slot] then self:despawn(p.slot) end
    self:spawn(p)
  end
  for _, p in ipairs(diff.changed or {}) do
    local m = self.members[p.slot]
    if m then
      m:setParticipant(p)
    elseif self.pending[p.slot] then
      self.pending[p.slot] = p
    end
  end
end

function Presence:retryPending()
  for slot, p in pairs(self.pending) do
    if not self.members[slot] then self:spawn(p) end
  end
end

function Presence:participant(member)
  if not member then return nil end
  local p = member.p
  return self.room:member(p.id) or (self.members[p.slot] == member and p or nil)
end

function Presence:memberById(id)
  for _, m in pairs(self.members) do
    if m.p.id == id then return m end
  end
  return nil
end

function Presence:memberAt(x, y)
  local slot = UnionRoomMap.slotAt(x, y)
  local m = slot and self.members[slot]
  if m and m.cellX == x and m.cellY == y then return m end
  return nil
end

function Presence:count()
  local n = 0
  for _ in pairs(self.members) do n = n + 1 end
  return n
end

function Presence:setBusy(on, speaker)
  self.busy = on and true or false
  self.speaker = self.busy and speaker or nil
  local status = self.busy and "busy" or "idle"
  if self.state == "joined" and self.statusSent ~= status then
    self.statusSent = status
    self.room:setStatus(status)
  end
end

function Presence:track(h)
  self.tracked[h] = true
end

function Presence:untrack(h)
  self.tracked[h] = nil
end

function Presence:abandon(h)
  self.tracked[h] = nil
  self.abandoned[h] = true
end

function Presence:sweepAbandoned()
  for h in pairs(self.abandoned) do
    if h.state == "accepted" then
      local prep = self.room:prep()
      if prep then
        prep:cancel("cancel")
        prep:leave()
        self.room:dropPrep()
        self.abandoned[h] = nil
      end
    elseif h.state == "closed" then
      self.abandoned[h] = nil
    end
  end
end

function Presence:updateFocus()
  local ow = self:ow()
  local player = ow and ow.player
  if not player or not player.cellX then
    self.focus = nil
    return
  end
  local Collision = require("src.world.Collision")
  local fx, fy = Collision.target(player.cellX, player.cellY, player.facing or "down")
  local speaker = self.busy and self.speaker
  local best = (speaker and self.members[speaker.p.slot] == speaker and speaker) or self:memberAt(fx, fy)
  if not best then
    local bestD = Presence.FOCUS_RANGE + 1
    for _, m in pairs(self.members) do
      local d = math.abs(m.cellX - player.cellX) + math.abs(m.cellY - player.cellY)
      if d < bestD or (d == bestD and best and m.p.slot < best.p.slot) then
        best, bestD = m, d
      end
    end
  end
  self.focus = best
  if best then
    self.overlay.px, self.overlay.py = best.px, best.py + 0.5
  end
end

function Presence:idle()
  local ow = self:ow()
  if not ow or self.game.stack:top() ~= ow then return false end
  if ow.transitioning or (ow.runner and ow.runner:isRunning()) then return false end
  if ow.scriptMoves and #ow.scriptMoves > 0 then return false end
  if ow.pendingScripts and ow.pendingScripts[1] then return false end
  local p = ow.player
  return p ~= nil and not p.moving
end

function Presence:connection()
  local cs = self:clientState()
  if self.state == "connecting" then
    if LIVE[cs] then
      self:join()
    elseif DOWN[cs] or now() - (self.since or now()) > Presence.CONNECT_SECONDS then
      self:goOffline("offline")
    end
  elseif self.state == "joining" or self.state == "joined" then
    if cs == "reconnecting" then
      self.state = "reconnecting"
      self.resumeState = self.room.state == "joined" and "joined" or "joining"
      self.lostAt = self.frames
      self.lostSince = now()
    elseif DOWN[cs] then
      self:goOffline("lost")
    elseif self.state == "joining" and self.room.state == "joined" then
      self.state = "joined"
      self:setBusy(self.busy, self.speaker)
    end
  elseif self.state == "reconnecting" then
    if LIVE[cs] then
      self.state = self.room.state == "joined" and "joined" or self.resumeState or "joining"
      self.lostAt = nil
      self.statusSent = nil
      self:setBusy(self.busy, self.speaker)
    elseif DOWN[cs] or now() - (self.lostSince or now()) > Presence.LOST_GIVE_UP_SECONDS then
      self:goOffline("lost")
    end
  end
end

function Presence:showLost()
  if self.lostBox and self.state ~= "reconnecting" then
    self.lostBox:close()
    self.lostBox = nil
  end
  if self.lostBox or self.state ~= "reconnecting" then return end
  if self.frames - (self.lostAt or 0) < Presence.LOST_SHOW_FRAMES or not self:idle() then return end
  local Dialog = ui("Dialog")
  self.lostBox = Dialog.hold(self.game, ui("Text").say("lost"), function(w)
    if self.state ~= "reconnecting" then
      w:close()
      self.lostBox = nil
    end
  end)
end

function Presence:offerInvite()
  if self.busy or self.state ~= "joined" or not self:idle() then return end
  for _, inv in ipairs(self.room:incoming()) do
    if not self.seenInvites[inv.id] then
      self.seenInvites[inv.id] = true
      ui("Talk").incoming(self.game, self, inv)
      return
    end
  end
end

function Presence:showNotice()
  if not self.notices[1] or self.busy or not self:idle() then return end
  local text = table.remove(self.notices, 1)
  ui("Dialog").say(self.game, text)
end

function Presence:tick()
  if self.closed then return end
  local ow = self:ow()
  if not (ow and ow.map and ow.map.id == Presence.MAP_ID) then
    self:leave()
    return
  end
  self.frames = self.frames + 1
  self:bind(ow)
  self:connection()
  if self.state == "joining" or self.state == "joined" or self.state == "reconnecting" then
    local diff = self.room:poll()
    if diff.error then
      self:goOffline(diff.error.error, diff.error.detail)
    else
      self:apply(diff)
    end
  end
  self:retryPending()
  self:sweepAbandoned()
  self:updateFocus()
  self:showLost()
  self:offerInvite()
  self:showNotice()
end

function Presence:entities()
  local out = {}
  for _, m in pairs(self.members) do out[#out + 1] = m end
  table.sort(out, function(a, b) return a.p.slot < b.p.slot end)
  return out
end

function Presence:entity(slot)
  return self.members[slot]
end

function Presence:leave()
  if self.closed then return end
  self.closed = true
  if self.activity then self.activity:abort("left") end
  self:unbind()
  self:clearMembers()
  if self.boardEntry then
    self.boardEntry = nil
    self.room:setBoard(false)
  end
  if self.room.state ~= "idle" and self.room.state ~= "left" then
    self.room:setStatus("busy")
    self.room:leave()
  end
  self.state = "left"
  if self.game.unionPresence == self then self.game.unionPresence = nil end
end

function Presence.enter(game, ow)
  local self = Presence.current(game)
  if not self then
    self = Presence.new(game)
    game.unionPresence = self
    self:start()
  end
  self:bind(ow or game.overworld)
  return self
end

function Presence.active()
  return Presence.current(require("src.core.Game"))
end

function Presence.tickGame(game)
  local self = game and game.unionPresence
  if self then self:tick() end
end

function Presence.talk(game, ow, npc, done)
  local self = Presence.current(game)
  if not (self and npc and npc.unionMember) then
    if done then done() end
    return
  end
  ui("Talk").begin(game, self, npc, done)
end

local function boardTalk(fn)
  return function(game, _, _, done)
    local self = Presence.current(game)
    if not self then
      if done then done() end
      return
    end
    ui("Board")[fn](game, self, done)
  end
end

Presence.attendant = boardTalk("attendant")
Presence.board = boardTalk("check")

return Presence
