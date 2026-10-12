local Caps = require("src.online.union.Caps")
local GameVersion = require("src.core.GameVersion")
local Participant = require("src.online.union.Participant")
local Prep = require("src.online.union.Prep")
local Protocol2 = require("src.online.Protocol2")
local Version = require("src.core.Version")
local Wire = require("src.link.Wire")

local Room = {}
Room.__index = Room

Room.CAP = Protocol2.PLAZA_CAP
Room.KIND = "union"
Room.RULESET_GB = "union"
Room.RULESET_G3 = "g3_single"

Room.ERRORS = {
  server_outdated = true, client_outdated = true, bad_profile = true, bad_avatar = true,
  bad_caps = true, profile = true, offline = true,
}

local PLAZA_REASONS = { bad_profile = true, bad_avatar = true, bad_caps = true }

local function defaultClient()
  return require("src.online.Client")
end

function Room.new(opts)
  opts = opts or {}
  return setmetatable({
    client = opts.client or defaultClient(),
    state = "idle",
    err = nil,
    errSent = false,
    bySlot = {},
    byId = {},
    me = nil,
    profile = nil,
    avatar = nil,
    caps = nil,
    ctx = nil,
    seen = nil,
    rejected = 0,
    builds = 0,
    handlers = nil,
    prepFor = nil,
    prepObj = nil,
  }, Room)
end

local function genOf(ctx)
  local v = ctx.version
  if not GameVersion.VERSIONS[v or ""] then return nil end
  return GameVersion.generation(v)
end

local function apiVersion()
  local ok, Handshake = pcall(require, "src.link.Handshake")
  return (ok and Handshake.apiVersion) or Version.modApi
end

local function gbFingerprint(ctx, gen)
  if ctx.fingerprint then return ctx.fingerprint end
  local game = ctx.game
  local data = ctx.data or (game and game.data)
  if type(data) ~= "table" then return nil end
  local Fingerprint = require("src.link.Fingerprint")
  local Handshake = require("src.link.Handshake")
  local ok, fp = pcall(Fingerprint.compute, data, Handshake.mods(game), gen)
  if ok then return fp end
  return nil
end

function Room.buildProfile(ctx)
  ctx = type(ctx) == "table" and ctx or {}
  if type(ctx.profile) == "table" then return ctx.profile end
  local gen = genOf(ctx)
  if not gen then return nil, "unknown game" end
  if gen == 3 then
    local ok, ArenaData = pcall(require, "src.online.ArenaData")
    if not ok then return nil, "unavailable" end
    local okP, profile, why = pcall(ArenaData.liveProfile3, ctx.game, ctx.rulesetId or Room.RULESET_G3)
    if not okP then return nil, tostring(profile) end
    if not profile then return nil, why or "profile" end
    return profile
  end
  local fp = gbFingerprint(ctx, gen)
  if not fp then return nil, "fingerprint" end
  return {
    engine = gen,
    version = ctx.version,
    engineVersion = Version.engine,
    apiVersion = apiVersion(),
    fingerprint = fp,
    rulesetId = Room.RULESET_GB,
    kind = "vanilla",
  }
end

function Room.buildAvatar(ctx)
  return Participant.wireAvatar({
    name = ctx.name, trainerId = ctx.trainerId, gender = ctx.gender,
    version = ctx.version, style = ctx.style, canLinkNationally = ctx.canLinkNationally,
  })
end

function Room:fail(code, detail)
  if self.err then return end
  self.err = { error = code, detail = detail }
  self.errSent = false
  self.state = "error"
end

function Room:error()
  return self.err
end

function Room:hook()
  if self.handlers then return end
  local onError = function(e)
    if type(e) ~= "table" or e.scope ~= "join" or not PLAZA_REASONS[e.reason] then return end
    if self.state ~= "joining" and self.state ~= "joined" then return end
    if e.reason == "bad_profile" and self.gen ~= 3 then
      self:fail("server_outdated", e.reason)
    else
      self:fail(e.reason)
    end
  end
  local onUpgrade = function(msg)
    if self.state == "joining" or self.state == "joined" then
      self:fail("client_outdated", msg and msg.minBuild)
    end
  end
  self.handlers = { error = onError, upgrade_required = onUpgrade }
  for event, fn in pairs(self.handlers) do self.client.on(event, fn) end
