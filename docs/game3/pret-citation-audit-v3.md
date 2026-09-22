# Pret citation + expectation audit across game3 test suites

Audited: 2026-09-22 by QA and Test Engineer (team G1R_Deluxe_Gen3).
Canonical source: `/Users/shanemcgovern/dev/pokefirered` @ `c75f35230` (local clone).
Authority rule: pret is the only authority for FireRed semantics (C1 lesson);
old comments/reports are never authority.

## Scope

- **862 line-level citations** (`pokefirered/<file>:<line>`) across **150 test files** in `tests/game3_*.lua` + `tests/engine/game3_*.lua`.
- 185 distinct pret file references (line-less) — all exist in the clone except
  `pokefirered.gba` (build artifact; the 3 suites citing it self-skip without it).
- **Exclusions honored:** `tests/game3_save_trainer_card_test.lua` and
  `tests/game3_link_session_test.lua` (Test Suite Builder owns — checked only,
  2 citation rows, both match), `tests/game3_anim_port_g3_test.lua` (check-only,
  5 rows, all verified below, no edits).
- Mechanic expectations were re-verified where they pin values (constants, ids, counts).

## Method

1. Machine pass: each citation's pret line ±2 compared against strong tokens from
   the citing test line (and neighbours): hex constants, snake_case and CamelCase
   symbols → MATCH / DRIFT / VALUE-MISMATCH / UNVERIFIED; citations with no symbol
   → ANCHOR (file+line must exist, be in bounds and substantive).
2. Human pass over every non-MATCH row (67 rows) against pret content; plus a
   20-row random sample of anchors and a 15-row random sample of MATCHes.
3. Fixes in QA's lane: stale test comments/values corrected with pret citations,
   each affected suite re-run twice to green.

## Verdict totals (862 citations)

| Verdict | Rows | Meaning |
| --- | --- | --- |
| MATCHES (unchanged) | 851 | pret line/semantics agree with the test — 339 symbol-confirmed, 455 anchors (file+line in bounds, 20 sampled against pret), 25 range/section refs content-checked, 12 symbol-less rows resolved, 20 function-internal line refs |
| STALE EXPECTATION (fixed) | 11 | test comment/value disagreed with pret — corrected in 8 suites, each green twice |
| CONTRADICTED | 0 | no test pins engine behavior pret contradicts |

## The 11 stale citations fixed (suite | before | after | action)

