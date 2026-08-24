# RFC 0015: Read-only imported dataset views

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

The concrete consumer is **Adaptive Trainers**, whose approved Phase G Kanto+
sidecar must derive nine Kanto-line continuations, Steel/type and move
definitions, and generated sprites from the player's existing verified Gold
cache while Red, Blue, or Yellow remains active. `mod.content` exposes only the
active R/B/Y dataset; `mod.imports` can read only separately declared raw mod
imports; and `mod.cache` is mod-private generated output. None can inspect the
launcher-owned Gold semantic dataset without a second ROM import and mod-side
ROM interpretation. The engine API remains generic and contains no Adaptive
Trainers policy.

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

`get` returns a bounded detached data-only copy or nil. `has` reports data-only
semantic presence.
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

An unknown version returns `nil, "unknown_version"`. A missing, partial, or
stale cache returns `nil, "not_imported"`. A required module that is malformed
or exceeds the limits (8 MiB per module, 48 MiB aggregate, depth 64, 500,000
values, 2 MiB per string, or 250,000 entries per table) returns
`nil, "invalid_cache"`; actionable detail is engine-logged but not exposed to
the mod. Generated Lua is decoded with the existing restricted
literal grammar and never executed. Functions, userdata, threads, metatables,
cycles, non-table roots, binary chunks, and trailing syntax cannot cross the
facade. Successful roots are decoded lazily and cached per selected version.
The API never exposes raw ROM bytes, generated source, host paths, or a mount.

## Migration and compatibility

Existing mods change nothing. `mod.datasets` is additive and requires no
permission. The service is allocated lazily on the first explicit
`mod.datasets:open` call. A boot with no mods, or with mods that do not call
it, performs no cross-version cache reads.

Opening a view does not change `GameVersion`, `CacheFs.prefix`, the active
`Data` table, PhysFS mounts, save state, or the selected game's behavior.
Red, Blue, Yellow, Gold, and Silver keep their existing active data paths.

The completion marker and per-version required-file rules live in the pure,
injected `CacheContract` shared by the importer and dataset service. It also
defines source-tree behavior. Neither consumer mutates `CacheFs.prefix` while
checking readiness. Every `open` revalidates the contract and required module
shapes; a stale/remove/reimport transition evicts the previous semantic view.

## Verification

- `tests/modkit/cases/dataset_views.lua` loads sandboxed fixture mods through
  the public API and covers Red, Blue, Yellow, Gold, and Silver independently.
- The test proves semantic registry normalization, deterministic iteration,
  detached records, read-only facades, cross-mod facade isolation,
  version-prefixed generated assets,
  traversal rejection, stable failure reasons, and stale-marker rejection.
- It also proves missing/empty/partial/stale/remove/reimport behavior, hostile
  generated-source rejection, canonical Gen 1/Yellow/Gold hydration, and the
  approved Kanto+ Gold records and assets.
- `tests/modkit/cases/dataset_views_nontermination.lua` proves generated code
  is rejected rather than executed; `tests/engine/generated_data_decoder_test.lua`
  proves every decoder resource bound.
- `tests/engine/dataset_views_no_mod_parity.lua` is the separate guarded no-mod
  parity suite and proves the service stays unallocated with zero cache reads.

## Deprecation etiquette

Nothing is removed, renamed, superseded, or deprecated.
