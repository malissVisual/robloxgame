# Cloud verification — six combined locations

Base: `main` / `95a8117`, Zombie Delivery 4.0.4. Review foundation
`codex/location-kit` and the six individual `codex/location-*` branches in README.
`codex/locations-preview` merges those branches for a local Studio test place.

Verified on 2026-10-05 with Luau 0.741 and Rojo 7.4.4:

- Existing suite: 22 logic test files, 483 reported checks; every test passed.
- Every source module compiles at Roblox's `-O0 -g2`, both individually and combined.
- Building validator executes all six blueprints and the real renderer with a
  property-recording mock: 159 anchored noncolliding details, finite data,
  original-footprint limits, full doorway heights, name-board clearance,
  at most two extra PointLights per building, labels and night registration.
- Part counts: depot 24, dealer 23, guns 29, mechanic 29, supplies 21, warehouse 33.
- An exact comparison with the original World source after removing the scoped
  facade additions and palette edits confirms every original gameplay line,
  uploaded sign call, prompt, car display slot, repair bay and freight call remains.
- The root `node tools/rojo-sync.js zombie-delivery` passes HTTP MessagePack
  handshake/read: protocol 5, 97 instances, all seven BuildingLooks modules with source.
- `rojo build zombie-delivery/default.project.json` produces a 1,164,347-byte
  `zombie-delivery-locations.rbxl` local place.

Roblox Studio is unavailable in this cloud. No live appearance or gameplay test
has been performed. Claude's Studio review should cover the interactions listed
in README, vehicle clearances, day/night lights and signs, and the two freight
loading docks with a truck. The delivered place builds the map when Play starts.
The published game and `main` have not been changed by this work.
