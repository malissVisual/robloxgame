# Art-only handoff tools

`server/ModelArt/Builder.luau` consumes a spec (`id`, `pieces`, `attachments`) and **caller-owned target BaseParts**. It welds only decorative pieces, adds named Attachment points to their target parts, and returns `{model, parts, points}`. Call `Builder.destroy(result)` when replacing a skin: points live on caller-owned targets, so destroying only the skin model is insufficient. Missing targets/finishes fail before allocation. Skin parts are always unanchored: their welds follow anchored review roots too, without freezing a caller's rig when those roots are later unanchored. No joints or physics controllers are supplied here.

Each group's pure geometry module exports `ids`, `pieces(id)` and `spec(id)`. Specs also carry review-only `origins` (positions of sample target roots), `camera` and `newRoots` (how many new hidden assembly roots integration needs). Bike specs also declare `reservedParts=2` for the gameplay seat and stable collider; the budget audit includes that reserve. Runtime art does not use those preview fields. All coordinates are studs; forward is -Z, up +Y. Euler rotations use degrees. Roblox cylinders run along local X; size Y/Z is the circular diameter. `finish` maps to the renderer's restrained materials. `night` sets a `NightLamp` attribute: Claude registers these Parts with DayNight. `textSlot` creates a named TextLabel inside the part's `ArtLabel` SurfaceGui for dynamic text.

Run from the repository root:

```sh
python3 zombie-delivery/tools/model-art/export.py zombie-delivery/src/shared/KitArt.luau /path/to/luau /tmp/kit.json
blender -b -t 6 --python zombie-delivery/tools/model-art/render.py -- /tmp/kit.json /tmp/kit-renders --workbench
python3 zombie-delivery/tools/model-art/sheets.py /tmp/kit.json /tmp/kit-renders /tmp/kit-sheet.png 'ZOMBIE DELIVERY / KIT'
python3 zombie-delivery/tools/model-art/rasterize.py zombie-delivery/art/icons/kit_*.svg
```

Python dependencies: Pillow and CairoSVG. Model rendering uses Blender 4.3 (Workbench avoids noise). The exporter uses the repository's rigid-frame/instance recorder to execute the **real builder**, checks each group's independently specified budget and additional handoff constraints, and tests cleanup and missing-target atomicity. It is not a physics simulator or R15 animation test. Budget checks count supplied `newRoots`; character bones already in the rig are excluded. Rendering imports no meshes into Roblox: Blender displays exactly the recorded Part/WedgePart/Cylinder shapes, labels and colors. Glass, material textures and lighting vary in Studio.

Building blueprints additionally use the existing `tools/check-building-looks.py` checker and `BuildingLooks/Kit`. All gameplay placement, colliders, animation, prompts and ownership remain with Claude.
