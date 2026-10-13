# Mapa, krok 2: menší alpské údolí (plán)

Toto je jen plán, ve hře se zatím nic nemění. Navazuje na **krok 1** (pryč japonská zahrada, domy jako chaty, prstenec
hor a lesy, nic se nestěhuje) a začít smí, až bude krok 1 v `main`. Krok 3 pak promění střed města ve staré
město (Altstadt) s kostelem a náměstím.

Všechna čísla tady pocházejí ze skutečného kódu hry: data mapy vytáhl sám `Map.luau` (a moduly kolem něj) a počty
dílů skutečný `World.build()` v nástroji `tools/perf`. Úplný seznam všech míst se souřadnicemi je v
`map-step2-plan.json` vedle tohoto souboru; druhá, anglická část tohoto dokumentu je návod pro agenty.

## Krátce

- **Velikost:** dnes je svět x -2150…1900, z -2950…1500 (4050 × 4450 studů). Nově **x -1350…1500, z -1500…1500**
  (2850 × 3000). To je **47 % dnešní plochy**, každá strana je asi o třetinu kratší. Za okrajem stojí kolem dokola
  zasněžené hory (prstenec z kroku 1), žádná neviditelná zeď v rovině.
- **Nic se nemaže, všechno se stěhuje blíž.** 16 míst se přesune celých (s budovami, deskou WORK HERE, ztraceným
  balíčkem i místem nakládky) a **se stejným id**. Nikdo proto nepřijde o koupený dům, garáž ani kancelář a není
  potřeba nic vracet.
- **Střed zůstává přesně na místě:** Downtown (81 bloků), předměstí (15 bloků) a první sloupec přístavu (7 bloků).
  Všech 208 domů, adresy, obchody, zastávky, koloběžky, lanovky i zkratky jsou stejné. Marge's House
  (155 Willow Ln) i Zeď u depa se nehnou, prolog funguje jako dnes.
- **Přístav se změní na alpské jezero** s molem. Zbývající sloupec přístavu bude nábřeží; Frosty's, věž Harbor
  Point a sklad se do něj posunou.
- **Zmizí:** moře, hora Mount Rot s tunelem, zamrzlé jezero s ledovou silnicí a zasněžený sever. Sníh zůstane jen
  na svahu u Ski Lodge (v údolí je léto, sníh nahoře).
- **Výkon:** dnes 22 823 dílů, po kroku 1 a 2 asi 20 700 (o 9 % méně). Vody je asi o tři čtvrtiny méně.

Obrázek „dnes a po kroku 2“ vedle sebe (vykreslený z dat mapy) je přiložený ke zprávě: `map-step2.png`.

## Co se změní

| | dnes | po kroku 2 |
| --- | --- | --- |
| hranice světa | x -2150…1900, z -2950…1500 | x -1350…1500, z -1500…1500 |
| plocha | 18,0 mil. stud² | 8,55 mil. stud² (47 %) |
| přes celou mapu | 4050 × 4450 | 2850 × 3000 |
| okraj | neviditelná zeď a deset kopců | prstenec zasněžených hor |
| voda | řeka, moře na východě, zamrzlé jezero | řeka a alpské jezero |
| nejdelší zvláštní zakázka (Army Supply, molo → základna) | 3926 studů | 1226 studů |
| Ski Lodge od depa | 2855 studů | 1377 studů |
| průměr z depa ke všem 29 místům | 1431 studů | 1264 studů |
| mapa v telefonu (mřížka objevování) | 35 × 39 políček | 25 × 26 políček |

Většina míst už dnes stojí blízko středu, proto průměr klesne jen o 12 %. Zkrátí se hlavně dlouhé cesty na sever
a na západ (základna, Ski Lodge, farma, maják, molo).

## Co zmizí

- **Moře** na východě (x > 1660) i s mořským břehem. Místo něj je alpské jezero.
- **Mount Rot a tunel.** North Highway končí u Ski Lodge.
- **Zamrzlé jezero, Ice Road, Lodge Road** a celé zasněžené pole na severu.
- **18 obyčejných bloků přístavu** (kontejnery, sklady, jejich silnice, semafory a pouliční předměty) a 36 adres
  na nich. Běžné zakázky a pevné trasy několika misí si místo nich vyberou jiné adresy.
- **Silnice:** Cliff Road, Lighthouse Road, Pine Lane, Sunset Lane, Airfield Road, Lodge Road, Ice Road a vzdálené
  konce West Highway a North Highway.
- (To už v kroku 1: Lantern Garden s lávkou.)

Žádné místo, žádný ztracený balíček, žádná mise ani výzva nezmizí.

## Co se přestěhuje (16 míst, všechna se stejným id)

| místo | dnes | nově (x, z) | kam a proč |
| --- | --- | --- | --- |
| Military Base (Maria, Army Supply, Cash Run, 4 mise) | daleko na severu za tunelem (300, -2600) | 1200, -1220 | severovýchodní kout údolí, nová Army Road od jezera |
| Old Farm (Jed, Farm Run, 5 misí) | konec West Highway (-1880, 520) | -648, -1320, otočená o 90° | sever nad městem jako farma na konceptu, nová Farm Road |
| Ski Lodge (Winter Run, budoucí Grand Hotel z příběhu) | za zamrzlým jezerem (-655, -2200) | 300, -1365, otočená o 90° | konec North Highway pod horami, sníh na svahu, vlek vede do hor |
| Harbor Docks (Army Supply, 3 mise) | u moře (1628, 0) | 1196, 0 | molo na západním břehu jezera, lodě na jezeře |
| Lighthouse Point (5 misí) | pobřeží na severu (1585, -1080) | 1380, -635, otočený o 90° | severní konec jezera, jako maják na Bodamském jezeře |
| Harbor Fuel Depot (Fuel Run, 2 mise) | jižně od přístavu (1465, 620) | 1110, 900 | pod elektrárnou, nová Depot Road |
| Old Airfield (6 misí) | daleko na jihozápadě (-1500, 1265) | 1220, 1375 | prázdný jihovýchodní kout, nová Lake Road South |
| Blackrock Prison (1 mise) | daleko na severozápadě (-1600, -1080) | -1140, -1300 | severozápad (Sankt Alm), přeložená Blackrock Road; v kroku 3 třeba stará pevnost (Burg) |
| Earl's Used Wheels (první dodávka) | daleko na západě (-1570, 460) | -1240, 156 | konec zkrácené West Highway |
| Frosty's Ice Cream (zmrzlinář, 1 mise) | blok přístavu (1, 0) | blok (0, -1) | zmrzlina na nábřeží |
| Harbor Point (věž s kanceláří k prodeji) | blok přístavu (3, -1) | blok (0, -2) | věž na nábřeží, kancelář zůstává majiteli |
| Harbor Warehouse (Freight Run, 9 misí) | blok přístavu (2, 2) | blok (0, 2) | sklad na nábřeží |
| Ocean View (vila) | útesy nad mořem (1486, -720) | 1200, -850 | svah nad jezerem (Bergdorf) |
| Pinecrest (vila) | v borovicích na západě (-1550, 806) | -1000, -1014 | les Sankt Alm |
| Lakeside Villa | u zamrzlého jezera (-60, -2157) | 1220, -677 | severní břeh alpského jezera (konečně opravdu „u jezera“) |
| Sunset Villa | konec Sunset Lane (-1460, -100) | -870, -1100, otočená | Sankt Alm, vchodem na Blackrock Road |

## Co zůstane na místě

