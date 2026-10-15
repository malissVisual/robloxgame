# 8.9.1: the house's fixtures in Blender (the contract)

The owner asked for the house's built-in things in their own Blender model: the kitchen, the bathroom, the Kachelofen
and the garage's things. Today `server/HouseInterior.luau`'s `LOOKS` build them from parts. The new model is
**ZDCFixtureArt** (`design/blender-fixtures/fixtures.py` → `roblox/ZDCFixtureArt.fbx`). The owner imports it once in
Studio, and `server/FixtureMesh.luau` dresses every fixture of every interior with it, the same way `FurnitureMesh`
dresses the furniture.

Owners: the **blender** agent owns `design/blender-fixtures/*` except this file. The **game** agent owns
`src/server/FixtureMesh.luau`, the hook in `src/server/HouseInterior.luau`, `src/server/Main.server.luau`'s import line,
`tests/run_tests.py`, `tools/fixtures-art/*` and the tests. The lead (the main session) owns this file, `COLLAB.md`,
`README.md` and `Config.Version`.

## The fixtures (`shared/HouseLayout.luau`'s plans; every size is fixed)

Each fixture is in its own frame: the origin at the bottom middle of its box, x along the wall (right as you face it
from the room), y up, and the front toward −Z (the room); its back, +Z, is against the wall. `size` is
(along the wall, height, depth). A plan gives `at` (the frame in the house) and `size`; the frame of a wall-hung one
is already at its height.

| kind | size W × H × D | where | what it is today (`LOOKS`) |
| --- | --- | --- | --- |
| `counter` | 4.5 × 3 × 2.6 | kitchen, the side run (2 of them) | cabinet with wooden fronts, a scrubbed wooden worktop |
| `stove` | 3 × 3 × 2.6 | kitchen, between the counters | enamel stove, black glass hob with 2 burners, oven door and handle |
| `sink` | 9 × 3 × 2.6 | kitchen, the front run under the window | the counter's body, a steel basin in the middle, a tap |
| `cabinets` | 4.5 × 3 × 1.4 | over each counter (its frame at y 6.4) | wall cupboards |
| `hood` | 3 × 2.2 × 1.8 | over the stove (its frame at y 7.0) | metal hood, 0.6 high, and its flue up to the ceiling |
| `corner_bench` | 7 × 3.4 × 1.6 | kitchen, the long leg of the Eckbank | plank seat 1.5 high, backrest, a cushion |
| `bench` | 2.4 × 3.4 × 1.6 | kitchen, the short leg (meets the long one in the corner) | plank seat and backrest, no cushion |
| `corner_shelf` | 2.2 × 1.4 × 2.2 | over the corner bench (its frame at y 4.9) | a three-cornered board in its +X, +Z corner, a candle, dried flowers |
| `tub` | 7.2 × 2.2 × 3.4 | bathroom, across the back | white tub, water, tap |
| `toilet` | 1.8 × 3.2 × 2.8 | bathroom | base, bowl, seat, cistern against the wall |
| `basin` | 2.6 × 3.2 × 1.8 | bathroom | pedestal basin and tap; a mirror over it up to y 6.9 (outside its box) |
| `kachelofen` | 6 × 6.6 × 3.2 | living room, on its outer wall | the tiled stove in two tiers under its cornice, an iron fire door with a glowing slot, a wooden bench along its front |
| `workbench` | 6.4 × 3.2 × 2.4 | garage | bench top on 4 legs, a low shelf, a pegboard up to y 5.5 (outside its box), a vise |
| `shelves` | 5 × 7 × 1.6 | garage | metal shelving, 4 shelves, 3 bins |
| `garage_door` | 12 × 8.5 × 0.3 | garage's outer wall | a metal sectional door, closed (a plan's width is `min(12, depth − 8)`: 12 in every house there is; another width keeps the parts) |

A model may reach out of its box only where today's look does: the basin's mirror, the hood's flue (up to the ceiling,
12 over the floor), the workbench's pegboard, the corner shelf's candle and flowers. It never reaches into the room
in front of its box, or into the wall behind (+Z past D/2) by more than 0.05.

## The model (the blender agent)

