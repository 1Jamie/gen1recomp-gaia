package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Net = require("src.link.Net")
local Session = require("src.link.Session")

local function sessionPair()
  local hostNet, guestNet = Net.loopbackPair()
  return Session.new(hostNet, { role = "host", kind = "link" }),
         Session.new(guestNet, { role = "guest", kind = "link" })
end

do
  local host, guest = sessionPair()
  T.eq(host:getRole(), "host", "host role is assigned locally")
  T.eq(guest:getRole(), "guest", "guest role is assigned locally")
  T.eq(host:getKind(), "link", "session kind is retained")
  T.eq(host:getStatus(), "paired", "wrapped loopback starts paired")

  guest:send({
    type = "hello", name = "BLUE", role = "host", kind = "tournament",
  })
  host:update()
  local hello = host:take("hello")
  T.eq(hello.name, "BLUE", "send forwards the original payload")
  T.eq(hello.session, nil, "send adds no session envelope")
  T.eq(host:getRole(), "host", "peer payload cannot replace local role")
  T.eq(host:getKind(), "link", "peer payload cannot replace local kind")
end

do
  local host, guest = sessionPair()
  guest:send({ type = "before", sequence = 1 })
  guest:send({ type = "hello", sequence = 2 })
  guest:send({ type = "after", sequence = 3 })
  guest:send({ type = "hello", sequence = 4 })
  host:update()

  local hello = host:take("hello")
  T.eq(hello.sequence, 2, "take removes the first matching packet")
  T.eq(host:pollOne().sequence, 1, "pollOne removes only the FIFO head")

  local rest = host:poll()
  T.eq(#rest, 2, "poll returns every remaining packet once")
  T.eq(rest[1].sequence, 3, "take preserves the earlier remainder order")
  T.eq(rest[2].sequence, 4, "take preserves repeated-type order")
  T.eq(#host:poll(), 0, "poll clears the private FIFO")
end

do
  local sent
  local transport = {
    paired = false,
    code = nil,
    address = "192.0.2.5:7777",
    target = "ROOM01",
    update = function(self)
      self.paired = true
      self.code = "ROOM02"
    end,
    poll = function() return {} end,
    send = function(_, message)
      sent = message
      return "queued", 7
    end,
    close = function(self) self.closed = true end,
  }
  local session = Session.new(transport, { role = "guest", kind = "tournament" })
  T.eq(session:getStatus(), "connecting", "unpaired transport starts connecting")
  T.eq(session.address, "192.0.2.5:7777", "address metadata is mirrored")
  T.eq(session.target, "ROOM01", "target metadata is mirrored")

  local outbound = { type = "ping" }
  local result, count = session:send(outbound)
  T.eq(result, "queued", "send preserves the transport's first return")
  T.eq(count, 7, "send preserves the transport's second return")
  T.eq(sent, outbound, "send forwards the original table unchanged")

  session:update()
  T.eq(session:getStatus(), "paired", "update observes transport pairing")
  T.eq(session.code, "ROOM02", "update refreshes relay metadata")
end

T.finish("link_session")
