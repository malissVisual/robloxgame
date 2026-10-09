# Mission chapter pictures: the brief for Codex

The owner's direction: "make pictures for the missions too." The job list already opens every job with Codex's
business picture (`art/job-thumbnails/`, 6.12.11). The MISSIONS window (U) is the clients and their **story chapters**
(`src/shared/Missions.luau` `Missions.Campaigns`): 11 chapters of six missions, each with a client, a place, a colour
and a pitch. This set is **one picture per chapter**: the client's place in the chapter's mood.

Claude has wired them already (6.12.13). The chosen chapter in the MISSIONS window opens with a **picture banner**: the
picture cropped across the chapter's list, with the chapter's name and the client's name on a dark label in its
bottom-left corner and a dark gradient under the label. Until a chapter's own picture is uploaded, six chapters borrow
the job picture of their client's place (`MissionArt.Fallback`: the City Clinic, FreshMart, the Military Base, Silver
Spur Ranch, the Research Lab and Second Life Pawn). The other five (First Shift, Partners in Crime, Smoke and Sirens,
Lights Out, Last Convoy) show no banner until theirs exists. The runtime map is `src/shared/MissionArt.luau`
(`MissionArt.Images`, empty slots); the banner is `src/client/MissionArtUi.luau`.

## The pictures

- **11 PNGs, 1672 × 941**, opaque RGB, landscape, the same format as `art/job-thumbnails/` (about 2–3 MB each is fine;
  Roblox keeps them at most 1024 px wide, which is enough for the banner).
- **One per chapter**, named by the chapter's campaign id: `dispatch.png`, `clinic.png`, `market.png`, `duo.png`,
  `firehouse.png`, `army.png`, `power.png`, `ranch.png`, `lab.png`, `underworld.png`, `exodus.png`.
- **New pictures.** Do not reuse or lightly edit a job thumbnail: the chapters that borrow one today get their own.

## The style (as in `art/job-thumbnails/`)

Look at `clinic.png`, `pawnshop.png`, `army.png` and `ranch.png` there. Keep their look:

- a **stylised 3D render** of a Roblox-like city: chunky, rounded "native-part" shapes, bevelled concrete, brick and
  timber with soft texture, trees with blocky leaf clusters, black cast-iron street lamps, square planters with round
  shrubs, yellow bollards;
- **the place is the subject**: one building or yard seen from the street in a three-quarter view, the camera at about
  eye level, the place filling most of the width, neighbouring brick and stone apartment blocks behind it, a strip of
  pavement, kerb and asphalt in the foreground;
- **warm, clean light**: soft shadows, glowing lamps and lit interiors, saturated but never neon; crisp props that tell
  what the place does (ammo crates, hay bales, safes, cooler boxes);
- the place's own **in-world sign** is welcome when its name is spelt exactly as in the table below (like "City
  Clinic" on the job picture), or no lettering at all.

What changes for the chapters is the **mood**: each picture shows the place at the moment of its story, with the
chapter's colour as an accent in the scene (a light, an awning, a glow, the sky), not as a colour filter. Use time of
day, weather and props: dusk and emergency lights, boarded windows, sandbags, smoke over the rooftops, a storm front.
Zombie Delivery is a Roblox game for all ages: no gore or blood, no corpses, no weapon pointed at the viewer, no scary
close-up faces. The dead are at most a few small shambling silhouettes far away. No close-up people: the client is
already in the window as their portrait. Small blocky figures seen from behind are fine where the table asks for them.

## Composition (how the game crops it)

- **On a monitor** the banner is about **2.6 : 1** (661 × 254 px in the window): the middle **68 %** of the height
  shows, about rows 151–790 of 941. Keep the place, its sign and the story props inside that band.
- **On a phone** the banner is a wider strip (about 6.5 : 1, 132 px tall): only the middle **27 %** shows, about rows
  340–600. Put the place's key cue (its sign, its roofline, the fire engine, the cooling tower) in that middle band.
- **Leave the bottom-left calm for the label**: the game draws the chapter's name and the client's name on a dark tile
  over roughly the left 45 % of the width and the lower 35 % of the visible band. Pavement, road, shadow or a low
  fence there; no faces, signs or story props. The place can sit a little right of centre.
- **No text overlays and no UI**: no title, chapter name, caption, logo, frame, border, button, badge or watermark.
  The game writes every label live.

## The eleven chapters

The places are the game's own names (`Missions.luau`, `Cast.luau`, `Map.luau`); the colour is the chapter's `color`;
the pitch is the line the window shows.

