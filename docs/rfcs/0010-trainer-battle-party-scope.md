# RFC 0010: Deferred trainer preparation and battle-local party scope

## Status

Proposed.

## Motivation

Challenge and tournament mods sometimes need a player to choose an eligible
subset of the save party before a trainer battle. The current public surface
can replace the opponent through `trainer.party` and observe
`world.trainer_engaged`, but it cannot pause the engagement before battle
construction or keep unselected save-party members out of initial send,
switch, replacement, exhaustion, experience, and party-menu traversal.

Temporarily rewriting `game.save.party` is not a safe substitute: it changes
authoritative save state, composes poorly with checkpoints and other mods, and
can strand excluded Pokémon if a callback or process fails.

## Decision and plan extended

This implements **D-AT-001: battle-local Gym registration without save-party
mutation**, the consuming design decision tracked as capability `AT-SP-001` in
the Adaptive Trainers implementation plan. The plan file is
[`docs/superpowers/plans/2026-08-14-adaptive-trainers.md`](https://github.com/MaxTomahawk/gen1recomp-adaptive-trainers/blob/main/docs/superpowers/plans/2026-08-14-adaptive-trainers.md),
Task 5. The engine delta also extends the additive, guarded public-hook
decision used by RFC 0007 and the screen facade documented in
`docs/modding.md`; it deliberately contains none of the consuming mod's Gym
or party-size policy.

## Exact API delta

Add the guarded hook:

```lua
mod.hooks:wrap("trainer.before_battle", function(next, game, context, continue)
  -- context = { trainerClass, partyIndex, mapId, npcId }
  -- Return true only when the battle has been deferred.
  -- Call continue() for the full save party, or:
  -- continue({ playerPartyIndices = { 2, 4, 5 } })
end)
```

The hook runs after the trainer's challenge text and immediately before the
trainer battle is constructed. A mod may push a registered screen with
`mod.ui.push`, return `true`, and retain `continue` for its confirm/cancel
callback. `continue` is one-shot and returns `false` after the first call.
Returning anything other than `true` without calling it continues immediately
with vanilla scope. With no subscriber, no context or continuation is built.

`playerPartyIndices` is an ordered, one-based list into `game.save.party`.
Valid unique indices create `battle.playerParty` as a battle-local view of the
same Pokémon records; the save party itself is never reordered or replaced.
Malformed or empty scopes degrade to the full party. The view governs initial
send, all battle party menus and targets, voluntary and forced replacement,
exhaustion/blackout checks, participant and EXP.ALL traversal, party counts,
and party-ball presentation. Checkpoints preserve the index list and rebuild
the same view before restoring battlers.

The API sets no maximum, chooses no members, identifies no boss, and contains
no scaling or challenge policy.

## Migration and compatibility

Existing mods change nothing. `BattleState.newTrainer(game, class, index)`
keeps its current behavior; the optional fourth argument is additive. Existing
battle checkpoints without a party scope restore against the full save party.
Wild, Safari, link, and no-mod battles are unchanged.

## Verification

- The catalog-driven hook gate proves empty-chain parity and the guarded hot
  path proves no-mod engagement starts exactly once without allocation.
- A sandboxed fixture mod defers through its public hook facade, inspects the
  data-only context, and resumes once with ordered indices.
- Engine tests cover initial send, party menus, replacement/exhaustion,
  EXP traversal, invalid-scope fallback, and save-party identity.
- Battle-checkpoint tests prove scoped capture/restore and old-checkpoint
  compatibility.

## Deprecation etiquette

Nothing is deprecated. The hook and optional constructor argument are
additive.
