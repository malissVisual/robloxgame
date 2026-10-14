# Performance and mobile: audit and fixes (6.13.1)

The game is public and many players are on phones. The owner chose "performance and mobile": smooth on a mid-range
phone, touch controls that work. Nothing could be profiled in Studio from here, so this is a static audit, the safe
fixes it led to, offline counts of what the world build makes, and a measuring tool for the owner's phone.
The owner's steps (Czech) are in [`NAVOD.md`](NAVOD.md).
8.2: the 8.x SANDBOX (the small test world the owner plays now) has its own counts and review in
[section 9](#9-the-8x-sandbox-82).

**How the numbers were made.**
- `python3 tools/perf/world_count.py <luau>` runs the real `World.build()` in the Luau CLI against a Roblox stand-in
  (`tools/perf/world-mock.luau`). It counts per area: parts, shadow casters, lights and SurfaceGuis. It finds 22,851
  parts, close to the ~22,900 the owner's Output prints. NPC bodies and animals are not counted.
- The cars' numbers come from `tools/vehicle-preview/export_fleet.py` (the real factory, 20 stage bodies).

## 1. Streaming

**State.** `Workspace.StreamingEnabled` is a property of the place file, and the project cannot set it:
- `tools/rojo-sync.js` builds every project node as a transparent service node with **no properties**
  (`buildFromNode` passes `{}`), and it never reads `$properties`;
- the project files (`default.project.json`, `zombie-delivery/default.project.json`) do not have any.

Teaching the sync to send typed service properties (Bool, Float, Enum variants in Rojo's MessagePack format) cannot be
tested against the real plugin from here, and a wrong encoding could break the owner's
`node tools/rojo-sync.js zombie-delivery`. So it is a one-time Studio setting instead (NAVOD.md, step 1):

| Workspace property | Value | Why |
|---|---|---|
| StreamingEnabled | on | 22,851 parts: a phone should not hold the whole city |
| StreamingMinRadius | 128 | a car at 60–80 studs/s needs ~2 s of road ahead |
| StreamingTargetRadius | 512 | the atmosphere hides beyond that; less memory on phones |
| StreamOutBehavior | Opportunistic | far parts go even without memory pressure |
| StreamingIntegrityMode | PauseOutsideLoadedArea | pauses only when you would fall through unloaded ground |
| ModelStreamingBehavior | Improved (if offered) | model containers are sent when needed, not at join |

The server still warns in the Output when streaming is off (`Main.server.luau`), and the overlay shows it.

**Client audit.** The client code was already written for streaming:
- world lookups use `FindFirstChild`, or `WaitForChild` with a timeout;
- `Bodies.of` and the pose modules look up bodies and joints again when they are gone;
- the tag users handle both added and removed: BusMapBoard, BusRide, ShopPropMotion, TrafficAnimator's lenses,
  Weather, WorldFx, Secrets.

Fixed:
- **AnimalAnimator:** an animal whose parts streamed out and back in kept its old rig, with a root whose Parent was
  nil, and **never moved again**. It now rebuilds the rig when the root is no longer the model's, and hooks
  `Destroying` once per model.
- **ZombieAnimator:** the zombies are a list kept by `ChildAdded` / `ChildRemoved`, so a streamed-out zombie is
  forgotten. Before, a rig was dropped only on `Destroying`, and every frame called `GetChildren`.
- **CarVisuals:** a car that leaves `Cars` / `BanditCars` (streamed out) is forgotten and its rider let go. Before,
  this happened only on `Destroying`.
- **GarageUi:** a `GaragePrompt` that streams out is dropped from the table, on `DescendantRemoving`.
- **WorldFx:** lights are registered when they stream in and dropped when they are gone (the light budget below).

**Models and network ownership.**
- **Every car stays Atomic** (as before 6.13.1), so it streams out together with the ground under it.
- **An empty car is the server's.** `Vehicles.claim(car)` hands the car's network ownership to its driver's client
  while somebody sits in the driver's seat (only the owner can), and to the server while it stands empty or a
  chauffeur drives it.
  - It runs from the seat's watcher (sit and leave), the spawn, the chauffeur's `handOver`, the repair lift letting
    go, a new kit or gun, StyleWear's decal, and CarCall's rescue / tow.
  - Before, the owner's client kept the parked car. Once streaming is on, a far owner's client loses the ground under
    it, the car falls, and the server reports "Your car sank!" and wrecks it. A first version of this commit made the
    car `PersistentPerPlayer`, which made exactly that case likely; review caught it and it is reverted.
  - Without ownership, the server's movers (still at zero) hold the empty car like a parking brake.
- **The depot** is now a `Model` with `ModelStreamingMode = Persistent` instead of a Folder. It has 274 parts: the hall,
  the JOBS booth, the gear stall with its counters and props, the spawn. Nothing looks the depot up by name or class.
- **Shop counters:** a counter is one part with its ShopPrompt as a child, so it streams as a unit. The clerks are NPCs
  in `workspace.Npcs` (Default mode); the clients find their bodies again when they stream back in. Left as they are.
- Already Atomic: the cars, zombies, street-prop blocks, rooftop shop props, bus stops, alleys, zip lines, docks and
  lost packages. Count: Atomic 161 models, Default 830, Persistent 1.

**Behaviour with streaming on (by design, not bugs).**
- The minimap and the big map show only streamed-in crates and bandit cars.
- A knock is heard only from characters this client has seen join (`Sounds.listenKnocks`).

## 2. Rendering

**Shadows.** `shared/RenderBudget.luau` (`casts`, `shadowFor`, numbers in `Config.Performance`) is the rule. A part
throws a shadow only when:
- its longest side is ≥ 2 studs and its second side ≥ 0.45, so lamp posts (0.5) keep theirs, while rails, strips,
  rods, frames, bolts and small boxes do not;
- and it is not a plate ≤ 0.25 thick lying flat **on the ground** (its middle at most 2.5 studs high: road marks,
  lawns, mats). Raised canopies, awnings and palm leaves high up keep their shadows.

Where the rule is applied:
- in World's `part()` (a do-block, no new top-level local), so CentralPark, LanternGarden, Footbridge, GunRange,
  GearStall, JobsSpot and every `BuildingLooks` Kit get it too (Kit keeps its own exclusions on top);
- in StreetDressing's fallback, BusStops, Shortcuts, ZipLines and the Rental docks;
- in Vehicles' `newPart`, by size only, since a car's thin roof and floor plates make its shadow;
- not at all on the ground tiles, embankments, snow and boundary (`tiled()`) or the curbs.

PolishArt, ModelArt and VehicleArt were already explicit per piece (their checks assert it).

| | before | after |
|---|---|---|
| visible world parts that cast a shadow | 18,209 of 22,751 | **14,088** (−23 %) |
| Downtown | 9,112 | 7,028 |
| mission places | 1,277 | 817 |
| Harbor / Suburbs / Estate | 1,259 / 1,112 / 1,388 | 1,036 / 842 / 1,298 |
| bus stops / crossings | 308 / 360 | 154 / 360 |
| ranch / riding school | 237 / 185 | 197 / 161 |
| a car body's casters (average of 20 stage bodies, 121 visible parts) | 46 | **37** |

Trade-off: thin rails (fences, guard rails) and small trims no longer throw thin shadow lines.

The first version (second side ≥ 0.6, the flat rule at any height) got to 12,704. Review found that it dropped the
shadows of the 0.5 lamp posts, raised canopies (EntryCanopy, the gear stall's awning) and palm leaves.

**Lights.** The built world has **501 lights**: 356 PointLights, 105 SpotLights and 40 SurfaceLights. None casts
shadows (`Shadows = false` everywhere).
- **327 are night lights** (`DayNight.nightLight`): street lamps, windows, shop awnings, the ceiling lights of
  `building()`, the alley lamps, the 26 flares. At runtime the cars add theirs: 2 headlight SpotLights per player
  car, 1 per traffic car (≤ 24), the buses, the bike lamps.
- **New: the light budget** (`client/WorldFx.luau`, `RenderBudget.choose`). Each client lets only the nearest
  **40 within 320 studs** shine; a phone gets **16 within 200** (`Config.Performance`). The choice is made again every
  0.5 s.
  - **Vehicles together:** a vehicle's lights (the model right under Cars, BanditCars, Traffic or Buses) are one unit,
    so its headlights are on together or not at all.
  - **Hysteresis:** a light that shines keeps shining until it is beyond range × 1.15 or ranks past N + 4, so nothing
    blinks at the edge.
  - **Fades:** a light fades in and out over 0.3 s (a Brightness tween, then Enabled off). A broken lamp's flicker
    snaps.
  - A server write that lights one over the budget (Traffic's and Buses' own switching) is put out at the next choice.
  - Every lamp still glows (its part turns Neon); the far ones just light nothing.
  - `tests/renderbudget_test.luau` covers the pairs and the hysteresis at both edges.
- **174 are always on** and outside the budget:
  - interior ceiling lights (estate homes, mission interiors, ~70, ranges 12–100);
  - 24 Kit interior SurfaceLights;
  - 13 tunnel strips;
  - 26 wreck fires (PointLight + Fire);
  - 30 lost-package glows (switched by `client/Secrets.luau`, so they must stay out of the budget);
  - 4 bay lamps;
  - the radio and bridge beacons.

  On top come 16 loot crates (`Items`) and your own night aura (`Weather`).

**DayNight.nightLight:** fine. The server only tags the item and sets its state at registration; every client
restyles at dusk in queues (near first). There are 1,693 tagged instances; their lights now go through the budget.

**Text (SurfaceGui.MaxDistance).** 971 SurfaceGuis in the world, **all** drawn at any distance before; now **104**.
- the name boards: 700 studs;
- the plain signs and the Kit labels: 220 studs, or 100 studs per stud of the board's height when that is more. So
  MOUNT ROT TUNNEL, SUNSET HILLS, the stadium's board, CITY POWER and the Harbor boards stay readable from afar.
  `World.build` hands Config's numbers to Kit (`Kit.SignRange`, `Kit.SignPerStud`), so Kit still loads bare in the
  tools;
- the house numbers, buzzers, mailboxes, FOR SALE plates, bus stop boards and alley signs: 220 studs.

The rest are PolishArt / ModelArt labels (pump displays, warning plates), which those builders own.

## 3. Client CPU: every per-frame connection

There are about 40 (35 always connected, the rest only while something runs). "Lite" means a phone or a tablet
(`client/DeviceBudget.luau`: a touch screen without a keyboard). On lite devices the ranges shrink to 60 % and the
posed bodies to 50 %.

| Module · signal | What it does each frame | Fate |
|---|---|---|
| ArmPose · PreSimulation | aim / carry / gesture poses, players within 180 + active NPCs; **12 cleanup sweeps** | sweeps **once a second** (were every frame); lite range 108 |
| BodyLife · PreSimulation | breath, weight, head, blinks on ≤ 40 bodies within 120 (retarget 0.4 s) | lite: ≤ 20 within 72, detail 30 |
| SprintPose · PreSimulation | run cycle, players within 150 | lite 90 |
| BagSway · PreSimulation | bag pendulum and bag arm, players within 120 | lite 72 |
| ZombieAnimator · PreSimulation | zombie joints within 220; **GetChildren every frame** | event-kept list, R15 known once; lite 132 |
| AnimalAnimator · PreSimulation | horse legs, neck and tail within 180 | streaming fix; lite 108 |
| TrafficAnimator · PreSimulation + RenderStepped | glide traffic cars within 450, wheels within 220 | lite 270 / 132 |
| CarVisuals · Stepped | every car: door / back / trolley prompts, name tag, exhaust, wheels, doors, back, bike lean | **prompts at 10 Hz**; lite 156 / riders 96 / smoke 84; streamed-out cars forgotten |
| ShopPropMotion · Heartbeat (30 Hz) | rooftop props within 700 | lite 420 |
| MapView · RenderStepped | minimap turn and position every frame, routes and markers 20 Hz | lite: routes 10 Hz, **moves at most 30 Hz** (its CanvasGroup redraws on every move) |
| WorldFx · Heartbeat ×2 + BindToRenderStep | restyle queue; beams, beacon, flicker 16 Hz; clock | **+ light budget at 2 Hz** (fades by TweenService); lite flicker range 192 |
| Hud · RenderStepped | speed, health, weapon-line key, guide beam, ring and label (shop and hint already 10 Hz since 5.9.2) | kept: Hud is at the register limit, the frame work is small |
| Weather · RenderStepped | cloud follows the camera; light bars 4.5 Hz; the look 10 Hz | kept (quality-aware since 5.9.2) |
| SoundScape · Heartbeat | footsteps of you + the nearest others (looks at 4 Hz) | kept |
| CameraRig · Heartbeat ×2 + 2 render binds | ram shake, your walk speed and stamina, the camera | kept (yours only) |
| BusRide · PreSimulation + RenderStepped | the walk on and off; the buses glide (few, anchored) | kept |
| CarBoarding, ZipRide · PreSimulation | boarding walks; zip riders within range | kept |
| Drive, CurbRide, Shooting · Heartbeat | your driving, the kerb, firing (return at once when idle) | kept |
| Stamina, WeaponWheel · RenderStepped | breath bar (returns when hidden), held-Q check | kept |
| TouchControls · Heartbeat (10 Hz), RoadEventUi · Heartbeat | touch buttons; the offer countdown | kept |
| PoseLedger · PreAnimation, Animate · Heartbeat | the pose layers' frame start; your own animation choice | kept |
| AdminFly · render bind + Stepped | fly and noclip (return unless an admin turned them on) | kept |
| only while running: Juice, RentalUi, Secrets, Throw, TutorialArrow, BikeRider | count-up, unclip slide, package bob, throw arc, arrow, rider cleanup | kept (disconnect when done) |
| PerfOverlay · RenderStepped (new, only while on) | frames and worst frame | new |

- There is no `GetDescendants` per frame. The ones that remain run once: GarageUi at start, AdminFly's noclip on a new
  character, StylePreview on open.
- Character connections live on the character or humanoid and die with it. The caches keyed by character are swept
  (Bodies, BagSway, SprintPose, BodyLife, ArmPose).

## 4. Server CPU

Every `while` loop waits 0.1–1 s:

| Loop | Wait (s) |
|---|---|
| Traffic | 0.1 |
| Buses | TICK |
| Npcs greet | 0.4 |
| Animals | 0.15 |
| DayNight | 0.25 |
| Fuel | 0.1 |
| Tutorial, Cargo | 0.5 |
| Missions, JobQueue, Crew, Business, Repair, Explore, Tasks, Challenges | their own ticks |
| Admin | 1 |
| Main | 1 |
| PlayerData autosave | its own interval |

The Heartbeat users either accumulate to a tick or do per-entity work that has to run every frame:

| Module | Heartbeat work |
|---|---|
| Jobs | 0.2 s |
| Equipment | 0.2 s |
| Items | 0.25 s |
| Buddy, Rental, Wheelie, ZipLines | their TICK |
| Zombies | ≤ 95 zombies a frame: cheap checks; touch at `TouchEvery`, slow work at 0.2 s, repath on timers |
| BanditCars | steering a frame (physics), think 0.25 s |
| CarCall | the chauffeur's steering |
| Vehicles | boarding, sink check |
| Admin | god mode, admins only |

- **No O(players × zombies × parts) loop.** The widest are O(zombies × cars) at 20 Hz and O(players × crates) at 4 Hz.
- No server change was needed.

## 5. Mobile UI and controls

- `tests/touchlayout_test.luau` now also runs **640×316** (a 640×360 phone under the new top bar) and **712×316**.
  FIRE, SPRINT, the hand button and DRAW are ≥ 44 px, on screen, clear of each other, of the thumbstick, of the jump
  button, of the right column, the actions' row, the ADMIN room, the contextual action and the bottom bar.
- `tests/phone_layout_test.luau` runs the phone and its popups at 640×324 and 640×316: they fit, at a readable scale,
  with ≥ 44 px targets. All pass, with no layout change needed.

Every core action has a touch way:

| Action | Touch way |
|---|---|
| sprint | SPRINT toggle |
| interact | the ProximityPrompts (default style: tap) |
| phone | PHONE action |
| hotbar | 2 slots + MORE, tap |
| aim / shoot | FIRE (auto-aim); tap the weapon line for the wheel |
| draw, punch | DRAW and the hand button |
| put down | the hand button says PUT DOWN, LET GO or SET DOWN |
| drive | Roblox's thumbstick drives the VehicleSeat (Drive reads `ThrottleFloat` / `SteerFloat`) |
| get out | EXIT, or the jump button |
| scooter | WHEELIE (held); Rent and Return prompts |
| zip lines | the Zip prompt; the jump button grabs and lets go (`JumpRequest`) |
| throw | Roblox's THROW action button |
| map | EXPAND on the minimap |
| JOBS and the queue | the JOBS button / phone JOBS (YOUR RUN, NEXT UP, + QUEUE) |
| backpack | phone BAG |

Bigger items, not done:
1. **Windows on a 640-wide phone** are 760×520 at `Ui.MinScale` 0.55, so 12 px text renders at ~7 px. Readable
   phone layouts need a touch minimum scale of ~0.7 and scrolling content per window (DispatchUi, MissionsUi,
   GarageUi, CareerUi, CrewPanel, EstateUi, BusinessUi).
2. **The minimap is a turning CanvasGroup**, which re-rasterizes its whole content on every move. A phone now moves it
   at most 30 times a second. A north-up minimap without CanvasGroup on touch would be much cheaper (a UX choice for
   the owner).
3. The horn (H) has no touch button (not core).

## 6. The measuring tool: the admin's performance overlay

`client/PerfOverlay.luau`, started from `Main`. For admins only (the place's creator or `Config.Admin.UserIds`; in
Studio everybody). Turn it on in the P panel (the ADMIN button on a phone), WORLD tab, **PERFORMANCE · ON**. A small box
at the top shows:
- **FPS** (the last 0.5 s) and the worst frame of the last 5 s;
- CPU and GPU ms per frame, draw calls and triangles (`Stats`, where Roblox lets a script read them);
- client **MEMORY** (and Lua's share) and **PING**;
- **INSTANCES, PARTS, SHADOW parts, LIGHTS** on / all in the workspace. They are counted every 5 s, at most 1,500
  instances a frame, so the count never makes the hitch it measures;
- the night-light budget (shining / known);
- **STREAMING ON/OFF**, PHONE/COMPUTER and LITE/FULL, the screen, the graphics quality, the version.

Its **LITE** button swaps this client between the phone's and the computer's budgets, to compare on one device.
**✕** closes it. Taps go through the box.

## 7. What remains (in order of expected payoff on a phone)

1. **Turn streaming on in the place** (NAVOD.md). Without it a phone loads all 22,851 parts; with it, only what is
   near.
2. **Measure** with the overlay on a real phone (NAVOD.md): FPS, memory, draws, GPU against CPU ms. Decide the next step
   from that.
3. If GPU-bound:
   - try `Lighting.Technology = ShadowMap` if the place uses Future;
   - consider fewer always-on interior lights, or bring them under the budget (they would need a tag of their own,
     and the lost packages stay out);
   - consider fewer wreck fires (26 Fire effects that burn day and night).
4. If CPU-bound: the pose layers are the biggest per-frame Lua. A lower `Config.Body.MaxPosed` and a lower
   `Performance.Lite.Count` are one-line tunings.
5. The phone-sized windows and the north-up minimap (section 5).
6. The PolishArt and ModelArt labels (104 SurfaceGuis) could take a MaxDistance in their builders. Their checks would
   need to know.

## 8. Checks

All pass:
- `luau-lsp analyze`;
- `tests/run_tests.py` (with the new `renderbudget_test`, and every module compiled at `-O0`);
- `phone-ui/check.py`;
- `character-art/check.py`;
- `check-building-looks.py`;
- `polish-art/check.py` street and shops;
- `vehicle-preview/check_fleet.py` (`export_fleet.py` now copies `RenderBudget`).

## 9. The 8.x SANDBOX (8.2)

With `Config.Sandbox.On` the server builds the small test world instead of the city, and the client starts only the
sandbox's systems (`client/Main.client.luau`). None of the city's numbers above apply to it. The owner tests it on
phones, so 8.2 measures it, reviews its per-frame and per-tick code and makes the safe fixes. The owner's steps (Czech)
are in [`NAVOD.md`](NAVOD.md), section "Sandbox (8.2)".

**How the numbers were made.** `python3 tools/perf/sandbox_count.py <luau>` (new) runs the real server code in the
Luau CLI, twice:
- `tools/perf/sandbox-count.luau` on `tools/perf/world-mock.luau` (world_count.py's preparation, with the real
  `server/Npcs.luau`):
  - `SandboxWorld.build()`, folder by folder;
  - the four Moving contracts kiosks (`MoveSites.plotBoard`);
  - the four warehouses (`Warehouse.start()`). The script uses stand-ins for Collection, SandboxPlots and Upgrades:
    four owners, every one of the 20 stands open and full of the 20 heaviest pieces (FurnitureLooks' part count:
    `knight_armour` 28 … `bed` 15; the average piece has 13.3 parts);
  - the house's inside while a move runs (`HouseInterior.build`). It counts the largest of 24 plans: 561–663 parts,
    616 on average;
  - Danny (`Npcs.spawn` of the "mover" look). The stand-in now makes Roblox's classic R15 for
    `CreateHumanoidModelFromDescription`.
- `tools/perf/van-count.luau` on `tools/vehicle-preview/roblox-mock.luau` (export_fleet.py's preparation): the
  sandbox's van (`Config.Sandbox.Van`, the ZDC Sprinter's parts model) with its kit, by day.

`tools/perf/census.luau` counts the same way on both stand-ins:
- parts and MeshParts;
- visible, see-through (0 < Transparency < 1) and invisible parts;
- shadow casters, and the small ones (RenderBudget's size rule: longest side under 2 or second side under 0.45);
- lights: all, on by day, and with Shadows on;
- SurfaceGuis and BillboardGuis, and those drawn at any distance (no MaxDistance);
- ParticleEmitters, Beams, fire / smoke / sparkles, decals, ProximityPrompts.

The client's own 3D (`client/SandboxGuide.luau`: the path's Beams, the chevron) is read from its source. The tool
also prints the models by ModelStreamingMode, and by name the small casters, the see-through parts, the lights that
shine or cast shadows, and the far-drawn SurfaceGuis. Give it an older checkout's `zombie-delivery` folder as a second
argument to count that one.

The worst case is 4 players, every warehouse's 20 stands full, 4 vans, and a move running with the inside and Danny.
It leaves out:
- the players' own avatars;
- the greeters on the porch (each a body like Danny's);
- the owner's Blender imports (the Sprinter, the furniture, the chalet). They hide the parts' looks and add MeshParts;
- the WarehouseUi picker's ViewportFrames: at most `Config.SandboxHud.MaxViews` (12), only while it is open.

**The numbers** (8.2; "→" where 8.2 changed one):

| piece | parts | visible (see-through) | cast shadow (small) | lights: all / on by day / shadows | SurfaceGuis (any distance) | BillboardGuis | prompts |
|---|---|---|---|---|---|---|---|
| the map (`SandboxWorld`) | 964 | 960 (0) | 249 (0) | 0 | 9 (0) | 0 | 0 |
| the four kiosks | 112 | 112 (0) | 20 (0) | 4 / 0 / 0 | 40 (0) | 0 | 0 |
| the four warehouses' halls, 20 stands each | 1,204 | 1,164 (0) | 52 (0) | 24 / 24 / 0 | 140 (0) | 80 | 244 |
| the pieces on show, 4 × 20 | 1,488 | 1,408 (16) | 160 (16) | 0 | 20 (20 → 0) | 0 | 0 |
| one van (Sprinter, stage 0) | 169 | 136 (6) | 58 (10) | 3 / 0 / 1 | 8 (8 → 0) | 0 | 4 |
| the house's inside (largest plan) | 663 | 635 (9) | 157 (14) | 10 / 10 / 0 | 5 (5 → 0) | 0 | 0 |
| Danny | 21 (15 MeshParts) | 20 (0) | 20 (17) | 0 | 0 | 1 | 0 |
| client: SandboxGuide | 0 | | | | | 1 (any distance) | 5 Beams |
| **worst case** | **5,128** | 4,843 (49) | **890** (87) | 50 / 34 / 4 | 246 (**57 → 0**) | 82 (1) | 260 |

The map, by folder:
- Scenery, 563 parts: 112 trees (a trunk and a spire each, the only casters there with the signboards), 198 fence
  posts, 96 wildflowers, 8 street lamps of 4 parts, the signpost;
- Far, 154 parts (Persistent, no shadows);
- Roads, 111 parts;
- TheOldChalet, 109 parts;
- Ground, 23 parts;
- Boundary, 4 parts.

ParticleEmitters, fire and smoke: none anywhere. For scale: the city builds 29,705 parts with 15,355 shadow casters
(`world_count.py`).

**What the numbers say.**
- **Small.** The worst case is about a sixth of the city's parts. The map has no small casters left
  (`SandboxScenery.Shadow`). The 87 small casters are a person's limbs (Danny 17), the vans' trim (10 each: mirrors,
  sills, the cab's cushions and wheel) and a few furniture bits.
- **Lights.** Only the van's bay light casts shadows. It keeps the light inside the van's bay, and it is on only while
  a door stands open, so there are at most 4 of them. By day (the sandbox's fixed afternoon), 34 lights shine: the 6
  hall lamps of each warehouse and the 10 lamps of the house's inside. The kiosks' lamps and the vans' headlights are
  DayNight night lights, so they stay off. `client/WorldFx.luau`'s light budget does not run in the sandbox, and it is
  not needed.
- **Transparency.** There are 49 see-through parts: glass, windows, bottles and lace. 285 parts are invisible: the
  colliders, the pieces' roots, the boundary walls and the parts that hold the halls' floor words.
- **Text.** Before 8.2, 57 of the 246 SurfaceGuis had no MaxDistance, so every client drew them at any distance:
  - each van's 8 fleet labels (the company name, the logos, the plates), seen across the whole map;
  - the furniture's own labels (20 on the stands);
  - 5 inside the house.

  Now all 246 have a MaxDistance. A phone draws each SurfaceGui on its own.
- **Billboards.** Of the 82 BillboardGuis:
  - 80 are the stands' tags. They are enabled only while a piece is on show, and drawn only within 48 studs, so at
    most one hall's 20 at once;
  - 1 is Danny's name tag (60 studs);
  - 1 is the guide's chevron. It is drawn at any distance on purpose.
- **Prompts.** The 244 warehouse prompts are 4 × (20 stands × 3 + the UPGRADES desk). The server enables only the
  ones that apply, and `client/CargoPrompts.luau` hides the other owners' prompts.

**Streaming.** `workspace.StreamingEnabled` is a property of the place. Rojo cannot set it (section 1), so the owner
sets it in Studio (NAVOD.md). The sandbox's code already expects streaming:
- the server streams a player in (`RequestStreamAroundAsync`) before every spawn at a plot, every trip through a
  door, and the walk into the house's inside. That inside is built far off the map (9000, 400, 9000), so only the
  players in it load it;
- SandboxGuide draws its path and chevron on Attachments in the Terrain, which is always there. It reads every place
  from `SandboxMap`. It finds the van again once a second, and loses it while the van is streamed out;
- SandboxSounds hooks every van on `Cars.ChildAdded`, so a van that streams back in is heard again;
- CargoPrompts follows the tag's added and removed signals;
- WarehouseUi, SandboxHud, UpgradeUi and CarryGripUi read only remotes.

Models by ModelStreamingMode:

| | before | after |
|---|---|---|
| the map | Atomic 36 (tree chunks …), Persistent 1 (Far), Default 2 (TheOldChalet, its house) | **Atomic 37**: TheOldChalet streams whole (its door's prompt, the garden, the Blender house with it); its house model inside it is Default |
| the warehouses | Default 4 (the halls), Atomic 80 (the pieces on show) | **Atomic 84**: a hall streams in whole, never half its walls |
| the kiosks | Persistent 4 | Persistent 4 |
| a van, a piece of furniture | Atomic | Atomic |

The map is 680 × 920 studs, and the chalet is about 690 studs from the warehouses. With the radii of NAVOD.md, step 1
(min 128, target 512), a phone at home lets the chalet go, and keeps the inside only while somebody is in it.

**Per-frame and per-tick code of the sandbox's own modules.** The city modules that the sandbox also starts (Hud,
CameraRig, ArmPose, GaitPose, BodyLife, CarVisuals, CarSway, TyreFx, ZombieAnimator …) are in section 3. CarSway
leaves a parked van's body at rest. EnemyOutline, TyreFx, ZombieFx and QuickChat do almost nothing per frame while
idle: a clock check, or an empty list.

The client:

| Module · hook | What it does | Fate |
|---|---|---|
| PairSteer · PreSimulation, every frame | while you carry a piece in two: your heading turns at PairTurn | **8.2:** the usual frame (nothing carried in two) reads one attribute and returns. Before, it looked up the Humanoid and the root every frame. AutoRotate is written only when it changes |
| SandboxGuide · loop every 0.2 s (`Config.SandboxGuide.Every`) | the step, the hint, the path (5 pooled Beams on 6 pooled Attachments), the chevron; the layout once a second while it shows | already pooled: no instance is made after start. **8.2:** the "empty stand" step made a table every look, and now refills one. The target and the path's points are written only when they move |
| CarryGripUi · RenderStepped, only while a check or its outcome shows; `place()` at 1 Hz | the needle, the timer | kept: it makes no tables or strings, and sets a property only when it changes |
| SandboxSounds · events only | the collection's cues, the income clink, the sliding door, the walk-in step (one ray when the floor changes) | **8.2:** the ray's filter table is made once per body, not at every floor change |
| SandboxHud, UpgradeUi · events | the money (Juice's count-up runs only while it counts), the stock chip | kept |
| WarehouseUi · events | at most 12 ViewportFrames, only for the tiles on screen, only while the picker is open; at most 24 models kept | kept |
| SandboxZones · admin only: vans at 1 Hz, stands every 5 s (one `workspace:GetDescendants()`) | SHOW ZONES debug marks | kept (debug tool, only while on) |

The server:

| Loop | Interval | Work | Fate |
|---|---|---|---|
| Moving | the tick at `Config.Moving.Tick` (0.2 s); the walk-in doors between ticks, every `Doors.Every` (0.1 s) | per running move: the rules, the van's prompts (the same values are not sent again), the doors' zone maths, Danny's and the greeters' sync, the state when it changed (0.25 s apart at least, else every 5 s) | kept |
| `SB.frontDoor` | once per move start (kept while the door stands) | one `workspace:GetDescendants()` | kept: it is not a loop |
| Collection payout | `Config.Collection.Tick` (10 s) | per player: settle and pay, O(stock ≤ 300) | kept |
| Warehouse rebuilds | no loop; a collection change refreshes the plot `Config.Warehouse.Rebuild` (0.15 s) later, once | only the stands whose piece changed are rebuilt; one `GetDescendants` per new piece | kept |
| MoveHelper (Danny) | `Config.MoveHelper.Tick` (0.1 s), only while he exists | his brain; a new path only when the goal moves | kept |
| MoveGreeters | 0.4 s | the porch's people | kept |
| SprinterBuild.wire, SandboxPlots, Upgrades | events | | kept |

No server change was needed for CPU.

**What 8.2 changed** (no gameplay, nothing the owner sees):
- `tools/perf/sandbox_count.py`, `sandbox-count.luau`, `van-count.luau` and `census.luau` are new. `world-mock.luau`
  got Roblox's classic R15 for `CreateHumanoidModelFromDescription`, an animation track's Length, and
  `SetStateEnabled`. `world_count.py`'s `prepare` can keep the real Npcs, and resolves two more ways of requiring a
  shared module. Its city count is unchanged (29,705).
- `server/SandboxWorld.luau`: TheOldChalet is Atomic.
- `server/Warehouse.luau` (one line): the hall's Model is Atomic.
- `server/Vehicles.luau` (one line, `SprinterBuild.emit`): the Sprinter's fleet labels have MaxDistance
  `max(Performance.SignRange, SignPerStud × the label's height)`, which is 220 studs for all of them.
- `shared/FurnitureLooks.luau` and `server/HouseInterior.luau` (one line each): their labels and signs have
  MaxDistance `Performance.SignRange` (220).
- `client/PairSteer.luau`, `client/SandboxGuide.luau`, `client/SandboxSounds.luau`: as in the table above.

**Left as it is, on purpose.**
- **The van's bay light keeps its Shadows.** Without them its light would shine through the van's walls onto the
  ground. It is on only while a door is open (4 at most), and phones at lower graphics quality do not draw the
  shadows of local lights anyway. Turn it off if the overlay shows GPU time with the doors open.
- **The shadows of the trees, the chalet, the halls and the pieces on show are kept.** The pieces near the roller
  door catch the afternoon sun.
- **The vans' 10 small casters are kept.** The mirrors, sills and fenders are part of the van's outline, and the cab's
  cushions and wheel are under its roof. They are 40 of 890 casters.
- **The stands' tags are kept.** Each is a BillboardGui sized in studs with TextScaled labels, so its labels re-fit
  as the camera moves. That is at most 20 at once, within 48 studs. If a phone shows UI cost inside a hall, size them
  in pixels or drop TextScaled (`server/Warehouse.luau` `makeTag`); the tag would then stop shrinking with distance.
- **Hud's 10 Hz shop scan still runs in the sandbox.** It checks distances to the city's shops. It is cheap, and Hud
  is at the register limit.

**Checks** (all pass):
- `tests/run_tests.py`;
- `tools/phone-ui/check.py` (with the real SandboxGuide);
- `luau-lsp analyze`;
- `tools/perf/world_count.py`;
- `tools/perf/sandbox_count.py`;
- `tools/vehicle-preview/check_fleet.py`.
