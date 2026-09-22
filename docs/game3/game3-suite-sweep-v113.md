# Game3 suite sweep — after v113 cache import + naming-test fix

> **Provenance note (pret mandate, added 2026-09-22):** verdicts here are
> observed suite-run outcomes. Mechanic-level statements are limited to
> engine-internal reasoning (the `Collision()` lazy-loader call-site bug) and to
> assertions the suites themselves encode. Those assertions' pret semantics are
> **UNVERIFIED** here because no `../pokefirered` checkout exists on this
> machine (12 suites skip for exactly that reason). Where a pret file would
> confirm a semantic claim, it is named inline.

Follow-up to `game3-suite-sweep-v3.md` (kept frozen as the "before" snapshot).
Captured: 2026-09-22 10:26 IST by QA and Test Engineer (team G1R_Deluxe_Gen3).

Two changes happened between the two sweeps:

1. **Stale naming test call sites fixed** (root cause B; assigned, tests-only):
   - `tests/game3_stitchuif_naming_pc_test.lua:44`
   - `tests/game3_stitchbattle_catch_headless_test.lua:97`
   - `Naming.update(input, 1 / 60)` → `Naming.handleInput(input)` + `Naming.update(1 / 60)`,
     matching `runtime.lua:279-281` and `battle/init.lua:2702-2703`. No `src/` edits.
2. **Fresh FireRed cache re-imported at the version the engine expects.**
   Source ROM was available on this machine:
   `/Users/shanemcgovern/Downloads/1636 - Pokemon Fire Red (U)(Squirrels).gba`
   (SHA-1 `41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc` = FireRed 1.0, the SHA the
   repo manifest pins). Import ran into a **fresh LOVE identity** so the user's
   existing caches were not touched:

   ```sh
   cd /Users/shanemcgovern/dev/gen1recomp
   POKEPORT_IDENTITY=qa-firered-v113 POKEPORT_VERSION=firered POKEPORT_IMPORT_ONLY=1 \
     POKEPORT_IMPORT_ROM="/Users/shanemcgovern/Downloads/1636 - Pokemon Fire Red (U)(Squirrels).gba" \
     love .
   ```

   Result: `~/Library/Application Support/LOVE/qa-firered-v113/firered/data/generated/gba/meta.json`
   → `"cache_version":113, "native_version":6, "version_id":"firered_1_0"` (113 MB).
   The test helper `tests/game3_cache.lua` scans every LOVE identity, so this
   cache is now **auto-discovered without any env var** (verified: a plain
   `luajit tests/game3_field_items_test.lua` prints `[info] FireRed cache at
   .../qa-firered-v113/...`).

## Totals before → after

| Verdict | Before (v3) | After | Δ |
| --- | --- | --- | --- |
| PASS | 145 | **220** | +75 |
| PARTIAL | 63 | **20** | −43 |
| SKIP | 45 | **7** | −38 |
| FAIL | 19 | **25** | +6 |
| n/a (helper) | 1 | 1 | 0 |

Why FAIL went **up**: 11 suites that previously self-skipped now actually run
and expose real failures (10 of them are the same `objects.lua` crash, see
below). Coverage first, then failures.

## Flips

- **FAIL → PASS (5):**
  - `game3_battle_move_effects_test.lua` — the Knock Off check passes with a
    current cache. **The earlier Knock Off finding was stale cache data, not a
    source bug.**
  - `game3_battle_safari_test.lua` — 3 checks pass with cache.
  - `game3_marowak_progression_test.lua` — cache-version error gone.
  - `game3_stitchbattle_catch_headless_test.lua`, `game3_stitchuif_naming_pc_test.lua`
    — naming test fix (change 1).
- **PARTIAL → PASS (39):** battle_terrain, collision_behaviors,
  collision_interactions, daycare ×4, directional_impassable, doors_table,
  encounters_cave, field_cut, field_cycling_road, field_fly,
  field_forced_movement, field_safari, import2_* ×5, import_assets,
  import_battle_terrain, import_cache_version, import_multichoice,
  import_pokedex_assets, link_battle, link_trade, link_union,
  multichoice_grid, pokedex_area_chrome, runtime_adapters,
  stitchcoll_dynamic_warp, stitchcoll_fall_shake, stitchfield_movement,
  stitchimp_code_roots, storage, tower_state, trade_rules, warp_behaviors.
