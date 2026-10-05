# Brief for Codex: building looks and signs

The owner wants every building in Zombie Delivery to have its own **sign** (a logo or name board) and a recognisable **look**. Today the signs are plain text on a dark board. `server/World.luau` draws them with the `sign()` helper: a SurfaceGui with text.

Read `zombie-delivery/AGENTS.md` and `COLLAB.md` first. Put your name under "In progress" and work on a branch `codex/<topic>`.

## Part 1: sign artwork (start here)

For every building in the table below, make a **sign image**, a logo board in the game's style:
- The style is post-apocalyptic courier city, a bit humorous. Signs may be worn, rusted or hand-patched.
- Use the 3.6 UI palette where it fits (`client/Theme.luau` `Theme.Postage`). Each business can have its own colours.

| What | Details |
|---|---|
| Format | PNG with transparency, plus an SVG source next to it (as in `art/icons/`) |
| Wide boards (most buildings) | 1024 × 256 |
| Square badges (garages, houses, small shops) | 512 × 512 |
| Folder | `zombie-delivery/art/signs/` |
| File names | `sign_<id>.png` and `sign_<id>.svg`, `<id>` from the table |
| Metadata | `art/signs/assets.json` in the same shape as `art/icons/assets.json` (name, file, size, intended use) |
| Text | the building's name, legible at a distance, short, English (the game text is English). A short slogan is optional, e.g. "Dead End Motors · we fix what's left" |
| Licence | no copyrighted logos, no real brands |

The owner uploads the PNGs in Roblox Studio (Asset Manager → Bulk Import) and sends the asset ids.

Claude then:
- adds `sign_<id>` slots to `src/shared/Icons.luau`;
- changes `World.luau` `sign()` to show the image when its id is filled in, with the text as the fallback.

You do not need to change code for Part 1.

## Part 2 (optional, one building per branch): the building's look

If you want to improve a building's 3D look, the code is in `src/server/World.luau`:
- Each place has its own builder function. Search for its name or id.
- Shops are built around `Map.Shops`, the mission places around `Map.Places` and `Map.Yards`.
- The estate is built from `Map.EstatePlots`, the towers from `Map.Towers`.

Rules:
- **Part count:** keep it sane, reuse helpers such as `part`, `box`, `building`, `deco`, `lamp` and `sign`. Anchored parts; `deco()` for parts that should not collide.
- **Keep clear:**
  - the roads;
  - the park circles and cargo piles (`Map.CargoSpots`), so the cargo walk stays free;
  - ProximityPrompts (shops, employers, FOR SALE signs, office computers, garage posts, repair bays);
  - the lost packages (`Map.Secrets`).
- **Check before pushing:** run `python3 zombie-delivery/tests/run_tests.py <path to luau>`. `logic_test` checks places, overlaps and spots. Every module must compile.
- **Studio:** say what to look at in Studio when you hand it over.

## Every building

`x, z` are the map coordinates; −z is north. `CELL` = one city block plus a road.

### The starting area (Downtown, the safe zone)
| id | Name | What it is | Sign today |
|---|---|---|---|
| depot | Depot Garage / ZOMBIE DELIVERY CO. | your company's depot: job board, the starting van's lot, GARAGE terminal | "ZOMBIE DELIVERY CO.", "JOBS", "GARAGE" |
| dealer | Dead End Motors | car dealership: 3 turntables inside, catalog at the counter | "DEAD END MOTORS", "SALES · CAR CATALOG" |
| guns | Lead & Co. | gun shop | "LEAD & CO. GUNS" |
| mechanic | Wrench Garage | upgrades, stages, paint, car guns, 2 repair bays | "BAY 1 · REPAIRS" … |
| supplies | Last Stop Supplies | items: repair kits, medkits, nitro, molotovs, mines | text |

### Repairs and garages
| id | Name | What it is |
|---|---|---|
| repairs | Rust Bridge Repairs | second repair shop in the Harbor (by the Rust Bridge) |
| garage_rented | Rented Lockup | small garage, +1 car slot |
| garage_south | Southside Garage | garage, +2 slots |
| garage_harbor | Harbor Lockup | garage, +4 slots |
| garage_north | Highway Garage | garage on the North Highway, +4 slots |
| garage_downtown | Downtown Parking | parking house floor, +6 slots |

### Employers (places with a WORK HERE board)
| id | Name | What it is |
|---|---|---|
| school | Sunny Hill School | school (school bus) |
| army / base | Military Base | army base, far north |
| icecream / frosty | Frosty's Ice Cream | ice cream shop in the Harbor |
| movers | Big Move Movers | moving company |
| farm | Old Farm | farm, far west (monster truck) |
| ranch | Silver Spur Ranch | horse ranch (+ Paddock) |
| clinic | City Clinic | the last hospital (ambulance) |
| gas | Gas Station | fuel station north of Downtown |

### Downtown and city places
| id | Name |
|---|---|
| bank | First Zombie Bank |
| pharmacy | Corner Pharmacy |
| market | FreshMart Supermarket |
| firestation | Fire Station 9 |
| police | Precinct 13 |
| cityhall | City Hall |
| dispatchtower | Dispatch Tower (14 floors, offices) |
| harborpoint | Harbor Point (12 floors, offices) |

### Harbor and industry
| id | Name |
|---|---|
| docks | Harbor Docks |
| warehouse | Harbor Warehouse |
| fueldepot | Harbor Fuel Depot |
| powerplant | Power Plant |
| waterworks | Water Works |
| trainyard | Train Yard |

### Out of town
| id | Name |
|---|---|
| radio | Radio Station |
| lodge | Ski Lodge (winter, north) |
| stables | Riverside Riding School (+ Riding Arena) |
| airfield | Old Airfield |
| lab | Biotech Lab |
| prison | Blackrock Prison |
| lighthouse | Lighthouse Point |
| camp | Survivor Camp |
| stadium | Stadium Shelter |

### Real estate (FOR SALE signs and house name plates)
| id | Name | Kind |
|---|---|---|
| hilltop | Hilltop Mansion | mansion (Sunset Hills) |
| oceanview | Ocean View Mansion | mansion |
| pinecrest | Pinecrest Mansion | mansion |
| lakeside | Lakeside Villa | villa |
| sunset | Sunset Villa | villa |
| maple | 12 Maple Street | house |
| oak | 7 Oak Lane | house |
| birch | Birch Cottage | house |
| elm | Elm Bungalow | house |
| office_harbor | Harbor Point Office | office (in Harbor Point) |
| office_tower | Dispatch Tower, 8th floor | office |
| office_penthouse | Dispatch Tower Penthouse | office |

For the houses a **house number plate** or a **mailbox name** is enough (square 512 × 512). The offices get a door plate for "your company", e.g. "ZOMBIE DELIVERY CO. · Suite 8".

## Order of work
1. Start with the 5 starting-area shops and the depot, then the repair shops and garages, then the employers. Those are what the player sees first.
2. Do the places after that, and the estate last.
3. You may hand them over in several branches (e.g. `codex/signs-1`, `codex/signs-2`). After each one, write it under "Ready for review" in `COLLAB.md`.
