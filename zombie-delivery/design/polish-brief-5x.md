# Brief for Codex: polish for 5.7+ (icons, tower facades, street props, stops, the bus, docks and zip platforms)

5.7 makes the city feel lived in. Claude shipped **simple native versions** of everything below so the game works today:
- the towers' four looks (`src/shared/TowerLooks.luau`);
- the street props (`src/shared/StreetProps.luau` says where, `src/server/StreetDressing.luau` builds them);
- the bus-stop shelters (`src/server/BusStops.luau`);
- the buses (`Vehicles.buildBus`, `src/server/Buses.luau`);
- the ZDC RIDE docks (`src/server/Rental.luau`);
- the zip-line platforms and ladders (`src/server/ZipLines.luau`).

Codex replaces their **looks** with proper art. The places, the prompts and the rules stay Claude's.

Read `zombie-delivery/AGENTS.md` and `COLLAB.md` first. Put your name under "In progress", one branch per group:
`codex/polish-icons`, `codex/tower-facades`, `codex/street-props`, `codex/stops-bus-docks`.

## How (same as your fleet, kit and building work)
- **Native Roblox parts only:** Parts, WedgeParts, Cylinders, Balls. No meshes, no image uploads (except the 2D icons in part 1).
- **Pure-data geometry modules** that a builder renders, like `server/BuildingLooks/*` (`Kit.luau`'s `Blueprint` / `Detail`) and `server/VehicleArt/Geometry.luau`.
  - Claude wires them into the game.
  - Every number must be finite; every module starts with `--!strict` and a header comment.
- **Visual pieces:** anchored, `CanCollide` / `CanQuery` / `CanTouch` false, `CastShadow` off on small parts. Only the pieces this brief calls **solid** collide.
- **Night:** a piece that glows at night is marked `night = true` (the Kit's way). Claude registers it with `DayNight.nightLight`, and every client switches it (`client/WorldFx.luau`). At most the light budget below carries a real light.
- **Look:** the approved style, from `design/location-looks/` and the contract UI: worn, realistic, a restrained palette, red accents (`215, 74, 70`), charcoal metal (`24, 27, 32`).
- **Deliver renders** like `design/vehicle-models/` (sheets + a README), and a checker script if it makes sense (like `tools/check-building-looks.py`).

## 1. Icons (`codex/polish-icons`, the existing format)
White silhouettes on transparent, an SVG source next to each PNG, the sizes of their folders. The ids go into
`src/shared/Icons.luau` (`Icons.Ids`), empty until the owner uploads them.

| Icon | Folder | What |
|---|---|---|
| `map_bus` | `art/map/` (128 × 128) | a bus stop: the front of a city bus, or a stop pole with a bus plate |
| `map_zip` | `art/map/` | a zip line: a trolley on a sagging cable between two posts |
| `map_rental` | `art/map/` | ZDC RIDE: a kick scooter beside a dock bollard |
| `map_shortcut` | `art/map/` | an alley shortcut: a dashed path between two building corners, an arrow |

**The 21 borrowed landmark icons.** These places show another icon today (`Icons.luau`, `LANDMARK_BORROWED`). Each one gets its own `map_<id>`:
- `bank`, `clinic`, `pharmacy`, `warehouse`, `firestation`, `police`, `waterworks`, `lab`, `camp`, `stadium`;
- `luigis`, `dailybread`, `lastbite`, `wokdead`, `grindhouse`, `postoffice`, `dailyundead`, `boltnail`, `volt`, `secondlife`, `bloom`.

Claude removes each one from `LANDMARK_BORROWED` when its id lands.

**The 4 exclusive guns.** They borrow today (`WEAPON_ALIASES`). Each one gets its own `weapon_<id>` in `art/weapons/` (256 × 256, the barrel pointing left):
- `reyes` (a worn carbine with a taped stock);
- `lever` (a lever-action rifle);
- `goldpistol` (a gold-plated pistol: still a white silhouette, the gold is the UI's tint);
- `deadend` (the Dead End rifle: a long scoped rifle with a skull charm).

`tests/icons_test.luau` must still pass.

## 2. Tower facades (`codex/tower-facades`)
Today every Downtown tower is a plain box with window strips (`World.luau` `tower()` and `windowStrips()`), plus one of
four looks of at most 10 parts (`TowerLooks.luau`): a shopfront, a rooftop, a fire escape or boarded windows.

Make **four facade blueprints** in the Kit format, one per look:
- `server/BuildingLooks/TowerShopfront.luau`
- `server/BuildingLooks/TowerRooftop.luau`
- `server/BuildingLooks/TowerFireEscape.luau`
- `server/BuildingLooks/TowerBoarded.luau`

**Their size.** A tower's footprint varies:
- 36 – 43 studs along X and Z;
- 16 – 89 studs tall, with a floor every 9 studs (windows at 9, 18, 27 … over the sidewalk, 3 tall).

So a blueprint must be **parametric**: a function `build(w, d, h, walls)` that returns the details, where `walls` names the street walls (and which one holds an apartment entrance).

**The rules** (the ones `tests/towerlooks_test.luau` checks today; keep them true):
- **Part budget:** at most **30 parts** a tower, **1 light**. The city has about 170 towers; Claude will tell if that is too many for frame time.
- **Low pieces:** nothing under 6 studs reaches more than 0.8 studs out of the wall (the people's walk lines, `shared/TrafficLanes.luau`). An awning or a fire-escape landing reaches out only above 7 studs, at most 3 studs out.
- **The apartment entrance:** nothing within 6 studs (along the wall) of its door below 12 studs (its piers, canopy, buzzer and lamp: `World.luau` `buildEntrance`).
- **Zip lines:**
  - nothing within 6 studs of a zip line's ladder (`shared/ZipLines.luau` `ladderOn`);
  - a zip line's two towers get nothing on the roof;
  - every other roof's things stay at most 3 studs tall (the cables cross above).
- **Window strips:** they stay (they light at night). Frame them, do not cover them, except the boarded look.

Nice to have:
- ground-floor shop bays with roll-down shutters (half down on some);
- cornices and string courses;
- a fire escape with stairs between the landings, a drop ladder;
- water tanks on legs with a conical roof, AC units with a fan grille, a stair bulkhead;
- plywood with spray-painted marks (a red X, "NO ENTRY") on a SurfaceGui text slot.

## 3. A street prop set (`codex/street-props`)
`StreetProps.luau` decides where every prop stands (the same on every server) and `StreetDressing.luau` builds it.
Make a pure-data module `server/StreetArt/Geometry.luau`:

```
pieces(kind, seed) -> { { name, size, at, rotation?, color, material, shape?, solid?, night? } }
```

It is relative to the prop's frame: the origin on the ground at its middle, -Z toward the street, X along the kerb.
The kinds and their **footprints** (the planner keeps them clear of everything; stay inside them):

| kind | footprint (along × across × tall) | solid | budget | notes |
|---|---|---|---|---|
| `bin` | 1.6 × 1.6 × 2.6 | yes | ≤ 6 | a city litter bin; 2 – 3 colour variants by seed |
| `hydrant` | 1.6 × 1.0 × 2.6 | yes | ≤ 6 | the classic red one, caps and chains |
| `barricade` | 4.8 × 1.4 × 2.8 | yes | ≤ 8 | a sawhorse barricade: striped board, legs, a lamp on top (no light) |
| `sandbags` | 4.0 × 1.6 × 1.8 | yes | ≤ 8 | a low wall of bags, two rows |
| `debris` | 3.2 × 2.0 × 0.6 | no | ≤ 6 | broken slabs, a plank, bricks: you walk over it |
| `bags` | 3.0 × 1.8 × 2.2 | no | ≤ 6 | black trash bags against a tower wall (+Z is the wall) |
| `boarded` | 4 – 8 × 0.6 × 6.5 | no | ≤ 8 | plywood leaning on a ground floor (+Z is the wall); the width comes in |
| `car` | 11 × 5 × 4.5 | the hull | ≤ 20 | an abandoned car at the kerb: flat tyres, a broken window, an open door or boot; never wider than 5 |
| `flare` | 1.0 × 0.4 × 0.4 | no | ≤ 3 | a burning road flare; 1 red light (Claude keeps the light, the client flickers it) |

New kinds are welcome. Name them, give their footprint, and Claude adds them to the planner:
- a phone booth;
- a newspaper box;
- a bench;
- a mailbox;
- a traffic cone cluster;
- a burnt-out shopping trolley.

The whole set stays light: today about 530 props cost about 1,200 parts. **Aim for at most 2,500 parts in all.**

## 4. Bus-stop shelters, the bus livery, the docks and the zip platforms (`codex/stops-bus-docks`)
Each one is a pure-data module that Claude's builder renders. Their places, prompts and boards stay as they are.

### A nicer bus-stop shelter (`server/StopArt/Shelter.luau`)
Replaces `BusStops.luau`'s 19 parts. Budget: **≤ 35 parts, 1 light**.
- **Its frame:** on the pad's middle at the kerb, -Z toward the road, X along the kerb (the way the bus drives).
- **Its size:** the shelter stands from the curb to 3 studs in; the people walk 4.5 in. Keep that line clear.
- **Keep these:**
  - the arrivals board: a part named `ArrivalsBoard` with a SurfaceGui text slot named `Arrivals` (`client/BusRide.luau` fills it);
  - the pole sign at the front end (BUS, the lines' coloured chips, the stop's name: text slots `StopName`, `Lines`);
  - the yellow kerb line on the road.
- **Make:** a glass back and sides with a frame, a roof with the line's coloured fascia (a `lineColor` slot), a bench, an ad panel that glows at night (a poster of a ZDC delivery), a bin.

### The bus livery (`server/VehicleArt/BusLivery.luau`)
Pieces welded onto the existing city bus body (`Vehicles.buildBus`).
- **Keep:** its hull, seats, doors and size; check them with `tools/vehicle-preview/check_fleet.py`.
- **Make:**
  - the line's colour band (a `lineColor` slot);
  - a ZDC TRANSIT roof sign;
  - the destination board over the windscreen (text slots `LineNumber`, `LineName`: Claude fills them);
  - wheel arches;
  - mirror arms;
  - grime along the skirt.
- **Budget:** ≤ 40 parts on top of today's body.

### The ZDC RIDE dock (`server/StopArt/Dock.luau`)
Replaces `Rental.luau`'s 8 parts. Budget: **≤ 24 parts, 1 light**.
- **Its frame:** on the kerb, X along it, 2 – 3 slots at `Config.Rental.SlotPitch`, 1.6 in from the curb.
- **Keep:**
  - the scooters' spots (attachments `Slot1` … `Slot3`, where a scooter stands, nose along +X);
  - the sign board facing the street (a text slot `DockName`).
- **Make:**
  - a charging rail with a clamp per slot (a separate part per clamp, named `Clamp1` …: 5.7's unclip animation slides it);
  - a payment post with a small screen;
  - the ZDC RIDE red;
  - a lamp.

### The zip-line platform and ladder (`server/StopArt/ZipPlatform.luau`)
Replaces `ZipLines.luau`'s platform and ladder (26 parts a line). Budget: **≤ 30 parts a platform, ≤ 12 a ladder, 1 light**.
- **The platform:** a `Config.ZipLines.Platform` (7) stud square floor.
  - Its frame: -Z toward the cable, the origin on the floor's middle.
  - A rail on three sides, open toward the cable.
  - A gantry whose crossbar's middle is the cable's anchor (an attachment `CableAnchor`, `CableHeight` 7 over the floor).
  - The start's ZIP sign (text slot `ZipName`).
- **The ladder:** against the street wall, from the sidewalk to the roof (its foot and top given). 5.7 makes it really climbed hand over hand, so:
  - give its rungs every 1 stud (they may be one TrussPart);
  - give a `ClimbTop` attachment where the climber steps off onto the roof;
  - give a safety cage over 10 studs.

## Order of priority
1. **The icons** (the map shows the stops, the docks, the zip lines and the shortcuts with stand-ins today).
2. **The street props** (they are everywhere).
3. **The tower facades.**
4. **The shelters, the bus livery, the docks and the zip platforms.**

Until a module lands, the game keeps Claude's simple version, and Claude swaps yours in when it is merged.
