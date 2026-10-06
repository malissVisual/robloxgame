# Brief for Codex: models for 5.x ("from the bottom": on foot → bike → van, fuel, the phone)

The career now starts **on foot**, then a **bike** (level 2), then the Old Van (level 4). Cars need **fuel** at gas stations. Marge gives you a **phone**. Claude builds the gameplay (5.0 on foot, 5.1 bike, 5.2 several orders, 5.3 fuel).

Codex builds the models below.

Read `zombie-delivery/AGENTS.md` and `COLLAB.md` first. Put your name under "In progress", one branch per group: `codex/kit-models`, `codex/bike-models`, `codex/gas-models`, `codex/phone-art`.

## How (same as your fleet and building work)
- **Native Roblox parts only:** Parts, WedgeParts, Cylinders. No meshes, no image uploads (except the 2D icons in part 5).
- **Pure-data geometry modules** that a builder welds, like `server/VehicleArt/Geometry.luau` + `Builder.luau` and `server/BuildingLooks/*`. Claude wires them into the game.
- **Visual pieces:** massless, `CanCollide` / `CanQuery` / `CanTouch` false, `CastShadow` off on small parts.
- **Look:** the approved style, from `design/location-looks/` and the contract UI: worn, realistic, restrained palette, red accents.
- **Deliver renders** like `design/vehicle-models/` (sheets + a README), and a checker script if it makes sense.

## 1. Personal kit, worn on the character (`codex/kit-models`)
Weld to an R15 character (UpperTorso / LowerTorso / feet). It must not block the arms (carrying pieces in two hands) or the sit pose.

| id | What | Budget |
|---|---|---|
| `backpack` | Courier backpack, medium, charcoal with a red stripe; 1 light piece visibly sticks out of the top when the pack holds cargo (a separate optional "load" part) | ≤ 14 parts |
| `bigpack` | Big insulated delivery backpack (the square food-courier box style) with a small logo panel | ≤ 18 parts |
| `shoes` | Running shoes (overlays on the feet: sole + upper + a red heel tab) | ≤ 6 per foot |
| `jacket` | Thermal jacket / vest (torso and upper-arm panels, a collar, a reflective strip) | ≤ 16 parts |
| `cart` (5.1) | Personal hand cart (two-wheeled sack truck) the player pushes; same rules as the existing hand trolley (`server/Equipment.luau` builds the trolley today; give geometry with a handle grip point and a deck) | ≤ 22 parts |

Output a module like `server/KitArt/Geometry.luau`: `pieces(id) -> { name, size, at (relative to the attach part), attach = "UpperTorso" | "LeftFoot" …, finish }`.

## 2. Bikes and bike gear (`codex/bike-models`)
Claude adds a vehicle style `bike`:
- 2 visible wheels, a hidden wide stable collider (no balance physics);
- one doorless seat (the rider sits on the saddle, hands on the bar);
- no back: the cargo sits in a rack or basket.

Rider pose (hands on the grips, feet on the pedals): give the **saddle, grip and pedal points** as attachments in the geometry.

| id | Bike | Notes |
|---|---|---|
| `rustbike` | Rusty Bike (L2, cheap) | an old steel city bike: rust, a mismatched wheel, a rear rack |
| `citybike` | Courier Bike (L2) | clean, a straight bar, a rear rack, a front lamp |
| `cargobike` | Cargo Bike (L3) | a long-john with a front cargo box (6 light pieces show inside) |
| `ebike` | E-Bike (L5) | a battery on the down tube, a display, disc brakes |

- **Size:** about 6.5 studs long, 1 stud wide frame, wheel radius ≈ 1.3.
- **Budget:** ≤ 70 parts each; the wheels are separate so they can spin (like the fleet's tyres).
- **Moving parts:** the cranks/pedals as a separate assembly so Claude can rotate them.

**Bike gear** (shows when installed; per bike):

| id | Gear | Budget |
|---|---|---|
| `basket` | front basket | ≤ 10 parts |
| `panniers` | rear pannier bags (2) | ≤ 12 parts |
| `trailer` | small 2-wheel cargo trailer with a hitch | ≤ 25 parts |
| `bell` / `light` | a bell and a lamp | tiny |

Mark each gear piece's cargo spots: attachments named `Slot1`, `Slot2`…

**Bike shop building** "SPOKE & CHAIN CYCLES": a `BuildingLooks` blueprint in the same Kit format as the other 40.
- Footprint about 60 × 40 × 16, on Downtown block (-1, 1).
- Inside: a counter, wall racks with bikes hanging, a repair stand, tyres, a "RENT · BUY · REPAIR" board.
- Outside: a bike rack on the sidewalk. Keep the door 12 wide and clear, and the name board where `sign()` puts it.

## 3. Gas stations and fuel (`codex/gas-models`)
| id | What | Budget |
|---|---|---|
| `pump` | fuel pump: a body with a display, a nozzle on a hose (the nozzle is a separate part the player takes), a price sign | ≤ 25 parts |
| `island` | pump island: 2 pumps on a kerbed island + a canopy with lights (night lamps like the Kit's `night = true`) | ≤ 70 parts |
| `kiosk` | small station shop / kiosk (a counter, a fridge, shelves, an ATM) as a BuildingLooks blueprint | ≤ 60 parts |
| `pricesign` | the tall roadside price sign (a pole + a board showing the price per litre via a SurfaceGui text slot) | ≤ 12 parts |
| `jerrycan` | a red jerry can (a carryable piece, like the cargo looks in `server/Cargo.luau` buildLook) | ≤ 8 parts |
| `fuelcap` | a fuel cap / filler flap on the cars (one per fleet style, a position on the body for the nozzle) | positions only |

- Claude places 4 stations: the existing Gas Station plus Downtown edge, Harbor, Suburbs.
- Give a **station layout** (island + kiosk + sign + parking lines) as one blueprint that fits a 70 × 50 lot.

## 4. The phone (`codex/phone-art`)
- **In hand:** a smartphone in the character's right hand (when the phone UI is open and on foot): ≤ 6 parts, a lit screen part.
- **The UI art** (2D, PNG + SVG like `art/icons/`):
  - app icons in the contract style, 256×256 white glyphs on transparent: `app_orders`, `app_board`, `app_career`, `app_shop`, `app_map`, `app_messages`, `app_bank`, `app_settings`;
  - a lock-screen wallpaper (1080×1920, the city at dusk, subtle) and a courier-company logo for the phone's splash.

## 5. Icons (`art/icons/`, the existing format)
`kit_backpack`, `kit_bigpack`, `kit_shoes`, `kit_jacket`, `kit_cart`, `bike_rust`, `bike_city`, `bike_cargo`, `bike_ebike`, `gear_basket`, `gear_panniers`, `gear_trailer`, `fuel`, `jerrycan`, `map_gas`, `map_bikes`.

## Order of priority
1. **Kit:** the backpacks first (5.0 is being built now).
2. **The phone's app icons.**
3. **Bikes + the bike shop** (5.1).
4. **Gas stations** (5.3).

Until a model lands, Claude ships simple placeholder geometry and swaps yours in when it is merged.
