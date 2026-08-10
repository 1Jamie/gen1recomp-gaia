# RFC 0006 — Selected title playthrough storage and checkpoint resume

## Status

Proposed. Engine: `SaveData.lua`, `Storage.lua`, `Checkpoint.lua`, and
`Loader.lua`. Tests: `title_playthrough_context.lua`, existing storage,
checkpoint, title, save-slot, and no-mod parity suites.

## Motivation

A tool checkpoint may be the first durable record of a new playthrough. The
engine intentionally keeps normal Pokémon SAVE independent: before the first
normal write, identity is retained by the engine-owned selected-slot mapping,
while title starts with a fresh New Game skeleton. Calling ordinary active
`mod.storage` there would allocate/adopt an identity, and live
`mod.checkpoints:restore` correctly refuses title because it has no gameplay
rollback state. A generic title capability is required; a tool must not use
private storage paths, slot ids, or a hidden normal SAVE.

## Additive public API

### `mod.storage:selected(game)`

Available only while the engine is in a title session. Returns an opaque bound
facade or `nil, code, message`:

```lua
local selected = mod.storage:selected(game)
local context = selected:context()
local history = selected:read("history/index")
```

The facade exposes `context()`, `read(key)`, `write(key, value)`,
`list(prefix)`, and `delete(key)`. It is bound internally to the launcher-
selected existing game-version/playthrough and the calling mod id. It neither
accepts an arbitrary playthrough id nor reveals a slot id, filesystem path, or
another mod namespace. Resolution is read-only; no selected mapping means
`no_selected_playthrough`, and opening a title browser never mints an identity.

### `mod.checkpoints:resume(game, checkpoint)`

Available only from title. It validates format, data-only structure, selected
game/playthrough identity, canonical save/content, overworld/battle runtime, and
RNG exactly as `restore` does. It then reconstructs semantic overworld or a
supported battle continuation, preserves current options, and differentially
recaptures before committing. On success it emits `checkpoint.restored` once.

Title has no live runtime rollback. A reconstruction or verification failure
therefore rebuilds a clean title session from the pre-operation title save and
RNG; it emits no success event and never writes normal progress. Validation
failure leaves the existing title session untouched. Stable errors include
`not_at_title`, `no_selected_playthrough`, normal checkpoint validation codes,
`resume_failed`, and `title_recovery_failed`.

## Isolation and migration

Explicit NEW GAME retains its existing fresh-identity rule. It does not reuse a
previous selected mapping and cannot see old tool history. Existing mods change
nothing: no identity, storage, title reconstruction, or event is created unless
the new methods are called. `mod.storage` remains independent durable data and
does not rewind with a checkpoint; canonical `game.save` / `mod.save` does.

## Verification

The public SDK test starts a fresh playthrough, stores tool history without a
normal SAVE, simulates title/restart, reads the selected binding without
allocating title identity, resumes an overworld checkpoint, preserves options,
performs no normal SAVE, differentially recaptures, and confirms a later
explicit NEW GAME receives another identity. Existing no-mod, storage,
checkpoint, battle, and title suites prove additive parity.
