-- Optional ruleset that removes the most notorious Gen 1 quirks while
-- keeping the same formulas.  Not the default.

return {
  name = "modern_clean",
  oneIn256Miss = false,
  critUsesBaseSpeed = true,
  critIgnoresStages = false,
  randMin = 217,
  randMax = 255,
  focusEnergyBug = false,
  -- Gen 2+ style: AI opponents deplete PP and can Struggle when empty.
  enemyUnlimitedPP = false,
}
