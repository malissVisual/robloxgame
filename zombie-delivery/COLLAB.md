# Zombie Delivery: the shared task board (Claude Code + Codex)

The rules are in `AGENTS.md`. Keep this file short: one line per task, newest on top. Update it in the same commit as your work.

## In progress
<!-- who · task · files · since -->
- Claude · building the Postage & Trouble UI (Codex's concept) into the game · client/Theme, Ui, Hud, MapView, MissionsUi, GarageUi, CrewPanel, new DispatchUi and the other windows · 2026-10-05

## Ready for review
<!-- Codex: branch · what changed · what to test in Studio -->
- (nothing yet)

## Questions / handoff
<!-- notes for the other helper: bugs seen, ideas, "please check X" -->
- Claude → Codex: thanks, `codex/cloud-setup` reviewed (tests pass, `node tools/rojo-sync.js zombie-delivery` starts with 69 instances) and merged. Next ideas are below; put your name on one under "In progress" first.

## Ideas / next
- **For Codex (the owner asked):** signs and looks for every building — the brief with the full list is `zombie-delivery/design/buildings-brief.md`. Start with the depot and the 5 shops.
- Icons for the 5 new vans and the exclusive guns (today they borrow other icons, see `WEAPON_ALIASES` in `src/shared/Icons.luau`).
- Map icons for the 15 mission places (they borrow icons, see `LANDMARK_BORROWED` in `src/shared/Icons.luau`).
- A short tutorial for new players: the first job, carrying, the back doors, Q for the weapon wheel.
- More sounds: door open/close, levers (DUO), van horn per van.
- Balance pass: playtest First Shift → Iron Supply with the 3.2 level curve and note what feels slow or too easy.
- Map icons for the repair shop and the garages (they borrow `map_mechanic` and `map_dealer`, see `LANDMARK_ALIASES`).
- Mechanics at the repair bays (an NPC with a wrench, sparks) while a car is on the lift: cosmetic, `server/Repair.luau`.

## Done (latest first)
- Codex · Postage & Trouble UI concept (`codex/ui-concept`, design/ui-concept/), reviewed and merged by Claude; Claude builds it into the game next.
- Claude · 3.5 van stages and a real dealership: the Cargo Rack is gone, every car has stages bought at Wrench Garage (a STAGE card with before → after) that change its look (server/Vehicles.luau `LOOKS`): the Old Van Rusty Van 2 → Work Van 3 → Cargo Van 4, the other cars a role and 1 – 2 stages (the Box Truck 6 → 8 is the only way to 6+); jobs and missions retuned (★ ≤ 2, First Shift ≤ 3, Code Red / Empty Shelves ≤ 4, a few big loads for the Box Truck); Dead End Motors sells from a catalog at the counter with three display cars inside (no lot outside); a 3.4 save's cars became the stage that holds the slots they had (capacity + rack; up to the car's most room). Test in Studio: buy the Work Van and the Cargo Van on the Old Van at Wrench Garage (the car rebuilds where it stands, load 3 / 4 pieces through the back), paint it, MAX UPGRADES + STAGES in the admin panel, the showroom's Look prompts and the Car catalog counter.
- Claude · 3.4 cargo capacity (Old Van 4, High-Roof / Box Truck 6, the Cargo Rack +1 a level on a visible roof rack; jobs and missions too big for your car are locked), the repair shop (bays in Wrench Garage and the new Rust Bridge Repairs, 20 – 60 s, $20 – $300, damage kept per car, no free repairs), garages you earn (the depot holds the starting van, Rented Lockup at level 2, Southside Garage at 4; switch cars only at your 🅿 GARAGE posts). Test in Studio: drive a damaged van into a Wrench Garage bay and get out; buy the Rented Lockup, then the Courier Van, and take it out there; a ★★★ bulk order with the Old Van.
- Codex · Merge Blades archived to `archive/merge-blades/`, the repository root is Zombie Delivery (`codex/cloud-setup`, merged by Claude). The default branch now has Zombie Delivery (PR #1).
- Claude · 3.3 five more vans, upgrades per car you can see, Quick Hands.
- Claude · 3.2 progression (levels for cars, estate and offices), campaign chain, DUO campaign, back doors loading, HUD restyle.
- Claude · 3.1 challenges, lost packages, exclusive guns and paints, titles, weapon wheel.
- Codex · graphics batch 1 (icons, logo, menu background): branch `codex/graphics`, merged.
