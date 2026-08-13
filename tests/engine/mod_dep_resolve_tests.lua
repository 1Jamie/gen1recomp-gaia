-- Install-time hard-dep resolve (src/mods/ModDepResolve.lua).
-- Fake release lists / local installs — no network.
--   luajit tests/engine/mod_dep_resolve_tests.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local ModDepResolve = require("src.mods.ModDepResolve")
local ModUpdate = require("src.mods.ModUpdate")

local function rel(version, url)
  return {
    version = version,
    prerelease = false,
    zip = { url = url or ("https://x/" .. version .. ".zip") },
  }
end

local function makeCtx(opts)
  opts = opts or {}
  local installed = opts.installed or {}
  local releasesByRepo = opts.releasesByRepo or {}
  local fetchErrByRepo = opts.fetchErrByRepo or {}
  local installErrById = opts.installErrById or {}
  local log = { fetches = {}, installs = {} }

  local ctx = {
    depth = opts.depth or 0,
    visited = opts.visited or {},
    findLocal = function(id)
      return installed[id]
    end,
    fetchReleases = function(github, id)
      log.fetches[#log.fetches + 1] = { github = github, id = id }
      if fetchErrByRepo[github] then
        return nil, fetchErrByRepo[github]
      end
      return releasesByRepo[github] or {}, nil
    end,
    installRelease = function(id, release)
      log.installs[#log.installs + 1] = { id = id, version = release.version }
      if installErrById[id] then
        return nil, installErrById[id]
      end
      local man = {
        id = id,
        version = release.version,
        dependencySpecs = (opts.depSpecsAfterInstall and opts.depSpecsAfterInstall[id])
          or {},
      }
      installed[id] = man
      return true, release.version
    end,
  }
  return ctx, log, installed
end

-- pickRelease: latest non-prerelease in range
do
  local pick = ModDepResolve.pickRelease({
    rel("1.0.0"),
    rel("1.2.0"),
    { version = "1.3.0-rc.1", prerelease = true,
      zip = { url = "https://x/rc.zip" } },
    rel("1.1.9"),
  }, "^1.0")
  eq(pick.version, "1.2.0", "pickRelease skips prereleases and takes newest")
  check(ModDepResolve.pickRelease({
    { version = "2.0.0", prerelease = false, zip = { url = "https://x/2.zip" } },
  }, "^1.0") == nil, "pickRelease returns nil when none satisfy")
end

-- rate-limit classifier
check(ModUpdate.isRateLimitError("API rate limit exceeded for 1.2.3.4"),
  "rate limit text is detected")
check(ModUpdate.isRateLimitError(
    "GET https://api.github.com/repos/a/b/releases failed: HTTP 403: API rate limit"),
  "HTTP 403 + rate limit is detected")
check(ModDepResolve.isRateLimitError("GitHub API rate limit exceeded; try again later"),
  "ModDepResolve delegates to ModUpdate")
check(not ModUpdate.isRateLimitError("no releases found"),
  "ordinary errors are not rate limits")

-- local already satisfies: no fetch
do
  local root = {
    id = "root", version = "1.0.0",
    dependencySpecs = {
      { id = "lib", range = "^1.0", github = "Acme/lib" },
    },
  }
  local ctx, log = makeCtx({
    installed = { lib = { id = "lib", version = "1.2.0", dependencySpecs = {} } },
    releasesByRepo = { ["Acme/lib"] = { rel("1.9.0") } },
  })
  local ok, err = ModDepResolve.resolve(root, ctx)
  check(ok, "local in-range dep succeeds: " .. tostring(err))
  eq(#log.fetches, 0, "local in-range dep does not fetch")
  eq(#log.installs, 0, "local in-range dep does not install")
end

-- missing dep with github: fetch + install latest in range
do
  local root = {
    id = "root", version = "1.0.0",
    dependencySpecs = {
      { id = "lib", range = "^1.0", github = "Acme/lib" },
    },
  }
  local ctx, log = makeCtx({
    releasesByRepo = {
      ["Acme/lib"] = { rel("2.0.0"), rel("1.4.0"), rel("1.0.0") },
    },
  })
  local ok, err = ModDepResolve.resolve(root, ctx)
  check(ok, "fetch install succeeds: " .. tostring(err))
  eq(#log.fetches, 1, "fetches once")
  eq(log.installs[1].id, "lib", "installs the dep id")
  eq(log.installs[1].version, "1.4.0", "installs latest satisfying tag")
end

-- missing github when fetch needed: skip (additive — Loader still owns this)
do
  local root = {
    id = "root", version = "1.0.0",
    dependencySpecs = { { id = "lib", range = "^1.0" } },
  }
  local ctx, log = makeCtx({})
  local ok, err = ModDepResolve.resolve(root, ctx)
  check(ok, "missing string-only dep does not fail install: " .. tostring(err))
  eq(#log.fetches, 0, "string-only missing dep does not fetch")
  eq(#log.installs, 0, "string-only missing dep does not install")
end

-- out-of-range local without github: also skip
do
  local root = {
    id = "root", version = "1.0.0",
    dependencySpecs = { { id = "lib", range = "^2.0" } },
  }
  local ctx, log = makeCtx({
    installed = { lib = { id = "lib", version = "1.0.0", dependencySpecs = {} } },
  })
  local ok, err = ModDepResolve.resolve(root, ctx)
  check(ok, "out-of-range string-only dep does not fail install: " .. tostring(err))
  eq(#log.fetches, 0, "out-of-range string-only dep does not fetch")
end

-- rate limit is distinct from "no releases"
do
  local root = {
    id = "root", version = "1.0.0",
    dependencySpecs = {
      { id = "lib", range = "^1.0", github = "Acme/lib" },
    },
  }
  local ctx = makeCtx({
    fetchErrByRepo = {
      ["Acme/lib"] = "GET https://api.github.com/repos/Acme/lib/releases failed: HTTP 403: API rate limit exceeded",
    },
  })
  local ok, err = ModDepResolve.resolve(root, ctx)
  check(not ok, "rate limit fails")
  check(tostring(err):find("rate limit", 1, true),
    "rate limit error is distinct: " .. tostring(err))
  check(not tostring(err):find("no tagged release", 1, true),
    "rate limit is not reported as no releases")
end

-- no satisfying tag
do
  local root = {
    id = "root", version = "1.0.0",
    dependencySpecs = {
      { id = "lib", range = "^2.0", github = "Acme/lib" },
    },
  }
  local ctx = makeCtx({
    releasesByRepo = { ["Acme/lib"] = { rel("1.9.0") } },
  })
  local ok, err = ModDepResolve.resolve(root, ctx)
  check(not ok and tostring(err):find("no tagged release", 1, true),
    "no satisfying tag fails: " .. tostring(err))
end

-- id mismatch on install
do
  local root = {
    id = "root", version = "1.0.0",
    dependencySpecs = {
      { id = "lib", range = "^1.0", github = "Acme/lib" },
    },
  }
  local ctx = makeCtx({
    releasesByRepo = { ["Acme/lib"] = { rel("1.0.0") } },
    installErrById = {
      lib = "zip is for 'other', expected 'lib'",
    },
  })
  local ok, err = ModDepResolve.resolve(root, ctx)
  check(not ok and tostring(err):find("failed to install", 1, true),
    "id mismatch / bad zip fails loud: " .. tostring(err))
end

-- cycle / visited: each id fetched at most once (A→B→A)
do
  local root = {
    id = "a", version = "1.0.0",
    dependencySpecs = {
      { id = "b", range = "^1.0", github = "Acme/b" },
    },
  }
  local ctx, log = makeCtx({
    installed = { a = root },
    releasesByRepo = {
      ["Acme/b"] = { rel("1.0.0") },
      ["Acme/a"] = { rel("9.9.9") },
    },
    depSpecsAfterInstall = {
      b = { { id = "a", range = "^1.0", github = "Acme/a" } },
    },
  })
  local ok, err = ModDepResolve.resolve(root, ctx)
  check(ok, "cycle resolve succeeds: " .. tostring(err))
  eq(#log.fetches, 1, "cycle fetches B once, not A again")
  eq(log.fetches[1].id, "b", "only B is fetched")
end

-- depth limit: root → d1 → d2 → d3 → d4 exceeds MAX_DEPTH 3
do
  local root = {
    id = "root", version = "1.0.0",
    dependencySpecs = {
      { id = "d1", range = "^1.0", github = "Acme/d1" },
    },
  }
  local ctx, log = makeCtx({
    releasesByRepo = {
      ["Acme/d1"] = { rel("1.0.0") },
      ["Acme/d2"] = { rel("1.0.0") },
      ["Acme/d3"] = { rel("1.0.0") },
      ["Acme/d4"] = { rel("1.0.0") },
    },
    depSpecsAfterInstall = {
      d1 = { { id = "d2", range = "^1.0", github = "Acme/d2" } },
      d2 = { { id = "d3", range = "^1.0", github = "Acme/d3" } },
      d3 = { { id = "d4", range = "^1.0", github = "Acme/d4" } },
      d4 = {},
    },
  })
  local ok, err = ModDepResolve.resolve(root, ctx)
  check(not ok and tostring(err):find("depth exceeded", 1, true),
    "depth > 3 fails: " .. tostring(err))
  check(#log.installs >= 3, "installs deps up to the depth limit")
end

-- empty hard deps: nothing to fetch
do
  local root = { id = "root", version = "1.0.0", dependencySpecs = {} }
  local ctx, log = makeCtx({})
  local ok = ModDepResolve.resolve(root, ctx)
  check(ok, "no hard deps succeeds")
  eq(#log.fetches, 0, "no hard deps means no fetches")
end

-- fetched ids are recorded for the install notice
do
  local root = {
    id = "root", version = "1.0.0",
    dependencySpecs = {
      { id = "lib", range = "^1.0", github = "Acme/lib" },
    },
  }
  local fetched = {}
  local ctx = makeCtx({
    releasesByRepo = { ["Acme/lib"] = { rel("1.2.0") } },
  })
  ctx.fetched = fetched
  local ok, err = ModDepResolve.resolve(root, ctx)
  check(ok, "fetched list resolve: " .. tostring(err))
  eq(#fetched, 1, "one fetched dep recorded")
  eq(fetched[1], "lib", "fetched dep id is lib")
end

do
  local LauncherMods = require("src.mods.LauncherMods")
  eq(LauncherMods.formatInstallNotice("Kanto-Reforged"),
    "Installed Kanto-Reforged", "notice without deps")
  eq(LauncherMods.formatInstallNotice("Kanto-Reforged", { "pokegear_cards" }),
    "Installed Kanto-Reforged (+ pokegear_cards)", "notice with one dep")
  eq(LauncherMods.formatInstallNotice("root", { "a", "b" }),
    "Installed root (+ a, b)", "notice with several deps")
end

print("mod_dep_resolve_tests: ok")
