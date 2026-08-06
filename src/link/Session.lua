local Session = {}
Session.__index = Session

local VALID_ROLES = { host = true, guest = true }
local REQUIRED_METHODS = { "update", "poll", "send", "close" }

function Session.new(transport, options)
  assert(type(transport) == "table", "Session.new requires a transport")
  assert(type(options) == "table", "Session.new requires options")
  assert(VALID_ROLES[options.role], "Session role must be host or guest")
  assert(type(options.kind) == "string" and options.kind ~= "",
    "Session kind must be a non-empty string")
  for _, method in ipairs(REQUIRED_METHODS) do
    assert(type(transport[method]) == "function",
      "Session transport requires " .. method)
  end

  local self = setmetatable({
    _transport = transport,
    _role = options.role,
    _kind = options.kind,
    _inbox = {},
    _status = "connecting",
    _terminal = nil,
    _transportCloseCalled = false,
    paired = false,
    closed = false,
    error = nil,
    code = nil,
    address = nil,
    target = nil,
  }, Session)
  self:_syncMetadata()
  self:_refreshStatus()
  return self
end

function Session:_syncMetadata()
  local transport = self._transport
  self.paired = transport.paired == true
  self.code = transport.code
  self.address = transport.address
  self.target = transport.target
end

function Session:_refreshStatus()
  if not self._terminal then
    self._status = self.paired and "paired" or "connecting"
    self.closed = false
    self.error = nil
  end
end

function Session:getRole() return self._role end
function Session:getKind() return self._kind end
function Session:getStatus() return self._status end
function Session:getFailure() return nil, nil end
function Session:hasPending() return #self._inbox > 0 end

function Session:send(message)
  if self._terminal then return nil end
  return self._transport:send(message)
end

function Session:update()
  if self._terminal then return end
  self._transport:update()
  self:_syncMetadata()
  local messages = self._transport:poll()
  for _, message in ipairs(messages) do
    self._inbox[#self._inbox + 1] = message
  end
  self:_refreshStatus()
end

function Session:take(messageType)
  assert(type(messageType) == "string", "Session.take requires a message type")
  for index, message in ipairs(self._inbox) do
    if message.type == messageType then
      return table.remove(self._inbox, index)
    end
  end
  return nil
end

function Session:pollOne()
  if #self._inbox == 0 then return nil end
  return table.remove(self._inbox, 1)
end

function Session:poll()
  local messages = self._inbox
  self._inbox = {}
  return messages
end

function Session:close()
  if self._transportCloseCalled then return end
  self._transportCloseCalled = true
  self._transport:close()
end

return Session
