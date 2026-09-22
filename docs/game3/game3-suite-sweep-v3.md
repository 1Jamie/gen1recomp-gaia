# Game3 top-level suite sweep v3 (pre-fix-wave baseline)

> **Provenance note (pret mandate, added 2026-09-22):** every verdict in this
> document is an observed suite-run outcome, not an independent behavioural
> claim. The one mechanic interpretation it makes — that Knock Off must keep
> the party's held item while clearing the battle copy — was **UNVERIFIED**
> against pret/pokefirered (no local checkout; `pokefirered/src/battle_script_commands.c`,
> Knock Off effect, would confirm) and has since been retracted: with a current
> v113 cache the suite passes (see `game3-suite-sweep-v113.md`).

Captured: 2026-09-22 10:19 IST by QA and Test Engineer (team G1R_Deluxe_Gen3).
Engine root: `/Users/shanemcgovern/dev/gen1recomp`. **Read-only run — nothing
fixed, every failure below is a data point for the fix wave.**

Scope: every top-level `tests/game3_*.lua` file (273 files = 272 suites +
1 helper module `game3_cache.lua`, which is the shared cache locator and is
reported as `n/a (helper)`). This is the coverage `./scripts/test.sh` does
**not** run (see `test-baseline-v3.md`).

## Method

```sh
cd /Users/shanemcgovern/dev/gen1recomp
# one suite per process, 120s alarm, env set defensively as instructed
POKEPORT_DATA_DIR="$PWD/tests/fixture_data" \
  perl -e 'alarm shift; exec @ARGV' 120 \
  luajit tests/game3_<name>_test.lua
```

Every suite was then re-run **without** `POKEPORT_DATA_DIR` and all 19
failures + both classifier false positives reproduced identically
(exit codes and messages). So **no suite is environment-variable-sensitive**;
`POKEPORT_DATA_DIR` is inert here (no top-level game3 suite calls `Data:load`).

Verdicts used in the table:

- **PASS** — exit 0, no failure lines, no skip markers.
- **PARTIAL** — exit 0 but at least one section self-skipped (missing
  cache/ROM/pret sources); the rest ran. *The green parts still prove nothing
  about the skipped paths.*
- **SKIP** — exit 0, everything self-skipped; no coverage at all.
- **FAIL** — non-zero exit, or real failure lines / `N failed` > 0.

## Totals

| Verdict | Count |
| --- | --- |
| PASS | 145 |
| PARTIAL | 63 |
| SKIP | 45 |
| FAIL | **19** |
| n/a (helper `game3_cache.lua`) | 1 |
| **Files swept** | **273** (272 suites + 1 helper) |

The 63 PARTIAL + 45 SKIP are dominated by one environmental hole: the
FireRed cache on this machine is **v112/native v6, while the engine now
expects v113/native v6** (89 suite logs say `none at cache v113`). Available
caches: `deoxys-visual` v112, `pokemon-love2d` v112 (LOVE app-support),
`gaia-review` v98, `gen1recomp-firered-help-test` v100,
`~/.local/share/love/pokemon-love2d` v98. A re-import to v113 should turn
most PARTIAL/SKIP rows into real coverage.

## Failing suites by subsystem (19)

### battle (4)

| Suite | Evidence |
| --- | --- |
| `game3_battle_ai_test.lua` | `[FAIL] pack loaded` (+13); `Ai.loadPack({force=true,extract=true})` returns nil — no extracted AI pack in this checkout. Data/env-dependent hard-fail; the suite has no self-skip path. |
| `game3_battle_move_effects_test.lua` | `[FAIL] Knock Off removes the item for the battle only` (125 passed, 1 failed). Knock Off zeroes `enemy.item` correctly but also nils `foeParty[1].item`; expected the party copy to keep item 200. |
| `game3_battle_safari_test.lua` | `[FAIL] the foe fled on a low roll (nil == enemy_fled)`, `outcome RAN (nil == run)`, `wild foe fled line` (66 passed, 3 failed). |
| `game3_stitchbattle_catch_headless_test.lua` | crash in `src/ui/game3/naming.lua:500` — stale two-arg `Naming.update` call, cluster B below. |

### field (11)

| Suite | Evidence |
| --- | --- |
| `game3_cerulean_block_exits_test.lua` | crash `src/core/game3/objects.lua:162` — cluster A. |
| `game3_cerulean_policeman_bill_test.lua` | cluster A. |
| `game3_collision_npc_dir_test.lua` | cluster A. |
| `game3_emote_movement_test.lua` | cluster A. |
| `game3_item_use_and_parcel_test.lua` | cluster A. |
| `game3_marowak_progression_test.lua` | `tests/game3_marowak_progression_test.lua:40: 5 imported FireRed cache(s) found, none at cache v113 / native v6` — cache-version hole (cluster C); errors instead of skipping. |
| `game3_npc_player_collision_test.lua` | cluster A. |
| `game3_objects_perm_reset_test.lua` | cluster A. |
| `game3_runtime_camera_object_test.lua` | cluster A. |
| `game3_trainer_sight_test.lua` | cluster A at `objects.lua:559`. |
| `game3_viridian_gym_door_test.lua` | cluster A. |

