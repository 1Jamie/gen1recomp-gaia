local K = require("tests.save_compat._codec")
local Diff = require("tests.save_compat._diff")
local Expect = require("tests.save_compat._expect")

local R1 = {}

function R1.run(T, gen, cases)
  local track = Expect.new("r1")
  local verbose = os.getenv("SAVE_COMPAT_VERBOSE") == "1"
  for _, c in ipairs(cases) do
    track.case(c.id)
    local save, err = K.import(gen, c.version, c.bytes)
    if c.refuse then
      if save then track.fail(c.id, "import-accepted", "a blank cart must be refused") end
      T.check(save ~= nil or type(err) == "string", c.id .. " refusal names a reason")
    elseif not save then
      track.fail(c.id, "import", err)
    else
      local out, xerr = K.export(gen, c.version, save, c.bytes)
      if not out then
        track.fail(c.id, "export", xerr)
      else
        for _, k in ipairs(K.compatKeys(out, c.version)) do track.fail(c.id, k.key, k.detail) end
        local entries = K.r1Diff(gen, c.version, c.bytes, out)
        for _, e in ipairs(entries) do
          track.fail(c.id, "diff:" .. e.name, Diff.format({ e }))
        end
        if verbose and #entries > 0 then print(c.id, Diff.format(entries, 12)) end
        local again = K.import(gen, c.version, out)
        if not again then track.fail(c.id, "reimport", "the export does not import") end
      end
    end
  end
  track.finish(T)
end

return R1
