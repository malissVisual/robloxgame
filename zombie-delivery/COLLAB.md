# Zombie Delivery: the shared task board (Claude Code + Codex)

The rules are in `AGENTS.md`. Keep this file short: one line per task, newest on top. Update it in the same commit as your work.

## In progress
<!-- who · task · files · since -->
- (nothing right now)

## Ready for review
<!-- Codex: branch · what changed · what to test in Studio -->
- Codex · `codex/cloud-setup` (base `7c0788d`, 2026-10-05) · Merge Blades archived unchanged in `archive/merge-blades/`; root project/README/Mac launchers target Zombie Delivery; both AGENTS files updated. Verified 12 test files, compilation of 61 modules, builds of both games and full sync tree via `node tools/rojo-sync.js zombie-delivery` from repo root; shared script and game code unchanged. Studio: connect with the same command and Play; also check the root Mac sync-only launchers (no automatic pull/plugin installation; originals preserved in archive).

## Questions / handoff
<!-- notes for the other helper: bugs seen, ideas, "please check X" -->
- Claude → Codex: welcome! If you have changes sitting uncommitted in the owner's local copy, please commit them to a branch `codex/<topic>` and list them under "Ready for review". Claude will review and merge them.

## Ideas / next
- Icons for the 5 new vans and the exclusive guns (today they borrow other icons, see `WEAPON_ALIASES` in `src/shared/Icons.luau`).
- Map icons for the 15 mission places (they borrow icons, see `LANDMARK_BORROWED` in `src/shared/Icons.luau`).
- A short tutorial for new players: the first job, carrying, the back doors, Q for the weapon wheel.
- More sounds: door open/close, levers (DUO), van horn per van.
- Balance pass: playtest First Shift → Iron Supply with the 3.2 level curve and note what feels slow or too easy.

## Done (latest first)
- Claude · 3.3 five more vans, upgrades per car you can see, Quick Hands.
- Claude · 3.2 progression (levels for cars, estate and offices), campaign chain, DUO campaign, back doors loading, HUD restyle.
- Claude · 3.1 challenges, lost packages, exclusive guns and paints, titles, weapon wheel.
- Codex · graphics batch 1 (icons, logo, menu background): branch `codex/graphics`, merged.
