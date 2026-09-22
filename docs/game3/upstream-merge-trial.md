# Upstream merge trial — PR #2393 branch → bryanthaboi/dev

Local-only investigation (scratch clone), 2026-09-22. No push, no PR action, live worktree untouched.

## Headline: the branch is already merged; the trial merge is a fast-forward

- Fresh fetch of `bryanthaboi/gen1recomp` `dev` resolves to **1ace9283**
  (`Merge pull request #2393 from Nexhas28/nexhas28/fixing-stuff-because-no-one-read-the-report`,
  2026-09-22 05:24:19 -0400).
- PR #2393 shows `merged: true`, merged by bryanthaboi at 2026-09-22T09:24:19Z,
  merge commit `1ace9283346deace4913c03151ef6c20d4716c79`.
- `git merge --no-edit upstream/dev` on branch `game3-review-fixes` (1b8b9b48):
  **"Updating 1b8b9b48..1ace9283 — Fast-forward"**.
- Conflicted files: **none** (0).
- Merge commit parents: `1f102048` (dev before) + `1b8b9b48` (branch tip).
- Commits the branch contributed: `a5f55d34`, `2c356f28`, `1b8b9b48` (3).
- Nothing else landed between `1f102048` and the merge:
  `git log 1f102048..upstream/dev ^1b8b9b48` lists only the merge commit itself.
- `git diff --stat 1b8b9b48..upstream/dev` is empty — merged content is identical to the branch tip.

## Conflict report

None. No hunk-level resolutions were needed, so no pret-cited resolution decisions arise from
this merge. Upstream did not touch any of the flagged files independently in this window.

Per-file status for the 22 conflict-risk files (plus `src/core/Data.lua`), verified with
`git diff --quiet 1b8b9b48 1ace9283 -- <file>` (empty means the merged content is identical to the
branch content):

| file | merge outcome |
|---|---|
| src/core/Data.lua | clean — branch version |
| src/core/game3/battle/effects/secondary.lua | clean — branch version |
| src/core/game3/battle/effects/special.lua | clean — branch version |
| src/core/game3/battle/init.lua | clean — branch version |
| src/core/game3/battle/state.lua | clean — branch version |
| src/core/game3/dataset.lua | clean — branch version |
| src/core/game3/map.lua | clean — branch version |
| src/core/game3/objects.lua | clean — branch version |
| src/core/game3/ow_sprites.lua | clean — branch version |
| src/core/game3/player.lua | clean — branch version |
| src/core/game3/runtime.lua | clean — branch version |
| src/core/game3/save_schema_firered.lua | clean — branch version |
| src/core/game3/scripting/opcodes.lua | clean — branch version |
| src/core/game3/scripting/ops_a.lua | clean — branch version |
| src/core/game3/storage.lua | clean — branch version |
| src/import/gba/native_pack.lua | clean — branch version |
| src/import/gba/versions.lua | clean — branch version |
| src/ui/game3/hall_of_fame.lua | clean — branch version |
| src/ui/game3/map_name_popup.lua | clean — branch version |
| src/ui/game3/naming.lua | clean — branch version |
| src/ui/game3/new_game_scene.lua | clean — branch version |
| src/ui/game3/save_menu.lua | clean — branch version |
| src/ui/kit/FileBrowser.lua | clean — branch version |

## Live tree state after the merge (nothing changed by this trial)

- `game3-review-fixes` still points at `1b8b9b48`; a fast-forward to `1ace9283` is available
  when the fix wave quietens down.
- `src/core/game3/objects.lua` in the live worktree now matches merged upstream
  (`diff -u <(git show 1ace9283:src/core/game3/objects.lua) ~/dev/gen1recomp/src/core/game3/objects.lua`
  → no output).
- In-flight teammate edits (5 battle files) and 3 untracked docs were not touched.

## Side finding: the 12 pret-blocked suites now run

With the local `~/dev/pokefirered` clone present, all 12 suites the sweep listed under
"pret checkout `../pokefirered` absent" execute and pass:

| suite | result |
|---|---|
| game3_battle_anims_pret_parity_test | 27 passed, 0 failed |
| game3_corner_prize_test | all passed |
| game3_corner_screen_test | all passed |
| game3_corner_slots_test | all passed |
| game3_import2_mt_ember_collision_test | all checks passed |
| game3_revision_view_test | all passed |
| game3_special_ids_test | all passed |
| game3_stitchimp_alt_layouts_test | all passed |
| game3_stitchimp_braille_text_test | all passed |
| game3_stitchimp_chrome_keys_test | ALL PASS |
| game3_stitchimp_condominiums_test | all passed |
| game3_stitchimp_heal_locations_test | all passed |

These are engine-side suite statuses, not game-mechanics claims, so no pret citation applies.

## Reproduce

```sh
git clone --local ~/dev/gen1recomp <scratch>
git -C <scratch> remote add upstream https://github.com/bryanthaboi/gen1recomp.git
git -C <scratch> fetch upstream dev
git -C <scratch> merge --no-edit upstream/dev   # fast-forwards
```
