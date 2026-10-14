# 8.0 SANDBOX: the contract between the parallel workers

**Pro majitele (česky):** malá testovací verze hry místo velkého města. Na mapě je:
- jeden dům na vystěhování;
- silnice;
- čtyři pozemky hráčů. Na každém stojí sklad ZDC a parkuje tam váš Sprinter van, do kterého se dá vejít.

Hra jde takhle:
1. Zakázku vezmete na tabuli u skladu.
2. Dojedete k domu a vynesete z něj věci do vanu.
3. Odvezete je do svého skladu.
4. Tam je vystavíte na stojany. Vystavené věci vydělávají každou minutu, co hrajete, a kdykoli je můžete prodat.

Staré město zůstane v kódu vypnuté (`Config.Sandbox.On = false` ho vrátí), dokud ho nesmažeme.

---

Everything below is for the workers (agents). **Keep the names and shapes here.** If you must change one, say so in your report.

## Shared files (already on the base branch)
- `src/shared/SandboxMap.luau`: the world's data. It holds only numbers: plots, roads, the house, spots.
  - A spot is `{ x, y, z, yaw }`.
  - yaw is in degrees and gives the way the spot looks: 0 = north (-z), 180 = south (+z).
  - `SandboxMap.cframe(spot)` builds the spot's CFrame.
- `Config.Sandbox = { On, Van = "sprinter", MaxPlayers = 4 }`.
- `src/server/SandboxPlots.luau` (done): one plot per player.
  - It sets the player attribute `Plot` (1..4).
  - API: `SandboxPlots.of(player)`, `SandboxPlots.owner(id)`, `SandboxPlots.onChanged(fn)`.
- `src/server/Collection.luau`: a STUB of the collection API (see "Collection" below). The collection worker fills it in; everyone else calls it as written.

## The loop
1. **PLAY.** You stand at your plot's `spawn`, and your Sprinter van waits at `vanSpot`, nose to the street and back doors to the warehouse's roller door.
2. **Contract.** The Moving contracts board at `board` offers one contract: "The Old Chalet" (`SandboxMap.House`). Each move gets a new seed, so the house is refilled.
3. **Drive.** Drive down Main Street to the house. Its front door at `House.door` has "Enter house", which fades you into `HouseInterior`, the existing system.
4. **Carry.** Carry the pieces out (grip, Danny, two-person lifts all as now) and load them into the van. You can walk inside the van; the load and packing work as now.
5. **Unload.** Drive back. With the van's back or middle (or the line between them; 8.0.1) inside your plot's `unload` circle, the van's contents go into your warehouse's stock: `Collection.add` for each piece, to the move's owner. This is a "trip". You can do more trips until you press FINISH or the clock runs out.
6. **Warehouse.** It has `Config.Warehouse.Stands` display stands. An empty stand's prompt opens the picker (`Collection.openPicker`), and you choose a piece from your stock. It stands there (its 3D model) and earns money every minute you play. A shown piece's prompt can take it down or sell it.

## Who owns what
These are the workers and their files. Don't edit another worker's files except for a one-line hook, and report any hook you add.

