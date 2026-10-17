# Deliveros

**Deliveros** is a Roblox moving game for up to four players. You start in a small **lobby** with your own
**warehouse**, step onto a portal with your friends, ride out to a house in the countryside and **empty it against the
clock**: carry the furniture and the rare finds out to the truck, past locked rooms, traps and, on the harder
difficulties, zombies. Everything you bring home is **loot**: each piece has a rarity, an outline in its colour and its
stars. At home you put the best pieces **on show**, where they earn money every minute you play, or sell them, trade
them with other players, fill the **collection book**, grow the warehouse from a garage to a logistics centre and build
up a **crew** of helpers you rescued on the runs.

> **10.5: only the sandbox.** The old city game (Zombie Delivery 1.0 – 7.x: deliveries, missions, the city map, the
> phone, the guns, the bikes, the traffic, the day and night) is gone. The owner (17. 10. 2026): "remove everything
> that is not active now, only the sandbox; that will be the game". Its code, tests, tools, art and designs are in
> git's history up to 10.4 (main's Deliveros 10.4). What was the 8.0 "sandbox" is the whole game now; the code still
> calls many of its parts Sandbox… (`SandboxBoot`, `SandboxMap`, `Config.Sandbox`).

Everything is built in code (the world, the houses, the truck, the people, the interface), so the game needs no assets
to run: open an empty place and sync. The owner's Blender models, the sounds and the store art are optional extras
(see **Running**).

## Working on the game with AI helpers

Claude Code and Codex both work on this game and share the work through the repository: the rules are in
[`AGENTS.md`](AGENTS.md), the task board is [`COLLAB.md`](COLLAB.md) (who works on what, branches to review).

## Running

```bash
node tools/rojo-sync.js zombie-delivery
```

From the repository root. Instead of the command you can double-click `zombie-delivery/spust-zombie-delivery.cmd`
(Windows) or `zombie-delivery/spust-zombie-delivery.command` (Mac): git pull + the sync.

In Studio open a **new Baseplate place** (not the Merge Blades one), then **Plugins → Rojo → Connect** and **Play**.
Once, in the place itself (Rojo syncs only scripts):
- **Workspace → StreamingEnabled** on (the radii in `design/performance/NAVOD.md`); the server warns in the Output when
  it is off.
- **Lighting → Technology = Future** (scripts cannot set it).
- **The place's maximum players: 4**, one player a plot (`Config.Sandbox.MaxPlayers`).

**The sync** (`tools/rojo-sync.js`, a stand-in for `rojo serve` that speaks Rojo 7.7's protocol):
- On every **Connect** it reads the disk again, and it checks the files every 5 s. Starting it a second time stops the
  old one, even in another window.
- Since 8.7 Studio **re-creates** every script after a Connect (and a changed one while connected) instead of
  overwriting it: Rojo's plugin sometimes left old scripts in place. Wait for
  **`✓ Studio převzalo Connect: … — můžeš dát Play`** in the terminal before Play; on **`! Studio nepotvrdilo`** follow
  the advice it prints. The terminal shows `Config.Version` on disk (`verze: …`): if that is already old, the
  `git pull` failed, not the sync. `--in-place` brings back the old behaviour. Its test: `node tools/rojo-sync.test.js`.
- **Build stamps** (8.5.1): `server/BuildStamp.luau` and `client/BuildStamp.luau` hold the version their scripts were
  written for (`tests/run_tests.py` checks they equal `Config.Version`). A mix of old and new scripts warns in the
  Output and, in Studio, shows a red banner: Stop, Rojo Disconnect, delete ReplicatedStorage > Shared,
  ServerScriptService > Server and StarterPlayer > StarterPlayerScripts > Client, then Connect and Play.
- Both `default.project.json` files (the repository's and `zombie-delivery/`'s) map the same folders, and
  `src/first/` goes to ReplicatedFirst.

**The owner's Blender models** (optional; meshes have to be uploaded under the owner's account): import each FBX once
in Studio (File → Import 3D, the defaults), save and publish; at the server's start the dressers move them to
ServerStorage and dress the game's parts with their MeshParts. Until then everything keeps its parts look.

