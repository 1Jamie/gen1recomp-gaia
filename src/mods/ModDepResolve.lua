-- Install-time hard-dependency fetch: when a mod is installed or updated,
-- missing or out-of-range hard deps that declare `github` are pulled through
-- the same ModUpdate release/zip pipeline as mod self-updates.
--
-- Additive / optional: string-only deps (no `github`) are left alone — install
-- succeeds as before and the Loader still reports missing/out-of-range at boot.
-- Auto-fetch only runs when a dep opts in with `github`.
--
-- Pure orchestration: callers inject findLocal / fetchReleases / installRelease
-- so tests can drive it without network or LOVE.  No boot-time use — Loader
-- stays local-only.

local Semver = require("src.mods.Semver")

local ModDepResolve = {}

ModDepResolve.MAX_DEPTH = 3

-- Prefer ModUpdate's classifier so install-time resolve and update checks
-- agree on what counts as a GitHub rate-limit failure.
function ModDepResolve.isRateLimitError(err)
  local ModUpdate = require("src.mods.ModUpdate")
  return ModUpdate.isRateLimitError(err)
end

-- Newest non-prerelease release whose version satisfies `range`.
-- `releases` is ModUpdate's newest-first (or unsorted) list.
function ModDepResolve.pickRelease(releases, range)
  if type(releases) ~= "table" then return nil end
  local versions, byVersion = {}, {}
  for _, rel in ipairs(releases) do
    if type(rel) == "table" and not rel.prerelease
        and type(rel.version) == "string" and rel.zip and rel.zip.url then
      if not byVersion[rel.version] then
        byVersion[rel.version] = rel
        versions[#versions + 1] = rel.version
      end
    end
  end
  local best = Semver.latestSatisfying(versions, range)
  return best and byVersion[best] or nil
end

local function fail(msg)
  return nil, msg
end

local function hasGithub(dep)
  return type(dep) == "table" and type(dep.github) == "string" and dep.github ~= ""
end

-- Resolve hard deps of `manifest`.  ctx:
--   depth (number, 0 = root install; only increments along fetched deps)
--   visited (table, dep id -> true)
--   fetched (optional array; append each dep id installed this pass)
--   findLocal(id) -> installed manifest or nil
--   fetchReleases(github, id) -> releases, err
--   installRelease(id, release) -> true|nil, err
--
-- Deps without `github` that are missing/out-of-range are skipped (not an
-- install error).  Only deps we fetch are recursed into, so local-only dep
-- graphs cannot trip the depth limit.
-- Returns true [, fetched] | nil, err.  `fetched` is ctx.fetched when provided.
function ModDepResolve.resolve(manifest, ctx)
  ctx = ctx or {}
  local depth = ctx.depth or 0
  if depth > ModDepResolve.MAX_DEPTH then
    return fail("dependency depth exceeded")
  end
  local visited = ctx.visited or {}
  ctx.visited = visited

  if type(manifest) ~= "table" then
    return fail("missing mod manifest")
  end
  local specs = manifest.dependencySpecs
  if type(specs) ~= "table" then return true, ctx.fetched end

  local findLocal = ctx.findLocal
  local fetchReleases = ctx.fetchReleases
  local installRelease = ctx.installRelease
  assert(type(findLocal) == "function", "ctx.findLocal required")
  assert(type(fetchReleases) == "function", "ctx.fetchReleases required")
  assert(type(installRelease) == "function", "ctx.installRelease required")

  for _, dep in ipairs(specs) do
    local id = dep.id
    if type(id) == "string" and id ~= "" and not visited[id] then
      visited[id] = true

      local localMan = findLocal(id)
      local localOk = localMan
        and Semver.satisfies(localMan.version, dep.range)

      if localOk then
        -- Already installed and in range: leave alone (Loader owns the rest).
        -- Do not recurse — walking local trees would change install cost and
        -- could trip depth limits on deep string-only graphs.
      elseif not hasGithub(dep) then
        -- Opt-in only: same as pre-feature installs — missing string deps are
        -- fine here; Loader reports them when the game boots.
      else
        local releases, fetchErr = fetchReleases(dep.github, id)
        if not releases then
          if ModDepResolve.isRateLimitError(fetchErr) then
            return fail("GitHub API rate limit exceeded; try again later")
          end
          return fail(("could not fetch releases for %s (%s): %s")
            :format(id, dep.github, tostring(fetchErr or "unknown error")))
        end
        local release = ModDepResolve.pickRelease(releases, dep.range)
        if not release then
          return fail(("no tagged release of %s (%s) satisfies %s")
            :format(id, dep.github, tostring(dep.range or "*")))
        end
        local ok, installErr = installRelease(id, release)
        if not ok then
          return fail(("failed to install dependency %q: %s")
            :format(id, tostring(installErr or "install failed")))
        end
        local fetched = ctx.fetched
        if type(fetched) == "table" then
          fetched[#fetched + 1] = id
        end
        local depManifest = findLocal(id)
        if not depManifest then
          return fail(("dependency %q installed but is not discoverable"):format(id))
        end
        if depManifest.id ~= id then
          return fail(("dependency zip id %q does not match expected %q")
            :format(tostring(depManifest.id), id))
        end
        if not Semver.satisfies(depManifest.version, dep.range) then
          return fail(("dependency %q installed version %s does not satisfy %s")
            :format(id, tostring(depManifest.version), tostring(dep.range or "*")))
        end
        local childCtx = {
          depth = depth + 1,
          visited = visited,
          fetched = ctx.fetched,
          findLocal = findLocal,
          fetchReleases = fetchReleases,
          installRelease = installRelease,
        }
        local childOk, childErr = ModDepResolve.resolve(depManifest, childCtx)
        if not childOk then return fail(childErr) end
      end
    end
  end
  return true, ctx.fetched
end

return ModDepResolve