### script (1)

| Suite | Evidence |
| --- | --- |
| `game3_special_events_test.lua` | 4 checks: `distinct id per special name (1 == 0)`, `cracked ice is not written impassable (true == false)`, `ForcePlayerOntoBike mounts the bike`, `ForcePlayerToStartSurfing puts the player on the water`. |

### save (1)

| Suite | Evidence |
| --- | --- |
| `game3_save_trainer_card_test.lua` | `[FAIL] SaveMenu confirm transitions to overwrite then saved ... Selecting YES in overwrite should transition to saved` (suite:16 lines; the save flow test at :109). |

### ui (1)

| Suite | Evidence |
| --- | --- |
| `game3_stitchuif_naming_pc_test.lua` | crash `src/ui/game3/naming.lua:500` — cluster B. |

### link (1)

| Suite | Evidence |
| --- | --- |
| `game3_link_session_test.lua` | `[FAIL] saving reports TRUE, which lets the link continue (0 == 1)`. |

## Root-cause clusters (for the fix wave)

**A. `objects.lua` lazy `Collision` indexed instead of called — 10 suites.**
`src/core/game3/objects.lua:63` defines `local function Collision() return require(...) end`,
but lines **162** and **559** write `Collision.elevationAt(...)`; the correct
pattern is `Collision()` (used at lines 916/924). Any code path reaching
those lines dies with `attempt to index upvalue 'Collision' (a function value)`.
Suites: cerulean_block_exits, cerulean_policeman_bill, collision_npc_dir,
emote_movement, item_use_and_parcel, npc_player_collision, objects_perm_reset,
runtime_camera_object, viridian_gym_door (:162) + trainer_sight (:559).

**B. `naming.lua` signature drift — 2 suites.**
`src/ui/game3/naming.lua:493` is now `Naming.update(dt)` (comment at :491
records that passing the input table first was the old bug), but the two
failing suites still call `Naming.update(input, 1 / 60)`, so `dt` arrives as a
table and line **500** does arithmetic on it. These look like **stale tests**,
not a src regression (`new_game_scene.lua`, `battle/init.lua`, `runtime.lua`
all use the one-arg form).

**C. FireRed cache version hole (v112/native v6 on disk vs v113/native v6 in src).**
89 suite logs report `none at cache v113`; 2 of them hard-fail instead of
self-skipping (marowak_progression, battle_ai). Fix = re-import fresh caches
(or provide `POKEPORT_GBA_CACHE`) before judging those suites.

**D. Genuine logic/data failures independent of environment (5 suites):**
battle_move_effects (Knock Off party item), battle_safari (foe-fled path),
link_session (save-while-linked result), save_trainer_card (overwrite → saved),
special_events (4 checks). Plus battle_ai (cluster C data hole).

## Verification / classifier notes

- Two suites initially flagged by a substring heuristic
  (`BALL_3_SHAKES_FAIL`, `LINKUP_FAILED`) were re-checked: both logs end
  `[ok] all` / `[pass] link union room` with no `[FAIL]` lines and exit 0 →
  counted **PASS**.
- `game3_cache.lua` exits 0 printing nothing: it is a helper module, not a
  suite; excluded from PASS/FAIL totals.
- Each FAIL row was run twice (with and without `POKEPORT_DATA_DIR`) with
  identical results; no flakes observed in the 19.

## Appendix A — every suite (273 rows)