| # | Suite | Citation before | Corrected to | Why |
| --- | --- | --- | --- | --- |
| 1 | `tests/game3_fame_screen_test.lua:139` | `pokefirered/src/fame_checker.c:1344 sDaisySpriteTemplate` | `pokefirered/src/fame_checker.c:1347 sDaisySpriteTemplate` | line drift: template use is at 1347 (`CreateSprite(&sDaisySpriteTemplate, ...)`); 1344 is `u8 spriteId;` |
| 2 | `tests/game3_link_battle_test.lua:189` | `pokefirered/src/cable_club.c:222 CreateLinkupTask waits for the other machine` | `pokefirered/src/cable_club.c:208-222 Task_LinkupAwaitConnection waits for the other machine` | named the wrong function: :222 is inside `Task_LinkupAwaitConnection` (def :208); `CreateLinkupTask` is :76 |
| 3 | `tests/game3_stitchcoll_fall_draw_test.lua:85` | `pokefirered/src/field_effect.c:1204 Task_FallWarpFieldEffect` | `pokefirered/src/field_effect.c:1166 Task_FallWarpFieldEffect` | :1204 is inside `FallWarpEffect_3` (:1200); the named task is defined at :1166 |
| 4 | `tests/game3_stitchsave_summary_test.lua:35` | `pokefirered/src/pokemon.c:5618 GetMonData(..., MON_DATA_POKERUS) & 0xF` | `pokefirered/src/pokemon.c:5630 GetMonData(..., MON_DATA_POKERUS) & 0xF` | :5618 is the function head (`CheckPartyPokerus`); the cited statement is at :5630 (also :5638) |
| 5 | `tests/game3_teachy_screen_test.lua:218` | `pokefirered/src/teachy_tv.c:118 sBgTemplates[1] priority 0` | `pokefirered/src/teachy_tv.c:122 sBgTemplates[1].priority = 0` | :118 is `.charBaseIndex = 0` (same struct, wrong member); `.priority = 0` is :122 |
| 6 | `tests/game3_teachy_screen_test.lua:301` | `pokefirered/include/constants/items.h:135 ITEM_ORAN_BERRY + Bag.add(id 133)` | `pokefirered/include/constants/items.h:143 ITEM_ORAN_BERRY (139) + Bag.add(id 139)` | STALE VALUE: pret items.h:143 `ITEM_ORAN_BERRY 139` (engine items_data frlg = 139); :135 is `ITEM_FAB_MAIL 131` and id 133 is `ITEM_CHERI_BERRY` (items.h:137) |
| 7 | `tests/game3_teachy_screen_test.lua:434` | `pokefirered/src/item_menu.c:2385 exitCB = Pokedude_InitTMCase` | `pokefirered/src/item_menu.c:2391 exitCB = Pokedude_InitTMCase` | :2385 is `HideBagWindow(6);`; the assignment is :2391 |
| 8 | `tests/game3_teachy_screen_test.lua:445` | `pokefirered/src/tm_case.c:1419 gPokedudeText_TMTypes` | `pokefirered/src/tm_case.c:1422 gPokedudeText_TMTypes` | :1419 is `break;`; the symbol use is :1422 |
| 9 | `tests/game3_teachy_model_test.lua:112` | `pokefirered/src/teachy_tv.c:553 the TM CASE gate` | `pokefirered/src/teachy_tv.c:554 the TM CASE gate` | off-by-one: :553 wires `moveCursorFunc`; the gate is `if (!CheckBagHasItem(ITEM_TM_CASE, 1))` at :554 |
| 10 | `tests/game3_static_encounter_test.lua:224` | `pokefirered/src/script.c:246 goto_if cond 5 = NE` | `pokefirered/src/scrcmd.c:153 ScrCmd_goto_if, sScriptConditionTable scrcmd.c:65 row 5 = !=` | STALE FILE: `src/script.c` has no `goto_if` (moved to `src/scrcmd.c:153`); condition row 5 = `!=` (NE) confirmed at scrcmd.c:65-74 |
| 11 | `tests/game3_trade_rules_test.lua:312` | `pokefirered/src/trade.c:2789` | `pokefirered/src/trade.c:2787-2788 SPECIES_EGG -> CANT_TRADE_PARTNER_EGG_YET` | :2789 is blank; the return the test asserts is :2787-2788 |

Verification: all 8 affected suites ran **twice**, exit 0 both runs:
`fame_screen`, `link_battle`, `stitchcoll_fall_draw`, `stitchsave_summary`,
`teachy_screen` (4 edits incl. the value change 133 → 139), `teachy_model`,
`static_encounter`, `trade_rules`.

## The 4 flagged citations — re-verified

| Citation | pret content | Verdict |
| --- | --- | --- |
| `include/constants/vars.h:105` | `#define VAR_PC_BOX_TO_SEND_MON 0x4037` | MATCHES — tests use `0x4037` |
| `include/constants/flags.h:1401` | `#define FLAG_SHOWN_BOX_WAS_FULL_MESSAGE (SYS_FLAGS + 0x43)` with `SYS_FLAGS (TRAINER_FLAGS_END + 1) // 0x800` (flags.h:1324) | MATCHES — tests use `0x843` |
| `src/field_specials.c:1985` | `bool8 ShouldShowBoxWasFullMessage(void)` — returns FALSE when the flag is set, sets the flag when it shows | MATCHES — the "shown once" latch |
| `data/battle_scripts_2.s:87` | `trygivecaughtmonnick BattleScript_CaughtPokemonSkipNickname` | MATCHES |

## Additional expectation checks (values pinned by tests)

