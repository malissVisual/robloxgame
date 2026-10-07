# Transit / dock polish — 5.8 art handoff

Pure native Parts, Cylinders and a native TrussPart; no meshes or uploaded images. Claude integrates these specs; this branch does not edit BusStops, Buses, Rental, ZipLines, Vehicles or any other gameplay module.

```luau
local spec = Shelter.build(line.color, stop.name, "1 / 3")
local art = PolishBuilder.build(parent, curbFrame, spec, {lineColor=lineRgb, nightLight=DayNight.nightLight})
```

All static parts are anchored/massless/non-colliding/non-queryable/non-touchable with small shadows off. **Keep the current invisible load-bearing / climbing geometry**, prompts and client metadata. Art's frame/attachments are placement contracts, not new gameplay. Destroying the returned Model cleans its surfaces, lights and attachments.

| Module / function | Frame and integration contract | Actual parts |
|---|---|---:|
| `StopArt/Shelter.build(lineTriple, stopName, linesText, routeColors?)` | Origin curb/pad middle; -Z road, +Z sidewalk. Shelter/back glass reaches at most +3, leaving the +4.5 walk line clear. Roof fascia uses lineColor; optional 1–3 route-colour chips sit below the Lines text (default one chip in the primary line colour). Keep `ArrivalsBoard` → `PolishLabel.Arrivals`, `StopPlate` → `StopName` / `Lines`, and `KerbLine`; Claude adapts the existing BusRide board lookup. ZDC poster, ribbed frame, bench, bin and one ceiling light. | 33–35 |
| `StopArt/Dock.build(slots, Config.Rental.SlotPitch, dockName)` | 2–3 slots; centered X spacing, Z=1.6 and Y=0, scooters nose +X. Mounts `Slot1..3` sit on `Bollard1..3`; do not add a second scooter offset. `Clamp1..3` are separate red locking parts; animate those parts only (the black `ContactShoe` stays fixed). DockName is on `DockBoard`, alongside the ZDC RIDE brand. Payment screen + one red lamp. | 14 / 17 |
| `StopArt/ZipPlatform.platform(Config.ZipLines.Platform, Config.ZipLines.CableHeight, name)` | Floor origin at surface centre; -Z cable. Three rails, open launch edge. Attachment `CableAnchor` at (0,height,0) on GantryBeam; `ZipBoard.PolishLabel.ZipName`. Claude aligns this frame to the existing zip endpoint and retains the current solid platform. One red readiness lamp. | 19 |
| `StopArt/ZipPlatform.ladder(height)` | Frame at sidewalk ladder foot, +Z toward wall/roof. One native TrussPart supplies the rung silhouette; heights are 2–100, brief towers 16–89. `ClimbTop` at (0,height,1.6), to step onto roof. Red cage rings/spines above ten studs. Claude retains hand-over-hand climbing and checks Truss sizing / exact rung pitch in Studio. | 1 / 9 |
| `VehicleArt/BusLivery.build()` | Relative to **chassis top**, `bus.chassis.CFrame * CFrame.new(0,.6,0)`. Build with `weldTo=bus.chassis`, lineColor set to lineRgb. Original body is width8, length24, roof7. DestinationBoard has separate LineNumber/LineName labels; roof fascia says ZDC TRANSIT. Mirror arms, mullions, angular wheel arches and skirt grime. Right band is split; front-right arch is omitted to preserve boarding. | 31 |

Bus handoff: replace the **visual** original LineStripe / LineSign at integration so no old board shows through; retain the hull, seats, folding doors, driver, size, collisions and all mover/boarding code. The spec does not mutate existing instances. Add line metadata/text lookup to the caller and update both text slots. SurfaceGui slots are white type on charcoal; Builder preserves each authored night/light colour (including the dock/zip red lamps).

Validation passed: 10 real Builder builds, budgets (35 / 24 / 30 / 12 / 40), ≤one static light, night registration, slot coordinates, label text, flags, finite geometry and cleanup. `check_bus.py` adds this art to the **actual Vehicles.buildBus** at four translated/cardinal poses and proves original hull/seats/joints/size remain unchanged, new parts weld to chassis, total art fits the original wheel/bumper envelope, and the front-right boarding bay remains clear. `tools/vehicle-preview/check_fleet.py` passes; all tests and O0/g2 module compilation pass.

Studio review: arriving board updates; both shelter orientations / walk line; board a bus, folding door and five seats; dock unclip / return for all slots; zip launch / landing / ladder animation; day and night red lamps. Engine physics and native Truss rung geometry require this Studio check.

Renders use exact authored parts. `bus-reference.json` is a **reference** snapshot from the actual unchanged Vehicles factory, excluded from art budgets and not instantiated by this module. Truss render rails/rungs and SurfaceGui slot layout proxies are explicitly reference-only Blender aids; native art remains one TrussPart. Workbench previews approximate glass, text and night illumination.

Regenerate from zombie-delivery/:

```sh
python3 tools/polish-art/check.py stops /path/to/luau design/stops-bus-docks/geometry.json
python3 tools/polish-art/check_bus.py /path/to/luau --reference design/stops-bus-docks/bus-reference.json
blender -b -t 2 --python tools/polish-art/render.py -- stops design/stops-bus-docks/geometry.json design/stops-bus-docks/renders
python3 tools/polish-art/sheet.py design/stops-bus-docks/renders design/stops-bus-docks/sheet.png
python3 tools/vehicle-preview/check_fleet.py /path/to/luau
python3 tests/run_tests.py /path/to/luau
```