- **Downtown:** depo se Zdí, Central Park, Dead End Motors, Wrench Garage, střelnice Lead & Co., banka, klinika,
  City Hall, policie, hasiči, FreshMart, lékárna, Big Move Movers, Dispatch Tower, Downtown Parking, všechny
  obchody (Luigi's, pekárna, pošta …), benzínky Depot Gas, Tower Gas a Westside Gas.
- **Předměstí:** škola, Grind House, Bloom, Willow Gas, Marge's House, tři domy na prodej, Birch Cottage, Rented
  Lockup a Southside Garage.
- **Nábřeží:** Harbor Gas, Rust Bridge Repairs, Harbor Lockup. **Řeka** a oba mosty.
- **Za městem:** Radio Station, Survivor Camp, Silver Spur Ranch, Riding School, Water Works, Power Plant,
  Biotech Lab, Train Yard, Gas Station s Highway Garage, Sunset Hills s Hilltop Mansion, Stadium Shelter.

## Nové rozložení (náčrt)

Sever je nahoře. Jeden znak je 60 studů na šířku a 120 na výšku. Okraj (^) jsou hory.

```
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
^XXXXXXX..FFFFF..........*LLLLL*****|||BBBBBBBBB.^
^XXXXXXX..FFFFF..........*LLLLL*****|||BBBBBBBBB.^
^XXXXXXX..FFFFF.................m...|||BBBBBBBBB.^
^........u......lllll...............|||BBBBBBBBB.^
^.....p.........lllll....GG.........|||..........^
^.............tttttttt...GG.........|||....o.....^
^...................................|||....v.....^
^..RRRR......#####################..|||......TTT.^
^..RRRR......#########$$$#########..|||.$$$..~~..^
^....cccc....####$$$#####$$#######..|||.$$$.~~~~.^
^....cccc....####$$$#####$$#######..|||.$$$d~~~~.^
^............#######=====ZZ$$#####..|||.$$$d~~~~.^
^............#######==PPP==#######..|||.$$$d~~~~.^
^EEE.........##$$$$$=======$$#####..|||.$$$d~~~~.^
^............####$$$##############..|||.$$$.~~~~.^
^............############$$#######..|||.HHH..~~~.^
^............############$$#######..|||.HHH......^
^............#####################..|||.WWWWW....^
^......rrr.....................wwwww|||.WWWWW....^
^......rrr.......hhhhhhhhhhhhh.wwwww|||UUUUUU....^
^................hhhhhhhhhhhhh...sss|||UUUUUU....^
^................hhhhhhhhhhhhh......|||..........^
^................hhhhh$$$hhhhh......|||..........^
^.............k.....SSSSSSS.........|||AAAAAAAAA.^
^...................SSSSSSS.........|||AAAAAAAAA.^
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

| znak | co to je | znak | co to je |
| --- | --- | --- | --- |
| `#` | blok Downtownu | `h` | blok předměstí |
| `$` | zvláštní blok (obchod, depo, místo mise …) | `=` / `P` / `Z` | Zeď (bezpečná zóna), park, depo |
| `H` | blok nábřeží (bývalý přístav) | `~` | alpské jezero |
| `\|` | řeka | `*` | sníh na svahu u Ski Lodge |
| `B` | Military Base | `L` | Ski Lodge |
| `F` | Old Farm | `X` | Blackrock Prison |
| `T` | Lighthouse Point | `d` | molo (Harbor Docks) |
| `U` | Harbor Fuel Depot | `A` | Old Airfield |
| `E` | Earl's Used Wheels | `R` / `c` | Radio Station, Survivor Camp |
| `r` / `s` | ranč, jezdecká škola | `W` / `w` | Power Plant, Water Works |
| `l` / `t` / `G` | laboratoř, nádraží, benzínka | `S` | stadion |
| `o` / `v` / `p` / `u` | vily Ocean View, Lakeside, Pinecrest, Sunset | `m` / `k` | Hilltop Mansion, Birch Cottage |

## Vesnice

Koncept má tři vesnice chat a staré město. Na skutečné mapě jim odpovídá:

- **Seewinkel (u jezera):** nábřeží, tedy zbývající sloupec přístavu s molem, Frosty's a majákem. Loděnice a domky
  u vody přidá krok 3.
- **Bergdorf (do svahu):** severovýchod nad městem: Sunset Hills s Hilltop Mansion a svah nad jezerem (Ocean View,
  Lakeside Villa). Volné místo na chaty je mezi základnou a jezerem (x 1270…1480, z -960…-740).
- **Sankt Alm (v lese, vesnice hráčů):** borový les na severozápadě s vilami Pinecrest a Sunset Villa; na konci
  cesty stojí vězení (v kroku 3 se z něj může stát stará pevnost).
- **Předměstí** na jihu jsou od kroku 1 chaty; jméno může dostat v kroku 3.
- **Altstadt** bude vnitřek Downtownu (krok 3).

Rozdíl proti konceptu: jezero leží na východě (tam, kde byl přístav, jak bylo zadáno), ne na jihovýchodě. Koncept
není v měřítku. Kdo chce jezero větší, má variantu B níže.

## Uložené hry

- Hra **neukládá, kde hráč stál** (po vstupu se objeví v depu nebo doma), takže stěhování míst nic nerozbije.
- **Koupené nemovitosti zůstávají** (stejné id). Kdo má domov v Lakeside Villa nebo Ocean View, objeví se na jejich
  novém místě; kancelář v Harbor Point zůstává i s firmou. **Nic se nevrací, protože nic nezmizí.**
- **Odkrytá mapa:** mřížka se změní (svět je menší). Hra už dnes umí převést starou mřížku na novou; doplní se, aby
  přestěhovaná místa, která hráč už objevil, zůstala objevená i na novém místě.
- **Navštívená místa, nalezené balíčky, výzvy (Cartographer, Every Last Box), hodnocení misí, Earl, štamgasti:**
  beze změny (pořád 29 míst a 30 balíčků).
- Kdyby se nakonec něco mazalo (varianta C), vrátí se jednou plná cena nemovitosti, stejně jako dřív u batohů,
  bundy a bot.

## Výkon

| | dílů |
| --- | --- |
| dnes (celý `World.build()`) | 22 823 |
| krok 1: pryč Lantern Garden a lávka | -1 355 |
| krok 2: pryč 18 bloků přístavu (kontejnery, silnice, lampy) | -464 |
| krok 2: semafory a přechody na zrušených křižovatkách | -184 |
| krok 2: pouliční předměty na zrušených blocích | -237 |
| krok 2: lampy na zrušených úsecích dálnic | -95 |
| krok 2: molo, palmy a skály vily Ocean View u moře | -77 |
| krok 2: tunel; zamrzlé jezero a sněhové pole | -24, -21 |
| krok 2 přidá: nábřeží, loděnice, molo, nové silnice, skály u hor | asi +290 |
| **po kroku 1 a 2** | **asi 20 700 (-9 %)** |

Přestěhovaná místa (2 466 dílů) se jen přesunou. Lesy a vraky u silnic mají pevný počet (260 stromů, 40 vraků),
takže se jen rozmístí po menším údolí. Hory kolem jsou z terénu, ne z dílů. Vody je asi o 75 % méně. Menší svět
také znamená méně objíždění a kratší cesty, takže se na mobilu méně načítá za jízdy.

## Rizika

- **Krok 1 a 2 mění stejné soubory** (`World.luau`, `Map.luau`, `MapView.luau`): proto krok 2 začne až po kroku 1 a
  hory z kroku 1 se musí stavět podle `Map.Bounds`, aby se s hranicí posunuly samy.
- **Náhodné adresy** se počítají jedním „hodem kostkou“ přes celou mapu (přístav před předměstím). Zrušené bloky
  musí dál „házet naprázdno“, jinak by se změnily adresy na předměstí. Hlídat to bude test se snímkem všech adres
  a domů dnes.
- **Přenesená místa** musí vzít s sebou všechno (postavu u desky WORK HERE, paprsky majáku, kopec sněhu). Seznam je
  v technické části.
- **Otočená místa** (farma, Ski Lodge, maják, Sunset Villa) se musí zkontrolovat ve Studiu, aby vchod mířil
  na silnici.
- **Ekonomika:** zvláštní zakázky mají pevnou výplatu a teď jsou kratší (Army Supply asi na třetinu), takže je
  potřeba přepočítat výplaty.
- **Pevné mise**, které vedly na adresy v přístavu, dostanou jiné zastávky (nic se neukládá, jen se trasa změní).

## Co prosím rozhodnout

1. **Varianta A** (doporučuji, tento plán): 47 % plochy, nic se nemaže.
   **Varianta B:** větší jezero přes celý přístav (asi 490 studů široké); přesunout by se musely i Harbor Gas,
   Harbor Lockup (garáž, kterou hráči mohou vlastnit) a Rust Bridge Repairs.
   **Varianta C:** ještě menší svět (asi 38 %) bez letiště, vězení a základny; jejich mise by se přesměrovaly jinam.
2. **Vězení a letiště:** nechat (v kroku 3 pevnost a horské letiště), nebo zrušit (varianta C)?
3. **Jména vesnic:** Seewinkel = nábřeží, Bergdorf = svah na severovýchodě, Sankt Alm = les na severozápadě.
   Hodí se takhle?
4. **Jméno přístavu:** do kroku 3 se bude dál jmenovat „Harbor“; potom třeba „Seeufer“?

## Jak se to postaví

Pět balíčků práce pro agenty (podrobně v anglické části):

1. **A – základ mapy** (sám, první): nové hranice, jezero, sníh u Ski Lodge, zrušené bloky přístavu, tabulka
   přesunů, silnice, texty míst a testy. Ostatní na něm staví.
2. **B – stavba světa** (`World.luau`): zem, voda, hory, nábřeží, přesun budov.
3. **C – mapa v telefonu, počasí, auta, provoz** (klient a moduly kolem aut).
4. **D – data, texty a uložené hry** (zakázky, texty misí, výzvy, převod odkryté mapy).
5. **E – spojení a kontrola** (všechny testy, počet dílů, Studio, README, nová verze).

B, C a D běží zároveň, každý ve svých souborech.

---

# Technical plan (English, for the agents)

Base: `claude/adoring-mendel-v77f7v` @ `4758292` (7.0; its map data is byte-identical to `8b6d8cf`). Machine-readable
twin: `design/rework/map-step2-plan.json` (bounds, geography, the 16 relocations with exact transforms, every road,
251 inventory items with old/new coordinates and references, work packages, tests, saves, risks). **Step 1 must be on
`main` before WP-A starts** (it edits `World.luau`, `Map.luau` and `MapView.luau` too).

How the numbers were made: `export.luau` required the real shared modules in the plain Luau CLI (Map, Config,
Missions, BusLines, RentalDocks, ZipLines, Shortcuts, Explore) and dumped every positional datum; the real
`World.build()` ran on `tools/perf`'s stand-in and every BasePart was binned by its position and piece; `design.py`
laid out the proposal and checked it (every new yard and plot inside the bounds, on land, no overlaps, no road through
a yard; the one flag left is the North Highway's last diagonal ending on the lodge's gate, accepted: it ends where its
old bend was).

## 1. Bounds, districts, geography

| | now | step 2 |
| --- | --- | --- |
| `Map.Bounds` | x -2150…1900, z -2950…1500 | **x -1350…1500, z -1500…1500** (47.4 % of the area; ×0.70 in x, ×0.67 in z) |
| edge | 10 terrain hills at the walls | step 1's mountain ring, from the walls outward; `Map.Ring = 420` |
| river `Map.River` | x 760…920, every z | unchanged (both bridges stay) |
| sea `Map.Sea` | x > 1660 | **gone** (shim until WP-E) |
| lake | `Map.Lake` frozen, x -490…-110, z -2340…-2060 (`onIce`) | **`Map.AlpineLake`** ellipse x 1230…1480, z -540…470, terrain water; `Map.inWater` = river or lake; `onIce` stays as an API, always false |
| winter | `Map.WinterZ = -1965` (everything north of it, west of the river) | **`Map.Winter`** rect x 120…760, z -1500…-1240 (the lodge's slope); `isWinter` reads it |
| `Map.Mountain` + tunnel | (300, -1700) r 265, tunnel z -1960…-1440 | **gone**: TrafficLanes.NorthLimit, MissionPlan.inRock, Vehicles.groundY, CarCall.roadStart lose it |
| Explore grid | 35 × 39 cells (X0 -2210, Z0 -3010), 244 chars | 25 × 26 cells (X0 -1410, Z0 -1560), 125 chars |

Districts:

- **Downtown** (ox 0, i/j -4…4, 81 blocks): **kept** as is. Step 3 turns the inner ring into the Altstadt (church and
  square on the park block); the Wall stays `Config.City.SafeHalf`.
- **Suburbs** (oz 900, i -2…2, j 0…2, 15 blocks): **kept** as is (chalets since step 1). Marge's `home_suburbs_2_0_00`
  and the `suburbs 2,0 n` EVACUATE spot are byte-identical.
- **Harbor** (ox 1080, i 0…3, j -3…3, 28 blocks): **keep column i = 0** (x 991…1169: the lake shore, its east avenue
  x 1152 the shore road), **cut i = 1…3**. Specials: `0,-3 lockup`, `0,0 gas`, `0,1 repairs` stay; `1,0 frosty → 0,-1`,
  `3,-1 harborpoint → 0,-2`, `2,2 warehouse → 0,2` (whole cells: their builders are block-relative). `(0,3)` stays
  ordinary (boathouses in step 3).
- **Dice stability (important):** `Map.addresses` rolls ONE `Map.lcg` stream across all districts in order
  (downtown, harbor, suburbs). Give the Harbor `i1 = 0` plus `diceI1 = 3` and roll the cut ordinary blocks' 5 dice
  dry; add `0,-2`, `0,-1`, `0,2` to `Map.FormerBlocks.harbor` (they turn special but roll as before). makeLots (per
  district stream, Harbor skipped), RentalDocks (Downtown/Suburbs only), StreetProps (seeded per block), ZipLines,
  Shortcuts, BusLines are unaffected. A golden snapshot test proves it.
- Harbor addresses: 44 today → 2 left (36 on cut blocks, 6 on the three blocks that turn special). Deliveries'
  `"harbor"` target (the bakery's `to`) must move to the lake shore (WP-D).

## 2. Inventory

Totals (full list with references in the JSON, 251 items): 29 `Map.Places` (19 keep, **10 move**, 0 removed),
19 yards (10 keep, 9 move), 30 secrets (20 keep, 10 move), 8 employer boards (5 keep, 3 move), 29 cargo spots
(19 keep, 10 move, each with its place), 17 estate plots (12 keep, 5 move incl. the Harbor Point office), 2 towers,
6 gas stations (all keep), 2 repair shops (keep), 16 venues (14 keep, Frosty's and the warehouse move), 67 landmarks
(51 keep, 16 move: they are derived), Earl's lot (move), the freight hub (moves with the warehouse), 3 receiving docks
(keep), Depot/Park/Gun range/shops (keep), Marge's house and the 3 EVACUATE spots (keep), 208 homes (all keep), 14 bus
stops, 21 rental docks, 8 zip lines, 8 alley shortcuts (all inside, unchanged). Geography removed: Mount Rot + tunnel,
the frozen lake + Ice Road, the sea, the WinterZ snowfield; the Lantern Garden goes in step 1.

**Relocation units: 16** (9 far yards, 3 Harbor special blocks, 4 estates); **removals: 0** (variant A).

Systems that reference places, checked one by one:

| system | what it reads | effect of step 2 |
| --- | --- | --- |
| missions (66 in `Missions.List`) | `pickupAt` / `dropAt` place ids; `MissionPlan.route` picks ordinary addresses round the depot | ids unchanged; 36 mission stops at moved places follow them; routes that used cut Harbor addresses pick others |
| job types / employers | `Config.JobTypes` pickupAt/dropAt/dropChoices, `Map.EmployerSpots` | army (base), farm, icecream (Frosty's) boards move with their places; armysupply, cashrun, winter, farmrun, fuelrun, freightrun follow their places; retune the fixed pay (WP-D) |
| tutorial | the depot, Marge (`Config.Tutorial.NpcSpot`), the first job round the depot | unchanged |
| moves (7.0) | `home_suburbs_2_0_00`, `Config.Moving.Board` / `DropOff` (the Wall), `Config.MoveSites.Spots`, MoveGreeters | unchanged (the golden test holds them) |
| shops | `Map.Shops`, gun range, gear stall, repair shops, gas stations | all inside and unchanged |
| live events | supply drop and horde round the safe zone and the depot (`LiveEvents.supplySpot`, `hordeSpot`) | unchanged (they use `Map.inWater`: the lake is water) |
| challenges | Sightseer / Cartographer (`profile.visited`, 29 places), Lost and Found / Package Sniffer / Every Last Box (30 secrets) | ids and totals unchanged |
| achievements / badges | none in the game (no BadgeService) | nothing to do |
| analytics | mission progression and economy events (`AnalyticsPlan`), no place ids | unchanged |
| discovery, GPS, location tags | `Map.Landmarks` (derived), `Explore` cells | follow the data; `Explore.migrate` keeps moved places discovered |
| zombies / bandits | bandit camps in the gas, farm, radio, lodge yards; soldiers in the base yard (by yard id) | follow their yards |
| buses, rental scooters, zip lines, shortcuts | Downtown and Suburbs blocks only | unchanged |

### 2.1 The places (`Map.Places`)

| id | name | now (x, z) | inside new bounds | fate | new (x, z) | referenced by |
| --- | --- | --- | --- | --- | --- | --- |
| `base` | Military Base | 300, -2600 | no | move | 1200, -1220 | missions (4): duo_9, army_1, army_3, army_10; job types: armysupply.dropAt, cashrun.dropAt; employer army (board Map.EmployerSpots) |
| `radio` | Radio Station | -1100, -560 | yes | keep | same | — |
| `farm` | Old Farm | -1880, 520 | no | move | -648, -1320 | missions (5): market_3, market_7, firehouse_5, ranch_2, ranch_5; job types: farmrun.pickupAt; employer farm (board Map.EmployerSpots) |
| `docks` | Harbor Docks | 1626, 0 | no | move | 1194, 0 | missions (3): market_9, army_1, underworld_8; job types: armysupply.pickupAt |
| `gas` | Gas Station | 146, -900 | yes | keep | same | missions (1): dispatch_9; job types: fuelrun.dropAt; employer gas (board Map.EmployerSpots) |
| `lodge` | Ski Lodge | -655, -2200 | no | move | 300, -1365 | job types: winter.dropAt; MoveStory ch.3 Room Service (the Grand Hotel: the concept's ski lodge/hotel) |
| `school` | Sunny Hill School | 0, 1127 | yes | keep | same | missions (1): exodus_8; job types: schoolrun.dropAt; employer school (board Map.EmployerSpots) |
| `frosty` | Frosty's Ice Cream | 1163, 0 | yes | move | 1019, -144 | missions (1): lab_5; job types: icecream.pickupAt; employer icecream (board Map.EmployerSpots) |
| `movers` | Big Move Movers | 349, 144 | yes | keep | same | job types: freightrun.dropChoices; employer movers (board Map.EmployerSpots); MoveStory villain Dana (Big Move Movers' board) |
| `ranch` | Silver Spur Ranch | -900, 740 | yes | keep | same | missions (6): ranch_1, ranch_2, ranch_3, ranch_5, ranch_8, ranch_10; job types: horses.pickupAt; employer ranch (board Map.EmployerSpots); MoveStory ch.1 Hold Your Horses (Walt, Silver Spur Ranch) |
| `stables` | Riverside Riding School | 640, 972 | yes | keep | same | missions (3): ranch_1, ranch_3, ranch_10; job types: horses.dropAt |
| `fueldepot` | Harbor Fuel Depot | 1440, 550 | yes | move | 1085, 829 | missions (2): firehouse_3, exodus_3; job types: fuelrun.pickupAt |
| `bank` | First Zombie Bank | 83, -288 | yes | keep | same | missions (3): duo_4, underworld_1, underworld_2; job types: cashrun.pickupAt |
| `clinic` | City Clinic | -227, 300 | yes | keep | same | missions (7): clinic_2, clinic_4, clinic_5, duo_7, army_4, power_2, lab_9; job types: ambulance.dropAt; employer clinic (board Map.EmployerSpots); MoveStory ch.2 Handle With Care (City Clinic) |
| `pharmacy` | Corner Pharmacy | 144, 371 | yes | keep | same | missions (1): clinic_1 |
| `market` | FreshMart Supermarket | -371, 144 | yes | keep | same | missions (4): market_1, market_3, market_9, market_10; job types: freightrun.dropChoices |
| `warehouse` | Harbor Warehouse | 1307, 288 | no | move | 1019, 288 | missions (9): dispatch_9, clinic_4, market_1, market_10, duo_2, firehouse_1, firehouse_9, power_1, underworld_5; job types: freightrun.pickupAt |
| `firestation` | Fire Station 9 | 349, -144 | yes | keep | same | missions (3): firehouse_1, firehouse_2, firehouse_3 |
| `police` | Precinct 13 | -288, -227 | yes | keep | same | missions (3): dispatch_8, ranch_8, exodus_1 |
| `cityhall` | City Hall | 0, -371 | yes | keep | same | missions (3): dispatch_8, duo_4, exodus_1; MoveStory ch.6 Heavy History (city museum: old town, step 3) |
| `airfield` | Old Airfield | -1400, 1185 | no | move | 1320, 1295 | missions (6): army_4, army_9, lab_8, exodus_3, exodus_8, exodus_10 |
| `powerplant` | Power Plant | 1100, 548 | yes | keep | same | missions (7): firehouse_9, power_1, power_2, power_7, power_8, power_10, lab_7; job types: freightrun.dropChoices; MoveStory ch.5 The Zero Files (power plant) |
| `waterworks` | Water Works | 452, 780 | yes | keep | same | missions (2): duo_2, power_8 |
| `lab` | Biotech Lab | -172, -1000 | yes | keep | same | missions (10): clinic_7, clinic_10, market_7, lab_2, lab_5, lab_7, lab_8, lab_9, lab_10, exodus_7; MoveStory ch.5 The Zero Files (Biotech Lab) |
| `prison` | Blackrock Prison | -1600, -925 | no | move | -1140, -1145 | missions (1): underworld_5 |
| `lighthouse` | Lighthouse Point | 1545, -1080 | no | move | 1380, -675 | missions (5): army_9, underworld_4, underworld_10, exodus_7, exodus_9 |
| `trainyard` | Train Yard | -216, -765 | yes | keep | same | missions (4): firehouse_5, army_3, power_7, underworld_8 |
| `camp` | Survivor Camp | -1058, -250 | yes | keep | same | missions (2): duo_1, lab_10 |
| `stadium` | Stadium Shelter | 0, 1300 | yes | keep | same | missions (6): dispatch_10, clinic_10, duo_10, firehouse_10, power_10, exodus_9 |

### 2.2 The relocations (exact transforms)

`new = to + R(turn)·(old − from)`, turn clockwise on the map with north up: R(90) maps (dx, dz) → (−dz, dx) (east →
south). In Roblox: `CFrame.new(to.x, 0, to.z) * CFrame.Angles(0, -math.rad(turn), 0) * CFrame.new(-from.x, 0, -from.z)`.

| id | from (old pivot) | to (new pivot) | turn | World mode | new yard / plot | why |
| --- | --- | --- | --- | --- | --- | --- |
| `base` | 300, -2600 | 1200, -1220 | 0° | data | yard x 940…1460, z -1460…-980 | Military Base: NE top of the valley, at the end of the new Army Road (entrance south) |
| `farm` | -1880, 520 | -648, -1320 | 90° | frame | yard x -798…-498, z -1470…-1170 | Old Farm: north of town (concept: FARM between town and the lodge), end of the new Farm Road (entrance east → south) |
| `docks` | 1628, 0 | 1196, 0 | 0° | data | yard x 1169…1224, z -200…200 | Harbor Docks → the lake pier on the west shore (piers and the ship over the lake) |
| `lodge` | -655, -2200 | 300, -1365 | 90° | frame | yard x 180…420, z -1490…-1240 | Ski Lodge: top of the North Highway (entrance east → south), the lift runs up into the peaks |
| `fueldepot` | 1465, 620 | 1110, 900 | 0° | data | yard x 935…1285, z 800…999 | Harbor Fuel Depot: south of the Power Plant, on the new Depot Road |
| `airfield` | -1500, 1265 | 1220, 1375 | 0° | frame | yard x 960…1480, z 1260…1490 | Old Airfield: the empty SE corner, end of the new Lake Road South |
| `prison` | -1600, -1080 | -1140, -1300 | 0° | frame | yard x -1340…-940, z -1480…-1120 | Blackrock Prison: NW, end of the re-routed Blackrock Road (step 3 idea: an old fortress, Burg) |
| `lighthouse` | 1585, -1080 | 1380, -635 | 90° | frame | yard x 1280…1480, z -700…-570 | Lighthouse Point → on the lake's north end (sea side east → lake side south), off the new Seeweg |
| `earl` | -1570, 460 | -1240, 156 | 0° | data | yard x -1320…-1160, z 116…196 | Earl's Used Wheels: the end of the shortened West Highway |
| `frosty` | 1224, 0 | 1080, -144 | 0° | data | its new block (whole cells) | Frosty's: Harbor block (1,0) → (0,-1), ice cream on the lake shore |
| `harborpoint` | 1512, -144 | 1080, -288 | 0° | data | its new block (whole cells) | Harbor Point tower (office_harbor): Harbor block (3,-1) → (0,-2) |
| `warehouse` | 1368, 288 | 1080, 288 | 0° | data | its new block (whole cells) | Harbor Warehouse (freight hub): Harbor block (2,2) → (0,2) |
| `oceanview` | 1486, -720 | 1200, -850 | 0° | data | plot (1200, -850) facing (-1, 0) | Ocean View mansion → on the NE slope over the lake (Bergdorf), facing the Army Road |
| `pinecrest` | -1550, 806 | -1000, -1014 | 0° | data | plot (-1000, -1014) facing (0, -1) | Pinecrest mansion → Sankt Alm (NW pine forest), on the Blackrock Road |
| `lakeside` | -60, -2157 | 1220, -677 | 0° | data | plot (1220, -677) facing (0, -1) | Lakeside Villa → the alpine lake's north shore, on the Seeweg (its jetty to the lake) |
| `sunset` | -1460, -100 | -870, -1100 | 90° | data | plot (-870, -1100) facing (0, 1) | Sunset Villa → Sankt Alm, facing south onto the Blackrock Road (front east → south) |

### 2.3 Roads

Kept: the Downtown, Suburbs and (column 0) Harbor grids, the six streets between Downtown and the Suburbs, Rust
Bridge, Old Bridge, Radio Road, Ranch Road, Riding School Lane, Sunset Drive, Birch Lane, Waterworks Road, Lab Road,
Rail Yard Road. Every new road starts on another road's centre line (a T-junction) and ends on its yard's gate, like the
old country roads; add the new names to `Map.PlaceRoads` / `Map.EstateRoads` (no wrecks on them).

| road | fate | new points | note |
| --- | --- | --- | --- |
| Airfield Road | remove | — |  |
| Birch Lane | keep | — |  |
| Blackrock Road | change | (-648, -1060) → (-1140, -1060) → (-1140, -1120) | re-routed: off the Farm Road to the prison's gate; Pinecrest and the Sunset Villa on it |
| Cliff Road | remove | — |  |
| Ice Road | remove | — |  |
| Lab Road | keep | — |  |
| Lighthouse Road | remove | — |  |
| Lodge Road | remove | — |  |
| North Highway | change | (72, -665) → (72, -1000) → (300, -1240) | ends at the Ski Lodge's gate (no tunnel, no base road) |
| Old Bridge | keep | — |  |
| Pine Lane | remove | — |  |
| Radio Road | keep | — |  |
| Rail Yard Road | keep | — |  |
| Ranch Road | keep | — |  |
| Riding School Lane | keep | — |  |
| Rust Bridge | keep | — |  |
| Sunset Drive | keep | — |  |
| Sunset Lane | remove | — |  |
| Waterworks Road | keep | — |  |
| West Highway | change | (-665, 216) → (-1100, 216) → (-1330, 216) | straight; ends at Earl's lot by the west mountains |
| Farm Road | new | (-648, -648) → (-648, -1170) | Downtown's NW corner north to the farm's gate (west of the Train Yard) |
| Army Road | new | (1152, -504) → (1152, -940) → (1200, -940) → (1200, -980) | the shore road's north end to the base's gate; Ocean View fronts it |
| Seeweg | new | (1152, -720) → (1380, -720) → (1380, -700) | along the lake's north end: the Lakeside Villa, Lighthouse Point |
| Lake Road South | new | (1152, 504) → (1320, 504) → (1320, 1260) | the shore road's south end down to the airfield's gate, east of the Power Plant |
| Depot Road | new | (1320, 780) → (950, 780) | along the Fuel Depot's north side (3 studs off the Power Plant) |

### 2.4 Everything else with a position

| group | id | now (x, z) | inside | fate | new (x, z) |
| --- | --- | --- | --- | --- | --- |
| Map.Yards | `base` | 300, -2600 | no | move | 1200, -1220 |
| Map.Yards | `radio` | -1100, -560 | yes | keep | — |
| Map.Yards | `farm` | -1880, 520 | no | move | -648, -1320 |
| Map.Yards | `docks` | 1628, 0 | no | move | 1196, 0 |
| Map.Yards | `gas` | 146, -900 | yes | keep | — |
| Map.Yards | `lodge` | -655, -2200 | no | move | 300, -1365 |
| Map.Yards | `ranch` | -900, 790 | yes | keep | — |
| Map.Yards | `stables` | 662, 975 | yes | keep | — |
| Map.Yards | `fueldepot` | 1465, 620 | yes | move | 1110, 900 |
| Map.Yards | `airfield` | -1500, 1265 | no | move | 1220, 1375 |
| Map.Yards | `powerplant` | 1142, 640 | yes | keep | — |
| Map.Yards | `waterworks` | 588, 780 | yes | keep | — |
| Map.Yards | `lab` | -285, -1050 | yes | keep | — |
| Map.Yards | `prison` | -1600, -1080 | no | move | -1140, -1300 |
| Map.Yards | `lighthouse` | 1585, -1080 | no | move | 1380, -635 |
| Map.Yards | `trainyard` | -340, -820 | yes | keep | — |
| Map.Yards | `camp` | -970, -250 | yes | keep | — |
| Map.Yards | `stadium` | 0, 1358 | yes | keep | — |
| Map.Yards | `earl` | -1570, 460 | no | move | -1240, 156 |
| Map.Clearings | `paddock` | -900, 950 | yes | keep | — |
| Map.Clearings | `arena` | 668, 1148 | yes | keep | — |
| Map.EmployerSpots | `army` | 330, -2385 | no | move | 1230, -1005 |
| Map.EmployerSpots | `clinic` | -241, 262 | yes | keep | — |
| Map.EmployerSpots | `farm` | -1790, 560 | no | move | -688, -1230 |
| Map.EmployerSpots | `gas` | 188, -948 | yes | keep | — |
| Map.EmployerSpots | `icecream` | 1177, 0 | no | move | 1033, -144 |
| Map.EmployerSpots | `movers` | 335, 144 | yes | keep | — |
| Map.EmployerSpots | `ranch` | -930, 728 | yes | keep | — |
| Map.EmployerSpots | `school` | 0, 1141 | yes | keep | — |
| Map.EstatePlots | `birch` | -513, 1260 | yes | keep | — |
| Map.EstatePlots | `elm` | -313, 1074 | yes | keep | — |
| Map.EstatePlots | `garage_downtown` | 144, 140 | yes | keep | — |
| Map.EstatePlots | `garage_harbor` | 1049, -432 | yes | keep | — |
| Map.EstatePlots | `garage_north` | 119, -722 | yes | keep | — |
| Map.EstatePlots | `garage_rented` | -30, 738 | yes | keep | — |
| Map.EstatePlots | `garage_south` | 172, 738 | yes | keep | — |
| Map.EstatePlots | `hilltop` | 520, -1186 | yes | keep | — |
| Map.EstatePlots | `lakeside` | -60, -2157 | no | move | 1220, -677 |
| Map.EstatePlots | `maple` | -169, 870 | yes | keep | — |
| Map.EstatePlots | `oak` | 169, 1014 | yes | keep | — |
| Map.EstatePlots | `oceanview` | 1486, -720 | yes | move | 1200, -850 |
| Map.EstatePlots | `office_harbor` | 1512, -144 | no | move | 1080, -288 |
| Map.EstatePlots | `office_penthouse` | -144, -144 | yes | keep | — |
| Map.EstatePlots | `office_tower` | -144, -144 | yes | keep | — |
| Map.EstatePlots | `pinecrest` | -1550, 806 | no | move | -1000, -1014 |
| Map.EstatePlots | `sunset` | -1460, -100 | no | move | -870, -1100 |
| Map.Towers | `dispatchtower` | -144, -144 | yes | keep | — |
| Map.Towers | `harborpoint` | 1512, -144 | no | move | 1080, -288 |
| Map.GasStations | `gas` | 136, -900 | yes | keep | — |
| Map.GasStations | `gas_downtown` | -576, 169 | yes | keep | — |
| Map.GasStations | `gas_harbor` | 1080, 25 | yes | keep | — |
| Map.GasStations | `gas_suburbs` | 144, 875 | yes | keep | — |
| Map.GasStations | `gas_depot` | 288, -25 | yes | keep | — |
| Map.GasStations | `gas_tower` | -288, -169 | yes | keep | — |
| Map.RepairShops | `mechanic` | 0, 144 | yes | keep | — |
| Map.RepairShops | `repairs` | 1080, 144 | yes | keep | — |
| Map.Venues | `luigis` | 266, 320 | yes | keep | — |
| Map.Venues | `dailybread` | -122, 400 | yes | keep | — |
| Map.Venues | `lastbite` | -320, -122 | yes | keep | — |
| Map.Venues | `wokdead` | 454, 112 | yes | keep | — |
| Map.Venues | `grindhouse` | -25, 868 | yes | keep | — |
| Map.Venues | `postoffice` | 22, 320 | yes | keep | — |
| Map.Venues | `dailyundead` | -32, -310 | yes | keep | — |
| Map.Venues | `boltnail` | -464, 310 | yes | keep | — |
| Map.Venues | `volt` | 400, -310 | yes | keep | — |
| Map.Venues | `secondlife` | -410, -400 | yes | keep | — |
| Map.Venues | `bloom` | -112, 1163 | yes | keep | — |
| Map.Venues | `pharmacy` | 144, 432 | yes | keep | — |
| Map.Venues | `market` | -432, 144 | yes | keep | — |
| Map.Venues | `bank` | 144, -288 | yes | keep | — |
| Map.Venues | `frosty` | 1224, 0 | no | move | 1080, -144 |
| Map.Venues | `warehouse` | 1368, 288 | no | move | 1080, 288 |
| Map.Shops | `bags` | 116, -142 | yes | keep | — |
| Map.Shops | `bikes` | 182, -18 | yes | keep | — |
| Map.Shops | `dealer` | 144, 0 | yes | keep | — |
| Map.Shops | `depot` | 144, -144 | yes | keep | — |
| Map.Shops | `guns` | -265, 116 | yes | keep | — |
| Map.Shops | `mechanic` | 0, 144 | yes | keep | — |
| Map.Shops | `supplies` | 116, -130 | yes | keep | — |
| Map.VanSeller | `earl` | -1592, 458 | no | move | -1262, 154 |
| Map.FreightDocks | `warehouse` | 1355, 306 | no | move | 1067, 306 |
| Map.ReceivingDocks | `market` | -389, 138 | yes | keep | — |
| Map.ReceivingDocks | `movers` | 326, 180 | yes | keep | — |
| Map.ReceivingDocks | `powerplant` | 1064, 574 | yes | keep | — |
| Map.Depot | `depot` | 144, -144 | yes | keep | — |
| Map.Park | `park` | 0, 0 | yes | keep | — |
| Map.Garden | `garden` | 0, -144 | yes | retire | — |
| Map.GunRange | `gunrange` | -288, 144 | yes | keep | — |
| Config.Moving.Contracts | `marge` | 263, 875 | yes | keep | — |
| Config.MoveSites.Spots | `spot1` | 288, -144 | yes | keep | — |
| Config.MoveSites.Spots | `spot2` | 288, 288 | yes | keep | — |
| Config.MoveSites.Spots | `spot3` | 288, 900 | yes | keep | — |
| Map.Mountain | `mountain` | 300, -1700 | no | cut | — |
| Map.Lake | `frozenlake` | -300, -2200 | no | cut | — |
| Map.Sea | `sea` | 1780, 0 | no | cut | — |
| Map.WinterZ | `winter` | -500, -2400 | no | cut | — |

### 2.5 The lost packages

| secret | place | now (x, z) | fate | new (x, z) |
| --- | --- | --- | --- | --- |
| `secret_base` | base | 330, -2632 | move | 1230, -1252 |
| `secret_radio` | radio | -1061, -604 | keep | same |
| `secret_farm` | farm | -1874, 470 | move | -598, -1314 |
| `secret_docks` | docks | 1650, -14 | move | 1218, -14 |
| `secret_gas` | gas | 196, -890 | keep | same |
| `secret_lodge` | lodge | -690, -2242 | move | 342, -1400 |
| `secret_ranch` | ranch | -940, 708 | keep | same |
| `secret_stables` | stables | 620, 932 | keep | same |
| `secret_fueldepot` | fueldepot | 1465, 592 | move | 1110, 871 |
| `secret_school` | school | -38, 1171 | keep | same |
| `secret_frosty` | frosty | 1210, -30 | move | 1066, -174 |
| `secret_movers` | movers | 302, 111 | keep | same |
| `secret_bank` | bank | 128, -266 | keep | same |
| `secret_clinic` | clinic | -266, 324 | keep | same |
| `secret_pharmacy` | pharmacy | 116, 414 | keep | same |
| `secret_market` | market | -411, 109 | keep | same |
| `secret_warehouse` | warehouse | 1345, 252 | move | 1057, 252 |
| `secret_firestation` | firestation | 316, -104 | keep | same |
| `secret_police` | police | -258, -258 | keep | same |
| `secret_cityhall` | cityhall | 22, -402 | keep | same |
| `secret_airfield` | airfield | -1430, 1156 | move | 1290, 1266 |
| `secret_powerplant` | powerplant | 1114, 603 | keep | same |
| `secret_waterworks` | waterworks | 483, 732 | keep | same |
| `secret_lab` | lab | -213, -1036 | keep | same |
| `secret_prison` | prison | -1626, -962 | move | -1166, -1182 |
| `secret_lighthouse` | lighthouse | 1590, -1051 | move | 1351, -630 |
| `secret_trainyard` | trainyard | -203, -817 | keep | same |
| `secret_camp` | camp | -1073, -286 | keep | same |
| `secret_stadium` | stadium | 15, 1318 | keep | same |
| `secret_stadium_top` | stadium | 191, 1430 | keep | same |

Cargo spots move 1:1 with their place (`Map.CargoSpots[id]` for the 10 moved places); the 67 landmarks are derived from
the tables above and follow automatically (their texts change: see WP-A).

## 3. Execution plan

### 3.1 The relocation recipe

1. `Map.luau` keeps every relocated datum written in its **old** coordinates (a reviewable diff) and adds
   `Map.Relocations = { [id] = { from = {x, z}, to = {x, z}, turn = 0|90|180|270 } }` with the 16 entries of 2.2, plus
   `Map.relocate(id, x, z)`, `Map.relocateDir(id, dx, dz)`, `Map.relocateRect(id, rect)`.
2. One pass at load, **after** the raw tables and **before** anything derived (Venues from Places + CargoSpots,
   Landmarks, `makeLots`' `free()`, `addresses()`, Explore's landmark cells): Yards, Clearings, Places (x, z, nx, nz),
   Secrets (x, z), EmployerSpots, CargoSpots (park, pile; facing recomputed), FreightDocks, ReceivingDocks, EstatePlots
   (x, z, facing), Towers (x, z, facing), VanSeller (all spots, facing). `Map.raw` keeps the unrelocated copies.
3. World builds each moved place in one of two modes (counted from the builders' literal world coordinates):
   - **data mode** — `base`, `docks`, `fueldepot`, `earl`, `frosty`, `warehouse`, `harborpoint`, `oceanview`,
     `pinecrest`, `lakeside`, `sunset`: the builder reads only Map data (yard, plot, block, cargo spot, VanSeller) and
     the turn is 0 or carried by a plot's facing, so it builds at the new place by itself. Literal extras to rewrite:
     Ocean View's sea pier / palms / cliff rocks at `Map.Sea.x0` (World ~4030–4046), Lakeside's jetty to
     `Map.Lake.x1 − 40` (~4054: point it south into the alpine lake); the docks' ship sits at literal z 0 (= the old
     yard's middle; the move keeps z).
   - **frame mode** — `farm` (turned), `lodge` (turned), `airfield` (10 literal calls), `prison` (10), `lighthouse`
     (turned, 7): build unchanged with `Map.raw` data into the place's folder, then pivot the folder with the transform.
     Move the side effects too: `World.EmployerNpcs.farm` (spawned outside the folder by `employerBoard`, which must
     read the raw spot during a frame build); every `LighthouseBeam` part's `Hub` attribute (a world `Vector3` that
     `client/WorldFx.luau` sweeps the beams round); the lodge's snow-hill `FillBall` (its centre lands in the north
     ring) and the ski lift (it now climbs north into the peaks).
4. The Harbor specials move by cells (2.2): only the `Map.SpecialBlocks.harbor` keys change; their builders read the
   relocated CargoSpots / FreightDocks / Towers.

### 3.2 Work packages (file ownership is exclusive)

**WP-A — Map foundation** (first and alone; ~1 agent-day; branch `wt-map2-a` from `main` after step 1)
- Owns: `src/shared/Map.luau`, `src/shared/Explore.luau`, `tests/logic_test.luau`, `roads_test`, `places_test`,
  `explore_test`, `locationtag_test`, `centre_test`, `icons_test`, NEW `tests/mapstep2_test.luau`, NEW
  `tests/mapgolden_test.luau`.
- Before any change: export the golden snapshot of the kept area (homes: id, name, door, park, floors; every
  non-Harbor address; venues except frosty/warehouse; rental docks; bus stops; zip lines; shortcuts; depot, park, gun
  range, shops; the EVACUATE spots; Marge's home) into `mapgolden_test` — it must stay green through every package.
- Bounds, `Map.Ring`, `Map.AlpineLake` + `inLake`, `inWater`, `Map.Winter` + `isWinter`, `onIce` → false; the Harbor
  cut with dry dice; the specials' keys; `Map.Relocations` + the pass + `Map.raw`; the roads of 2.3; texts in Map.luau
  (EMPLOYER_WHERE army / farm / icecream, the far places' lines for lodge, docks, fueldepot, airfield, prison,
  lighthouse, the four estates' WHERE lines, Harbor Point, Earl; the `secret_docks` hint "with the sea at your back" → the lake).
- Compat shims until WP-E (marked DEPRECATED): `Map.Sea`, `Map.Lake`, `Map.Mountain`, `Map.WinterZ` with harmless
  off-valley values, so World and MapView still run between merges.
- Explore: the grid follows the bounds; `Explore.migrate(set, oldHeader)` marks the new cell of every moved landmark
  whose raw position's cell was explored on the old grid; `decode` skips the middle mark of an old cell that lies
  outside the new grid (today it clamps to an edge cell and would uncover the new north edge for anyone who visited
  the old far north).
- Tests: each relocated datum equals transform(raw); every place / yard / secret / cargo spot / employer spot / plot /
  landmark inside the bounds, on land (the docks' piers excepted), ≤ 40 studs from a road; no overlapping yards or
  plots; every place reachable by road (`roads_test`); the golden snapshot unchanged.

**WP-B — World build** (parallel after A; ~1–2 agent-days; one helper: World.luau is one file)
- Owns: `src/server/World.luau`, NEW `src/server/Relocate.luau` (optional frame-mode helper),
  `src/server/BuildingLooks/Lodge.luau` (only if the turned lodge needs it), `tools/perf/*`,
  `tools/check-building-looks.py`, `design/performance/REPORT.md`.
- `buildGround`: tiles over the valley and the ring margin only; no SeaBed, sea water or sea embankment; river water and
  bed from ring to ring; the lake as terrain water (rows of FillBlock to the ellipse) with a bed and a shore; the edge
  hills replaced by step 1's ring (verify it reads `Map.Bounds`). `buildBoundary` follows the bounds.
- Harbor column 0 only (automatic); the shore strip x 1169…1230 and block (0,3): promenade, boathouses, a pier walk
  (~220 parts).
- Remove `buildMountain` (Tunnel), the frozen lake, its cracks, the snowfield tiles and the ice-road signs; the lodge in
  frame mode (entrance south onto the North Highway) with terrain snow over `Map.Winter`.
- The 16 relocations per 3.1; forests and road wrecks inside the valley (automatic) and off the new roads.
- `tools/perf/world_count.py` before/after into `REPORT.md`; `check-building-looks.py` (the warehouse's spot moved).

**WP-C — Runtime consumers** (parallel after A; ~1 agent-day)
- Owns: `src/client/MapView.luau`, `Weather.luau`, `Menu.luau`, `WorldFx.luau`, `Drive.luau`, `TyreFx.luau`;
  `src/server/CarCall.luau`, `Vehicles.luau`, `Traffic.luau`, `BanditCars.luau`, `Admin.luau`, `Zombies.luau`;
  `src/shared/TrafficLanes.luau`, `MissionPlan.luau`, `SoundPlan.luau`, `DriveFeel.luau`; tests `traffic_test`,
  `missionplan_test`, `soundplan_test`, `curb_test`, `liveevents_test`, `board_test`, `transport_test`.
- MapView: the ring at the edge, the lake (rounded), the snow slope; drop the sea strip, frozen lake, mountain disc and
  the TUNNEL / FROZEN LAKE / WINTER captions; add SEEWINKEL, BERGDORF, SANKT ALM (ALTSTADT in step 3); `WORLD_W/H`
  follow the bounds (the big map gets ~40 % larger on screen).
- Weather: snow only over `Map.Winter`; river mist and clouds inside the bounds. Vehicles.groundY / CarCall.roadStart
  without `Map.Mountain`; `TrafficLanes.NorthLimit` → the winter slope's edge; `MissionPlan.inRock` → false;
  `SoundPlan.waterTop` → the lake. Drive / TyreFx / DriveFeel keep their API. Menu shots and Admin teleports inside the
  valley. Zombies' bandit camps (gas, farm, radio, lodge) and soldiers (base) follow their yards by themselves.
- Tests: `traffic_test` (its point 1200, 100 is lake now; NorthLimit), `curb_test` (its sweep to x 1700), the rest
  for invariants.

**WP-D — Gameplay data, texts, saves** (parallel after A; ~1 agent-day)
- Owns: `src/shared/Config.luau`, `Deliveries.luau`, `Missions.luau`, `Challenges.luau`; `src/server/Challenges.luau`,
  `PlayerData.luau`, `Explore.luau`, `Jobs.luau`; tests `deliveries_test`, `freight_test`, `fuel_test`,
  `missions_test`, `challenges_test`, `readiness_test`, `vanquest_test`, `career_test`, `regulars_test`,
  `cargorules_test`, `jobthumbs_test`.
- Texts: JobTypes `winter` ("Through the tunnel … over the frozen lake"), the Estate descriptions (oceanview,
  lakeside, sunset, pinecrest, garage_harbor, office_harbor), the employers' pitches that name far places; mission
  briefings: 6 × tunnel, 2 × coast, 1 × ice ("Harbor" may stay until step 3 renames the shore).
- Deliveries' `"harbor"` target → the lake shore (Harbor column 0 addresses + the pier). Balance the fixed-pay special
  jobs that got shorter: `armysupply` (3926 → 1226 studs), `winter` (lodge 2855 → 1377 from the depot), `cashrun`
  (2529 → 2049), `farmrun`; the board jobs already pay by distance (`Economy.jobPay`).
- Saves: `PlayerData.applySaved` once (flag `map2 = true`) runs `Explore.migrate` on `profile.explored`; Challenges count
  `visited` and `secrets` only over current ids.
- Tests: `deliveries_test` (the Harbor target; its spot 1302, 270 is lake now), `freight_test` (the hub on block 0,2),
  the others for invariants.

**WP-E — Integration and release** (after B, C, D; ~½ day; the reviewer who merges)
- Merge B, C, D onto A; delete the shims. Run `python3 tests/run_tests.py <luau>` (every test and the `-O0 -g2`
  register check), `luau-lsp analyze`, `tools/perf/world_count.py`, `tools/move-sites/check.py`,
  `tools/polish-art/check.py`, `tools/check-building-looks.py` and a map render.
- Studio: drive every new and changed road; each moved place's employer job and one mission there; the prologue
  (155 Willow Ln → the Wall); the lake (swim, a car sinks, the pier); the lodge's snow; the minimap and the big map;
  discovering a moved place; an old save (explored map, a Lakeside Villa / Ocean View home spawn, the Harbor Point
  office and the Harbor Lockup).
- README (the map sections), COLLAB, this plan's status; version bump.

Parallelism: A alone; then B, C and D at once (disjoint files); E merges. No package edits another's files; a need
there goes to COLLAB's "Questions / handoff".

### 3.3 Tests and tools

- **Update:** WP-A `logic`, `roads`, `places`, `explore`, `locationtag`, `centre`, `icons` (+ the two new tests);
  WP-C `traffic`, `missionplan`, `soundplan`, `curb`, `liveevents`, `board`, `transport`; WP-D `deliveries`, `freight`,
  `fuel`, `missions`, `challenges`, `readiness`, `vanquest`, `career`, `regulars`, `cargorules`, `jobthumbs`.
- **Must stay green unchanged:** `buslines`, `rentaldocks`, `ziplines`, `shortcuts`, `streetprops`, `towerlooks`,
  `residents`, `movesites`, `moving_*`, `movegreeters_runtime`, `gunrange`, `gearstall`, `houseinterior` (the
  interiors at 9000, 400, 9000 stay beyond the ring); `garden_test` goes with step 1.
- **Tools:** `tools/perf/world_count.py` (re-run, REPORT.md), `tools/check-building-looks.py` (follows the moved
  warehouse spot), `tools/move-sites/check.py` + `render.py` and `tools/polish-art/check.py` (their areas are
  unchanged: must pass as they are), `tools/vehicle-preview/clearance-check.luau` (the footbridge: step 1).

## 4. Performance estimate

From the real `World.build()` on the perf stand-in (parts; terrain is not parts):

| | parts |
| --- | --- |
| now | 22,823 |
| step 1: Lantern Garden + footbridge | -1,355 → 21,468 |
| step 2 removes: Harbor columns 1–3 (containers, roads, lamps, wrecks) | -464 |
| … traffic lights and crosswalks of the cut junctions | -184 |
| … street props on the cut blocks | -237 |
| … highway lamps on the cut stretches | -95 |
| … Ocean View's sea pier, palms and rocks | -77 |
| … the tunnel; the frozen lake and the snowfield tiles | -24; -21 |
| step 2 adds: the shore promenade, boathouses, pier walk (~220), new roads (~40), rocks at road ends (~30) | +~290 |
| **after steps 1 and 2** | **~20,660 (-9.5 %)** |

Relocated (moved, not added): 2,466 parts (harborpoint 271, pinecrest 281, oceanview 260, fueldepot 210, warehouse
192, airfield 180, base 152, lakeside 136, sunset 133, prison 127, docks 109, lighthouse 100, earl 95, farm 84, lodge 77,
frosty 59). Forests (260 trees) and road wrecks (40) keep their caps, re-scattered over the smaller valley (denser).
Water surface about -75 % (the 488 × 5050 sea goes; the lake is a 250 × 1010 ellipse). Step 1's own additions (ring,
forests) are not in these numbers. Lights: ~24 fewer (the tunnel's 13 always-on strips, 7 highway lamps, 4 Harbor lamps); the moved places keep theirs.

## 5. Save data

- **No position is saved** (a player spawns at the depot or at their home), so moving places breaks nothing.
- `properties` / `home` / `business`: every `Config.Estate` id stays; the four moved estates and the Harbor Point office
  keep their owners; the home spawn and the garage drive-out come from the relocated plots
  (`World.EstateSpawns` / `EstateGarages`). **No refund.**
- `explored`: the grid changes with the bounds (the save string's header records its grid); `Explore.decode` already
  maps an old grid onto the new one; add `Explore.migrate` (moved landmarks keep "discovered") and the edge-clamp fix.
- `visited` / `secrets` (Sightseer, Cartographer, Every Last Box): ids and totals unchanged (29 places, 30 secrets);
  count only current ids anyway.
- `missions` / `campaigns`: ids unchanged; some fixed routes (MissionPlan) pick other ordinary addresses where cut
  Harbor addresses were (no save field).
- `vanQuest`, `regulars`, `tasks`, `story`: unchanged (Earl moves with his lot, Frosty's venue with its block).
- If the owner removes something after all (variant C): refund once through `applySaved` (the 6.6 / 6.7 / 6.12.2
  pattern: a flag and a refund line): an estate → its full `Config.Estate` price (an office: plus its business
  upgrades and the safe), `profile.home` cleared if it pointed there; places and secrets need no refund (the counts
  ignore unknown ids); a done challenge stays done.

## 6. Acceptance

- `tests/run_tests.py` all green, including `mapgolden_test` (the kept area byte-identical) and `mapstep2_test`.
- Every place / yard / secret / cargo spot / employer spot / estate plot / landmark inside the bounds, on land and
  reachable by road.
- `tools/perf/world_count.py` ≤ ~20.7k parts after both steps.
- The prologue plays as before (155 Willow Ln → the Wall's checkpoint at the depot).
- An old save loads with its estates, home spawn, explored map (moved places carried over) and challenge counts.