| Worker | Owns | Reads / calls |
| --- | --- | --- |
| **boot-server** | `server/Main.server.luau`. In sandbox mode it skips the city and its services. It also wires the new services, gives the van at PLAY (at `vanSpot`), sets the spawn, and owns `Config.Sandbox`. | SandboxPlots, Vehicles |
| **boot-client** | `client/Main.client.luau`, `client/Hud.luau` gating (do-blocks only; -O0 limit) and `client/Menu.luau`. In sandbox mode only the needed client systems start. | — |
| **map** | `server/SandboxWorld.luau` (new): ground, roads, the turnaround, scenery (a light alpine meadow: trees, a fence, far mountains), the lighting, and the house's outside (a chalet, `ChaletLooks`). Not the warehouses. | SandboxMap |
| **sprinter** | `Config.Cars` entry `sprinter` (Mercedes Sprinter-like, high roof, ZDC livery), its parts look (`shared/SprinterLooks.luau` + the Vehicles style), and a walk-in cargo bay: floor and walls collide, the back doors open, a side sliding door, a bed big enough for every furniture piece. Plus `Config.Sprinter`. | Vehicles |
| **sprinter-blender** | `design/blender-sprinter/` (script, .blend, FBX `ZDCSprinterArt`, Czech guide) and `server/SprinterMesh.luau`, which dresses the sprinter once the owner imports the FBX. The parts look stays as the fallback and the collision. | Config.Sprinter |
| **moves** | `server/Moving.luau`, `MoveSites`, `Config.Moving`. In sandbox mode: one contract (the house), boards at the plots, the drop-off = your plot's `unload`, `Collection.add` per piece, a new seed each move, the Sprinter's bed (`Config.Moving.Beds.sprinter`), and no Wall/soldier. | SandboxMap, SandboxPlots, Collection |
| **warehouse** | `server/Warehouse.luau` + `shared/WarehouseLayout.luau` (new): the warehouse building on every plot (roller door, lights, ZDC sign, owner's name), the display stands (prompts: Display / Take down / Sell), the shown pieces' models (`FurnitureLooks.build` + `FurnitureMesh.dress`), and a $/min tag on each. `Config.Warehouse`. | SandboxMap, SandboxPlots, Collection |
| **collection** | `server/Collection.luau` (replace the stub), `shared/CollectionRules.luau` (pure: values, rarity, income a minute, sell price), the save (`profile.collection`, its own migration flag), the `"Collection"` remote and its rate limit, the income tick, and the analytics reasons `CollectionIncome` / `CollectionSale`. `Config.Collection`. | PlayerData |
| **ui** | `client/SandboxHud.luau` (money, income a minute, the stock count, toasts) and `client/WarehouseUi.luau` (the picker: your stock's pieces with picture, name, condition, $/min, sell price; DISPLAY / SELL). `Config.SandboxHud`. | the `"Collection"` remote |
| **collectibles** | New rare pieces (`FurnitureLooks` + `Config.Furniture` defs with a `rarity`), e.g. gold record, antique vase, oil painting, trophy, vintage radio, jukebox, knight's armour, globe. The house's layout places a few each move. | — |
| **admin** | The admin panel's SANDBOX tab and its server commands: money, refill the house, clear or fill the stock, teleport to the house or the warehouse, bring the van, skip the clock. | every API above |

## Collection (the API, server)
```
Collection.add(player, { item, variant?, condition, name? }) -> uid?
Collection.stock(player) -> { Entry }      Entry = { uid, item, variant, condition, name, stand?, got }
Collection.display(player, uid, stand) -> ok, why
Collection.undisplay(player, uid) -> ok, why
Collection.sell(player, uid) -> money?, why
Collection.incomePerMinute(player) -> number
Collection.openPicker(player, stand)
Collection.onChanged(fn(player))
Collection.onAdded(fn(player, entry))   8.2: after Collection.add took a piece (entry a copy): the collection book
Collection.sell(player, uid, expect?)   8.3: at the market's price (shared/Market.luau); `expect` given: only at that price
Collection.market(player) -> View?      8.3: today's hot and cold kinds and the player's demand
Collection.marketIncome(item) -> number 8.3: today's × on a piece's income (the stands' tags)
Collection.onPaid(fn(player, kind, money, paid))   8.3: paid = { hot } (the hot kinds' share)
Collection.sellAt(player, uid, price, reason) -> money?, why   8.3 visitors: sold at a price the server set (a visitor's offer, server/VisitorOffers.luau), paid as `reason`
```

**The remote `"Collection"`:**
- client → server: `{ kind = "display", uid, stand }`, `{ kind = "undisplay", uid }`, `{ kind = "sell", uid }`, `{ kind = "state" }`.
- server → client:
  - `{ kind = "state", stock = { Entry }, income = n, stands = n }`, sent after every change and on request;
  - `{ kind = "pick", stand = n }`, which opens the picker;
  - `{ kind = "sold", name, money }`.
  - 8.3: the state also carries `market` (the player's Market View); a View has `base` (the price without the market) and `market` ("hot", "cold" or nil); `sell` and `sellmany` may carry `expect` (the price the client showed).

## Config tables
Each worker appends its own table at the end of `shared/Config.luau`, just before `return Config`:
- `Config.Sprinter`;
- `Config.Warehouse` (`Stands`, …);
- `Config.Collection` (`Tiers`, …);
- `Config.SandboxHud`.

Moves keeps `Config.Moving`. Boot keeps `Config.Sandbox`.

## Rules (as always)
- `--!strict`; the server decides money and items; game text in English.
- **The -O0 limit:** no new top-level locals in `client/Hud.luau`, `server/Jobs.luau` or `server/World.luau`.
- **Save migrations:** only real saves (`saved.money ~= nil`), with a flag.
- New money reasons go into `shared/AnalyticsPlan.luau`; remote rate limits into `Config.Robust.Limits`.
- New pure modules go into the `run_tests.py` PURE list, with tests.
- Run the checks from `zombie-delivery/AGENTS.md`.
- Commit on your branch with the trailers. Don't push. Don't bump the version. Don't edit COLLAB or README; put a README paragraph in your report.