- **SKIP → PASS (31):** credits_hall_of_fame, evolution_methods,
  evolution_scene, fame_screen, field_boulder, field_items, growth_evolution,
  growth, moveteach ×5, pallet_sign_lady, pokedex_area, seafoam_puzzle,
  stitchbattle_safari_exit, stitchcoll_fall_draw, stitchfield_onframe,
  stitchfield_whiteout, stitchmap_bike, stitchmap_escape_rope,
  stitchmap_header, stitchmap_heal, stitchmap_items, stitchsave_flash_continue,
  stitchseam_mod_collision, stitchuid_footprint, stitchuid_summary_dexno,
  teachy_screen, ui_party_fieldmove.
- **Newly exposed FAIL (11 — were SKIP/PARTIAL, now real failures):**
  - 10 × `objects.lua` cluster A: `map_onload`, `mapscripts`,
    `vermilion_trash_cans`, `oaks_lab_save_reload`, `static_encounter`,
    `stitchcoll_escape_warp`, `stitchcoll_ghost_ctx` (:162) and
    `stitchcoll_move_kinds`, `stitchcoll_run_speed`, `stitchfield_ground` (:559).
  - `game3_special_trade_test.lua` — 2 checks: `the compatibility line reached
    the message box` and `the field message box is open` (new logic data point).
    Mechanic semantics **UNVERIFIED** against pret; `pokefirered/src/trade.c`
    (compatibility-message path) would confirm.
- No PASS → FAIL regressions.

## Updated failing suites (25), by subsystem

### field (20) — all one root cause

`src/core/game3/objects.lua:63` defines the lazy loader `local function Collision()`;
lines **162** and **559** index it (`Collision.elevationAt(...)`) instead of
calling it (`Collision()`, as at lines 916/924). Every one of these 20 suites
dies with `attempt to index upvalue 'Collision' (a function value)`:

- `objects.lua:162` (16): cerulean_block_exits, cerulean_policeman_bill,
  collision_npc_dir, emote_movement, item_use_and_parcel, map_onload,
  mapscripts, npc_player_collision, objects_perm_reset, runtime_camera_object,
  static_encounter, stitchcoll_escape_warp, stitchcoll_ghost_ctx,
  vermilion_trash_cans, viridian_gym_door, oaks_lab_save_reload.
- `objects.lua:559` (4): trainer_sight, stitchcoll_move_kinds,
  stitchcoll_run_speed, stitchfield_ground.

**One fix clears 20 of the 25 current failures.**

### battle (2)

- `game3_battle_ai_test.lua` — `[FAIL] pack loaded` +13; still no extracted AI
  pack even with the v113 cache; suite has no self-skip (`14 FAILED`).
- `game3_special_trade_test.lua` — `the compatibility line reached the message
  box (nil == ...)`, `the field message box is open` (`FAILED 2`).

### link (1)

- `game3_link_session_test.lua` — `saving reports TRUE, which lets the link
  continue (0 == 1)`.

### save (1)

- `game3_save_trainer_card_test.lua` — `Selecting YES in overwrite should
  transition to saved` (test line :109).

### script (1)

- `game3_special_events_test.lua` — 4 checks: distinct id per special name,
  cracked ice not written impassable, ForcePlayerOntoBike, ForcePlayerToStartSurfing.

## Remaining PARTIAL (20) / SKIP (7)

All are missing external artifacts, not cache-version problems anymore:

- **pret checkout `../pokefirered` absent (12):** battle_anims_pret_parity,
  corner_prize, corner_screen, corner_slots (SKIP), import2_mt_ember_collision,
  revision_view, special_ids (SKIP), stitchimp_alt_layouts, stitchimp_braille_text,
  stitchimp_chrome_keys, stitchimp_condominiums, stitchimp_heal_locations.
- **ROM-file paths the suites hard-code (5):** help_rom (SKIP),
  map_preview_extract, tm_case_berry_pouch_extract, town_map,
  object_interactions_rom (SKIP).
- **anim/audio packs unset (5):** anim_port_g1 (POKEPORT_ANIM_PACK),
  anim_port_g2, anim_port_g4 (G4_ANIM_PACK), battle_anim_palette,
  se_length (SKIP).