- **Specials ids match pret exactly.** With the `def_special` macro line excluded from numbering: `specials.inc:230 = 0xDB` (ChooseMonForMoveRelearner), `:233 = 0xDE` (BufferMoveDeleterNicknameAndMove), `:234 = 0xDF` (GetNumMovesSelectedMonHas), `:408 = 0x18D` (ChooseMonForMoveTutor), `:430 = 0x1A3`, `:431 = 0x1A4` — equal to both the tests' pinned ids and `stdscripts.lua`'s engine ids. No drift.
- `specials.inc:207 = 0xC4 ShowBattleRecords` matches `stdscripts.lua:127`.
- `global.h:238` = `LINK_B_RECORDS_COUNT 5` grounds the test's five-opponent rows.
- `trainer_tower.c:772` clamps `>= NUM_TOWER_CHALLENGE_TYPES` to `0`, and `CHALLENGE_TYPE_SINGLE = 0` (trainer_tower.h:5) — the test's "clamps to SINGLE" MATCHES.
- `species.h:142` = `SPECIES_OMANYTE 138` matches the test's pinned `138`.
- `items.h:300` = `ITEM_TM01 289` matches the test's `289`.
- `fieldmap.h:8` = `NUM_METATILES_IN_PRIMARY 640`; `global.fieldmap.h:80` = `struct Tileset`; `:191` = `struct MapHeader` — all match.
- `scrcmd.c:65` `sScriptConditionTable[6][3]` row 5 = `1, 0, 1 // !=` — grounds "goto_if cond 5 = NE" (citation fixed to `scrcmd.c:153`).

## Findings for lead (no src edits made)

1. **No CONTRADICTED expectations found** — every value the QA-lane tests pin has a pret counterpart with the same value, including the specials-id table that looked off by one until the `def_special` macro line was excluded from numbering.
2. The one stale *value* (teachy_screen item id 133 vs pret 139) was a test error, not an engine error: engine `items_data.lua:105` already has `frlg = 139`.
3. Stale citations were concentrated in comments that named a symbol while pointing at a nearby-but-different line (function head vs statement, struct member vs another member) — 10 comment fixes + the 1 value fix.

## Check-only exclusions (no edits)

| Suite | Citations | Verdict |
| --- | --- | --- |
| `tests/game3_anim_port_g3_test.lua` | 5 (`trig.c:514`, `battle_anim_ghost.c:308/:396/:458`, `battle_anim_mons.c:105`) | all MATCH — lines are exactly `s16 Sin(s16 index, s16 amplitude)`, `AnimConfuseRayBallSpiral`, `AnimShadowBall`, `AnimLick`, `GetBattlerSpriteCoord` |
| `tests/game3_link_session_test.lua` | 2 | MATCH (Test Suite Builder owns file) |
| `tests/game3_save_trainer_card_test.lua` | 0 pret citations | n/a |

## Per-suite rollup (citations per suite)