end

function Room:unhook()
  if not self.handlers then return end
  for event, fn in pairs(self.handlers) do self.client.off(event, fn) end
  self.handlers = nil
end

function Room:join(ctx)
  ctx = type(ctx) == "table" and ctx or {}
  self.err, self.errSent = nil, false
  local gen = genOf(ctx)
  if not gen then
    self:fail("profile", "unknown game")
    return false, self.err
  end
  local profile, why = Room.buildProfile(ctx)
  if not profile then
    self:fail("profile", why)
    return false, self.err
  end
  if self.client.upgradeRequired and self.client.upgradeRequired() then
    self:fail("client_outdated")
    return false, self.err
  end
  self.ctx = ctx
  self.gen = gen
  self.profile = profile
  self.avatar = Room.buildAvatar(ctx)
  self.caps = ctx.caps or Caps.compute(ctx)
  self.state = "joining"
  self.seen = nil
  self:hook()
  self.client.joinPlaza(Room.KIND, profile, self.avatar, Room.CAP,
    { xgen = Protocol2.XGEN, caps = self.caps })
  self.client.setStatus("idle")
  return true
end

function Room:setCaps(caps)
  self.caps = caps
  return self.client.setCaps(caps)
end

function Room:leave()
  if self.state == "idle" or self.state == "left" then return false end
  self.client.leavePlaza(Room.KIND)
  self:unhook()
  self.state = "left"
  self.bySlot, self.byId, self.me, self.seen = {}, {}, nil, nil
  return true
end

local function myId(client)
  local you = client.you and client.you()
  return you and you.id or nil
end

local function emptyDiff()
  return { joined = {}, left = {}, changed = {} }
end

