# Performance: what the sandbox costs to draw (8.2)

The game is public and many players are on phones. This is 8.2's count and review of the sandbox (the game since
10.6), made without Studio: offline counts of what the real server code builds, a review of the per-frame and per-tick
code, and the safe fixes it led to. The owner's steps (Czech) are in [`NAVOD.md`](NAVOD.md).

- **The numbers below are 8.2's**, the alpine meadow's with its chalet and kiosks. The world has changed since (9.0
  the countryside, 10.0 the lobby and the runs). Re-count today's with `python3 tools/perf/sandbox_count.py <luau>`:
  at 10.4 the lobby's map is 1,313 parts (1,414 with the Auction House) of `SandboxScenery.Budget`'s 2,500.
- 10.6: the 6.13.1 audit of the old city (its streaming, rendering, CPU and mobile sections and its counts by
  `tools/perf/world_count.py`) went with the city; it is in git's history up to 10.5.

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

ParticleEmitters, fire and smoke: none anywhere.

**What the numbers say.**
- **Small.** The map has no small casters left
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

**Streaming.** `workspace.StreamingEnabled` is a property of the place. Rojo cannot set it, so the owner
sets it in Studio (NAVOD.md, step 1). The sandbox's code already expects streaming:
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
CameraRig, ArmPose, GaitPose, BodyLife, CarVisuals, CarSway, TyreFx, ZombieAnimator …) were reviewed in the old
city audit's section 3 (git's history up to 10.5). CarSway
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
  shared module.
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
- `tools/perf/sandbox_count.py`.
