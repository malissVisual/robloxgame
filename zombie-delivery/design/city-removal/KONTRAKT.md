# 10.5: only the sandbox (the contract for the workers)

The owner (17. 10. 2026): "remove everything that is not active now, only the sandbox; that will be the game, what
was before I don't want any more" and, asked to confirm, "ano, smaž to" (yes, delete it). The reason: helpers keep
spending time on code that is not in the game. **Deleting the city's code, tests, tools, art and designs is approved.**
Everything stays in git's history (main up to Deliveros 10.4).

`PLAN.md` (this folder) is the analysis this follows. It was written on an older tree, so its numbers are old, but its
stages, the save rules and "Behaviour hidden in city helpers" still hold. **Stage 1 is done** on
`claude/magical-brahmagupta-af54ch`:
- `server/Main.server.luau` and `client/Main.client.luau` start only the sandbox;
- the 61 modules nothing reached are deleted, with their tests.

## What the game is (it stays)

Deliveros 10.4, as main's README describes it:
- **The lobby:** `LobbyWorld`, the plaza, the four plots and warehouses, the portals.
- **The runs:**
  - `Runs`, `RunUi`, `RunRules`, the difficulties;
  - the danger: `RunDanger`, `DangerRules`, `RunDangerUi`, locks and keys, the vault, hazards, zombies from Hard,
    the bat.
- **Loot:** `Loot`, `LootRules`, `LootOutline`, `LootStars`.
- **The map:** `SandboxMapUi`, `SandboxMiniMap`, `SandboxMapDraw`, `SandboxMapData`, `SandboxMapRules`.
- **The crew:** `HelperCrew`, `CrewRules`, `CrewUi`; Danny, Bruno, Zip, Gus and Lucy, rescues, the hospital.
- **The start:**
  - the intro and loading screen (`src/first/Loading.client.luau`);
  - the save slots (`SaveSlots`, `SaveSlotRules`);
  - the character creator (`CharacterCreator`, `CharacterLooks` and what it uses);
  - the start screen.
- **The ride:** `RideUi`.
- **The countryside's houses:** in their run zones (`SandboxMap`, `Layouts/Countryside`, `CountryLooks`, the spots).
- **The moves inside a run:**
  - `Moving`, `HouseLayout`, `HouseInterior`, the furniture and fixtures and their Blender dressers;
  - carrying, `PairCarry`, the doors;
  - the truck at the house (`Vehicles` parks it).
- **The warehouse and what it holds:** the warehouses and their levels, the collection, the book, the upgrades, the
  tasks, the leaders, the market, the visitors.
- **The rest:**
  - the PAINT shop, trading, the auction, the badges;
  - the light, the sounds, the guide;
  - the admin's SANDBOX tab, the key hints, the HUD's sandbox parts.