| Suite | Citations | Symbol-match | Anchor | Edited |
| --- | --- | --- | --- | --- |
| `tests/engine/game3_egg_moves.lua` | 4 | 4 | 0 | 0 |
| `tests/engine/game3_knock_off_item_test.lua` | 1 | 0 | 1 | 0 |
| `tests/engine/game3_versions_game_test.lua` | 1 | 1 | 0 | 0 |
| `tests/game3_anim_port_g3_test.lua` | 5 | 0 | 5 | 0 |
| `tests/game3_battle_ai_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_battle_anim_palette_test.lua` | 6 | 0 | 6 | 0 |
| `tests/game3_battle_anims_coverage_test.lua` | 3 | 0 | 3 | 0 |
| `tests/game3_battle_anims_phase1_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_battle_anims_phase2_test.lua` | 7 | 0 | 7 | 0 |
| `tests/game3_battle_anims_phase3_test.lua` | 13 | 0 | 13 | 0 |
| `tests/game3_battle_anims_phase4_test.lua` | 21 | 0 | 21 | 0 |
| `tests/game3_battle_anims_pret_parity_test.lua` | 11 | 0 | 11 | 0 |
| `tests/game3_battle_catch_ball_open_test.lua` | 5 | 0 | 3 | 0 |
| `tests/game3_battle_doubles_engine_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_battle_event_seq_test.lua` | 4 | 0 | 4 | 0 |
| `tests/game3_battle_friendship_test.lua` | 11 | 1 | 10 | 0 |
| `tests/game3_battle_items_abilities_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_battle_move_effects_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_battle_rendering_test.lua` | 3 | 0 | 3 | 0 |
| `tests/game3_battle_safari_test.lua` | 13 | 0 | 13 | 0 |
| `tests/game3_battle_special_moves_test.lua` | 6 | 0 | 6 | 0 |
| `tests/game3_battle_terrain_test.lua` | 3 | 3 | 0 | 0 |
| `tests/game3_bedroom_pc_test.lua` | 2 | 2 | 0 | 0 |
| `tests/game3_cerulean_block_exits_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_collision_behaviors_test.lua` | 1 | 1 | 0 | 0 |
| `tests/game3_collision_interactions_test.lua` | 2 | 1 | 1 | 0 |
| `tests/game3_collision_npc_dir_test.lua` | 4 | 3 | 1 | 0 |
| `tests/game3_corner_prize_test.lua` | 10 | 0 | 9 | 0 |
| `tests/game3_corner_screen_test.lua` | 10 | 0 | 10 | 0 |
| `tests/game3_corner_slots_test.lua` | 6 | 0 | 6 | 0 |
| `tests/game3_credits_hall_of_fame_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_cry_modes_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_daycare_breeding_test.lua` | 5 | 4 | 1 | 0 |
| `tests/game3_daycare_hatch_test.lua` | 12 | 10 | 2 | 0 |
| `tests/game3_daycare_menu_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_daycare_model_test.lua` | 3 | 2 | 1 | 0 |
| `tests/game3_deoxys_test.lua` | 2 | 1 | 0 | 0 |
| `tests/game3_directional_impassable_test.lua` | 2 | 1 | 1 | 0 |
| `tests/game3_encounters_areas_test.lua` | 5 | 0 | 5 | 0 |
| `tests/game3_encounters_cave_test.lua` | 2 | 0 | 2 | 0 |
| `tests/game3_encounters_flash_test.lua` | 8 | 0 | 8 | 0 |
| `tests/game3_evolution_scene_test.lua` | 3 | 0 | 3 | 0 |
| `tests/game3_fame_model_test.lua` | 7 | 0 | 7 | 0 |
| `tests/game3_fame_screen_test.lua` | 15 | 8 | 5 | 1 |
| `tests/game3_field_boulder_test.lua` | 6 | 2 | 2 | 0 |
| `tests/game3_field_cut_test.lua` | 3 | 3 | 0 | 0 |
| `tests/game3_field_cycling_road_test.lua` | 5 | 4 | 1 | 0 |
| `tests/game3_field_fly_test.lua` | 4 | 2 | 2 | 0 |
| `tests/game3_field_forced_movement_test.lua` | 11 | 6 | 4 | 0 |
| `tests/game3_field_items_test.lua` | 8 | 8 | 0 | 0 |
| `tests/game3_field_safari_test.lua` | 6 | 4 | 0 | 0 |
| `tests/game3_gift_delivery_test.lua` | 6 | 4 | 2 | 0 |
| `tests/game3_gift_menu_test.lua` | 7 | 6 | 0 | 0 |
| `tests/game3_gift_model_test.lua` | 14 | 12 | 2 | 0 |
| `tests/game3_import2_field_effects_test.lua` | 3 | 0 | 3 | 0 |
| `tests/game3_link_battle_test.lua` | 6 | 3 | 0 | 1 |
| `tests/game3_link_session_test.lua` | 2 | 2 | 0 | 0 |
| `tests/game3_link_trade_test.lua` | 22 | 15 | 3 | 0 |
| `tests/game3_link_union_test.lua` | 4 | 3 | 1 | 0 |
| `tests/game3_misc_window_test.lua` | 5 | 0 | 5 | 0 |
| `tests/game3_moveteach_deleter_test.lua` | 5 | 1 | 2 | 0 |
| `tests/game3_moveteach_dig_escape_test.lua` | 4 | 3 | 0 | 0 |
| `tests/game3_moveteach_partyselect_test.lua` | 5 | 2 | 1 | 0 |
| `tests/game3_moveteach_relearner_test.lua` | 4 | 0 | 1 | 0 |
| `tests/game3_moveteach_tutor_test.lua` | 7 | 2 | 2 | 0 |
| `tests/game3_national_dex_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_nickname_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_npc_player_collision_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_oak_first_battle_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_ops_coins_test.lua` | 10 | 0 | 10 | 0 |
| `tests/game3_ops_scene_test.lua` | 14 | 0 | 14 | 0 |
| `tests/game3_ops_vars_test.lua` | 8 | 0 | 7 | 0 |
| `tests/game3_partial_trap_safari_test.lua` | 4 | 0 | 3 | 0 |
| `tests/game3_pokedex_area_chrome_test.lua` | 6 | 0 | 6 | 0 |
| `tests/game3_region_map_assets_test.lua` | 1 | 1 | 0 | 0 |
| `tests/game3_runtime_adapters_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_runtime_camera_object_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_runtime_input_order_test.lua` | 3 | 1 | 2 | 0 |
| `tests/game3_runtime_registered_item_test.lua` | 8 | 8 | 0 | 0 |
| `tests/game3_runtime_reset_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_save_frames_test.lua` | 1 | 0 | 0 | 0 |
| `tests/game3_se_length_test.lua` | 4 | 0 | 4 | 0 |
| `tests/game3_seagallop_test.lua` | 1 | 1 | 0 | 0 |
| `tests/game3_special_elevator_test.lua` | 2 | 2 | 0 | 0 |
| `tests/game3_special_events_test.lua` | 2 | 0 | 2 | 0 |
| `tests/game3_special_handlers_test.lua` | 3 | 1 | 2 | 0 |
| `tests/game3_special_queries_test.lua` | 11 | 2 | 8 | 0 |
| `tests/game3_special_trade_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_static_encounter_test.lua` | 6 | -1 | 5 | 1 |
| `tests/game3_stitchbattle_catch_headless_test.lua` | 3 | 0 | 3 | 0 |
| `tests/game3_stitchbattle_pc_transfer_test.lua` | 2 | 1 | 0 | 0 |
| `tests/game3_stitchbattle_safari_exit_test.lua` | 15 | 3 | 12 | 0 |
| `tests/game3_stitchcoll_dynamic_warp_test.lua` | 8 | 7 | 1 | 0 |
| `tests/game3_stitchcoll_escape_warp_test.lua` | 6 | 6 | 0 | 0 |
| `tests/game3_stitchcoll_fall_draw_test.lua` | 3 | 0 | 1 | 1 |
| `tests/game3_stitchcoll_fall_shake_test.lua` | 2 | 2 | 0 | 0 |
| `tests/game3_stitchcoll_ghost_ctx_test.lua` | 3 | 2 | 1 | 0 |
| `tests/game3_stitchcoll_move_kinds_test.lua` | 5 | 5 | 0 | 0 |
| `tests/game3_stitchcoll_run_speed_test.lua` | 4 | 2 | 2 | 0 |
| `tests/game3_stitchfield_flash_test.lua` | 3 | 2 | 1 | 0 |
| `tests/game3_stitchfield_ground_test.lua` | 12 | 9 | 3 | 0 |
| `tests/game3_stitchfield_movement_test.lua` | 22 | 18 | 4 | 0 |
| `tests/game3_stitchfield_onframe_test.lua` | 2 | 0 | 2 | 0 |
| `tests/game3_stitchfield_whiteout_test.lua` | 4 | 4 | 0 | 0 |
| `tests/game3_stitchimp_alt_layouts_test.lua` | 5 | 0 | 5 | 0 |
| `tests/game3_stitchimp_chrome_keys_test.lua` | 3 | 0 | 1 | 0 |
| `tests/game3_stitchimp_code_roots_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_stitchimp_condominiums_test.lua` | 3 | 0 | 3 | 0 |
| `tests/game3_stitchimp_heal_locations_test.lua` | 7 | 0 | 5 | 0 |
| `tests/game3_stitchmap_bike_test.lua` | 1 | 1 | 0 | 0 |
| `tests/game3_stitchmap_escape_rope_test.lua` | 8 | 8 | 0 | 0 |
| `tests/game3_stitchmap_header_test.lua` | 2 | 1 | 1 | 0 |
| `tests/game3_stitchmap_heal_test.lua` | 3 | 2 | 1 | 0 |
| `tests/game3_stitchmap_item_ids_test.lua` | 6 | 6 | 0 | 0 |
| `tests/game3_stitchmap_item_messages_test.lua` | 6 | 6 | 0 | 0 |
| `tests/game3_stitchmap_items_test.lua` | 12 | 12 | 0 | 0 |
| `tests/game3_stitchsave_flash_continue_test.lua` | 2 | 2 | 0 | 0 |
| `tests/game3_stitchsave_schema_fields_test.lua` | 9 | 6 | 2 | 0 |
| `tests/game3_stitchsave_summary_test.lua` | 9 | 7 | 0 | 1 |
| `tests/game3_stitchscript_mail_test.lua` | 2 | 1 | 1 | 0 |
| `tests/game3_stitchscript_natdex_var_test.lua` | 2 | 1 | 1 | 0 |
| `tests/game3_stitchseam_elevator_hud_test.lua` | 7 | 1 | 6 | 0 |
| `tests/game3_stitchseam_mod_collision_test.lua` | 5 | 4 | 1 | 0 |
| `tests/game3_stitchuid_dex_toc_test.lua` | 4 | 0 | 3 | 0 |
| `tests/game3_stitchuid_footprint_test.lua` | 2 | 0 | 2 | 0 |
| `tests/game3_stitchuid_region_guide_test.lua` | 5 | 0 | 4 | 0 |
| `tests/game3_stitchuid_summary_dexno_test.lua` | 4 | 0 | 4 | 0 |
| `tests/game3_stitchuif_boxsend_test.lua` | 2 | 0 | 2 | 0 |
| `tests/game3_stitchuif_money_window_test.lua` | 2 | 0 | 2 | 0 |
| `tests/game3_stitchuif_naming_pc_test.lua` | 5 | 0 | 3 | 0 |
| `tests/game3_stitchuif_start_forced_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_teachy_model_test.lua` | 16 | 5 | 8 | 1 |
| `tests/game3_teachy_screen_test.lua` | 44 | 22 | 12 | 4 |
| `tests/game3_tower_party_test.lua` | 19 | 8 | 9 | 0 |
| `tests/game3_tower_records_test.lua` | 10 | 5 | 5 | 0 |
| `tests/game3_tower_screen_test.lua` | 14 | 6 | 5 | 0 |
| `tests/game3_tower_state_test.lua` | 25 | 7 | 15 | 0 |
| `tests/game3_town_map_test.lua` | 2 | 0 | 2 | 0 |
| `tests/game3_trade_rules_test.lua` | 25 | 11 | 8 | 1 |
| `tests/game3_trade_scene_test.lua` | 6 | 2 | 4 | 0 |
| `tests/game3_ui_braille_test.lua` | 7 | 0 | 6 | 0 |
| `tests/game3_ui_coins_box_test.lua` | 3 | 0 | 3 | 0 |
| `tests/game3_ui_elevator_window_test.lua` | 5 | 1 | 4 | 0 |
| `tests/game3_ui_party_fieldmove_test.lua` | 4 | 0 | 4 | 0 |
| `tests/game3_ui_region_map_fly_test.lua` | 2 | 0 | 2 | 0 |
| `tests/game3_ui_summary_pokerus_test.lua` | 2 | 0 | 2 | 0 |
| `tests/game3_vermilion_trash_cans_test.lua` | 1 | 0 | 1 | 0 |
| `tests/game3_vs_seeker_test.lua` | 1 | 1 | 0 | 0 |
| `tests/game3_warp_behaviors_test.lua` | 8 | 2 | 6 | 0 |
| `tests/game3_waterfall_test.lua` | 2 | 0 | 2 | 0 |

