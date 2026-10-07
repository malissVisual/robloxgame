# Street polish: 9 native kinds

[Sheet](sheet.png) and renders/ show actual factory geometry. Pure data: server/StreetArt/Geometry.pieces(kind,seed,width?).
Coordinates are ground-relative, X along the kerb, -Z toward the street. Pass the planner's prop.width for boarded
shops (clamped 4–8). Three seeded color variants; no Roblox Random, meshes, textures, frame loops or gameplay hooks.

| Kind | Parts | Solid/query behavior |
| --- | ---: | --- |
| bin | 3 | hull solid |
| hydrant | 5 | barrel solid |
| barricade | 6 | board/legs solid; visual amber beacon |
| sandbags | 4 | two staggered rows of native ellipsoids, solid |
| debris | 3 | walk-through slabs, plank, brick |
| bags | 4 | nonblocking trash bags/tie |
| boarded | 4 | nonblocking plywood/red X; Warning text slot |
| car | 16 | solid/queryable hull; flat tyres, broken glass, ajar door, rust |
| flare | 2 | nonblocking; keep Claude's existing single red light and flicker tag |

The actual StreetProps.blocks plan: **534 props / 2,466 parts**. Every rotated piece stays inside the brief's
footprint, including the abandoned car's 5-stud width. No placement or planner changes are made.

Claude wiring: require Geometry and the optional shared PolishArt.Builder; build
`{id=prop.kind,pieces=Geometry.pieces(prop.kind,prop.seed,prop.width)}` in the existing ground/kerb frame. Builder
anchors static pieces, sets only declared solid/query flags, disables CanTouch/shadows and builds named text slots.
Pass DayNight.nightLight in options. Register the existing Flare tag/light on FlareTip; do not add a second light.
The optional builder has a weldTo mode for bus art, and is identical across the three 3D polish branches.

Checks/reproduce from zombie-delivery:

```bash
python3 tools/polish-art/check.py street /path/to/luau design/street-props/geometry.json
blender -b -t 4 --python tools/polish-art/render.py -- street design/street-props/geometry.json design/street-props/renders
python3 tools/polish-art/sheet.py design/street-props/renders design/street-props/sheet.png
python3 tests/run_tests.py /path/to/luau
```

27 factory cases pass native-only, rotated footprint, budget, solid/query, named labels and cleanup audits.
Full suite/Studio-style compilation pass. Review in Studio: pedestrians passing every kind, cars driving around
the abandoned hull, bullets stopping at that hull only, and nighttime flare/beacon behavior. Claude integrates it.
