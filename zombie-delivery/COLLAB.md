# Zombie Delivery: the shared task board (Claude Code + Codex)

The rules are in `AGENTS.md`. Keep this file short: one line per task, newest on top. Update it in the same commit as your work.

## In progress
<!-- who · task · files · since -->
- (nothing right now)

## Ready for review
<!-- Codex: branch · what changed · what to test in Studio -->
- (nothing yet)

## Questions / handoff
<!-- notes for the other helper: bugs seen, ideas, "please check X" -->
- Claude → Codex: thanks, `codex/cloud-setup` reviewed (tests pass, `node tools/rojo-sync.js zombie-delivery` starts with 69 instances) and merged. Next ideas are below; put your name on one under "In progress" first.

## Ideas / next
- Icons for the 5 new vans and the exclusive guns (today they borrow other icons, see `WEAPON_ALIASES` in `src/shared/Icons.luau`).
- Map icons for the 15 mission places (they borrow icons, see `LANDMARK_BORROWED` in `src/shared/Icons.luau`).
- A short tutorial for new players: the first job, carrying, the back doors, Q for the weapon wheel.
- More sounds: door open/close, levers (DUO), van horn per van.
- Balance pass: playtest First Shift → Iron Supply with the 3.2 level curve and note what feels slow or too easy.

## Done (latest first)
- Codex · Merge Blades archived to `archive/merge-blades/`, the repository root is Zombie Delivery (`codex/cloud-setup`, merged by Claude). The default branch now has Zombie Delivery (PR #1).
- Claude · 3.3 five more vans, upgrades per car you can see, Quick Hands.
- Claude · 3.2 progression (levels for cars, estate and offices), campaign chain, DUO campaign, back doors loading, HUD restyle.
- Claude · 3.1 challenges, lost packages, exclusive guns and paints, titles, weapon wheel.
- Codex · graphics batch 1 (icons, logo, menu background): branch `codex/graphics`, merged.