| File | Chapter | Client | Place | Colour | Pitch | What to show |
|---|---|---|---|---|---|---|
| `dispatch.png` | 📦 First Shift | Marge, the dispatcher | **Dead End Dispatch**, Marge's courier office at the **ZDC depot** (your company's yard north-east of the Central Park, the giant parcel on its roof) | `255, 200, 70` `#FFC846` | "Marge runs Dead End Dispatch, the last courier office in a city that ate its own post office. Your van is new and the streets are not: keep the parcels moving, and find out who wants the dispatch shut." | The depot's yard on a fresh morning: a corrugated depot with the giant parcel on the roof, an old delivery van with its back doors open, stacked parcels and mail sacks, a dispatch board by the door, a boarded window. Scrappy but hopeful. Not a post office (the story's burned down). |
| `clinic.png` | 🏥 Code Red | Doctor Ellie, the City Clinic | **City Clinic** | `240, 80, 80` `#F05050` | "The City Clinic is the last hospital still open, and Doctor Ellie runs it on coffee and spite. Pills, patients, power, and then a strain of the virus nobody has seen before." | The clinic at dusk with its red emergency lights on: the ambulance bay, a humming generator with cables, quarantine sheeting on a side door, medicine coolers by the entrance. Urgent, but the windows glow warm. |
| `market.png` | 🛒 Empty Shelves | Raj, FreshMart's owner | **FreshMart** (the map's FreshMart Supermarket) | `110, 200, 90` `#6EC85A` | "FreshMart has been open for thirty-two years, and Raj won't let the apocalypse close it. The shelves are empty, the farm road belongs to bandits, and a man called Tusk wants the city's food for himself." | The storefront in late afternoon, nearly empty shelves seen through the glass, potato sacks, bread crates and seedling trays at the door, shopping carts lined up as a barricade in the lot. Stubborn, a shop holding on. |
| `duo.png` | 🤝 Partners in Crime (DUO) | Rosa & Rico, the twins | **Survivor Camp** (the twins' place; the chapter also runs to the Water Works, the bank and the Stadium Shelter) | `236, 92, 60` `#EC5C3C` | "Rosa plans, Rico jokes, and neither of them ever works alone. Every job is made for two: pieces two of you carry, gates two of you open. Bring a partner, and help them settle a score with Tusk." | The camp's big gate with **two lever posts** far apart (the chapter's two-lever gates), a heavy crate on a pallet with handles at both ends, tents and a fence behind, two matching courier bags. Two of everything: a playful heist for two. Two small figures from behind at most. |
| `firehouse.png` | 🚒 Smoke and Sirens | Chief Carlos, Fire Station 9 | **Fire Station 9** | `255, 120, 40` `#FF7828` | "Fire Station 9 has the last working engine in the city, and Chief Carlos needs a driver who doesn't panic. Hoses, fuel, dynamite and foam, until the whole east side goes up." | The open engine bay with the city's last red fire engine, hose reels, diesel jerry cans and foam drums; orange smoke and a glow over the rooftops behind. Heat and sirens at sunset. |
| `army.png` | 🪖 Iron Supply | Captain Maria, the Military Base | **Military Base** | `130, 150, 90` `#82965A` | "The army holds the line at the Military Base, and the scouts say the big horde is coming down from the mountains. Ammo, food, dynamite and eyes on the coast: get the base ready before it hits." | The base's gate and perimeter (not the job picture's bunker door): sandbag walls, a watchtower with a searchlight, olive ammo crates, a steaming field kitchen pot, a scout chopper on its pad, dark mountains and a storm front behind. The calm before the horde. |
| `power.png` | ⚡ Lights Out | Engineer Ivan, the Power Plant | **Power Plant** | `90, 180, 255` `#5AB4FF` | "The grid is failing block by block, and Engineer Ivan holds it together with spare parts and stubbornness. Turbines, batteries, copper thieves and a plant that wants to boil over: bring the lights back." | The plant at blue hour: the turbine hall, a cooling tower venting steam, a transformer yard with a spark or two, cable drums; behind it half the skyline dark, a few windows lit. Fragile blue light against the dark. |
| `ranch.png` | 🐴 Wild West End | Walt, the rancher | **Silver Spur Ranch** | `200, 150, 90` `#C8965A` | "Out west the Rust Riders rule the roads, and Walt's ranch is the last thing between them and the farms. Horses, feed, rustlers and rifles: a feud that ends with you." | More of the yard than the job picture's stable front, at golden hour: the paddock with blocky horses, feed sacks, a lantern-lit porch, a dusty road with tyre tracks and a dust cloud on the horizon where the Rust Riders come. A western stand-off; a rifle rack at most. |
| `lab.png` | 🧪 Patient Zero | Doctor Hiro, the lab chief | **Biotech Lab** (the job picture calls it the Research Lab) | `160, 110, 255` `#A06EFF` | "Doctor Hiro's booster buys a bitten person one day. He wants a cure. Equipment, freezers, power, and the woman who was bitten on day one and never turned: handle with care." | The lab at night: violet light from the windows, cold-chain freezers and cooler boxes at the delivery door, a generator cable, a sealed hazard door, one cooler with a glowing vial. Clinical mystery, hope in the dark. |
| `underworld.png` | 💰 Dirty Money | Vinnie, the fixer | **Second Life Pawn** (Downtown, on Grave St.) | `230, 200, 60` `#E6C83C` | "Vinnie runs Second Life Pawn, pays the best and asks no questions. Ticking boxes, dirty cash, stolen paintings and a rival with a boat: everybody wants what is in your trunk." | The pawnshop at night with its three brass balls, gold light from the window on safes and a framed painting, a black car at the kerb with its trunk ajar (cash sacks, a wrapped painting), a wet street reflecting the gold. Noir: gold on black. |
| `exodus.png` | 🚌 Last Convoy | Mayor Ruth, City Hall | **City Hall** | `235, 235, 240` `#EBEBF0` | "Mayor Ruth says it out loud: the city is lost. The cure has to get out, and so do the people. The plans, the fuel, the seed vault, her own kids, the last boat and the last plane." | City Hall's steps at sunrise with a convoy of buses lining up, suitcases and medicine coolers on the pavement, a plane climbing over the rooftops towards the Old Airfield, the lighthouse far away. Bittersweet farewell, pale white-gold light. |

## Files to deliver

On a branch `codex/mission-art` (the board's rules, `AGENTS.md`):

- `art/mission-art/<campaignId>.png`: the 11 originals.
- `art/mission-art/manifest.json`: **the schema of `art/job-thumbnails/manifest.json`**. The top level has
  `schema` (1), `sourceRevision`, `date`, `scope` and `status`. In place of the job maps (`ordinary`, `special`,
  `round`, `tutorial`) it has `campaigns`, the 11 campaign ids in `Missions.Campaigns` order. `assets` is one entry
  per chapter in the same order, with the job manifest's fields: `id` (the campaign id), `name` (the chapter's name,
  "Code Red"), `file`, `robloxImage` (`""`, the slot the upload fills), `description`, `width`, `height` and
  `sha256File`.
- `tools/mission-art/check.py`, **like `tools/job-thumbnails/check.py`**. It checks that:
  - every chapter in `Missions.Campaigns` (`src/shared/Missions.luau`) has exactly one manifest asset and one PNG, in
    that order, with no uncatalogued PNG;
  - each `file` is `<id>.png`, a real PNG, 1672 × 941 (landscape, ratio 1.70–1.90) and matching its `width`, `height`
    and `sha256File`;
  - no picture is a duplicate of another chapter's or a byte copy of a job thumbnail;
  - `robloxImage` is `""` or `rbxassetid://<digits>`;
  - `src/shared/MissionArt.luau` agrees: `MissionArt.Images` has the same ids in the same order with the same
    `robloxImage` values.

  It prints one `PASS: …` line.
- `design/mission-art/README.md`, `index.html` (an offline gallery, as for the job pictures), `upload.csv`
  (`asset_id,file,roblox_image`) and `NAHRAT-OBRAZKY.md`: the owner's upload steps in Czech, a copy of
  `design/job-thumbnails/NAHRAT-OBRAZKY.md` with the `art/mission-art` folder and the 11 pictures (the MISSIONS window
  instead of the job list).

Please leave `src/` alone: the runtime map and the banner are Claude's. Do not rename the campaign ids.

## Upload and ids

The owner uploads the 11 PNGs the same way as the job pictures (Asset Manager → Bulk Import, then the Decals'
`Name Texture` lines from the Output, `design/mission-art/NAHRAT-OBRAZKY.md`) and sends Claude the lines. Claude runs
`python3 tools/mission-art/fill-ids.py ids.txt` (already in the repository). It writes the ids into
`MissionArt.Images` and, when they exist, the manifest's `robloxImage` and `upload.csv`. It skips a job picture's id
by mistake: the job pictures share names like `clinic`, `army`, `ranch` and `lab`. Each chapter's own picture then
replaces its borrowed one in the banner.

## Validation

From `zombie-delivery/`:

```sh
python3 tools/mission-art/check.py
python3 tools/job-thumbnails/check.py
python3 tests/run_tests.py /path/to/luau
```

`tests/missionart_test.luau` already checks the runtime map (every chapter has a slot; the fallbacks are job pictures
of the client's own place). The MISSIONS window's check `python3 tools/phone-ui/check.py /path/to/luau` checks the
banner. Studio, after the upload: open U and choose each client. Check the banner on a 1280 × 720 screen and on a
phone held sideways, look at the crop and the label's corner, and see a shut chapter dimmed.
