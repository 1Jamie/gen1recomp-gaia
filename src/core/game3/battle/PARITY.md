# Game3 battle core — ownership & pret target

Owned under `src/core/game3/battle/`. **No** live `require` of KR `battle/core` or host `Battle` / `BattleState`.

## Goal

Replicate pret FireRed/LeafGreen battle behavior. KR `mods/Kanto-Reforged/battle/core/effects/*` is a **port farm** for adapter-pure handler bodies only. **ROM `gBattleMoves[].effect`** (extracted pack) is the dispatch key via [`effect_ids.lua`](effect_ids.lua) `STATUS_SETUP` / `AFTER_HIT` / `STAT_CHANGES`.

## Layers

| Layer | Status |
|-------|--------|
| Rules / capabilities / type chart / damage | Owned MVP (Gen3-shaped) |
| Residuals scheduler + status/weather/seed/trap/perish/wish | Owned |
| Effect registry (FRLG-legal; KR-sourced bodies) | Growing; ROM effect-byte driven |
| Turn / commands (FIGHT/BAG/POKéMON/RUN) | Owned; BAG/switch placeholder |
| UI | ROM chrome extract + pret layout (healthboxes, textbox panels, 2×2 cursors) |
| Battle anims | **Owned MVP**: pret IR extract + ANIM_TAG PNGs → VM; template callbacks (HitSplat, RoarNoiseLine, …); stub rare AnimTask_* |
| Battle intro / send-out | **Owned MVP**: `intro_seq.lua` (BeginBattleIntro); ROM trainer pics + class/name; pret-timed ball send-out host tweens; party summary bar. Deferred: battle_transition mugshot/VS, shiny anim, doubles, real affine emerge / scanline BG slide |
| EXP / level-up | **Owned MVP**: ROM `expYield` + `growthRate`; pret tables; Cmd_getexp; EXP bar; **learn-move** (ROM learnsets, YES/NO forget, HM block); **EVO_LEVEL** after win (Everstone). Exp.Share split per pret Cmd_getexp. Deferred: stones/trade/friendship evo, evo animation, Summary forget UI |
| ROM `gBattleMoves` extract | Owned (`data/generated/gba/pokemon/battle_moves.lua`) |
| Base stats / abilities on battlers | From species pack; ability effects in [`abilities.lua`](abilities.lua) |
| Held items | [`held_items.lua`](held_items.lua): pret hold effects (berries, Leftovers, Focus Band, Choice Band, type boosts, King's Rock, Shell Bell, Quick Claw, Smoke Ball) |

## Battle anim architecture

- **Host** [`anim.lua`](anim.lua): present state (ox/oy/alpha/z), HP display tween + `onComplete`, composite `busy()`
- **Event sequencer** [`anim_seq.lua`](anim_seq.lua): plays the adapter event stream (msg / move / anim general·status·special / hit / hp / faint / switch / end) in pret battle-script order; Battle Scene OFF follows Cmd_attackanimation / Cmd_playanimation / Cmd_statusanimation
- **VM context** [`anim_ctx.lua`](anim_ctx.lua): gAnimMovePower / gAnimMoveDmg / gAnimFriendship / gWeatherMoveAnim / gAnimDisableStructPtr / behindSubstitute filled at every launch
- **Intro sequencer** [`intro_seq.lua`](intro_seq.lua): bgslide → slide-in → party summary → msgs → send-out → healthbox (pret `BeginBattleIntro` + `DoPokeballSendOutAnimation` host tweens — **not** catch `Special_BallThrow`)
- **EXP sequencer** [`exp_seq.lua`](exp_seq.lua) + [`experience.lua`](experience.lua): faint → award → gained text → bar fill → level-up → [`learn_move.lua`](learn_move.lua) (ROM learnset)
- **Evo sequencer** [`evo_seq.lua`](evo_seq.lua) + [`../evolution.lua`](../evolution.lua): after win, `EVO_LEVEL` from ROM evolutions.lua → learn moves at level for new species
- **VM** [`anim_vm.lua`](anim_vm.lua): portable IR opcodes; **`isReversed`** on enemy attackers; palette shader draw
- **Pools** [`anim_sprites.lua`](anim_sprites.lua) / [`anim_tasks.lua`](anim_tasks.lua): fixed 128 sprites + 48 tasks (no GC churn)
- **Extract** → `pokemon/battle_anims/pack.lua` (named template/task IDs, not live ROM pointers)
- **Palettes** [`anim_pal.lua`](anim_pal.lua): every ANIM_TAG sheet also ships as a 4bpp index PNG + its gBattleAnimPaletteTable colours (`tags[T].pal`, `tagPals`); per-tag unfaded/faded palettes live in `AnimPal`, and rotations / LoadPalette / greyscale / allocated palettes write real indices; sprites and anim BGs draw through a palette-lookup shader (RGBA PNGs remain for other consumers)
- **Anim BGs** `pack.animBgs`: the 27 gBattleAnimBackgroundTable entries plus task-loaded BG1/BG2 layers (ATTRACT, SCARY_FACE_*, MORNING_SUN, METAL_SHINE, CURE_BUBBLES, CURSE, FOG, SANDSTORM, SURF_*; `bgPals.MUDDY_WATER`), drawn with exact BLDALPHA eva/evb; mon-window masks go through `present.statMask`
- Unknown `AnimTask_*` stub to 1-frame finish so scripts reach `end`
- Headless / `runToEnd`: VM + tweens instant-complete

## Dispatch

1. `Moves.get(id)` merges ROM row (power/type/accuracy/pp/**effect**/…).
2. Status/setup: `EffectIds.STATUS_SETUP[effect]` → registry handler.
3. Stat ups/downs: `STATUS_SETUP` → `EXP_STAT_FROM_EFFECT` + `STAT_CHANGES[effect]`.
4. Damaging secondaries: `AFTER_HIT[effect]`.

Gen4+ MODERN leftovers (Stealth Rock, Toxic Spikes, Trick Room, Aqua Ring, Tailwind) are **not** registered.

## Pret 1:1 (later pass)

- Exact damage formula / crit / accuracy / damage variance from pret
- Remaining move effects (two-turn, OHKO, multi-hit polish, Metronome/Mirror Move/Sleep Talk, …)
- Fill visual-task long tail; full ANIM_TAG bank from ROM; BG affine / monbg fidelity
- Trainer AI scripts
- Double battles out of scope until singles match

## Wire-in

`BattleBridge` → `Battle.start` (session party only). Scripts wait on `nativePoll`.
