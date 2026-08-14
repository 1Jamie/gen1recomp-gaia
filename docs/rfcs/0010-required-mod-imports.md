# RFC 0010 — Manifest-declared user imports for mods

## Status

Proposed. Engine: `Manifest.lua`, `RequiredImports.lua`, `Loader.lua`,
`LauncherMods.lua`. Launcher: `RomImporter.lua`, `LauncherView.lua`. Native
picker bridges: Android and iOS.

## Motivation

Some mods derive presentation data from another cartridge the player owns.
Shipping those bytes in a mod is not acceptable, while asking each mod to
escape the sandbox, implement native pickers, and maintain platform-specific
paths defeats the sandbox's purpose. Pokemon Stadium and Pokemon Stadium 2 are
the first concrete consumers, but the ownership/import problem is generic.

## The decision it extends

This extends the manifest as the engine-owned declaration of mod dependencies
and preserves the sandbox rule in `src/mods/Sandbox.lua`: mods do not receive
raw host filesystem access. It also extends the launcher's established ROM,
save, and mod archive picker/inbox flows instead of introducing a second host
integration.

## Exact manifest delta

Additive `required_imports` and `optional_imports` arrays are accepted:

```json
{
  "required_imports": [{
    "id": "stadium2",
    "name": "Pokemon Stadium 2 ROM",
    "file": "stadium2.z64",
    "format": "n64",
    "md5": ["00000000000000000000000000000000"]
  }]
}
```

Both arrays use the same object schema. A missing `required_imports` entry
blocks the mod; a missing `optional_imports` entry only leaves that bonus
functionality unavailable.

- `id` is unique within the manifest and uses the mod-id vocabulary.
- `name` is launcher-facing text.
- `file` is one safe filename below the mod's `baseroms/` directory.
- `md5` is one 32-digit hexadecimal digest or a non-empty array of accepted
  digests. MD5 is a known-dump identity convention, not a trust primitive.
- `format` is `raw` by default. `n64` recognizes a canonical big-endian dump,
  pair-byte-swapped and little-endian-word dumps, with or without a recognized
  512-byte copier header. Validation and stored output use canonical big-endian
  bytes.

The launcher copies a validated file to
`mods/<manifest.id>/baseroms/<file>`. Missing required imports make the launcher
row need attention and make the loader refuse that enabled mod before its entry
chunk runs. Missing optional imports remain selectable without changing load
status. A matching validated import owned by another installed mod is
copied automatically. Replace and remove remain explicit per-mod actions.

Desktop and UWP use their existing native/host picker routes. Android and iOS
add a `required_import` picker kind which stages
`picked_required_import.bin`. NX scans the engine-owned
`imports/baseroms/` MTP inbox. All writes continue through `CacheFs`, preserving
portable-mode placement.

`modkit validate` and `modkit pack` report MK307 for every file beneath a
source mod's `baseroms/` directory, so the packaging path cannot accidentally
distribute a file the launcher placed there. The installer also rejects a mod
archive containing `baseroms/` files, covering packages built without modkit.

## Mod-facing API and sandbox statement

There is no new runtime API and no new permission. A mod reads its own copied
file through the existing `mod:read("baseroms/<file>")` capability. It never
learns the selected host path, cannot browse another mod's tree, and receives
no raw `io`, `love.filesystem`, or platform-picker access.

## Migration and compatibility

Existing manifests omit both import arrays and behave exactly as before. The
fields are additive for both manifest API levels. Mods currently maintaining
their own cross-platform picker can declare the source file and remove that
host integration; their processing code changes only to read the declared
`baseroms/<file>` path.

## Parity tests

- Empty/absent `required_imports` leaves existing manifests and loader behavior
  unchanged.
- Manifest validation refuses path traversal, duplicate ids/files, malformed
  MD5 values, and unknown normalization formats.
- N64 byte orders and the recognized copier-header form produce identical
  canonical bytes before MD5 validation.
- A mismatched selection is never written.
- An enabled mod with a missing declared file never executes its entry chunk.
- A matching import in another installed mod is copied into the requesting
  mod's own `baseroms/` directory.
- The packaging gate refuses every `baseroms/` file.
- The launcher refuses an archive that contains `baseroms/` files.

## Deprecation etiquette

Nothing deprecated or removed.
