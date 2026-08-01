# Switch hardware evidence (Phase 0 + ROM import)

**Branch / commit at test:** `feat/switch-nx` @ `df7cea4`  
**love-nx:** `11.5-nx1`  
**Console:** Switch OLED  
**Date:** 2026-08-01  
**Operator:** Andrew  

Do **not** commit ROM dumps or private dump hashes.

## Artifact SHA-256

| File | SHA-256 |
| ---- | ------- |
| `gen1recomp.nro` | `8290ac153d4c630e48c9b26ef9123f5204ed8ee0cef3042511707b5b645918f5` |
| `game.love` (probe session, truncated report) | `9f198637…fa2e34f` |

Manifest updated: `scripts/switch/love-nx-11.5-nx1.sha256` (`love.nro` + `love.elf`).

## Phase 0 — probe (T4)

| Field | Value | Pass |
| ----- | ----- | ---- |
| `getOS()` | `NX` | yes |
| `love._os` | `NX` | yes |
| Dimensions | 1280×720 | yes |
| Save directory | `sdmc:/switch/gen1recomp/switch-probe` | yes |
| Touch events | OK | yes |
| Joy-Con | `joystickpressed` + `gamepadpressed` (e.g. Y→`#3`, X→`#4`) | yes |
| Title override / MTP deploy | used per runbook | yes |

## T12 — Red import + Play

| Check | Result |
| ----- | ------ |
| Dump copied to shown `imports/` via MTP | yes |
| “Procurar novamente” started import | yes |
| Game started (Play) | yes |
| Joy-Con launcher + early gameplay | yes (not touch-only) |
| ROM version | Red |

### Deferred defect (input — Phase 3)

On the **player naming screen**, Joy-Con did not reliably select/confirm letters. After extended retries, rival naming eventually became selectable. Track under T13–T16 (`NamingScreen` uses `Input:wasPressed` for A/B/Start/Select/D-pad). Does **not** fail T12 import gate.
