# Career thumbnails — all 15 levels

100 standalone PNGs cover every one of the **90 unlock entries** in the real `Career.road()` on main `882c11c`, plus every pictured level reward (levels 2–15). The road and rewards in `art/career-thumbnails/manifest.json` are exported from actual Luau, not transcribed from a screenshot.

Open **index.html** in this folder. The offline gallery has level/category/search filters, full-size previews and individual PNG downloads. Unlocks and automatically granted rewards have separate sections. Keep the whole `zombie-delivery/` folder structure when extracting the ZIP so image links work.

## What is in the set

| Images | Contents | Source |
|---|---|---|
| 47 | 9 cars, 11 vehicle stages, 5 bikes/scooters, 4 kit items, 7 gear items, 6 guns, 3 car guns, 2 paint rewards | Exact native geometry recorded from the real factories; rendered in Blender for 2D UI art |
| 12 | Each special job's commissioning business/location | Review concept illustrations reused from `codex/job-thumbnails` |
| 33 | 12 estates/offices, 5 garages, 11 campaigns, on-foot work, 4 danger tiers | Generated scene illustrations based on actual descriptions |
| 8 | Cash, 5 consumables, 2 title credentials | Representative primitive illustrations; these are not exported game models |

All files have Windows-safe names and approximately 16:9 composition. Native renders are 960×540. Generated scenes have their original resolution; there is no baked-in UI title, price, lock badge or count. Credential rewards contain their actual title text.

**The generated scenes are concept artwork, not screenshots or promises of the current Studio environment.** In particular the properties/offices use a more realistic illustration style. Review those before adoption. Consumable primitives exist only in the preview tooling and do not introduce new held objects into the game. Native render materials/lighting are a Blender approximation; primitive shapes, dimensions, placement and base colors come from the actual factory output.

## Handoff to Claude

Nothing in gameplay or UI is changed. No Roblox image has been uploaded and `robloxImage` fields are intentionally empty.

1. Review gallery level by level; the manufacturer/model render should match the game, and campaign pictures should communicate the right story.
2. Upload approved PNGs as Roblox image assets. Record their real IDs in **upload.csv**, then use `rbxassetid://<actual ID>` when wiring the UI.
3. Map with **`kind:id`**, never just the bare ID. Vehicle-stage keys already contain both car and stage, e.g. `stage:van:2`. The ordinary ice cream delivery and special `job:icecream` must remain distinct.
4. Level unlocks describe availability to buy/start, not automatically given possessions. Paints, cash, consumables, shoes/backpack and titles in `rewardEntries` are the granted reward pictures. Counts/amounts must stay live UI text; reuse the cash picture for all amounts.
5. Keep quest/shop guidance from `reward.text` as text. It is a note, not another automatically granted van or shop. Winter's image is the ski lodge destination; its configured pickup remains at the diner.
6. Use the actual runtime Career result for prices, locks, rank, XP and reward counts. The gallery is a dated review snapshot.

## Reproduce / check

From `zombie-delivery/`, with a Luau CLI and matching `luau-compile` installed:

```sh
python3 tools/career-thumbnails/inventory.py /path/to/luau /tmp/career-inventory.json
python3 tools/career-thumbnails/native.py /path/to/luau /tmp/career-native.json
python3 tools/model-art/export.py src/server/KitArt/Geometry.luau /path/to/luau /tmp/career-kit.json
python3 tools/model-art/export.py src/server/BikeArt/Geometry.luau /path/to/luau /tmp/career-bikegear.json
python3 tools/career-thumbnails/objects.py /tmp/career-native.json /tmp/career-kit.json /tmp/career-bikegear.json /tmp/career-objects.json
blender --background --threads 4 --python tools/career-thumbnails/render.py -- /tmp/career-objects.json /tmp/career-renders
python3 tools/career-thumbnails/check.py /path/to/luau
python3 tests/run_tests.py /path/to/luau
```

`native.py` executes temporary copies of the real factories with the repository's Roblox mock. It does not patch gameplay files. The roof rack is isolated from a base Courier Van; the Long Cargo Van already has its own rack, so it correctly adds no second rack. Kit/BikeArt export audits actual welded, massless, non-colliding decoration and budgets.

To rebuild gallery/CSV after approved source art changes, construct a JSON object mapping each asset key to its source classification (`actual-factory`, `concept-business`, `concept-scene`, `representative-art`) and pass it with the fresh inventory to `tools/career-thumbnails/gallery.py`. `check.py` compares all saved road/reward entries against current Luau and checks full image coverage, PNG validity, SHA-256, aspect ratios, Windows names, embedded gallery data and upload mapping. New gameplay unlocks should cause a missing-coverage failure rather than silently reuse an unrelated thumbnail.