| # | Suite | Verdict | Failure line |
| --- | --- | --- | --- |
| 1 | `game3_anim_port_g1_test.lua` | PARTIAL |  |
| 2 | `game3_anim_port_g2_test.lua` | PARTIAL |  |
| 3 | `game3_anim_port_g3_test.lua` | PASS |  |
| 4 | `game3_anim_port_g4_test.lua` | PARTIAL |  |
| 5 | `game3_bag_test.lua` | PASS |  |
| 6 | `game3_battle_ai_test.lua` | FAIL | [FAIL] pack loaded |
| 7 | `game3_battle_anim_pack_test.lua` | PASS |  |
| 8 | `game3_battle_anim_palette_test.lua` | PARTIAL |  |
| 9 | `game3_battle_anims_coverage_test.lua` | PASS |  |
| 10 | `game3_battle_anims_phase1_test.lua` | PASS |  |
| 11 | `game3_battle_anims_phase2_test.lua` | PASS |  |
| 12 | `game3_battle_anims_phase3_test.lua` | PASS |  |
| 13 | `game3_battle_anims_phase4_test.lua` | PASS |  |
| 14 | `game3_battle_anims_pret_parity_test.lua` | PARTIAL |  |
| 15 | `game3_battle_bag_test.lua` | PASS |  |
| 16 | `game3_battle_ball_open_test.lua` | PASS |  |
| 17 | `game3_battle_baton_pass_test.lua` | PASS |  |
| 18 | `game3_battle_catch_ball_open_test.lua` | PASS |  |
| 19 | `game3_battle_caught_marker_test.lua` | PASS |  |
| 20 | `game3_battle_doubles_engine_test.lua` | PASS |  |
| 21 | `game3_battle_event_seq_test.lua` | PASS |  |
| 22 | `game3_battle_faint_test.lua` | PASS |  |
| 23 | `game3_battle_fainted_lead_test.lua` | PASS |  |
| 24 | `game3_battle_forms_intro_test.lua` | PASS |  |
| 25 | `game3_battle_friendship_test.lua` | PASS |  |
| 26 | `game3_battle_ghost_test.lua` | PASS |  |
| 27 | `game3_battle_intro_test.lua` | PASS |  |
| 28 | `game3_battle_item_party_test.lua` | PASS |  |
| 29 | `game3_battle_items_abilities_test.lua` | PASS |  |
| 30 | `game3_battle_move_effects_test.lua` | FAIL | [FAIL] Knock Off removes the item for the battle only |
| 31 | `game3_battle_music_test.lua` | PARTIAL |  |
| 32 | `game3_battle_rendering_test.lua` | PASS |  |
| 33 | `game3_battle_rewards_test.lua` | PASS |  |
| 34 | `game3_battle_safari_test.lua` | FAIL | [FAIL] the foe fled on a low roll (nil == enemy_fled) |
| 35 | `game3_battle_sendout_scale_test.lua` | PASS |  |
| 36 | `game3_battle_special_moves_test.lua` | PASS |  |
| 37 | `game3_battle_status_timing_test.lua` | PASS |  |
| 38 | `game3_battle_switch_and_faint_test.lua` | PASS |  |
| 39 | `game3_battle_terrain_test.lua` | PARTIAL |  |
| 40 | `game3_battle_transition_test.lua` | PASS |  |
| 41 | `game3_battle_translated_text_test.lua` | PASS |  |
| 42 | `game3_battle_win_text_test.lua` | PASS |  |
| 43 | `game3_battle_yesno_frame_test.lua` | PASS |  |
| 44 | `game3_bedroom_pc_test.lua` | PASS |  |
| 45 | `game3_berry_pouch_1to1_test.lua` | PASS |  |
| 46 | `game3_cache.lua` | n/a (helper) |  |
| 47 | `game3_cerulean_block_exits_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/core/game3/objects.lua:162: attempt to index upvalue 'Collision' (a function value) |
| 48 | `game3_cerulean_policeman_bill_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/core/game3/objects.lua:162: attempt to index upvalue 'Collision' (a function value) |
| 49 | `game3_collision_behaviors_test.lua` | PARTIAL |  |
| 50 | `game3_collision_interactions_test.lua` | PARTIAL |  |
| 51 | `game3_collision_npc_dir_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/core/game3/objects.lua:162: attempt to index upvalue 'Collision' (a function value) |
| 52 | `game3_corner_prize_test.lua` | PARTIAL |  |
| 53 | `game3_corner_screen_test.lua` | PARTIAL |  |
| 54 | `game3_corner_slots_test.lua` | SKIP |  |
| 55 | `game3_credits_hall_of_fame_test.lua` | SKIP |  |
| 56 | `game3_cry_modes_test.lua` | PASS |  |
| 57 | `game3_daycare_breeding_test.lua` | PARTIAL |  |
| 58 | `game3_daycare_hatch_test.lua` | PARTIAL |  |
| 59 | `game3_daycare_menu_test.lua` | PARTIAL |  |
| 60 | `game3_daycare_model_test.lua` | PARTIAL |  |
| 61 | `game3_deoxys_test.lua` | PASS |  |
| 62 | `game3_directional_impassable_test.lua` | PARTIAL |  |
| 63 | `game3_display_fit_test.lua` | PASS |  |
| 64 | `game3_doors_table_test.lua` | PARTIAL |  |
| 65 | `game3_doors_viewport_test.lua` | PASS |  |
| 66 | `game3_easy_chat_test.lua` | PASS |  |
| 67 | `game3_elevation_oam_priority_test.lua` | PASS |  |
| 68 | `game3_emote_movement_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/core/game3/objects.lua:162: attempt to index upvalue 'Collision' (a function value) |
| 69 | `game3_encounters_areas_test.lua` | PASS |  |
| 70 | `game3_encounters_cave_test.lua` | PARTIAL |  |
| 71 | `game3_encounters_flash_test.lua` | PASS |  |
| 72 | `game3_encounters_lookup_test.lua` | PASS |  |
| 73 | `game3_event_flags_test.lua` | PASS |  |
| 74 | `game3_evolution_learn_move_test.lua` | PASS |  |
| 75 | `game3_evolution_methods_test.lua` | SKIP |  |
| 76 | `game3_evolution_scene_test.lua` | SKIP |  |
| 77 | `game3_fame_model_test.lua` | PASS |  |
| 78 | `game3_fame_screen_test.lua` | SKIP |  |
| 79 | `game3_field_boulder_test.lua` | SKIP |  |
| 80 | `game3_field_cut_test.lua` | PARTIAL |  |
| 81 | `game3_field_cycling_road_test.lua` | PARTIAL |  |
| 82 | `game3_field_fly_test.lua` | PARTIAL |  |
| 83 | `game3_field_forced_movement_test.lua` | PARTIAL |  |
| 84 | `game3_field_items_test.lua` | SKIP |  |
| 85 | `game3_field_safari_test.lua` | PARTIAL |  |
| 86 | `game3_flags_extract_preserve_test.lua` | PASS |  |
| 87 | `game3_gift_delivery_test.lua` | PASS |  |
| 88 | `game3_gift_menu_test.lua` | PASS |  |
| 89 | `game3_gift_model_test.lua` | PASS |  |
| 90 | `game3_growth_coins_test.lua` | PASS |  |
| 91 | `game3_growth_evolution_test.lua` | SKIP |  |
| 92 | `game3_growth_test.lua` | SKIP |  |
| 93 | `game3_hall_of_fame_test.lua` | PASS |  |
| 94 | `game3_healthbox_erase_test.lua` | PASS |  |
| 95 | `game3_help_rom_test.lua` | SKIP |  |
| 96 | `game3_hidden_item_persistence_test.lua` | PASS |  |
| 97 | `game3_hidden_items_test.lua` | PASS |  |
| 98 | `game3_import2_cache_version_test.lua` | PARTIAL |  |
| 99 | `game3_import2_corner_assets_test.lua` | PARTIAL |  |
| 100 | `game3_import2_field_effects_test.lua` | PARTIAL |  |
| 101 | `game3_import2_misc_assets_test.lua` | PARTIAL |  |
| 102 | `game3_import2_mt_ember_collision_test.lua` | PARTIAL |  |
| 103 | `game3_import2_system_assets_test.lua` | PARTIAL |  |
| 104 | `game3_import_assets_test.lua` | PARTIAL |  |
| 105 | `game3_import_battle_terrain_test.lua` | PARTIAL |  |
| 106 | `game3_import_cache_version_test.lua` | PARTIAL |  |
| 107 | `game3_import_hardening_test.lua` | PASS |  |
| 108 | `game3_import_multichoice_test.lua` | PARTIAL |  |
| 109 | `game3_import_pokedex_assets_test.lua` | PARTIAL |  |
| 110 | `game3_item_pc_potion_test.lua` | PASS |  |
| 111 | `game3_item_use_and_parcel_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/core/game3/objects.lua:162: attempt to index upvalue 'Collision' (a function value) |
| 112 | `game3_item_use_party_test.lua` | PASS |  |
| 113 | `game3_latin_glyphs_test.lua` | PASS |  |
| 114 | `game3_learn_move_test.lua` | PASS |  |
| 115 | `game3_link_battle_test.lua` | PARTIAL |  |
| 116 | `game3_link_session_test.lua` | FAIL | [FAIL] saving reports TRUE, which lets the link continue (0 == 1) |
| 117 | `game3_link_trade_test.lua` | PARTIAL |  |
| 118 | `game3_link_union_test.lua` | PARTIAL |  |
| 119 | `game3_map_onload_test.lua` | PARTIAL |  |
| 120 | `game3_map_preview_extract_test.lua` | PARTIAL |  |
| 121 | `game3_mapscripts_test.lua` | PARTIAL |  |
| 122 | `game3_marowak_progression_test.lua` | FAIL | /opt/homebrew/bin/luajit: tests/game3_marowak_progression_test.lua:40: 5 imported FireRed cache(s) found, none at cache v113 / native v6 |
| 123 | `game3_menu_sfx_test.lua` | PASS |  |
| 124 | `game3_misc_window_test.lua` | PASS |  |
| 125 | `game3_mon_pic_center_test.lua` | PASS |  |
| 126 | `game3_move_names_test.lua` | PASS |  |
| 127 | `game3_moveset_assignment_test.lua` | PASS |  |
| 128 | `game3_moveteach_deleter_test.lua` | SKIP |  |
| 129 | `game3_moveteach_dig_escape_test.lua` | SKIP |  |
| 130 | `game3_moveteach_partyselect_test.lua` | SKIP |  |
| 131 | `game3_moveteach_relearner_test.lua` | SKIP |  |
| 132 | `game3_moveteach_tutor_test.lua` | SKIP |  |
| 133 | `game3_multichoice_grid_test.lua` | PARTIAL |  |
| 134 | `game3_multichoice_window_test.lua` | PASS |  |
| 135 | `game3_national_dex_test.lua` | PASS |  |
| 136 | `game3_nickname_test.lua` | PASS |  |
| 137 | `game3_npc_player_collision_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/core/game3/objects.lua:162: attempt to index upvalue 'Collision' (a function value) |
| 138 | `game3_nurse_joy_heal_test.lua` | PASS |  |
| 139 | `game3_oak_first_battle_test.lua` | PASS |  |
| 140 | `game3_oaks_lab_save_reload_test.lua` | SKIP |  |
| 141 | `game3_object_interactions_cache_test.lua` | SKIP |  |
| 142 | `game3_object_interactions_rom_test.lua` | SKIP |  |
| 143 | `game3_object_interactions_test.lua` | PASS |  |
| 144 | `game3_objects_perm_reset_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/core/game3/objects.lua:162: attempt to index upvalue 'Collision' (a function value) |
| 145 | `game3_oneoff_specials_test.lua` | PASS |  |
| 146 | `game3_ops_coins_test.lua` | PASS |  |
| 147 | `game3_ops_scene_test.lua` | PASS |  |
| 148 | `game3_ops_vars_test.lua` | PASS |  |
| 149 | `game3_pallet_sign_lady_test.lua` | SKIP |  |
| 150 | `game3_partial_trap_safari_test.lua` | PASS |  |
| 151 | `game3_pause_and_main_menu_exit_test.lua` | PASS |  |
| 152 | `game3_payday_pickup_test.lua` | PASS |  |
| 153 | `game3_pc_anim_test.lua` | PASS |  |
| 154 | `game3_pokecenter_heal_test.lua` | PASS |  |
| 155 | `game3_pokedex_and_catch_test.lua` | PASS |  |
| 156 | `game3_pokedex_area_chrome_test.lua` | PARTIAL |  |
| 157 | `game3_pokedex_area_test.lua` | SKIP |  |
| 158 | `game3_pokedex_card_chrome_test.lua` | PASS |  |
| 159 | `game3_pokedex_rating_test.lua` | PASS |  |
| 160 | `game3_pokedex_sorting_test.lua` | PASS |  |
| 161 | `game3_quest_log_events_test.lua` | PASS |  |
| 162 | `game3_quest_log_integration_test.lua` | PASS |  |
| 163 | `game3_quest_log_rom_test.lua` | SKIP |  |
| 164 | `game3_quest_log_test.lua` | PASS |  |
| 165 | `game3_region_map_assets_test.lua` | PARTIAL |  |
| 166 | `game3_revision_view_test.lua` | PARTIAL |  |
| 167 | `game3_rng_test.lua` | PASS |  |
| 168 | `game3_running_shoes_test.lua` | PASS |  |
| 169 | `game3_runtime_adapters_test.lua` | PARTIAL |  |
| 170 | `game3_runtime_camera_object_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/core/game3/objects.lua:162: attempt to index upvalue 'Collision' (a function value) |
| 171 | `game3_runtime_input_order_test.lua` | PASS |  |
| 172 | `game3_runtime_registered_item_test.lua` | PASS |  |
| 173 | `game3_runtime_reset_test.lua` | PASS |  |
| 174 | `game3_save_frames_test.lua` | PASS |  |
| 175 | `game3_save_menu_layout_test.lua` | PASS |  |
| 176 | `game3_save_pokeball_test.lua` | PASS |  |
| 177 | `game3_save_trainer_card_test.lua` | FAIL | [FAIL] SaveMenu confirm transitions to overwrite then saved: tests/game3_save_trainer_card_test.lua:109: Selecting YES in overwrite should transition to saved |
| 178 | `game3_se_length_test.lua` | SKIP |  |
| 179 | `game3_seafoam_puzzle_test.lua` | SKIP |  |
| 180 | `game3_seagallop_test.lua` | PASS |  |
| 181 | `game3_shop_bag_chrome_test.lua` | PASS |  |
| 182 | `game3_shop_menu_test.lua` | PASS |  |
| 183 | `game3_size_record_test.lua` | PASS |  |
| 184 | `game3_special_elevator_test.lua` | PASS |  |
| 185 | `game3_special_events_test.lua` | FAIL | [FAIL] distinct id per special name (1 == 0) |
| 186 | `game3_special_handlers_test.lua` | PASS |  |
| 187 | `game3_special_ids_test.lua` | SKIP |  |
| 188 | `game3_special_queries_test.lua` | PASS |  |
| 189 | `game3_special_trade_test.lua` | PARTIAL |  |
| 190 | `game3_static_encounter_test.lua` | SKIP |  |
| 191 | `game3_step_events_queue_test.lua` | PASS |  |
| 192 | `game3_stitchbattle_catch_headless_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/ui/game3/naming.lua:500: attempt to perform arithmetic on a table value |
| 193 | `game3_stitchbattle_pc_transfer_test.lua` | PASS |  |
| 194 | `game3_stitchbattle_safari_exit_test.lua` | SKIP |  |
| 195 | `game3_stitchcoll_dynamic_warp_test.lua` | PARTIAL |  |
| 196 | `game3_stitchcoll_escape_warp_test.lua` | SKIP |  |
| 197 | `game3_stitchcoll_fall_draw_test.lua` | SKIP |  |
| 198 | `game3_stitchcoll_fall_shake_test.lua` | PARTIAL |  |
| 199 | `game3_stitchcoll_ghost_ctx_test.lua` | SKIP |  |
| 200 | `game3_stitchcoll_move_kinds_test.lua` | SKIP |  |
| 201 | `game3_stitchcoll_run_speed_test.lua` | SKIP |  |
| 202 | `game3_stitchfield_flash_test.lua` | PASS |  |
| 203 | `game3_stitchfield_ground_test.lua` | SKIP |  |
| 204 | `game3_stitchfield_movement_test.lua` | PARTIAL |  |
| 205 | `game3_stitchfield_onframe_test.lua` | SKIP |  |
| 206 | `game3_stitchfield_whiteout_test.lua` | SKIP |  |
| 207 | `game3_stitchimp_alt_layouts_test.lua` | PARTIAL |  |
| 208 | `game3_stitchimp_braille_text_test.lua` | PARTIAL |  |
| 209 | `game3_stitchimp_chrome_keys_test.lua` | PARTIAL |  |
| 210 | `game3_stitchimp_code_roots_test.lua` | PARTIAL |  |
| 211 | `game3_stitchimp_condominiums_test.lua` | PARTIAL |  |
| 212 | `game3_stitchimp_heal_locations_test.lua` | PARTIAL |  |
| 213 | `game3_stitchmap_bike_test.lua` | SKIP |  |
| 214 | `game3_stitchmap_escape_rope_test.lua` | SKIP |  |
| 215 | `game3_stitchmap_header_test.lua` | SKIP |  |
| 216 | `game3_stitchmap_heal_test.lua` | SKIP |  |
| 217 | `game3_stitchmap_item_ids_test.lua` | PASS |  |
| 218 | `game3_stitchmap_item_messages_test.lua` | PASS |  |
| 219 | `game3_stitchmap_items_test.lua` | SKIP |  |
| 220 | `game3_stitchsave_flash_continue_test.lua` | SKIP |  |
| 221 | `game3_stitchsave_schema_fields_test.lua` | PASS |  |
| 222 | `game3_stitchsave_summary_test.lua` | PASS |  |
| 223 | `game3_stitchscript_mail_test.lua` | PASS |  |
| 224 | `game3_stitchscript_natdex_var_test.lua` | PASS |  |
| 225 | `game3_stitchscript_seams_test.lua` | PASS |  |
| 226 | `game3_stitchscript_warp_gifts_test.lua` | PASS |  |
| 227 | `game3_stitchseam_elevator_hud_test.lua` | PASS |  |
| 228 | `game3_stitchseam_mod_collision_test.lua` | SKIP |  |
| 229 | `game3_stitchuid_dex_toc_test.lua` | PASS |  |
| 230 | `game3_stitchuid_footprint_test.lua` | SKIP |  |
| 231 | `game3_stitchuid_region_guide_test.lua` | PASS |  |
| 232 | `game3_stitchuid_summary_dexno_test.lua` | SKIP |  |
| 233 | `game3_stitchuif_bag_use_test.lua` | PASS |  |
| 234 | `game3_stitchuif_boxsend_test.lua` | PASS |  |
| 235 | `game3_stitchuif_money_window_test.lua` | PASS |  |
| 236 | `game3_stitchuif_naming_pc_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/ui/game3/naming.lua:500: attempt to perform arithmetic on a table value |
| 237 | `game3_stitchuif_start_forced_test.lua` | PASS |  |
| 238 | `game3_stitchuif_terrain_lazy_test.lua` | PASS |  |
| 239 | `game3_storage_pc_box_test.lua` | PASS |  |
| 240 | `game3_storage_test.lua` | PARTIAL |  |
| 241 | `game3_strings_catalog_test.lua` | PASS |  |
| 242 | `game3_strings_module_tables_test.lua` | PASS |  |
| 243 | `game3_summary_description_test.lua` | PASS |  |
| 244 | `game3_teachy_model_test.lua` | PASS |  |
| 245 | `game3_teachy_screen_test.lua` | SKIP |  |
| 246 | `game3_text_colors_test.lua` | PASS |  |
| 247 | `game3_tm_case_berry_pouch_extract_test.lua` | PARTIAL |  |
| 248 | `game3_tower_party_test.lua` | PASS |  |
| 249 | `game3_tower_records_test.lua` | PASS |  |
| 250 | `game3_tower_screen_test.lua` | PASS |  |
| 251 | `game3_tower_state_test.lua` | PARTIAL |  |
| 252 | `game3_town_map_test.lua` | PARTIAL |  |
| 253 | `game3_trade_rules_test.lua` | PARTIAL |  |
| 254 | `game3_trade_scene_test.lua` | PASS |  |
| 255 | `game3_trainer_card_layout_test.lua` | PASS |  |
| 256 | `game3_trainer_dialogs_test.lua` | PASS |  |
| 257 | `game3_trainer_fan_club_test.lua` | PASS |  |
| 258 | `game3_trainer_rewards_dialogs_test.lua` | PASS |  |
| 259 | `game3_trainer_sight_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/core/game3/objects.lua:559: attempt to index upvalue 'Collision' (a function value) |
| 260 | `game3_u10_intro_layer_test.lua` | PASS |  |
| 261 | `game3_u12_healthbox_hp_text_test.lua` | PASS |  |
| 262 | `game3_ui_braille_test.lua` | PASS |  |
| 263 | `game3_ui_coins_box_test.lua` | PASS |  |
| 264 | `game3_ui_elevator_window_test.lua` | PASS |  |
| 265 | `game3_ui_party_fieldmove_test.lua` | SKIP |  |
| 266 | `game3_ui_region_map_fly_test.lua` | PASS |  |
| 267 | `game3_ui_summary_pokerus_test.lua` | PASS |  |
| 268 | `game3_vermilion_trash_cans_test.lua` | PARTIAL |  |
| 269 | `game3_viridian_gym_door_test.lua` | FAIL | /opt/homebrew/bin/luajit: ./src/core/game3/objects.lua:162: attempt to index upvalue 'Collision' (a function value) |
| 270 | `game3_void_fill_test.lua` | PARTIAL |  |
| 271 | `game3_vs_seeker_test.lua` | PASS |  |
| 272 | `game3_warp_behaviors_test.lua` | PARTIAL |  |
| 273 | `game3_waterfall_test.lua` | PASS |  |

## Appendix B — SKIP / PARTIAL inventory by reason

### anim/audio pack missing
- PARTIAL `game3_anim_port_g1_test.lua`
- PARTIAL `game3_anim_port_g2_test.lua`
- PARTIAL `game3_anim_port_g4_test.lua`
- SKIP    `game3_se_length_test.lua`
### other/self-skip
- PARTIAL `game3_battle_anim_palette_test.lua`
- PARTIAL `game3_battle_music_test.lua`
- SKIP    `game3_help_rom_test.lua`
- SKIP    `game3_object_interactions_cache_test.lua`
- PARTIAL `game3_void_fill_test.lua`
### pret checkout missing (../pokefirered)
- PARTIAL `game3_battle_anims_pret_parity_test.lua`
- PARTIAL `game3_corner_screen_test.lua`
- SKIP    `game3_corner_slots_test.lua`
- PARTIAL `game3_revision_view_test.lua`
- SKIP    `game3_special_ids_test.lua`
### FireRed cache version (v113/native v6)
- PARTIAL `game3_battle_terrain_test.lua`
- PARTIAL `game3_collision_behaviors_test.lua`
- PARTIAL `game3_collision_interactions_test.lua`
- PARTIAL `game3_corner_prize_test.lua`
- SKIP    `game3_credits_hall_of_fame_test.lua`
- PARTIAL `game3_daycare_breeding_test.lua`
- PARTIAL `game3_daycare_hatch_test.lua`
- PARTIAL `game3_daycare_menu_test.lua`
- PARTIAL `game3_daycare_model_test.lua`
- PARTIAL `game3_directional_impassable_test.lua`
- PARTIAL `game3_doors_table_test.lua`
- PARTIAL `game3_encounters_cave_test.lua`
- SKIP    `game3_evolution_methods_test.lua`
- SKIP    `game3_evolution_scene_test.lua`
- SKIP    `game3_fame_screen_test.lua`
- SKIP    `game3_field_boulder_test.lua`
- PARTIAL `game3_field_cut_test.lua`
- PARTIAL `game3_field_cycling_road_test.lua`
- PARTIAL `game3_field_fly_test.lua`
- PARTIAL `game3_field_forced_movement_test.lua`
- SKIP    `game3_field_items_test.lua`
- PARTIAL `game3_field_safari_test.lua`
- SKIP    `game3_growth_evolution_test.lua`
- SKIP    `game3_growth_test.lua`
- PARTIAL `game3_import2_cache_version_test.lua`
- PARTIAL `game3_import2_corner_assets_test.lua`
- PARTIAL `game3_import2_field_effects_test.lua`
- PARTIAL `game3_import2_misc_assets_test.lua`
- PARTIAL `game3_import2_mt_ember_collision_test.lua`
- PARTIAL `game3_import2_system_assets_test.lua`
- PARTIAL `game3_import_assets_test.lua`
- PARTIAL `game3_import_battle_terrain_test.lua`
- PARTIAL `game3_import_cache_version_test.lua`
- PARTIAL `game3_import_multichoice_test.lua`
- PARTIAL `game3_import_pokedex_assets_test.lua`
- PARTIAL `game3_link_battle_test.lua`
- PARTIAL `game3_link_trade_test.lua`
- PARTIAL `game3_link_union_test.lua`
- PARTIAL `game3_map_onload_test.lua`
- PARTIAL `game3_mapscripts_test.lua`
- SKIP    `game3_moveteach_deleter_test.lua`
- SKIP    `game3_moveteach_dig_escape_test.lua`
- SKIP    `game3_moveteach_partyselect_test.lua`
- SKIP    `game3_moveteach_relearner_test.lua`
- SKIP    `game3_moveteach_tutor_test.lua`
- PARTIAL `game3_multichoice_grid_test.lua`
- SKIP    `game3_oaks_lab_save_reload_test.lua`
- SKIP    `game3_pallet_sign_lady_test.lua`
- PARTIAL `game3_pokedex_area_chrome_test.lua`
- SKIP    `game3_pokedex_area_test.lua`
- PARTIAL `game3_region_map_assets_test.lua`
- PARTIAL `game3_runtime_adapters_test.lua`
- SKIP    `game3_seafoam_puzzle_test.lua`
- PARTIAL `game3_special_trade_test.lua`
- SKIP    `game3_static_encounter_test.lua`
- SKIP    `game3_stitchbattle_safari_exit_test.lua`
- PARTIAL `game3_stitchcoll_dynamic_warp_test.lua`
- SKIP    `game3_stitchcoll_escape_warp_test.lua`
- SKIP    `game3_stitchcoll_fall_draw_test.lua`
- PARTIAL `game3_stitchcoll_fall_shake_test.lua`
- SKIP    `game3_stitchcoll_ghost_ctx_test.lua`
- SKIP    `game3_stitchcoll_move_kinds_test.lua`
- SKIP    `game3_stitchcoll_run_speed_test.lua`
- SKIP    `game3_stitchfield_ground_test.lua`
- PARTIAL `game3_stitchfield_movement_test.lua`
- SKIP    `game3_stitchfield_onframe_test.lua`
- SKIP    `game3_stitchfield_whiteout_test.lua`
- PARTIAL `game3_stitchimp_alt_layouts_test.lua`
- PARTIAL `game3_stitchimp_braille_text_test.lua`
- PARTIAL `game3_stitchimp_chrome_keys_test.lua`
- PARTIAL `game3_stitchimp_code_roots_test.lua`
- PARTIAL `game3_stitchimp_condominiums_test.lua`
- PARTIAL `game3_stitchimp_heal_locations_test.lua`
- SKIP    `game3_stitchmap_bike_test.lua`
- SKIP    `game3_stitchmap_escape_rope_test.lua`
- SKIP    `game3_stitchmap_header_test.lua`
- SKIP    `game3_stitchmap_heal_test.lua`
- SKIP    `game3_stitchmap_items_test.lua`
- SKIP    `game3_stitchsave_flash_continue_test.lua`
- SKIP    `game3_stitchseam_mod_collision_test.lua`
- SKIP    `game3_stitchuid_footprint_test.lua`
- SKIP    `game3_stitchuid_summary_dexno_test.lua`
- PARTIAL `game3_storage_test.lua`
- SKIP    `game3_teachy_screen_test.lua`
- PARTIAL `game3_tower_state_test.lua`
- PARTIAL `game3_trade_rules_test.lua`
- SKIP    `game3_ui_party_fieldmove_test.lua`
- PARTIAL `game3_vermilion_trash_cans_test.lua`
- PARTIAL `game3_warp_behaviors_test.lua`
### ROM file missing
- PARTIAL `game3_map_preview_extract_test.lua`
- SKIP    `game3_object_interactions_rom_test.lua`
- SKIP    `game3_quest_log_rom_test.lua`
- PARTIAL `game3_tm_case_berry_pouch_extract_test.lua`
- PARTIAL `game3_town_map_test.lua`

## Appendix C — coverage caveat recap

1. PASS in this table means pass **in this checkout**; 63 PARTIAL and 45 SKIP
   rows ran only part of their checks because of the v112→v113 cache gap,
   missing `../pokefirered` pret checkout, or missing ROM/pack files.
2. Re-run the exact command in §Method after the fix wave; compare row by row.
   Any suite flipping PASS→FAIL is a regression, and any FAIL→PASS should be
   verified as real (not a new skip).
3. No `src/` file was edited by this sweep.
