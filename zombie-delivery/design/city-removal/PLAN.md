# Removing the old city: the plan

## Pro majitele (česky)
Staré město je v kódu celé, jen vypnuté (`Config.Sandbox.On = false` ho vrací). Sandbox z něj při startu načítá asi 160
modulů, které nikdy nespustí.
- **Smazalo by se:** zhruba dvě třetiny kódu:
  - 258 ze 408 souborů, asi 105 000 řádků;
  - plus asi 22 000 řádků městských částí uvnitř souborů, které zůstanou.
  - Patří sem mapa města, zakázky a doručování, mise a příběh, obchody, nemovitosti, firma, telefon, zbraně, kola a
    koloběžky, autobusy, lanovky, provoz, bandité, počasí a den a noc.
  - Dále asi 83 ze 155 testů, městské nástroje, asi 110 MB obrázků a 39 MB návrhů.
- **Zůstane:** celý sandbox a uložené hry v sandboxu beze změny. Město půjde kdykoli vrátit z Gitu: před prvním krokem
  se na něj dá značka (tag).
- **Rozsah:** osm kroků (0–7) po zhruba 2–12 hodinách práce agenta, celkem 5–7 pracovních dní. Po každém kroku projdou
  všechny kontroly a dostanete verzi k vyzkoušení. Nejmenší smysluplný řez jsou kroky 1 a 2: asi 1,5 dne a minus asi
  60 000 řádků.
- **Ve Studiu:** Rojo nahraje asi 150 skriptů místo 408, hráč stáhne asi 110 místo 250. Připojení i Play budou
  rychlejší.
- **Pozor:** po kroku 1 už `Config.Sandbox.On = false` město nevrátí, proto je potřeba vaše potvrzení.

## For the workers
This is a read-only analysis of `claude/adoring-mendel-v77f7v` at ed2b5fc (main + the Danny hop fix), made on
2026-10-14.
- **Static require graph:** 408 modules and 2,037 edges, each marked load-time or lazy, traced from both boot paths.
- **Stage 1 dry run (on a scratch copy):** luau-lsp clean, check-requires clean, and 138 of 140 tests green. The other
  two are the city halves of `boot_runtime_test` / `clientboot_test`, which Stage 1 removes.
- **Note:** 8.3 replaced The Old Chalet with The Alpine Lodge after this analysis. Re-run the graph before Stage 1.

### Why the sandbox loads the city today
- **Server:** `server/Main.server.luau` requires about 30 city services at its top, before `if Config.Sandbox.On`.
  `server/Admin.luau` load-requires World, Jobs, Estate, Missions, Challenges, Traffic, Buddy, BanditCars and DayNight.
  A sandbox server loads about 163 modules (about 106k lines).
- **Client:** `client/Hud.luau` load-requires Shooting, MapView, Leaderboard, BagUi, Hotbar, Holster and Objective.
  A sandbox client loads about 134 modules (about 69k lines). Every client downloads 249 client and shared scripts
  (5.5 MB).

### Stages (each keeps run_tests, phone-ui, luau-lsp and the art and mesh checks green)
| Stage | What | Code | Tests | Time |
|---|---|---|---|---|
| 0 | Tag main (e.g. `zd-city-final`), record the baseline, put an entry on the COLLAB board | – | – | 15 min |
| 1 | Make `Main.server` sandbox-only (−421 lines) and leave only the sandbox block in `Main.client` (−304). Delete the 67 modules nothing in the sandbox reaches. Update run_tests' PURE lists and city checks, the city halves of boot_runtime / clientboot, the phone-ui phone, hotbar and MISSIONS scenes, and the city tools | 67 files, about 31.9k lines | −15 files | 1.5–2 h |
| 2a | Port the 10 move runtime tests that run Moving's CITY path (`tests/runtime/MovingRuntime.luau` sets `Sandbox.On = false`): moving_runtime, movehelper_runtime, movehelper_hop, movehelper_art, carrygrip_runtime, vanpack, moving_art, farmmove, movegreeters, movestory | – | about 10 edited | 4–6 h |
| 2b | Admin's city commands; Moving's city path (Jobs, BanditCars, MoveGreeters, story, the Wall, the farm, Hand); Crew; Analytics' city funnel; Main's State (shift, bag); SandboxBoot stops starting Transport and KitWear; HouseLayout's farm; the harness fakes | 36 files, about 31.8k lines | −15 files | 4–6 h |
| 3 | Take World, DayNight and Map out of Vehicles, Zombies and the meshes (a lamp helper, the safe rule, RoadTop). City tools | 83 files, about 15.9k lines | −7 files | 3–5 h |
| 4 | Client: trim Hud, add a small Waypoint module to replace MapView, CrewPanel, MovingHud's story hooks, AdminPanel's city tabs, the feel modules | 58 files, about 26.6k lines | −24 files | 8–12 h |
| 5 | PlayerData down to the sandbox fields, Map → SandboxMap constants, MoveStory, the city funnel | 14 files, about 8.8k lines | −22 files | 4–6 h |
| 6 | Trims inside kept files: Config (about −5k), Vehicles (−1.6k), AlpineLayout (−1.6k), Economy, MoveSiteLooks, Zombies' bandits, the sounds. Inline the 319 `Sandbox.On` / `SB.on` checks | about 12k lines | a few edited | 8–12 h |
| 7 | Art (−110 MB), design (−39 MB), city tools, README (3,739 → about 300 lines), AGENTS.md, KONTRAKT, COLLAB | docs | – | 2–4 h |

End state: about 152 files and 67k lines, down from 408 files and 194k lines. The test run drops from about 92 s to
about 55 s.

### The sandbox save must stay byte-compatible
- **Store and key:** store `ZombieDelivery_v2_Sandbox` (`Config.Sandbox.Store = DataStoreName .. "_Sandbox"`), key
  `Player_<UserId>`, and the `lock` protocol.
- **Fields to keep:**
  - `money`, `cars` / `car`;
  - `collection`, `collectionBook`, `collectionBookPaid`, `sandboxUpgrades`, `sandboxTasks`, `sandboxOnboarding`,
    `market`, and every 8.3 field, each with its `*Kept` flag;
  - `rewards` with its `"book:<id>"` keys.
- **Leaderboard:** the OrderedDataStore `Sandbox_TopCollection`.
- **Safe to drop:** the city migrations (refunds, kit flags, estate, missions…). An older server reading a trimmed save
  would hand back a pistol and a vest once, so publish the save stage with "shut down all servers", or keep writing the
  ten boolean flags.

### Behaviour hidden in city helpers (keep it when replacing)
- `World.isSafe` = `Map.isSafe` (|x|, |z| < 235). This only matters if the horde is ever turned on.
- `Map.inPond`, `isWinter` and `onIce` are false or no-ops in the sandbox.
- `DayNight.nightLight` applies the day look at once.
- `TouchControls` stays: it provides SPRINT and PUT DOWN on phones.
- Keep `ZDCVanArt` and `ZDCHouseArt` in Main's move-out list. Otherwise an old place's loose import pieces fall over the
  map (the 8.0.2 bug).
- Keep all five audio sheets. The sandbox plays from each one, and cutting a sheet means uploading it again.
- Modules found by name at runtime:
  - SandboxBoot's `optional` list;
  - Main.client's own-module list;
  - Moving's `moduleNamed`;
  - Ui's PhoneContract sibling search;
  - the `FindFirstChild` requires in WarehouseUi, SandboxGuide and SandboxSounds.

The analysis's scratch files (the require graph and the stage simulation) were in the 8.3 session's scratchpad and are
not kept. Re-run the graph before starting.