| Model | Dresses | Folder (the owner's Czech guide `NAVOD.md` in each) |
| --- | --- | --- |
| `ZDCSprinterArt` | every Sprinter van (`server/SprinterMesh.luau`) | `design/blender-sprinter/` |
| `ZDCWarehouseArt` | the warehouse, all five levels (`server/WarehouseMesh.luau`) | `design/blender-warehouse/` |
| `ZDCFurnitureArt` | every piece of furniture and every collectible (`server/FurnitureMesh.luau`) | `design/blender-furniture/` |
| `ZDCFixtureArt` | the kitchens', bathrooms' and garages' built-in things (`server/FixtureMesh.luau`) | `design/blender-fixtures/` |
| `ZDCHouseArt` | The Old Farmstead (`server/HouseMesh.luau`) | `design/blender-house/` |

The dressers check that an import's markers still form a square frame and that its pieces are turned alike; an import
that moved (renamed and left in the Workspace) is refused with a warning, and the old place's loose `ZDCVanArt` and
`ZDCHouseArt` pieces are moved out of the Workspace first thing (`server/Main.server.luau`). `tools/sprinter/`,
`tools/warehouse/`, `tools/furniture/`, `tools/fixtures-art/` and `tools/house-art/` simulate each import without
Studio (the Sprinter's, the warehouse's and the fixtures' run in `tests/run_tests.py`).

**Saves:** a Play test in Studio without API access plays but keeps nothing. A published game saves in its own
DataStore, `Config.Sandbox.Store` (`ZombieDelivery_v2_Sandbox`), and a new save starts with `Config.Sandbox.StartMoney`
($500). See **Saving**.

## How to play

| | Computer | Gamepad | Touch |
| --- | --- | --- | --- |
| Use, pick up, load, untie, revive | E (hold where a prompt says so) | X | the prompt |
| Put down | G | B | PUT DOWN |
| The grip check | LMB or F | R2 | GRIP |
| Search a piece of furniture (a key) | hold F | the prompt | the prompt |
| Danny's clipboard (orders) | Q, then E / LMB on a piece | R1 | 📋 |
| STOCK · BOOK · TASKS | B · C · J | D-pad ← · → · ↓ | the chips |
| The map | M | L2 | 🗺 MAP (a minimap in a run) |
| Turn the camera | right mouse, a trackpad's two-finger swipe, `,` / `.`, ← / → | right stick | drag |
| The admin panel | P (admins only) | | 🛠 ADMIN |

The key hints strip (folded behind **? KEYS [F1]**) shows the keys of the moment in the words of the device you use
(`shared/SandboxPad.luau`, `client/KeyHints.luau`); a gamepad sees its own glyphs, a touch screen its buttons. The
mouse is free (`CameraRig.aimOnly`: no crosshair and no Alt; the locked aim only while a weapon is held); the wheel
zooms. A run starts by stepping onto a portal's pad.

## The start: intro, save slots, your courier (10.1)

- **The intro and the loading screen** (`src/first/Loading.client.luau`, a LocalScript in ReplicatedFirst that
  requires nothing): a sunrise, the Deliveros van drives in, **DELIVEROS** pops up over **MOVE · FIND · GROW**, then a
  bar and a tip while the game loads. It goes once the start screen is up (the player attribute `StartScreen`, set by
  `client/Menu.luau`) or after 25 s; any key skips the intro, never the loading. Its sounds are on sfx6.
- **Three save slots** (`Config.SaveSlots`, `server/SaveSlots.luau`, `shared/SaveSlotRules.luau`). Every slot is its own
  game: money, warehouse, collection, book, upgrades, tasks, paint, crew and courier. The start screen lists them (the
  courier, LEVEL n · the warehouse's name, the money, the pieces, the moves, the time played, "saved … ago") with
  **CONTINUE**, **NEW GAME**, **LOOK** and **START OVER**; the save loads and locks only once a slot is picked
  (`PlayerData.chooseSlot`). Slot 1 is the save from before 10.1 (key `Player_<id>`), slot n `Player_<id>_slot<n>`.
- **The character creator** (`client/CharacterCreator.luau`, `Config.Characters`, `shared/CharacterLooks.luau`): your
  own Roblox avatar or a courier made here (the skin, eight hair styles and their colours, a hat, a top, the trousers,
  glasses or a beard, a name Roblox's TextService filters, 🎲 RANDOM) in a turning 3D preview. A made courier is
  Roblox's classic blocky R15 in those colours with plain pieces welded on (`StyleBuild.character`);
  `server/CourierAvatar.luau` puts it on at once and at every spawn, so everybody sees what you picked.

## The lobby (10.0)

A small lobby (480 × 400 studs, `design/lobby/plan.py` → `plan.json`; `tools/lobby/sandboxmap.py` writes
`SandboxMap`'s LOBBY section; built by `server/LobbyWorld.luau`): a plaza with the spawn, a fountain and the Deliveros
dispatch; the four players' plots with their warehouses along the north edge; the UPGRADES desks; the PAINT shop's
booth; the **TOP MOVERS** board; the Auction House's place; and **six portals**, one for each house (a gate, a facade
in the house's colours, its sign and a glowing pad: blue FREE, amber counting down, red IN USE). Previews:
`design/lobby/`.

## The runs (10.0)

Step onto a portal's pad and a 10 s countdown starts (`Config.Runs`, `server/Runs.luau`, `shared/RunRules.luau`,
`client/RunUi.luau`). Up to four go together, and the first on the pad picks the difficulty:

| Difficulty | The clock (× the house's time) | What the house holds besides the loot (`Config.Runs.Danger`) |
| --- | --- | --- |
| Easy | × 1.3 | a locked room, a few hazards |
| Normal | × 1 | a locked room, the vault, more hazards |
| Hard | × 0.85 | two locked rooms, the vault, zombies in the house and the yard, the bat |
| Insane | × 0.72 | two vaults, more and faster zombies, a horde at half time |
| Nightmare | × 0.6 | the most of everything, a Legendary at a chance in the vault, THE LANDLORD by it |

Easy and Normal are open; each next one opens when you finish a run at the one before (saved as `runUnlocked` with its
flag). **The ride** (10.4, `client/RideUi.luau`, `Config.Runs.Ride`): while the jump fades, the Deliveros van drives
across the screen to the house (3.4 s) and back (2.4 s) under the difficulty's sky (a fresh morning for Easy … a night
with the moon and the van's lamps for Nightmare), with ON THE WAY TO, the house's name, its difficulty and who rides
along; your controls are off meanwhile. The party arrives in the house's fenced run zone with the truck parked at the
curb (there is no driving): carry the loot out and into the truck before the clock runs out. The host's FINISH at the
truck, everybody else's vote or the clock ends the run; what you loaded goes to your own warehouse's stock, a results
card shows the haul ("Vault opened ✓/✗ · Zombies stopped"), and everybody fades back next to the portal. LEAVE THE RUN
takes you back alone; the host leaving ends it for all.

**The danger** (10.2, `shared/DangerRules.luau`, `server/RunDanger.luau`, `client/RunDangerUi.luau`):
- **Locked rooms:** their keys ("Bedroom key") are hidden in searchable furniture of a room you can already reach (hold
  **F** · Search; found for the whole party). A locked room's pieces come a tier up, and its doorway is a wall for
  Danny and the zombies until it opens.
- **The vault** (from Normal): the best piece or two in a steel and glass case, Epic or better, with its own gold key
  hidden deeper.
- **Hazards** on open floor, never in a doorway or on a way out: creaky boards (carry over them and you stumble and drop
  the piece), puddles (you slide), a cracked ceiling that shakes and sheds dust before the plaster falls.
- **Zombies** (from Hard, `shared/ZombieKinds.luau`, `server/Zombies.luau`): in the house and the yard, faster on Insane
  with a horde at half time, THE LANDLORD (a big brute) by the vault on Nightmare. A bite drops what you carry; the
  truck is nobody's target. From Hard everybody has a **bat** (picking a piece up puts it away). A death drops the piece
  and puts you back by the truck.
- The danger strip shows the run's state; the results card says what was opened and stopped.

## Loot (10.0)

Every piece of a house gets a rarity from the server as the house is made (`server/Loot.luau`, `shared/LootRules.luau`,
`Config.Loot`): its own (the furniture's by its value, a collectible's own: common, uncommon, rare, epic, legendary)
rolled by the difficulty. Easy now and then gives a tier lower; Hard, Insane and Nightmare lift pieces (more rolls, the
best kept; Nightmare always at least one Epic, a Legendary in about one house of three). The same house at the same
difficulty always holds the same loot. A tier up is worth × 1.5, a tier down × 0.8. The model carries `Rarity`, `Stars`
and `Value` and the tag `LootPiece`; the stock keeps the rarity, so the stands, selling, the book, the trades and the
auction all show the same rarity and value.

On your screen (`client/LootOutline.luau`, `client/LootStars.luau`): an outline in the tier's colour (green, blue,
purple, gold; Commons none) on the pieces near you, in your hands, in the truck and on the stands (the rarest first,
never through walls; one budget with the zombies' outlines within Roblox's 31, `shared/OutlinePick.luau`); ★ × its
stars over the nearest few ("★★★ RARE · $450" up close); a toast when you pick one up or load it; and an Epic or
Legendary piece sparkles with a sound the first time you see it. Previews: `design/loot/`.

## The map (10.2)

M (a gamepad's L2, the 🗺 MAP chip): in the lobby the plaza, your warehouse in gold, the shops and the six portals with
their live state (FREE, STARTING IN 7 with who is on the pad, IN USE with the difficulty and the party; click one and
the guide leads there); in a run the house's floor plan (`MapPlan`, published once by `server/HouseInterior.luau`), the
yard and the truck, you, the party, the helpers, the zombies near you, the dangers (🔒 🔑 🏦 ⚠ 🆘) and the loot you
have seen in its tier's colour (the rest in the fog), the clock and the truck's load. A corner minimap in a run.
`client/SandboxMapUi.luau`, `SandboxMiniMap`, `SandboxMapDraw`, `SandboxMapData`, `shared/SandboxMapRules.luau`,
`Config.SandboxMapUi`; previews in `design/map/`.

## The crew (10.2, 10.3)

`Config.Crew`, `shared/CrewRules.luau`, `server/HelperCrew.luau`, `client/CrewUi.luau`. **Danny** is every player's
from the start, free: he waits by your warehouse, his Crew prompt opens the CREW window, and he comes into every run.
Four more can join your crew, each with his own look and way of working:

| Helper | What he does |
| --- | --- |
| Danny | carries what you give him; lifts the heavy pieces with you |
| Bruno | carries a two-person piece alone, slowly |
| Zip | runs one-hand and small pieces out fast; no heavy or two-person ones |
| Gus | carries nothing: walks with you and fights the zombies |
| Lucy | carries small pieces and shows the party the Epic and Legendary loot through walls |

You get them by **rescuing** them: some run houses hold one tied to a chair (more often on the harder difficulties;
hold E to untie him). He joins the crew of everybody in the party who lacks him (the others get a money bonus), says
he'll wait at your warehouse and fades away (10.3). One helper comes into a run: the host's pick in CREW. A helper at 0
health goes **down** (a ring and a countdown): any party player holds E within 15 s to revive him at half health, else
he is out of the run and **in hospital** for 4 minutes (CREW shows the time left and can discharge him early for
money). Nobody is lost for good; the crew is saved with its flag (`crewKept`). Previews: `design/crew/`.

## Inside a run: the houses, carrying, Danny

**The six places** (9.0, `design/countryside/plan.py` → `plan.json`; `tools/countryside/sandboxmap.py` writes
`SandboxMap`'s countryside section; `shared/CountryLooks.luau` the surroundings): each stands in its own fenced run zone
of open countryside, at the end of its own country lane.
- **The Old Farmstead** (The Nováks): the big house (the owner's Blender house), now a farm with a barn, a tractor and
  bales; ten rooms (`Config.Furniture.Big`), a back door as a second way in and out.
- **The Pond Cabin** (the Vodičkas), **The Lone House** (the Kopeckýs), **The Forest Lodge** (the Lesáks), **The Old
  Mill** (the Mlynářs) and **The Orchard Cottage** (the Sadíleks): their own looks, interiors and pieces
  (`shared/Layouts/Countryside.luau`, HouseLayout's kinds cabin, lodge, mill and cottage).

Every visit plans a fresh layout (`shared/HouseLayout.luau`; the walls and floors `server/HouseInterior.luau`) with its
furniture (`shared/FurnitureLooks.luau`) and 1 – 3 collectibles; the built-in fixtures (kitchen, bathroom, the
Kachelofen, the garage) wear `ZDCFixtureArt` once imported. The moves inside a run are `server/Moving.luau` with its
rules in `shared/MovingRules.luau`; there are no roles (8.8): anyone carries, loads and unloads.

**Doors** (8.1 – 8.5, `shared/DoorSwing.luau`, `client/WalkDoors.luau`, `Config.Moving.Doors`): no E at a house. Walk
at a door and its leaves swing open for everyone nearby; keep walking and the screen fades while you cross, and you
arrive inside still walking. A crew mate carrying the other end of a piece comes along in the same dark moment.

**Carrying** (`shared/CarryGrip.luau`, `client/CarryGripUi.luau`, `Config.CarryGrip`): lifting a piece is a timing check
(a hit lifts it balanced, a miss knocks it), and while you carry, a WOBBLE! now and then (a hit: steady; a miss
staggers a sturdy piece and the next drops it; a fragile piece drops at once). A piece for two is carried in two,
slowly and physically (`shared/PairCarry.luau`, `client/PairSteer.luau`, `server/PairHold.luau`): it lies along the
carry, each holding an end, the leader's heading turns slowly, a way behind is walked backwards, and nobody runs with
it. The truck at the curb is the walk-in **Sprinter** (`Config.Sandbox.Van`, `shared/SprinterLooks.luau`; parked by
`server/Vehicles.luau`): open its back or its sliding door, walk up the step and load from inside.

**Danny** (`server/MoveHelper.luau`, `shared/MoveHelperBrain.luau`, `shared/HouseRoute.luau`, `Config.MoveHelper`):
- **Orders:** take out the clipboard (Q, R1, 📋) and a click, a tap or E on a piece gives it to him (again: take it
  back; `server/Clipboard.luau`, `client/DannyOrders.luau`, `shared/ClipboardRules.luau`). The piece you point at glows
  green, orange (on his list) or red with the reason.
- **A heavy piece:** your Lift calls him to its far end ("On three... lift!"); on your screen your own client drives his
  end (`client/PairLead.luau`), so he backs away as you walk forwards and follows as you back up, with no lag.
- **His walk:** inside a house he walks the plan's grid to an arm's-length spot with a clear line to the piece, aims a
  few studs ahead along a line clear of walls, fixtures and pieces, and only after 10 s stuck does he fade over.
- **His bubble** shows his move's crew what he does now ("📦 Carrying: Sofa → van", "⏳ Needs you: Piano",
  `client/DannyBubble.luau`); PUT IT DOWN sets down what he carries. **Danny's training** at the UPGRADES desk makes him
  faster.

## Your warehouse

Everything a run brings home goes to your **stock** (`server/Collection.luau`, `shared/CollectionRules.luau`,
`Config.Collection`). In the warehouse put pieces **on show** on its stands (E at a stand → the picker,
`client/WarehouseUi.luau`): they **earn money every minute you play** (0.5 – 1.5 % of their worth a minute, common to
legendary; a quarter after 10 idle minutes, "+$X/min · idle"), or sell them any time (about a quarter of an hour of
that income). The STOCK list (B) has ⭐ FILL BEST, 💰 SELL… (all Common, all broken, the duplicates; never a piece on
show), ↩ TAKE ALL DOWN, a sort and a search (`shared/StockPlan.luau`). The HUD (`client/SandboxHud.luau`) shows the
money counting up, "+$X/min" and the chips 📦 STOCK, 📖 BOOK, 📋 TASKS and 🗺 MAP.

**The five levels** (8.3, `Config.Warehouse.Levels`, `shared/WarehouseLayout.luau`, `server/Warehouse.luau`;
`design/warehouse-levels/KONTRAKT.md`), bought at the UPGRADES desk's first card; each is its own building on the plot,
rebuilt at once (the pieces on show stay):

| Level | Name | W × H × D | Big stands | Price |
| --- | --- | --- | --- | --- |
| 1 | Garage | 26 × 12 × 22 | 2 | the start |
| 2 | Workshop | 40 × 15 × 30 | 4 | $1,000 |
| 3 | Storehouse | 58 × 19 × 42 | 8 | $7,500 |
| 4 | Big Warehouse | 80 × 24 × 60 | 12 | $30,000 |
| 5 | Logistics Center | 104 × 28 × 84 | 24 | $100,000 |

From the Big Warehouse on, **More stands** adds small stands (+2 a level, +8 at the top: up to 32 at level 5).

**The UPGRADES desk** (`server/Upgrades.luau`, `client/UpgradeUi.luau`, `shared/UpgradeRules.luau`,
`Config.SandboxUpgrades`): the Deliveros Warehouse ($1,000 – 100,000), More stands ($4,000 – 25,000), Showroom lights
(more income, $1,500 – 75,000), the Van engine ($1,500 – 15,000) and Danny's training ($1,500 – 12,000).

**The collection book** (8.2, `server/CollectionBook.luau`, `client/CollectionBookUi.luau`,
`shared/CollectionBookRules.luau`, `Config.CollectionBook`; 📖 BOOK, C): every piece the houses can hold (97 since
9.0), the unknown ones dark silhouettes, and milestones that pay once (found 10 / 20, all the furniture, every
collectible, a legendary). Their paid ids are mirrored as `rewards`' `"book:<id>"` keys. **24 collectibles** from
uncommon to legendary (8.4) and the countryside's own pieces (9.0) wear the owner's Blender look once
`ZDCFurnitureArt` is imported.

**Daily tasks** (8.2, `server/SandboxTasks.luau`, `shared/SandboxTasks.luau`, `Config.SandboxTasks`; 📋 TASKS, J):
three a day and one a week, picked by the UTC day; CLAIM pays, and all three daily ones pay a bonus.

**The market** (8.4, `shared/Market.luau`, `Config.Market`): every UTC day 3 kinds are 🔥 hot (sell × 1.4, earn × 1.2
on show) and 1 is ❄ cold (sell × 0.7); selling many of a kind lowers its price for you (5 % a piece, 40 % at most,
coming back over time). The STOCK list, the picker and SELL's question show it.

**Showroom visitors** (8.4, `shared/Visitors.luau`, `server/Visitors.luau`, `server/VisitorOffers.luau`,
`client/OfferCard.luau`, `Config.Visitors`): tourists, hikers, a collector and an antique dealer walk in through the
roller door, stroll between your stands and leave; now and then one offers 10 – 50 % over the market price for a piece
on show (ACCEPT / DECLINE within 30 s). The server always has the price.

**The PAINT shop** (8.4, `server/VanPaint.luau`, `client/VanPaintUi.luau`, `shared/VanPaintRules.luau`,
`shared/VanLook.luau`, `Config.VanPaint`): 13 body colours and 4 liveries for your van, bought once and kept,
cosmetic only (Collector gold opens with the book's legendary milestone; Mirror chrome costs $50,000). Saved as
`profile.vanPaint`, mirrored as `rewards`' `paint:<id>` / `paintOn:<id>`.

**Trading** (8.7, `server/PlayerTrade.luau`, `client/TradeUi.luau`, `shared/PlayerTradeRules.luau`,
`Config.PlayerTrade`): at another player's piece on show **Make an offer** (1× – 10× its value); the owner answers on
the offer card. A **FOR SALE** sign on a piece on show (Set price) lets everybody else **Buy $X**, even while the owner
is on a run. The server re-checks everything in one step; the seller gets the price minus an 8 % fee; both are saved at
once.

**Showing off** (8.2, `server/SandboxLeaders.luau`, `shared/SandboxLeadersRules.luau`): the player list's 💰 $, 📈 $/min
and ⭐ Collection, and the **TOP MOVERS** board in the lobby with the all-time best (the OrderedDataStore
`Sandbox_TopCollection`).

**The Auction House** (8.8, groundwork): the rules (`shared/AuctionRules.luau`), the building
(`shared/AuctionHouseLayout.luau`, its place in the lobby) and the window (`client/AuctionUi.luau`) exist; the server's
part does not yet, so `Config.Auction.On = false` keeps it out of the game (`design/auction/PLAN.md`).

**Roblox badges** (8.4, `server/SandboxBadges.luau`, `shared/SandboxBadgeRules.luau`, `Config.SandboxBadges`): 13
milestones (First Move, Seasoned Mover, Handle With Care, On Display, First Sale, Hot Seller, Legendary Find,
Completionist, Upgraded, Logistics Tycoon, Fresh Paint, Top Mover, First Deal). Every badge is **off** until the owner
creates it on Roblox and pastes its id (an id of 0 is never awarded): `design/sandbox/BADGES.md`.

**The economy** (8.4): you save up, or you are lucky. Ordinary furniture is at most Rare; Epic and Legendary pieces are
collectibles; the upgrades cost $352,000 in all. A house stays the same (its seed kept in your save) until a run brings
something home.

## The guide, hints and keys (8.4, 10.3)

- **The guide** (`client/SandboxGuide.luau`, `shared/SandboxSteps.luau`, `Config.SandboxGuide`): a hint line, a chevron
  and a glowing path say what to do next. The path shows only while it helps (`Path`: "new", a player with nothing home
  yet this session; "always"; "never") and always for a place picked on the big map; it slides after your feet. Once
  nothing is urgent, soft steps point at one new thing at a time: grow the warehouse, a hot piece, an upgrade in reach,
  the PAINT shop. Hold G (B, 💡) turns it off and on.
- **First-time hints** (`shared/SandboxHints.luau`, `client/SandboxHintsUi.luau`): the first piece in the book, the
  first task done, FILL BEST worth it, the clipboard, trading; once each, never over a window or a grip check.
- **Notices** come in the words of your device (`SandboxHud.notice`): no key in brackets on a phone or a gamepad.
- **Phones:** `client/TouchControls.luau` gives SPRINT and PUT DOWN; every window and button keeps a finger's size
  (`Ui.MinTouch`), and `tools/phone-ui/check.py` checks the windows at 844 × 390, 667 × 375, 1280 × 800 and 1920 × 1080.

## Light and sound

**The light** (8.4, `Config.SandboxLight`, `shared/SandboxLightRules.luau`, `client/SandboxLight.luau`): a fixed
afternoon outdoors; calm lamps indoors (the house, each warehouse level, the van's bay); and the eyes adapt: the
exposure, one bloom, a colour grade and the sun rays ease to the place you are in (outdoors, the house, a hall, the
van) over 0.6 s, never at once, and at once behind a door's black. A phone or a tablet blooms less. A bloom or sun rays
from the place's template are switched off on the screen. `tests/sandboxlight_test.luau` and
`tests/sandboxlight_runtime_test.luau` hold every light to `Caps`.

**The sounds** are synthesized for the game by `art/audio/make_audio.py` (numpy + ffmpeg, nothing borrowed). Roblox
limits audio uploads, so they are sheets: `art/audio/music.ogg` (the loops) and `sfx.ogg`, `sfx2.ogg` … `sfx6.ogg` (the
effects one after another; sfx4 the moves' and the warehouse's sounds, sfx5 the clipboard, the trades and the auction,
sfx6 the start: the intro's van and jingle, the start screen, the creator and the ride). `src/shared/SoundSheet.luau`
(written by the script) says where each sound sits and holds each sheet's asset id; `client/Sounds.luau` plays just that
region, and while a sheet is not uploaded its stand-ins play (`SoundSheet.Fallback`). The sandbox's own cues are
`client/SandboxSounds.luau`, `client/MoveSounds.luau` and `client/SoundScape.luau` (`shared/SoundPlan.luau`). **All six
sheets stay**: the game plays from each one, and cutting one means uploading it again. To change a sound, edit the
script, run `python3 art/audio/make_audio.py` from `zombie-delivery/`, upload the sheet again (View → Asset Manager →
Bulk Import) and paste its id into `SoundSheet` (the owner's steps: `art/audio/NAHRAT-SFX*.md`). `tests/audio_test.luau`
checks every region and `tests/run_tests.py` every sheet's length (with ffprobe).

**The store art** (`art/store/`, made by `design/store-art/`): the DELIVEROS logo, four thumbnails and two icons for the
game's page on Roblox (`design/store-art/NAVOD.md`).

## Saving (8.4)

`server/PlayerData.luau` writes every save with UpdateAsync, and only while the stored save is still this server's
session (its lock holds the JobId, a session id and the save's number). Every save passes through
`shared/SaveGuard.luau` first: a NaN, an infinity, a function, a table with holes or a string that is not UTF-8 is
mended and named in the Output instead of failing the write. Top-level keys this version does not know (a newer
server's) are written back unchanged.
- **When:** every 60 s, 3 s after a purchase, a book milestone or pieces brought home (`PlayerData.saveSoon`), when a
  player leaves, and for everyone on shutdown.
- **When it fails:** tries again with a backoff (3 tries, 5 for the leave and shutdown saves); a load that fails never
  gets a fresh profile that could be saved over the real one: the player is kicked with a message to rejoin. A rejoin
  waits for its own leave save.
- **Compatibility (keep it byte-compatible):** the store `Config.Sandbox.Store` and its keys (and the 10.1 slots' own),
  the lock; every field and its `*Kept` flag; `rewards`' short keys (`book:<id>`, `warehouse:<k>`, `paint:<id>`,
  `paintOn:<id>`, `mv:<n>`), which an older server keeps, so a save it wrote again gets them back; the OrderedDataStore
  `Sandbox_TopCollection`. A save keeps writing the old city's boolean flags it has, so an older server never pays a
  refund twice.

The numbers are in `Config.Saving`; `tests/saveguard_test.luau` and `tests/saving_runtime_test.luau` (a failing, slow
and throttled DataStore) cover it.

## Testing in Studio

- **Local Server** with 2 players (Studio → Test → Clients and Servers) for the party, the trades and the crew; keep the
  server's window open: its Output must stay free of red errors.
- **The admin panel** (P, or 🛠 ADMIN top right; a Studio Play test, the place's owner and `Config.Admin.UserIds`; the
  server checks every command again, `server/Admin.luau`, `shared/SandboxAdmin.luau`). Its **SANDBOX** tab, for the
  TARGET player: 💰 +$10K / MONEY 0; **Runs**: the difficulty (🎚 EASY … NIGHTMARE), ▶ any of the six houses, ⏹ END RUN,
  ⏩ SKIP CLOCK, 🧟 HORDE NOW; 📦 FILL / 🗑 CLEAR STOCK, ⭐ FILL STANDS, 📖 FILL / CLEAR BOOK; 📍 TO HOUSE / TO WAREHOUSE /
  TO LOBBY; ⬆ MAX / ↺ RESET UPGRADES, 🏗 LV 1 … LV 5, 🎨 UNLOCK / RESET PAINTS; 🔍 SHOW ZONES; the read-only Badges
  line. Outside that tab: the performance overlay (`client/PerfOverlay.luau`, `design/performance/NAVOD.md`), fly and
  noclip, and RESET MY SAVE (the slot played; its courier kept).
- **The end-to-end test** (`tests/sandbox_e2e_runtime_test.luau`) runs the whole loop with the real modules; the Studio
  checklist for what it cannot see is `design/sandbox/TEST-STUDIO.md` (written for 8.3: its steps before the lobby and
  the runs are older).
- **Analytics** (`server/Analytics.luau`, `server/SandboxAnalytics.luau`, `shared/AnalyticsPlan.luau`): the 10-step
  onboarding funnel and the moves' events; nothing is sent from Studio, the admin panel shows the counts. The owner's
  guide: `design/analytics/NAVOD.md`.

## Code

```
src/server/   Main.server (boots the game: SandboxBoot), SandboxBoot (starts every service in order), PlayerData and
              SaveSlots (saves), LobbyWorld and SandboxWorld (the lobby and the countryside), SandboxPlots (a plot
              each), Runs, RunDanger, Loot (the runs), Moving, HouseInterior, MoveSites, MoveHelper, Clipboard,
              PairHold, Npcs (the moves, the houses, Danny), HelperCrew (the crew), Vehicles, SprinterMesh, VanPaint
              (the van),
              Collection, CollectionBook, Warehouse, WarehouseMesh, Upgrades, SandboxTasks, Visitors, VisitorOffers,
              PlayerTrade, SandboxLeaders, SandboxBadges (the warehouse and what it holds), FurnitureMesh,
              FixtureMesh, HouseMesh (the Blender dressers), CourierAvatar, CharacterArt (the bodies), Zombies,
              Admin, Analytics, SandboxAnalytics
src/client/   Main.client (starts the client's modules), Menu (the start screen), CharacterCreator, RideUi, Hud and
              SandboxHud, RunUi, RunDangerUi, LootOutline, LootStars, SandboxMapUi / SandboxMiniMap / SandboxMapDraw /
              SandboxMapData, CrewUi, WarehouseUi, UpgradeUi, CollectionBookUi, SandboxTasksUi, VanPaintUi, TradeUi,
              OfferCard, AuctionUi, DannyOrders, DannyBubble, MoveHelperCard, CarryGripUi, PairSteer, PairLead,
              WalkDoors, SandboxGuide, SandboxHintsUi, KeyHints, SandboxLight, Sounds, SandboxSounds, CameraRig,
              TouchControls, AdminPanel, PerfOverlay; Ui, Theme, CardKit (the windows' parts)
src/first/    Loading.client (the intro and the loading screen, ReplicatedFirst)
src/shared/   Config (every number), Net (the remotes), SandboxMap (the lobby's and the countryside's plan),
              RunRules, DangerRules, LootRules, CrewRules, SandboxMapRules, HouseLayout and Layouts/, FurnitureLooks,
              HouseRoute, MovingRules, MoveHelperBrain, CarryGrip, PairCarry, DoorSwing, CollectionRules,
              CollectionBookRules, WarehouseLayout, UpgradeRules, Market, Visitors, VanPaintRules, VanLook,
              PlayerTradeRules, AuctionRules, SandboxBadgeRules, SandboxLeadersRules, SandboxTasks, SandboxSteps,
              SandboxHints, SandboxPad, SandboxLightRules, SaveGuard, SaveSlotRules, CharacterLooks, SoundSheet,
              SoundPlan, Joints, Icons
tests/        run_tests.py and every *_test.luau; tests/runtime/ the harnesses (Roblox stand-ins)
tools/        check-requires.py, phone-ui/ (the windows on phones and computers), the Blender imports' checks
              (sprinter/, warehouse/, furniture/, fixtures-art/, house-art/), countryside/, lobby/, spots/,
              move-sites/, crew/, loot/ (the plans' data and their previews), perf/ (the counts), sandbox-map/,
              village/ (the 3D views' renderer), vehicle-preview/ (the van on a recorder), character-art/, model-art/
design/       the plans and the owner's guides: lobby, countryside, sandbox, warehouse-levels, crew, loot, map,
              auction, the blender-* models, store-art, analytics, performance
art/          audio/ (the sound sheets and make_audio.py), store/ (the Roblox page's art)
```

**Code rules** (the full list in `AGENTS.md`): Luau `--!strict`, a header comment that says what each module does,
every number in `Config.luau`, the server decides money, items and rewards (the client only asks through `Net`), at
most 200 registers a function (`client/Hud.luau` is at the limit), and the characters' joints are AnimationConstraints:
write `Transform` through `shared/Joints.luau` in `RunService.PreSimulation`, never `C0`.

## Tests

From `zombie-delivery/`:

```bash
python3 tests/run_tests.py <path to the luau binary>      # ends with ALL TEST FILES PASSED
python3 tools/phone-ui/check.py <path to the luau binary>
python3 tools/check-requires.py
```

- `run_tests.py` runs every `tests/*_test.luau` (each must print `ALL CHECKS PASSED`), the source checks (the build
  stamps, the D-pad, the guide's points, the audio sheets' lengths), the plans' data
  (`tools/countryside/sandboxmap.py --check`, `tools/lobby/sandboxmap.py --check`), every require
  (`tools/check-requires.py`), the Blender imports' checks (the Sprinter, the warehouse, the fixtures), and it compiles
  every module the way Studio does (`luau-compile -O0 -g2`: at most 200 registers a function). It reads
  `design/countryside/plan.json`, `design/lobby/plan.json`, `design/jinocany/plan.json` (the village art kit that the
  countryside and the lobby still use) and `design/blender-house/roblox/ZDCHouseArt.json`, and copies
  `tools/vehicle-preview/roblox-mock.luau`, `tools/fixtures/item-mock.luau` and `tools/perf/world-mock.luau` (the Roblox
  stand-ins).
- `tools/phone-ui/check.py` checks every window on a phone, a computer and a gamepad.
- The Luau CLI is the `luau` and `luau-compile` binaries from https://github.com/luau-lang/luau/releases. An optional
  type check: `luau-lsp analyze` with a Rojo sourcemap and the Roblox definitions.

## History

- **1.0 – 7.x, Zombie Delivery:** a delivery game in a zombie city (jobs, missions, the phone, the guns, cars and bikes,
  traffic, the day and night, real estate, 7.x's moving rework). Gone in 10.5; git's history up to 10.4 has it all.
- **8.0, the sandbox:** a small test world in place of the city (an alpine meadow with one road, one house to empty,
  four plots with a warehouse each, the walk-in Sprinter you drove home), then the collection, the book, the tasks, the
  warehouse's levels, the market, the visitors, the PAINT shop, trading (8.1 – 8.7).
- **8.9, Jinočany:** the owner's village as the map; **9.0, the countryside:** open fields and six places to empty.
- **10.0, the lobby and the runs:** no more driving, loot with rarities; 10.1 the intro, save slots and the character
  creator; 10.2 the danger, the map and the crew; 10.3 a quieter guide; 10.4 the ride.
- **10.5:** only the sandbox is the game.