- `fixtures.py` builds every kind in its exact box, each at its own place in a row (with a nice preview scene: a
  kitchen corner, the bathroom and the living room's Kachelofen), alpine chalet style to match the house: pine and
  painted wood, ceramic tiles, white enamel, brushed metal. Keep it light: at most 3,000 triangles a kind (the
  Kachelofen 4,000; the lead relaxed the first 1,500 once the model came to about 22,000 in all), every piece
  ("<kind>_<finish>") at most 10,000.
- Pieces are named `<kind>_<finish>` (one mesh per kind and finish), as in `design/blender-furniture/furniture.py`'s
  `export_game`. Its markers: `mark_o`, `mark_x`, `mark_y`, `mark_z` (the game's axes: x right = Blender −x, y up =
  Blender z, z back = Blender y; 10 studs each); `mark_<kind>` at each kind's frame origin (the bottom middle);
  `mark_<kind>_box` at its box's corner (W / 2, H, D / 2 in the frame).
- Finishes and their looks are a table in fixtures.py (`FINISHES`) and the same in `FixtureMesh.Looks`. Four finishes
  take the colour the game rolled for that fixture, read from today's parts before they go (a palette):
  `tile` (the Kachelofen's tiles: the part "Stove"), `tile2` (its upper tier: "Upper"), `pine` (the benches' wood: the
  part "Seat", the Kachelofen's "StoveBench") and `cushion` (the part "Cushion"). Every other finish is fixed.
- The manifest `roblox/ZDCFixtureArt.json`:
  ```
  { "fixtures": { "<kind>": { "size": [W, H, D], "pieces": ["<kind>_<finish>", ...], "triangles": n } },
    "pieces": { "<kind>_<finish>": { "kind": k, "finish": f, "center": [x, y, z], "size": [x, y, z], "triangles": n } },
    "details": [ { "kind": k, "name": "...", "finish": f, "center": [x, y, z], "size": [x, y, z] } ] }
  ```
  Every box is in its kind's frame, in the game's axes. `details` lists every object of the model.
- `NAVOD.md` (Czech, like `design/blender-furniture/NAVOD.md`): what it is, how to open and change it, and how to import
  it in Studio (delete an older `ZDCFixtureArt` first, Import 3D, move it to ServerStorage, save, publish).
- `fixtures-preview.png` rendered with Cycles. `fixtures.blend` saved.

## The game (the game agent)

- `server/HouseInterior.luau`: each fixture's parts go into a Model `Fixture_<kind>` (attribute `Fixture` = kind)
  inside the interior's `Decor`, then `FixtureMesh.dress(model, kind, at, size)`. Nothing else in the interior
  changes. Without an import, the house is exactly as today (the same parts, names, colours and collisions).
- `server/FixtureMesh.luau` (`--!strict`, a header like `FurnitureMesh`'s):
  - `FixtureMesh.start()` finds `ZDCFixtureArt` (ServerStorage or Workspace, or a top-level Model holding
    `mark_o` and `mark_counter`), moves it to ServerStorage and reads it once. Read the markers as `FurnitureMesh`
    and `HouseMesh` do, and refuse an import that moved or came out mirrored (8.0.3's checks: three equal right-angle
    marker arms within 2 %, every piece turned alike).
  - `FixtureMesh.dress(model, kind, at, size) → boolean` dresses one fixture when the import has that kind and its box
    (from `mark_<kind>_box`) equals `size` within 0.05. It reads the palette colours from the model's parts first.
    Then it destroys the parts that do not collide, hides the solid ones (`Transparency` 1, no shadow; they keep their
    collision and query), and adds the kind's MeshPart clones (anchored, no collision, no query, no touch) at
    `at * piece`.
  - `FixtureMesh.Looks` holds the finishes. A Neon finish (the fire's glow) stays small: at most `NeonArea`.
- `server/Main.server.luau`: `ZDCFixtureArt` joins the imports moved to ServerStorage first thing (and
  `tests/run_tests.py`'s `imports_first_check` names it).
- `tools/fixtures-art/check.py <luau>` (run by `tests/run_tests.py` like the other mesh checks). It simulates the
  import from the manifest (turned a quarter round, 3 × the size, moved; and a scattered one that must be refused),
  builds real interiors (`HouseLayout.plan` on a few seeds of "house" and "big", `HouseInterior.build`) with the real
  `FixtureMesh`, and checks:
  - every fixture of every kind is dressed, with every piece where the manifest has it;
  - the solid parts are kept and still solid, the others gone;
  - no mesh collides;
  - the model stays in its box (but the allowed reaches above);
  - the interiors stay within their part budgets (`InteriorMaxParts`, `Big.InteriorMaxParts`);
  - Neon stays small;
  - no import, a wrong-sized fixture, a scattered import: the parts as today.
  Until the blender agent's manifest exists, test against one you generate from the table above (plain boxes);
  switch to the real one once it lands (`design/blender-fixtures/roblox/ZDCFixtureArt.json`).
- `python3 tests/run_tests.py <luau>` passes.
