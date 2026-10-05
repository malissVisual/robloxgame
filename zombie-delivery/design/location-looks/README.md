# Cinematic locations — approved architecture, Roblox implementation

The owner approved `approved-preview.png`: restrained concrete, charcoal metal,
brick and glazing, narrow red accents, practical warm lights. The reference is a
concept sheet; the actual map, functional layout and existing business signs stay
those of Zombie Delivery 4.0.4. No real-world brands or imported meshes are used.

## Review branches

Merge the shared foundation `codex/location-kit` first. Each building branch is
based on that same foundation and changes just its own World builder and blueprint:

| Branch | Building | Studio check |
| --- | --- | --- |
| `codex/location-depot` | Zombie Delivery Co. | JOBS, garage switch, spawn, Marge, van exit |
| `codex/location-dealer` | Dead End Motors | Glass showroom, three display cars, catalog counter |
| `codex/location-guns` | Lead & Co. | Door and counter, wall racks, readable sign |
| `codex/location-mechanic` | Wrench Garage | Drive into both repair bays, timer signs and tools |
| `codex/location-supplies` | Last Stop Supplies | Awning, doorway, shelves and counter |
| `codex/location-warehouse` | Harbor Warehouse | Three open doors, both freight docks, pallet jacks, forklift secret |

`codex/locations-preview` combines these branches for the owner's local Studio
preview. Review the individual branches; the combined branch is not a release.
Claude handles merging and the version bump according to `AGENTS.md`.

## Runtime

`src/server/BuildingLooks/Kit.luau` uses World's existing `part` and `deco`
helpers once during world construction. Decorations are anchored, have no
collision, touch or query, and add no frame callbacks. Lighting uses the existing
DayNight registry; at most two additional PointLights per building. Each blueprint
adds at most 80 simple parts. Gameplay geometry, prompt objects, car positions,
repair zones, cargo piles, loading docks and secrets remain in World.

The warehouse blueprint takes the actual door positions from its builder rather
than re-creating the map coordinates. Its three doors remain open as in 4.0.
The original uploaded `sign(..., id, artHeight)` calls are retained.

## Validation

From the repository root (substitute your Luau executable):

```sh
python3 zombie-delivery/tests/run_tests.py /path/to/luau
python3 zombie-delivery/tools/check-building-looks.py /path/to/luau
node tools/rojo-sync.js zombie-delivery
```

The building check executes the pure blueprints with Luau and validates part/light
budgets, finite data, footprints, door heights and name-board clearance. Studio
Play is still required to assess the appearance, day/night readability, traffic,
all prompts and the freight workflow with a truck.

For a local place preview, build with Rojo:

```sh
rojo build zombie-delivery/default.project.json -o zombie-delivery-locations.rbxl
```

Open that place in Roblox Studio and press Play: World constructs the city at
runtime. This is a separate local test place; it does not update the published
game or the owner's saved place. The owner's usual live-sync command is unchanged.