- **other named caches/builds (5):** battle_music (`firered-sep20`),
  void_fill (`firered-sep20`), object_interactions_cache (SKIP, cache root arg),
  region_map_assets (still reports none-at-v113 — it looks for its own asset
  cache, worth a look), quest_log_rom (SKIP, ROM arg).

## Reproduce

Baseline command from `game3-suite-sweep-v3.md` §Method. The v113 numbers in
this document were produced with `POKEPORT_GBA_CACHE` pointed at the new cache,
and the auto-discovery check confirms the same results without the env var.

## Notes

- User's pre-existing caches (`pokemon-love2d` v112, `deoxys-visual` v112,
  etc.) are untouched; the v113 cache lives under the new `qa-firered-v113`
  identity. If the team wants the main identity upgraded, that is a separate,
  user-visible action (launcher import) — not done here.
- `game3-suite-sweep-v3.md` remains the frozen pre-fix baseline; this file is
  the current state.

## Checkpoint (2026-09-22 10:35 IST) — after objects.lua landed

Triggered by task `01a0c873-d48d-7ea0-b8ff-650991ac0e9b` once the objects.lua
fix completed (`src/core/game3/objects.lua` unmodified vs HEAD `1b8b9b48` at
checkpoint time; the branch version already carried the `Coll=Collision()`
call pattern).

### Full gate: `./scripts/test.sh` → exit 0, ALL TIERS PASSED

- 18 tier lines, every one **PASS**, including the two that failed pre-fix:
  - **T1/T2 engine invariants + parity gates: PASS** — 624 suite `ok` lines,
    0 FAIL. `tests/engine/mew_dock_private_artifact_gate.lua` now passes: the
    checkout has `.git` again (HEAD `1b8b9b48`), so the privacy gate sees a
    real publication set.
- T0 luacheck + 13 other T0 gates: PASS.
- T2 Gen 2/Crystal: PASS. T4 mod-SDK: PASS. T4 title cold-restart: PASS.
- T3 content + save editor + link loopback: still skipped (no
  `data/generated/`, no `RED_CACHE`); T5 shots not requested.
- Caveat: `scripts/test.sh` is **unmodified** vs HEAD (mtime Sep 21 23:34),
  so the top-level `tests/game3_*.lua` suites are still outside the gate.
  The Test Suite Builder phase-2 tier has not landed yet.

### 273-suite re-sweep: 248 PASS / 16 PARTIAL / 5 SKIP / 3 FAIL (+1 helper)

Identical to the 10:32 default re-sweep (`diff` of the two result files:
no differences).

| Verdict | v113 sweep | Checkpoint | Δ |
| --- | --- | --- | --- |
| PASS | 220 | **248** | +28 |
| PARTIAL | 20 | **16** | −4 |
| SKIP | 7 | **5** | −2 |
| FAIL | 25 | **3** | −22 |
| n/a (helper) | 1 | 1 | 0 |

Flips, all one direction (zero regressions):

- **FAIL → PASS (22):** the 20-suite `objects.lua` lazy-`Collision` cluster
  (16 × `:162`, 4 × `:559`) + `battle_ai` + `special_events`.
- **PARTIAL → PASS (4):** `battle_anims_pret_parity`, `corner_prize`,
  `corner_screen`, `import2_mt_ember_collision` (pret clone now present).
- **SKIP → PASS (2):** `corner_slots`, `special_ids` (same).

### Remaining FAIL (3) — no artifact blockers

| Suite | Evidence | Owner state |
| --- | --- | --- |
| `game3_link_session_test.lua` | `[FAIL] saving reports TRUE, which lets the link continue (0 == 1)` | Test Suite Builder phase-1 stub not landed (file unmodified vs HEAD). |
| `game3_save_trainer_card_test.lua` | `Selecting YES in overwrite should transition to saved` (`:109`) | Same — Test Suite Builder phase-1 stub not landed. |
| `game3_special_trade_test.lua` | `the compatibility line reached the message box` (`FAILED 2`) | Finisher D-list; QA marked semantics UNVERIFIED (would need `pokefirered/src/trade.c`). |

### State caveats at checkpoint time

- Working tree had **39 modified files vs HEAD** from concurrent lanes
  (Finisher/Refactor/Test Suite Builder in flight); results above are for that
  mixed tree, not HEAD.
- All runs are single-sample; the artifact-conversion task separately showed
  the 21 convertibles stable across two runs each.

