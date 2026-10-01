# Save conversion

Cartridge `.sav` files go in and out of the launcher through `src/save_convert/`. One codec per generation:
`GenSave` (Red/Blue/Yellow), `Gen2Save` (Gold/Silver/Crystal), `Gen3Save` (FireRed/LeafGreen/Emerald).
`SaveConvert.importSav` / `exportSav` are the only entry points; both return `nil, message` instead of raising.

## Supported

- Gen 1: 32768 bytes, English. Gen 2: 32768 bytes plus an optional RTC footer, English. Gen 3: 128 KB flash plus an optional footer.
- Not converted: Japanese and Korean carts, Ruby/Sapphire. Detected ones are refused with a named reason.
- Gen 1 and Gen 2 need the selected game's imported ROM cache; missing data refuses conversion with a named reason.

## Round trips

- `export(import(cart), cart)` reproduces the cart except for a short list of normalizations (box checksums, party level byte, Gen 3 slot rotation and counter).
- Every region is tiered in `src/save_convert/regions/gen<N>.lua`: T1 modeled, T2 carried verbatim from the cart image, T3 derived.
- The cart image rides inside the slot (`rawImport` for Gen 1/2, `modData.cartImage` for Gen 3), so export needs no second file.
  A `.cart` sidecar from an older build is read once at export, folded into the slot and deleted.
- Import returns an optional note (backup copy used, stale active box, older Gen 3 slot) that the launcher shows beside the result.
- Gen 2 preserves the current map's object visibility and rebuilds visible NPCs when exporting onto a new map. Fresh and moved exports need the current ROM cache's sprite metadata; re-import the ROM when an older cache is refused.
- Successful exports return named reader warnings to the launcher and CLI. Damaged embedded Gen 3 images refuse export unless a valid matching template can recover them.
- Gen 3 `modData.cartImage` is `PKCI1:<length>:<base64 of LZ>` (`gen3_port/imagepack.lua`, about 5 KB for a typical slot instead of 190 KB); a raw image from an older build is still read.
- Gen 3 regions with no engine state are carried and proven so in `regions/gen3.lua` (`proof` per row, checked by `tests/save_compat/gen3_carry_contract_test.lua`).
  The FireRed quest log is carried and reset with the map window: the engine's own quest log is a sampled replay, the cart's is an input script.
- Emerald and FireRed engine sections (TV, Frontier, Trainer Hill, Mauville, Lilycove, Apprentices, Hall records, VS Seeker, Trainer Tower, minigame records, Mystery Gift news/card/metadata) live in `gen3_port/sections/`.
  The Wonder Card gift payload is script bytecode and stays template-carried; a different engine card clears the cart card instead of writing a card the game would reject.

## Reader validator

`Compat.check(bytes, version)` mirrors the detectors of PKHeX, PKForge and OpenHome and the game's own checks.
Errors block the export (`Compat.gate`), warnings are returned and never block.
The tested PKHeX Gold/Silver writer overlaps the last 45 Hall of Fame bytes with a backup copy; exports warn when existing Hall of Fame data would change.
Rules are listed in `Compat.RULES`; `tests/save_compat/compat_validator_test.lua` crafts a bad image for each one.

## Tests and tools

- `luajit tests/run_save_compat.lua`: fixtures, R1/R2 round trips, fuzz, validator. `SAVE_COMPAT_FUZZ_N` and `SAVE_COMPAT_FUZZ_SEED` widen the fuzz runs.
- `SAVE_COMPAT_REAL_SAVES="red=/path/a.sav;crystal=/path/b.sav"` runs the validator over your own carts.
- `scripts/save-compat.sh` dumps every fixture export and runs the PKHeX probe (dotnet) and the OpenHome probe (node), then diffs against `tests/fixtures/save/expected/`.
  `--bless` rewrites the expected files; a missing toolchain skips that probe. Needs `PKHEX_ROOT` and `OPENHOME_ROOT` checkouts.
- `tools/save_convert/convert.lua` is the CLI. Set `<GAME>_CACHE` (for example `YELLOW_CACHE` or `EMERALD_CACHE`) to that game's imported cache directory.