Anchor rows are line-only citations (`-- pokefirered/src/x.c:123` with no symbol on the line): verified file exists, line in bounds and non-empty, plus a 20-row random sample read against pret (19 exactly on topic, 1 imprecise → fixed). `value-mismatch` rows: 0 (no hex/value conflicts between any test line and its pret window).
## Fold-in 1: `parity_daycare` fixture reconciliation (lead add-on)

Correction of scope: there is no `tests/game3_parity_daycare*.lua`; the suite is
**`tests/parity_daycare.lua`** (self-contained, also `dofile`d by
`tests/drivers/daycare_moves_test.lua`).

**(a) Gate impact: NONE.** `scripts/test.sh` T6 globs `tests/game3_*.lua` only
(`scripts/test.sh:190`) and `parity_daycare` has 0 hits in
`KNOWN_GAME3_FAILURES`. `tests/parity_*.lua` runs under the **T3 content tier**
(`tests/run_tests.lua:3814`), which `scripts/test.sh` skips in this checkout
(no `data/generated/`, no `RED_CACHE`). On a ROM-imported gate machine T3 loads
real species, where `RATTATA` exists.

**(b) Not gate-affecting → documented only; no fixture edit, no self-skip.**
Adding `RATTATA` to the 3-species `tests/fixture_data` risks the suite
assertions that count fixture species, and a self-skip would mask real T3 runs.