function Room:rebuild(plaza, diff)
  self.builds = self.builds + 1
  local me = myId(self.client)
  local mySlot = tonumber(plaza.you)
  local fresh, freshIds = {}, {}
  local mine = nil
  for _, row in ipairs(plaza.members or {}) do
    local isMe = (me ~= nil and row.id == me) or (mySlot ~= nil and row.slot == mySlot)
    if isMe then
      mine = row
    else
      local p = Participant.fromMember(row)
      if p and not fresh[p.slot] and not freshIds[p.id] then
        fresh[p.slot] = p
        freshIds[p.id] = p
      else
        self.rejected = self.rejected + 1
      end
    end
  end
  if mine then
    local av = type(mine.avatar) == "table" and mine.avatar or nil
    if not av or av.gen == nil then
      self:fail("server_outdated", "legacy_shard")
      self.client.leavePlaza(Room.KIND)
      return
    end
    self.me = Participant.fromMember(mine)
  end
  for slot, old in pairs(self.bySlot) do
    local now = fresh[slot]
    if not now or now.id ~= old.id then diff.left[#diff.left + 1] = old end
  end
  for slot, now in pairs(fresh) do
    local old = self.bySlot[slot]
    if not old or old.id ~= now.id then
      diff.joined[#diff.joined + 1] = now
    elseif not Participant.same(old, now) then
      diff.changed[#diff.changed + 1] = now
    end
  end
  local bySlot = function(a, b) return a.slot < b.slot end
  table.sort(diff.joined, bySlot)
  table.sort(diff.left, bySlot)
  table.sort(diff.changed, bySlot)
  self.bySlot, self.byId = fresh, freshIds
  if self.state == "joining" then self.state = "joined" end
end

function Room:poll()
  local diff = emptyDiff()
  if self.state == "idle" or self.state == "left" then return diff end
  if not self.err and self.client.upgradeRequired and self.client.upgradeRequired() then
    self:fail("client_outdated")
  end
  if not self.err then
    local plaza = self.client.plaza()
    if type(plaza) == "table" and plaza.kind == Room.KIND then
      local seen = self.seen
      if not seen or seen.plaza ~= plaza or seen.instance ~= plaza.instance or seen.rev ~= plaza.rev then
        self.seen = { plaza = plaza, instance = plaza.instance, rev = plaza.rev }
        self:rebuild(plaza, diff)
      end
    end
  end
  if self.err and not self.errSent then
    self.errSent = true
    diff.error = self.err
  end
  return diff
end

function Room:members()
  local out = {}
  for _, p in pairs(self.bySlot) do out[#out + 1] = p end
  table.sort(out, function(a, b) return a.slot < b.slot end)
  return out
end

function Room:member(ref)
  if type(ref) == "number" then return self.bySlot[ref] end
  if type(ref) == "string" then return self.byId[ref] end
  if type(ref) == "table" then return self.byId[ref.id] end
  return nil
end

function Room:self()
  return self.me
end

function Room:count()
  local n = 0
  for _ in pairs(self.bySlot) do n = n + 1 end
  return n + (self.me and 1 or 0)
end

function Room:invite(to, activity)
  activity = activity or "xg_battle"
  local id = type(to) == "table" and to.id or to
  id = Wire.playerId(id)
  if not id or not (Protocol2.XG_ACTIVITIES[activity] or Protocol2.ACTIVITY_SET[activity]) then
    return nil, "bad_invite"
  end
  return self.client.invite(id, activity, {}, self.profile)
end

function Room:outgoing()
  return self.client.outgoing()
end

local function fromParticipant(self, inv)
  local from = type(inv.from) == "table" and inv.from or {}
  local known = self.byId[from.id or ""]
  if known then return known end
  local av = type(from.avatar) == "table" and from.avatar or nil
  if not av then return nil end
  local slot = 1
  return Participant.fromMember({ id = from.id, name = from.name, verified = from.verified,
                                  slot = slot, avatar = av, status = "idle" })
end

function Room:incoming(includeLegacy)
  local out = {}
  for _, inv in ipairs(self.client.invites() or {}) do
    local mode = Protocol2.XG_ACTIVITIES[inv.activity or ""]
    if mode or includeLegacy then
      out[#out + 1] = { id = inv.id, activity = inv.activity, mode = mode,
                        from = fromParticipant(self, inv),
                        fromId = type(inv.from) == "table" and inv.from.id or nil,
                        expiresAt = inv.expiresAt }
    end
  end
  return out
end

function Room:reply(id, accept)
  return self.client.replyInvite(id, accept == true)
end

function Room:setStatus(status)
  if not Protocol2.STATUSES[status or ""] then return false end
  return self.client.setStatus(status)
end

function Room:setBoard(board)
  if board ~= false and type(board) ~= "table" then return false end
  return self.client.setPresence({ board = board })
end

function Room:busy(p)
  return Participant.busy(p or self.me)
end

function Room:xgRoom()
  local r = self.client.room()
  if type(r) == "table" and r.intent == "xg" then return r end
  return nil
end

local function adapter(client, roomId)
  local rs = client.roomSession()
  local a = {}
  function a.send(msg)
    if rs and not rs.closed then
      rs:send(msg)
      return true
    end
    return false
  end
  function a.take(pred)
    if not rs then return nil end
    return rs:takeWhere(pred)
  end
  function a.snapshot()
    local r = client.room()
    if type(r) == "table" and r.room == roomId then return r.xg, r end
    return nil
  end
  function a.seat()
    local r = client.room()
    if type(r) == "table" and r.room == roomId then return client.seat() end
    return nil
  end
  function a.open()
    local r = client.room()
    return type(r) == "table" and r.room == roomId
  end
  function a.leave()
    if rs and not rs.left then rs:close() end
  end
  return a
end

Room.adapter = adapter

function Room:prep()
  local r = self:xgRoom()
  if r and self.prepFor ~= r.room then
    self.prepFor = r.room
    self.prepObj = Prep.new(adapter(self.client, r.room), { mode = r.mode or (r.xg and r.xg.mode) })
  end
  return self.prepObj
end

function Room:dropPrep()
  self.prepFor, self.prepObj = nil, nil
end

return Room