**The sandbox save must stay byte-compatible** (`PLAN.md`):
- the store `Config.Sandbox.Store` (`ZombieDelivery_v2_Sandbox`), its keys (and the 10.1 save slots' own keys), the
  lock;
- every sandbox field and its `*Kept` flag, `rewards`' `"book:<id>"` keys, and the OrderedDataStore
  `Sandbox_TopCollection`;
- keep writing the boolean city flags a save has, so an older server never pays a refund twice.

## What goes

1. **The old city:** everything `Config.Sandbox.On = false` used to boot, and every branch for it.
2. **Sandbox leftovers the game can no longer reach.** For example:
   - driving the van yourself: there is no driving since 10.0 (10.4's ride is an animation), so the 9.1 pedals and
     the driver's input go if nothing drives;
   - the Jinočany village and its traffic, which the 9.0 countryside replaced;
   - the old kiosk and contract flow, if the portals replaced it;
   - Danny's hire (10.2 made him free).

   **Prove each one dead** from the code path (`SandboxBoot`, the client's Main, the runs) before deleting it.
3. **Not deleted:** a feature only switched off by a Config flag (e.g. `Config.Auction.On`, a badge id of 0). List
   it in your report; the owner decides.

## Who owns what (one owner per file; ask the lead before touching another's)

The require graph's sides (who requires a shared module today):

| Owner | Files |
| --- | --- |
| **server** | `src/server/**`; the shared modules only the server requires: BagFill BuddyBrain CarUpright CargoLooks ChaletLooks CourierMotion Crossings Deliveries FootEvents FootbridgeShape Freight GunModels HouseLayout HouseRoute JobQueue JobRules KitArt MissionPlan MoveSiteLooks MovingRules SandboxBadgeRules SandboxLeadersRules SandboxScenery SaveGuard Shift Shortcuts SpawnSpot StreetProps TowerLooks TrafficLanes VanQuest VillageLooks WeatherPlan ZombieKinds, and `shared/Layouts/*`; `tests/runtime/**`; the tests of those modules; the checks in `tools/` that test server things (`move-sites`, `fixtures-art`, `warehouse`, `sprinter`, `house-art`, `furniture`, `spots`, `lobby`, `countryside`, `crew`, `loot`), only as far as their checks need |
| **client** | `src/client/**` and `src/first/**`; the shared modules only the client requires: AuctionRules BodyMotion CardLayout DriveFeel Explore Gait Goal InteractPose Inventory ItemLooks MapStyle MissionArt OutlinePick PedalRules Readiness RentalDocks RiderPose SandboxHints SandboxPad SandboxSteps ScooterRide ShopPick ShotFeel SoundPlan SoundSheet StyleLooks Suspension; `tools/phone-ui/**`; the tests of those modules |
| **assets** | `art/**`; `design/**` except `design/city-removal/*`; `tools/**` except the server's and client's above, `tools/check-requires.py`, `tools/fixtures/item-mock.luau` and `tools/vehicle-preview/roblox-mock.luau` (`tests/run_tests.py` runs or copies what it names: check it); `README.md`; `AGENTS.md` |
| **lead** | `src/shared/Config.luau`, `Net.luau`, every shared module both sides require (Map, Economy, Missions, CharacterLooks, …) and the ones nobody requires directly (`CountryLooks`, `JobThumbs`, `RunCycle`, `TutorialSteps`, `ZipLines`, `Layouts` are the server's); `COLLAB.md`; `design/city-removal/*`; the version and the build stamps; the final merge |

`tests/run_tests.py` is everyone's. Only remove lines in it (a PURE name, a copy of a file you deleted, a city
check), or change the few that name your files. Keep those edits small: the lead merges three branches.

## The rules

- **Delete** what the game no longer needs in your own files: modules, their tests, the harness pieces only they
  used. Shared modules both sides require are not yours: stop requiring what you no longer need, and the lead
  deletes them once nothing does.
- **Treat `Config.Sandbox.On` as always true** in your files: keep the sandbox branch, drop the other. Do not edit
  `Config.luau`. If you need a constant, keep it in your module or ask the lead. List the Config sections you no
  longer read in your report.
- **The State** (`Main.server`'s `sendState`, the `State` remote) is the server's to trim. The client worker makes
  the client read only what the sandbox needs: `money`, `car`, `cars` and whatever the start screen, the save slots
  and the character creator read. Each worker lists the fields it keeps in its report. Every other sandbox state (the
  collection, the upgrades, the paint, the runs, the crew …) comes on its own remote, as now.
- **The admin:** the server drops `Admin`'s city commands, and the client drops `AdminPanel`'s city tabs and buttons.
  The SANDBOX tab and its Runs group stay, and so do the performance overlay, fly and noclip.
- **Keep** what `PLAN.md` "Behaviour hidden in city helpers" lists when you replace a city helper:
  - `TouchControls` (SPRINT and PUT DOWN on phones);
  - `ZDCVanArt` and `ZDCHouseArt` in Main's move-out list;
  - all six audio sheets;
  - the modules found by name.
- `--!strict`, the header comments (say what the game does, not what the city did), the file's own style.
- Before you hand over:
  - `python3 tests/run_tests.py <luau>` and `python3 tools/phone-ui/check.py <luau>` pass;
  - `python3 tools/check-requires.py` is clean;
  - luau-lsp on the files you changed is clean (if you can run it);
  - commit on your branch, and report what you deleted, what you changed, the tests you changed and why, and the
    Config sections and shared modules you no longer use.
