-- FRLG options mirrored into game3 session (option_menu.c fields used on field).

local Options = {}

-- pret: textSpeed 0=SLOW 1=MID 2=FAST
Options.DEFAULTS = {
  textSpeed = 1,
  battleScene = 0,   -- 0=ON 1=OFF
  battleStyle = 0,   -- 0=SHIFT 1=SET
  sound = 0,         -- 0=MONO 1=STEREO
  buttonMode = 0,    -- 0=NORMAL 1=LR 2=L=A
  frameType = 0,
}

function Options.ensure(session)
  session = session or {}
  local o = session.options
  if type(o) ~= "table" then
    o = {}
    session.options = o
  end
  for k, v in pairs(Options.DEFAULTS) do
    if o[k] == nil then o[k] = v end
  end
  return o
end

function Options.textSpeed(session)
  local o = Options.ensure(session)
  -- Canonical field is textSpeed; text_speed is a schema alias.
  local n = tonumber(o.textSpeed)
  if n == nil then n = tonumber(o.text_speed) end
  n = n or 1
  if n < 0 then n = 0 end
  if n > 2 then n = 2 end
  return n
end

function Options.lEqualsA(session)
  local o = Options.ensure(session)
  if o.l_equals_a ~= nil then return o.l_equals_a and true or false end
  return tonumber(o.buttonMode) == 2
end

function Options.set(session, key, value)
  local o = Options.ensure(session)
  o[key] = value
  if key == "textSpeed" or key == "text_speed" then
    o.textSpeed = value
    o.text_speed = value
  end
  if key == "buttonMode" then
    o.l_equals_a = (tonumber(value) == 2)
  end
  if key == "l_equals_a" then
    o.buttonMode = value and 2 or 0
  end
  return o
end

return Options
