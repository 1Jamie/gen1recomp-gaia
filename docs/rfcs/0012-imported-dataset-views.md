# RFC 0012: Read-only imported dataset views

## Status

Proposed.

## Motivation

A cross-version content mod can read only the active merged dataset through
`mod.content`. Even when the player has already imported another supported
game, a mod cannot inspect that version's semantic species, moves, items, type
chart, or generated asset namespace. The available alternatives are private:
mutating `CacheFs.prefix`, mounting another cache over the active one, loading
generated Lua directly, or asking for a second raw-ROM import. They compose
poorly with the active game, expose unstable import layout, and make safe
read-only use impossible from the sandbox.

The immediate example is an optional content pack derived from an already
verified Gold import while Red, Blue, or Yellow remains active. The capability
is generic and useful to randomizers, compatibility inspectors, dex tools, and
other cross-version content mods.

## Decision and plan extended

This implements **D-AT-004: optional Kanto+ content consumes an
active-independent semantic dataset view**. The consuming design is tracked in
the Adaptive Trainers implementation plan,
[`docs/superpowers/plans/2026-08-14-adaptive-trainers.md`](https://github.com/MaxTomahawk/gen1recomp-adaptive-trainers/blob/main/docs/superpowers/plans/2026-08-14-adaptive-trainers.md),
Task 8. The delta is a generic, additive public API and contains no trainer
pools, scaling, boss identities, version-mixing rules, or Adaptive Trainers
policy.

## Exact API delta

Every sandboxed mod receives:

```lua
local view, reason = mod.datasets:open("gold")
```

A known version with the current completed import marker returns a read-only view:

```lua
view = {
  version = "gold",
  generation = 2,
  content = {
    pokemon = {
      get = function(self, id) end,
      has = function(self, id) end,
      each = function(self) end,
    },
    -- every public registry name and alias
  },
  assets = {
    path = function(self, generatedPath) end,
    info = function(self, generatedPath) end,
  },
}
```

`get` returns a detached copy or nil. `has` reports semantic presence.
`each` returns ids in lexical order and detached values. The registries use
the selected version's generation routing and the engine's existing
`Schemas`, `Registry`, and `Builtins` normalization, so structured sources
such as type matchups retain the same public ids used by the active
`mod.content` facade. No register, patch, override, or remove verb is exposed. Each call returns an
independent facade over the cached internal dataset, so facade mutation cannot cross
mod boundaries.

`assets:path` returns the selected cache-prefixed virtual path.
`assets:info` returns sanitized `type` and optional `size` metadata. Both
accept only relative paths below `assets/generated/`, reject control
characters, absolute paths, backslashes, and traversal, and expose no byte
reader.

An unknown version returns `nil, "unknown_version"`. A missing or stale
completion marker returns `nil, "not_imported"`. Generated tables are parsed
under an empty environment and cached per version; the API never exposes raw
ROM bytes, generated source, host paths, or a cache mount.

## Migration and compatibility

Existing mods change nothing. `mod.datasets` is additive and requires no
permission. The service is allocated lazily on the first explicit
`mod.datasets:open` call. A boot with no mods, or with mods that do not call
it, performs no cross-version cache reads.

Opening a view does not change `GameVersion`, `CacheFs.prefix`, the active
`Data` table, PhysFS mounts, save state, or the selected game's behavior.
Red, Blue, Yellow, Gold, and Silver keep their existing active data paths.

The completion-marker format moves to the pure `CacheFormat` helper shared by
the importer and dataset service. The literal marker and import readiness
behavior are unchanged.

## Verification

- `tests/modkit/cases/dataset_views.lua` loads a sandboxed fixture mod through
  the public API and covers Red, Blue, Yellow, and Gold independently.
- The test proves semantic registry normalization, deterministic iteration,
  detached records, read-only facades, cross-mod facade isolation,
  version-prefixed generated assets,
  traversal rejection, stable failure reasons, and stale-marker rejection.
- The same test proves that cross-version reads do not change the active data,
  active game, or cache prefix, and that a no-mod boot performs zero
  cross-version cache reads.
- The existing importer and engine/modkit suites prove unchanged marker
  readiness and no-mod behavior.

## Deprecation etiquette

Nothing is removed, renamed, superseded, or deprecated.