**(c) Both invocation styles run twice (both environmentally failing, identical
both runs):**

| Invocation | Exit | Failure line |
| --- | --- | --- |
| `POKEPORT_DATA_DIR=$PWD/tests/fixture_data luajit tests/parity_daycare.lua` (Finisher's style) | 1 | `./src/pokemon/Pokemon.lua:62: unknown species RATTATA` |
| `luajit tests/parity_daycare.lua` (gate style) | 1 | `src/core/Data.lua:316: missing generated data module 'data/generated/constants.lua'` — the reason scripts/test.sh skips T3 here |

**Verdict:** invocation mismatch, not a gate failure. The fixture env var is a
`game3_*`-suite convention; `parity_*` suites need T3 conditions (real imported
data). Document, move on.

## Fold-in 2: `game3_object_interactions_cache` configured run (lead add-on)

Config (pack/cache already on disk from the v113 import):

```sh
POKEPORT_DATA_DIR="$PWD/tests/fixture_data" \
  luajit tests/game3_object_interactions_cache_test.lua \
  "$HOME/Library/Application Support/LOVE/qa-firered-v113/firered"
```

**Result after the Finisher's `natives_tower.lua` rework: FAIL, twice,
identical:**

```
tests/game3_object_interactions_cache_test.lua:80: furniture did not release
control CableClub_EventScript_ShowBattleRecords
```

Evidence tiers:
- **(a) observed:** 2/2 runs exit 1 at line 80 (the 100-tick
  `assert(not Space.vm:isRunning())` after the furniture dispatch).
- **(b) engine-internal:** `recordsScreen()`
  (`src/core/game3/scripting/natives_tower.lua:178-183`) successfully loads
  `src.ui.game3.trainer_tower_records` under plain luajit, so the Screen is
  non-nil and the reworked handler **parks** on the waitstate (its comment cites
  `cable_club.inc:566-575` + `battle_records.c:83`). The headless test has no
  frame loop to close the screen, so the script never ends within 100 ticks.
- **(c) pret:** `data/scripts/cable_club.inc:566-575` —
  `special ShowBattleRecords` + `waitstate` waits for the screen, then
  `releaseall`; `src/battle_records.c:83` `ShowBattleRecords`.

**Verdict: configured FAIL is a finding for the lead, not a fixture problem.**
It is the collision between the adjudicated *park-while-screen-up* behavior and
the test's *release within 100 ticks* expectation. Resolution needs adjudication
— either the test drives the records screen's `onDone` before asserting
release, or headless must take the no-screen path. No src/ or test edit made by
QA for this item.

**Lead adjudication (option a) and fix — implemented:** the TEST drives the
dismissal. `tests/game3_object_interactions_cache_test.lua` now, for the
`SCREEN_ONLY` branch: (1) asserts the VM is **still running** after 100 ticks
with the screen up (pins `cable_club.inc:566-575` + `battle_records.c:83` —
release must not happen spontaneously while the screen is up, matching
`code_roots:86`), (2) requires `src.ui.game3.trainer_tower_records`,
asserts `Records.isOpen()`, calls `Records.close()` + 60 `Fade.tick`s (the
dismissal seam), (3) ticks the VM again and keeps the original release
assertion at line 80. Results: **configured run twice → EXIT 0,**
`PASS 425 maps audited, 1527 furniture cells, 29 furniture types dispatched`;
arg-less invocation still `SKIP ... supply FireRed cache root` (EXIT 0), so the
T6 gate behaviour is unchanged. No src/ edits.
