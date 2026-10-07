# Tower facades — 5.8 art handoff

Four native Kit blueprints; World keeps its shell, luminous window strips, apartment entrances and all gameplay.

```luau
local build = require(server.BuildingLooks.TowerShopfront) -- or Rooftop / FireEscape / Boarded
local blueprint = build(w, d, h, {
    {nx=0, nz=-1, door=0, ladders={-10}, zipRoof=true},
    {nx=1, nz=0, ladders={}},
})
Kit.build(parent, towerGroundFrame, blueprint, context)
```

`w,d`: 36–43; `h`: 16–89. Origin is ground centre; one or two distinct cardinal street walls. `door` and each `ladders` coordinate are along **world-local X for Z walls, Z for X walls**. Supply every street entrance/ladder, and set `zipRoof` on either wall whenever this tower owns a zip endpoint. Claude's World/TowerLooks adapter supplies this metadata; these modules are intentionally not wired in.

Ground shop bays have glass, a part-down ribbed shutter, red-edged canopy and pickup plate. Courses frame existing window strips. Rooftop furniture includes a stepped native cylindrical tank cap, AC grille and stair bulkhead; all stays below h+3. The fire escape is a narrow two-level access stair at the window-free corner, with a drop-ladder silhouette. Boarded patches use plywood, wooden braces and `X / NO ENTRY` SurfaceGui labels. These are cosmetic access details; Claude retains climb mechanics.

Protected features are omitted before emission. Low trim extends ≤0.8; larger overhangs start ≥7 and extend ≤3. Door bays remain clear ±6 below12; ladder bays ±6 at every height. Roof furniture is omitted entirely for zip roofs. Kit's decoration now explicitly sets Massless; new details set transparency=0 to suppress small-part shadows. All decoration is anchored/non-colliding/non-queryable/non-touchable, one optional shop light, registered through the provided nightLight callback.

Audited maximum counts: Shopfront 22, Rooftop 22, FireEscape 28, Boarded 26. The test grid contains 192 actual Kit builds (all four orientations; small, medium and tall footprints; doors at -12/0/+12, ladders at -12/-10/+12 and empty cases). Rotated bounds, strip visibility, entry/ladder/roof clearance, finite data, part/light budgets, cleanup and instance flags passed. Existing TowerLooks tests and the full O0/g2 compile suite passed.

The Blender sheet/renders show the exact emitted native geometry on an explicitly marked **reference caller shell and window strips**. Reference parts are not authored, not counted, and not instantiated by the blueprints. Workbench previews do not simulate Roblox night lights, text surfaces or gameplay. Please check a protected Downtown tower, all cardinal walls and the zip landing in Studio during integration.

Regenerate from zombie-delivery/:

```sh
python3 tools/polish-art/check.py towers /path/to/luau design/tower-facades/geometry.json
blender -b -t 2 --python tools/polish-art/render.py -- towers design/tower-facades/geometry.json design/tower-facades/renders
python3 tools/polish-art/sheet.py design/tower-facades/renders design/tower-facades/sheet.png
python3 tools/check-building-looks.py /path/to/luau
python3 tests/run_tests.py /path/to/luau
```
