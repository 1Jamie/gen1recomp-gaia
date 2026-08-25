-- Single source of every compatibility-relevant number: engine release,
-- mod API major, link protocol, save format and ROM cache generation.  Zero
-- requires so it loads during love.conf and under plain Lua for tools and
-- tests.

local Version = {
  engine = "0.0.0-dev",   -- game/engine release (semver).  Repo default is the
                          -- "-dev" placeholder; CI stamps the real X.Y.Z into
                          -- the packed game.love only, never the working tree.
  shell = 1,              -- native-shell contract this build implements
  payloadHost = "love",   -- native host family for in-place Lua payloads.
                          -- A payload must name the same family; this prevents
                          -- mounting code packaged for a different native host.
  minShell = 1,           -- lowest shell contract that can RUN this payload.
                          -- Bump only when a payload needs a newer native
                          -- binary (e.g. a LOVE version bump); an older shell
                          -- refuses to chainload a payload whose minShell
                          -- exceeds the shell it provides.
  modApi = 2,             -- mod API major (manifest `api`)
  linkProtocol = 2,       -- link handshake wire version (Handshake.PROTOCOL)
  saveFormat = 5,         -- save.meta.format
  cache = "rom-cache-v5", -- ROM import cache generation (RomImporter marker)
}

-- True for the working-tree placeholder and any stamped "-dev" pre-release.
-- Shipped builds get a bare X.Y.Z from CI and are not "dev" here.
function Version.isDev()
  local engine = tostring(Version.engine or "")
  return engine == "0.0.0-dev" or engine:find("%-dev", 1) ~= nil
end

-- Window / chrome title.  Dev builds keep the version visible
-- ("gen1recomp v0.0.0-dev"); release builds are just the base name so Linux
-- window chrome and taskbars do not read "gen1recomp 0.1.73".
function Version.title(base)
  base = base or "gen1recomp"
  if Version.isDev() then
    return base .. " v" .. Version.engine
  end
  return base
end

return Version
