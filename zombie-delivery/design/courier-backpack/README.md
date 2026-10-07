# ZDC Courier Backpack — 5.8

Compact charcoal courier pack matching the approved courier: reinforced base/lid, rear pocket, muted red band, zip and pull, ZDC plate, front shoulder straps/buckles, carry tab. Thirteen native visual Parts, fourteen with the carried parcel. No meshes or uploaded images.

`KitArt/Geometry.pieces("backpack")` and `backpack_loaded` supply the refreshed art; all other kit variants remain available. The existing `KitWear` / `KitFit` event-based body fitting and UpperTorso welds already consume this geometry after merge. Claude reviews this art branch and merges; it is not yet on main. Profile ownership, capacity, prices, jobs, cargo logic and avatar joints are unchanged. `Geometry.load()` is unchanged; the new lid clears the parcel rather than intersecting it.

## Native Studio file

`ZDC-Courier-Backpack.rbxmx` is an actual XML Roblox **Accessory**, with BodyBackAttachment, invisible massless Handle and thirteen native visual Parts welded to it. Import with Studio's Insert from File, or drag the model file into Studio. For a nominal block R15 test rig, add it via `Humanoid:AddAccessory(accessory)`. BodyBackAttachment is at the nominal torso's rear face, Z=.7; use KitWear/KitFit for the game's actual/scaled avatars. Do not wear the standalone accessory alongside KitWear's pack or you will see both.

Every visual part is unanchored/massless/non-colliding/non-queryable/non-touchable and follows the torso; only the main pack body casts a shadow. There are no scripts inside the asset. A direct Studio import/mount/animation check is still needed; the XML and factory audits do not simulate Roblox engine physics.

## Review / regeneration

`renders/backpack.png` shows the exact native pack. `renders/courier-backpack-worn.png` shows it on an explicitly marked **reference R15 mannequin**; the mannequin is a Blender review aid, not an authored avatar included in the accessory. Neither image is an image-generation concept.

```sh
python3 tools/model-art/export.py src/server/KitArt/Geometry.luau /path/to/luau design/courier-backpack/kit-audit.json
python3 tools/model-art/export_backpack.py design/courier-backpack/kit-audit.json design/courier-backpack
blender -b -t 2 --python tools/model-art/render.py -- design/courier-backpack/render.json design/courier-backpack/renders --workbench
python3 tests/run_tests.py /path/to/luau
```

The real Builder audit verifies all six kit variants, part budgets, finite geometry, hip/arm envelope, target welds, instance flags, cleanup and missing-target atomicity. The accessory roundtrip verifies fourteen Parts including Handle, thirteen valid welds, mount, labels and no meshes; parcel/lid clearance passes. Full tests and O0/g2 compile pass.

Claude's Studio review: fresh Courier Backpack outfit, visible loaded parcel, torso scaling, walking/running, seating/boarding, death/respawn and the exported accessory on a nominal R15 rig. Config.Version is left for the merger.
