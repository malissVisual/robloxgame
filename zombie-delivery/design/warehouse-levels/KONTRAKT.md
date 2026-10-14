# 8.3 SANDBOX: the warehouse's five levels (the contract)

The owner: "a model of my own warehouse … level 1 to level 5, each upgrade a bigger warehouse with more room, starting
as a garage". 8.0.4 built the five levels in Blender (`design/blender-warehouse`, `ZDCWarehouseArt.fbx`, the owner has
imported it). 8.2 dresses every warehouse in level 4 (`WarehouseMesh`, `Config.Warehouse.ArtLevel`). 8.3 makes the
level a player's own and buyable: the UPGRADES desk gets a **ZDC Warehouse** card (level 1 Garage → 5 Logistics
Center). Every level is its own building (the parts warehouse and the Blender model's level), its own stands.
Players who already have a warehouse (a real save from before 8.3) start at **level 4** (what they have today, nothing
lost); a new player starts at **level 1**.

Everyone works against this file. One owner per file (below); ask the lead (Claude, the main session) before touching
another's file.

## The levels (the numbers: `Config.Warehouse.Levels`, lead)

| Level | Name (in game) | Size W × H × D (H: the front wall) | Door | Roof (rise) | Big stands |
| --- | --- | --- | --- | --- | --- |
| 1 | Garage | 26 × 12 × 22 | 14 × 9.5 | shed (front 12, back 9.5) | 2 |
| 2 | Workshop | 40 × 15 × 30 | 18 × 12 | gable (4.5) | 4 |
| 3 | Storehouse | 58 × 19 × 42 | 22 × 14 | gable (6) | 8 |
| 4 | Big Warehouse | 80 × 24 × 60 | 26 × 16 | gable (8) | 12 (today's) |
| 5 | Logistics Center | 104 × 28 × 84 | 26 × 18 | barrel (10; the game's own parts: a gable of 10 under it) | 24 |

- Every level's front (south) wall is where today's is (SandboxMap's `WALL_Z`, z −130), its door in the middle of it
  (the plot's `door`, `vanSpot`, `unload`, `spawn`, `board` and the UNLOAD HERE bay do not move); the building goes
  back (north) from there: level n's box is `{ x = plot.warehouse.x, y = 0, z = WALL_Z − D / 2, sx = W, sy = H, sz = D }`.
- These are exactly the Blender levels (`design/blender-warehouse/roblox/ZDCWarehouseArt.json`: `size`, `door`,
  `marks.top` = H + rise, for the shed H). **The FBX is not re-exported**: the owner keeps the import they have.
- A big stand is 10 × 10 (`Config.Warehouse.StandSize`: every piece fits). The **More stands** upgrade's small stands
  (8 × 5, +2 a level, +8 at the top) exist from level 4 on (level 4: today's 8 spots; level 5: 8 such spots of its own).
  Below level 4 the More stands card is locked ("Needs the Big Warehouse"). A player's stands:
  `base(level) + (level ≥ 4 ? 2 × moreStandsLevel : 0)` → level 1: 2, 2: 4, 3: 8, 4: 12 … 20, 5: 24 … 32. Stand
  numbers 1 … base are the big ones, base + 1 … the small ones; a level up never makes a stand smaller (a piece on show
  stays where it is).
- A free plot (no owner) shows level `Config.Warehouse.FreeLevel` (1: a garage FOR RENT).

## The upgrade (`Config.SandboxUpgrades`, lead)

- `List.warehouse = { name = "ZDC Warehouse", icon = "🏭", max = 4, step = 1, prices = { 1500, 5000, 12000, 30000 } }`;
  `Order = { "warehouse", "stands", "lights", "engine", "danny" }`. Its upgrade level k (0 … 4) is warehouse level
  k + 1 (0 is not saved: a save without it is level 1).
- `Config.SandboxUpgrades.WarehouseFlag = "warehouseLevelKept"` (written in every save, `PlayerData`) and
  `Config.SandboxUpgrades.WarehouseAttribute = "WarehouseLevel"` (the player attribute: their level 1 … 5, set by
  `Upgrades` whenever their levels change, the client reads it).
- The migration (`UpgradeRules.fromSave`): a real save (money in it) **without** `warehouseLevelKept` gets
  `warehouse = 3` (level 4) on top of what it had; a save with the flag keeps its own; a new player (no save) has none
  (level 1).
- Buying it rebuilds the owner's warehouse at the new level (`Warehouse` listens to `Upgrades.onChanged`); the stands'
  pieces stay on their stands (`Collection.upgrade` as for More stands); the admin's MAX UPGRADES gives level 5, RESET
  level 1 (the stands lost send their pieces to the stock, as today).

## The API (who writes it)

### `shared/WarehouseLayout.luau` (lead)
A **Site** is a Plot with its level: `WarehouseLayout.site(plot | id, level?) → Site` (a copy of the Plot with
`warehouse` set to the level's box and `level` = 1 … 5; level nil or out of range: 4). Every existing function takes a
Plot or a Site; **a plain Plot is level 4** (today's building: every existing caller and test keeps working).
- `WarehouseLayout.levelOf(plotOrSite) → 1 … 5` (a plain Plot: 4)
- `WarehouseLayout.level(n) → { name, size = { W, H, D }, door = { w, h }, roof, rise, stands }` (Config's, clamped)
- `count(level?)` the big stands of a level (nil: 4 → 12); `capacity(level?)` all its stands (big + small spots:
  level 1 → 2, 4 → 20, 5 → 32)
- `stand(site, i)`, `stands(site | id, count?)`, `standAt(site, x, z)`: the level's spots (unchanged shape)
- `standSize(i, level?)`, `fits(i, size, level?)`: stand i of that level (nil: 4)
- `outline(site)` (`top`: H + rise; the shed's H), `inside`, `door(site)` (the level's door width × height),
  `receiving`, `doorPath`, `terminal(site)` (against the back wall's middle on every level, `yaw` 180 as today; the
  Garage's is a smaller desk, 3.6 × 2.4, between its two stands), `bay` (the same on every level), `pieces(site)` (the
  level's building: its walls, its roof, its own lamps and beams under the Blender model's, its stands and small spots,
  desk, signs; the Garage's STOCK board on its west wall)
- `grid(n)` level n's stand grid (`columns, middle, aisle, side, front, gap, receiving, walk`: `walk` the least room in
  front of a stand and past the receiving zone, `side` the room along the side walls, 0 where stands stand against them)
- `WarehouseLayout.Levels` = 5

### `shared/UpgradeRules.luau`, `shared/CollectionRules.luau` (lead)
- `UpgradeRules.warehouseLevel(levels) → 1 … 5`; `UpgradeRules.totalStands(levels)` (the rule above);
  `CollectionRules.standsFor(profile)` = `UpgradeRules.totalStands(profile.sandboxUpgrades)`
- `UpgradeRules.locked(levels, id) → string?` (why it can't be bought now: "Needs the Big Warehouse"); a `Row` gets
  `locked: string?` (and `can = false` when locked); `UpgradeRules.effect(id, level, levels?)` ("Garage · 2 stands",
  "Workshop · 4 stands" …; More stands: "14 display stands" with the warehouse's base)
- `UpgradeRules.WarehouseFlag`, `UpgradeRules.WarehouseAttribute`

### Server (agent "server")
- `server/Warehouse.luau`: builds each plot at its owner's level (a free plot at FreeLevel), rebuilds the plot's
  Model when its owner's level changes (`Upgrades.onChanged`; the claim/free of a plot), keeping the PlotState and its
  prompts' closures working (destroy the old Model, build the new from `WarehouseLayout.pieces(site)`, the shown pieces
  re-placed by `refresh`). The Model gets the attribute `Level` (1 … 5); `workspace.Warehouses` gets the attribute
  `Level<plot id>` for the clients. The desk's prompt follows the desk's turn.
- `server/WarehouseMesh.luau`: `WarehouseMesh.level(plot)` reads the Model's `Level` (Config's ArtLevel only as the
  fallback); `dressNow` checks the level against `WarehouseLayout.site(plot, n)`.
- `server/Collection.luau`: `fits(stand, size, level)` with the owner's level; the "too big for small stand" words with
  `count(level)`.
- `server/Upgrades.luau`: the warehouse card (bought like the others; refused while `UpgradeRules.locked`), the player
  attribute `WarehouseLevel`; the admin MAX / RESET as above.
- `server/PlayerData.luau`: `warehouseLevelKept = true` in the save; `fromSave` does the migration.
- Their runtime tests (`tests/warehouse_runtime_test.luau`, `tests/upgrades_runtime_test.luau`,
  `tests/collection_runtime_test.luau`, `tests/sandbox_e2e_runtime_test.luau` + `tests/runtime/*`).

### Client (agent "client")
- `client/UpgradeUi.luau`: the warehouse card (its effect lines, a locked card greyed with its reason instead of BUY),
  the header's words; the toast after a purchase with the levels.
- `client/WarehouseUi.luau`: `WarehouseLayout.fits(stand, size, level)` with the player's `WarehouseLevel` attribute.
- `client/SandboxGuide.luau`: the stands' places from `WarehouseLayout.stands(WarehouseLayout.site(plotId, level))`
  (cached per plot and level); `shared/SoundPlan.luau` + its caller: the warehouse box of the plot's level
  (`workspace.Warehouses`' `Level<id>`, else 4); `client/Menu.luau`: the warehouse shots at the player's level.
- `tools/phone-ui/upgrades.luau` and the phone-ui check (the window with five cards, a locked one).

### Tools and words (agent "tools")
- `tools/warehouse/mesh-check.py`: every level (1 … 5) dressed on its Site: the model's level box, door and top equal
  the Site's (`outline`, `door`, `sy`), the game's solid parts inside the model's walls and roof, the stands / desk /
  signs / bay clear of the model's details, the lamps' lights just under the model's lamps, nothing of the model in
  the door's way.
- `design/blender-warehouse/NAVOD.md` (Czech, the owner's guide: the levels are in the game now, how to buy them, the
  stands per level, no re-import needed), `zombie-delivery/README.md` (a section), `design/sandbox/TEST-STUDIO.md`
  (what to test).

## Rules
- `--!strict`, the header comments, the code style of the file you are in; numbers in `Config.luau`.
- `python3 tests/run_tests.py <luau>` must pass before you hand over; say which tests you changed and why.
- Do not edit another owner's files; write what you need from them to the lead.
