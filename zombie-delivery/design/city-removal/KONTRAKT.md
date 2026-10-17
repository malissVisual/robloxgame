# 10.0: only the sandbox (the contract for the workers)

The owner (17. 10. 2026): "remove everything that is not active now, only the sandbox; that will be the game, what
was before I don't want any more" and, asked to confirm, "ano, smaž to" (yes, delete it). The reason: helpers keep
spending time on code that is not in the game. **Deleting the city's code, tests, tools, art and designs is approved.**
Everything stays in git's history (main up to 8.9.4).

`PLAN.md` (this folder) is the analysis this follows; its stage numbers are used below. Stage 0 needs no tag (the
history is enough), and stage 1 is done on `claude/magical-brahmagupta-af54ch`:
- `server/Main.server.luau` and `client/Main.client.luau` start only the sandbox;
- the 65 modules nothing reached are deleted, with their tests.

## What stays (the game)

Jinočany (the village, `SandboxMap`, `SandboxWorld`, `VillageScenery`, `VillageTraffic`), the moves (`Moving`,
`HouseLayout`'s house and big house, `HouseInterior`, the furniture and fixtures, carrying, `PairCarry`, the doors,
Danny: `MoveHelper*`, his clipboard, his card, his orders), the move's zombies (the horde a move spawns: `Zombies`
with ambient off, `ZombieAnimator`, `ZombieLife`, `ZombieFx`, `EnemyOutline`), the van (`Sprinter*`, `Vehicles` for
it, driving, boarding, the pedals), the plots and warehouses (`Warehouse*`, `SandboxPlots`), the collection, the book,
the upgrades, the tasks, the leaders, the market, the visitors, the PAINT shop, trading, the auction, the badges, the
light, the sounds, the admin's SANDBOX tab, the crew and the lobby for moves, the HUD's sandbox parts, the key hints,
the start screen.

**The sandbox save must stay byte-compatible** (`PLAN.md` "The sandbox save must stay byte-compatible"): the store
`Config.Sandbox.Store` (`ZombieDelivery_v2_Sandbox`), the key `Player_<UserId>`, the lock, every sandbox field and
its `*Kept` flag, `rewards`' `"book:<id>"` keys, the OrderedDataStore `Sandbox_TopCollection`. Keep writing the ten
boolean city flags a save has (so an older server never pays a refund twice).

## Who owns what (one owner per file; ask the lead before touching another's)

The require graph's sides (who requires a shared module today):

| Owner | Files |
| --- | --- |
| **server** | `src/server/**`; the shared modules only the server requires: AvatarLook BagFill BuddyBrain CarUpright CargoLooks ChaletLooks CourierMotion Crossings Deliveries FootEvents FootbridgeShape Freight GunModels HouseLayout HouseRoute JobQueue JobRules KitArt MissionPlan MoveSiteLooks MovingRules SandboxBadgeRules SandboxLeadersRules SandboxScenery SaveGuard Shift Shortcuts SpawnSpot StreetProps Style TowerLooks TrafficLanes VanQuest VillageLooks WeatherPlan ZombieKinds, and `shared/Layouts/Farm.luau`; `tests/runtime/**`; the tests of those modules; `tools/move-sites`, `tools/fixtures-art`, `tools/warehouse`, `tools/sprinter`, `tools/house-art`, `tools/furniture` (only as far as their checks need) |
| **client** | `src/client/**`; the shared modules only the client requires: AuctionRules BodyMotion CardLayout DriveFeel Explore Gait Goal InteractPose Inventory ItemLooks MapStyle Melee MissionArt OutlinePick PedalRules Readiness RentalDocks RiderPose SandboxHints SandboxPad SandboxSteps ScooterRide ShopPick ShotFeel SoundPlan SoundSheet Suspension; `tools/phone-ui/**`; the tests of those modules |
| **assets** | `art/**`; `design/**` except `design/city-removal/*`; `tools/**` except the server's and client's above, `tools/check-requires.py`, `tools/village`, `tools/fixtures/item-mock.luau` and `tools/vehicle-preview/roblox-mock.luau` (`tests/run_tests.py` runs or copies them); `README.md`; `AGENTS.md` |
| **lead** | `src/shared/Config.luau`, `Net.luau`, every shared module both sides require (Map, Economy, Missions, …) and `TutorialSteps`, `JobThumbs`, `RunCycle`, `ZipLines`; `COLLAB.md`; `design/city-removal/*`; the version and the build stamps; the final merge |

`tests/run_tests.py` is everyone's. Only remove lines in it (a PURE name, a copy of a file you deleted, a city
check), or change the few that name your files. Keep those edits small: the lead merges three branches.

## The rules

- **Delete** what the game no longer needs in your own files: modules, their tests, the harness pieces only they
  used. Shared modules both sides require are not yours: stop requiring what you no longer need, and the lead
  deletes them once nothing does.
- **Treat `Config.Sandbox.On` as always true** in your files: keep the sandbox branch, drop the other (the 319
  `Sandbox.On` / `SB.on` checks, `PLAN.md` stage 6). Do not edit `Config.luau`. If you need a constant, keep it in your
  module or ask the lead. List the Config sections you no longer read in your report.
- **The State** (`Main.server`'s `sendState`, the `State` remote) is the server's to trim. The sandbox client reads
  only `money`, `car` and `cars` from it; the client worker makes the client read nothing else there. Every other
  sandbox state (the collection, the upgrades, the paint …) comes on its own remote, as now.
- **The admin:** the server drops `Admin`'s city commands, and the client drops `AdminPanel`'s city tabs and buttons.
  The SANDBOX tab and its commands stay, and so do the performance overlay, fly and noclip.
- **Keep** what `PLAN.md` "Behaviour hidden in city helpers" lists when you replace a city helper:
  - `TouchControls` (SPRINT and PUT DOWN on phones);
  - `ZDCVanArt` and `ZDCHouseArt` in Main's move-out list;
  - all five audio sheets;
  - the modules found by name.
- `--!strict`, the header comments (say what is the game's, not what the city did), the file's own style.
- Before you hand over:
  - `python3 tests/run_tests.py <luau>` and `python3 tools/phone-ui/check.py <luau>` pass;
  - `python3 tools/check-requires.py` is clean;
  - luau-lsp on the files you changed is clean (if you can run it);
  - commit on your branch, and report what you deleted, what you changed, the tests you changed and why, and the
    Config sections and shared modules you no longer use.
