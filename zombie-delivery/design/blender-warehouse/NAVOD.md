# Sklad ZDC v pěti úrovních (Blender)

![Pět úrovní skladu](warehouse-levels.png)

Tvůj nápad: sklad se dá vylepšovat od **levelu 1** do **levelu 5** a s každým vylepšením je větší (víc místa na
stojany a další věci, které vymyslíš). Tady je pět modelů v Blenderu, od malé garáže po logistické centrum:

| Level | Budova | Velikost (šířka × výška zdí × hloubka) | Vrata | Stojanů (návrh) |
| --- | --- | --- | --- | --- |
| 1 | **Garáž**: omítnutá, pultová střecha, otevřená sekční vrata, boční dveře, okno, popelnice | 26 × 12 × 22 | 14 × 9,5 | 2 |
| 2 | **Dílna**: plechová (vlnitý plech), nízká sedlová střecha, oranžový rám vrat, ZDC na štítu, palety a sudy | 40 × 15 × 30 | 18 × 12 | 4 |
| 3 | **Sklad**: betonový sokl, plech, světlíky ve střeše, nápis ZDC STORAGE, sloupky a nárazníky u vrat | 58 × 19 × 42 | 22 × 14 | 8 |
| 4 | **Velký sklad**: dvoubarevný plášť s oranžovým pruhem, prosklená kancelář na boku, klimatizace na střeše | 80 × 24 × 60 | 26 × 16 | 12 |
| 5 | **Logistické centrum**: klenutá střecha se solárními panely, dva doky s rampami, prosklený roh, vlajky | 104 × 28 × 84 | 26 × 18 | 20 |

- **Level 4 má přesně rozměry dnešního skladu ve hře.** Dnešní sklad je tedy „level 4“ a hra může začínat menším.
  **Od verze 8.2 ho hra používá:** jakmile model naimportuješ, dostane sklad na každém pozemku vzhled levelu 4
  (krok 3).
- **Level 5 se ještě vejde na pozemek** (120 × 152) a nic z žádného levelu nezabírá místo, které pozemek potřebuje:
  - místo, kam couvá dodávka (UNLOAD HERE);
  - cestu vraty dovnitř;
  - nástěnku se zakázkami;
  - místo, kde se objevíš;
  - podlahu uvnitř, kam se staví stojany.

  Hlídá to kontrola `tools/warehouse-art/check.py`.
- Všechny budovy mají vrata uprostřed přední zdi (tam, kde jsou dnes) a uvnitř prázdnou podlahu a světla. Pod
  střechou mají ocelové vazníky, garáž dřevěný trám.

| Soubor | Co to je |
| --- | --- |
| `warehouse.blend` | Hotová scéna: pět budov vedle sebe, slunce, kamery. Stačí ji otevřít. |
| `warehouse.py` | Skript, který budovy postaví (je přibalený i uvnitř `warehouse.blend`). |
| `roblox/ZDCWarehouseArt.fbx` | **Model pro hru**: všech pět levelů, každý rozdělený podle povrchu. |
| `roblox/ZDCWarehouseArt.json` | Velikost, vrata, zdi (na kolize) a všechny díly každého levelu. |
| `warehouse-levels.png` | Náhled: celá řada a každý level zvlášť (Cycles). |
| `warehouse-preview.png` | Náhled levelu 4 tak, jak bude ve hře: zvenku a zevnitř, se stojany, pultem UPGRADES, tabulí STOCK a cedulí s tvým jménem (8.2). |

## 1. Otevři ho v Blenderu
Dvakrát klikni na `warehouse.blend`. Je uložený v Blenderu 5.2. Pokud ho tvoje verze neotevře, otevři prázdný Blender a
spusť `warehouse.py` (krok 3): postaví úplně stejnou scénu.

- **prostřední tlačítko myši** = otáčení, **Shift + prostřední** = posun, **kolečko** = přiblížení;
- klikni na budovu a zmáčkni **Numpad .** = přiblíží se na ni, **Home** = ukáže všechno;
- kamery: `Kamera řada` (všech pět) a `Kamera level 1` … `Kamera level 5`. Klikni na kameru v Outlineru a zmáčkni
  **Ctrl + Numpad 0**, pak **F12** = render (hezčí s *Render Engine: Cycles*).

V Outlineru je kolekce **Warehouses** a v ní **Level 1** … **Level 5**. Oko u kolekce ji schová, takže si můžeš
prohlédnout jen jednu budovu, i zevnitř.

## 2. Změň ho skriptem
Záložka **Scripting** → `warehouse.py`. Nahoře je **NASTAVENÍ**, hlavně seznam `LEVELS`:

```python
{"id": 1, "name": "Garáž", "W": 26, "D": 22, "H": 12, "door": (14, 9.5), "roof": "shed", "rise": 2.5, "wall": "plaster", "stands": 2},
```

- `W`, `D`, `H` = šířka, hloubka a výška zdí, `door` = šířka a výška vrat;
- `roof` = střecha: `shed` (pultová), `gable` (sedlová), `barrel` (klenutá), `rise` = jak vysoko jde nad zdi;
- `wall` = plášť: `plaster` (omítka), `metal` (plech), `plinth` (beton dole, plech nahoře), `twotone` (s oranžovým pruhem);
- `FINISHES` pod tím = barvy (třeba `"orange"` je barva ZDC, `"metal"` plech).

Změň, co chceš, a dej **Run Script** (▶ nebo Alt + P). Staré budovy se smažou a postaví se nové. Pak spusť kontrolu
(`tools/warehouse-art/check.py`, krok „pro AI pomocníky“ níže), jestli se pořád vejdou na pozemek. Nebo napiš Claudovi.

## 3. Ve hře (od verze 8.2)
![Level 4 ve hře](warehouse-preview.png)

Sklad na každém pozemku dostane vzhled **svého levelu** z Blenderu (od verze 8.3, viz níže), až model jednou nahraješ
do Roblox Studia. Udělat to musíš ty: Roblox zobrazí 3D model jen tehdy, když je nahraný pod tvým účtem, a k tvému
účtu se nepřihlásím. Do té doby stojí sklad z kostiček, také ve velikosti svého levelu.

Mění se jen vzhled. Všechno ostatní zůstává z dílů hry (`src/server/Warehouse.luau`):
- **kolize:** neviditelné zdi, střecha a sloupky u vrat stojí přesně tam, kde je má model; kancelář na boku má navíc
  svůj neviditelný blok, takže jí neprojdeš;
- stojany a věci na nich, pult UPGRADES, tabule STOCK, cedule s tvým jménem nad vraty;
- žluté čáry na podlaze a místo UNLOAD HERE před vraty;
- světla v hale: svítí z lamp modelu.

Aby to sedělo, upravil Claude level 4 v `warehouse.py` podle dílů hry (zvenku skoro stejný):
- zdi jsou tlusté 1 stud jako ve hře;
- podlaha je nízko pod nápisy na podlaze a má betonové desky ve třech odstínech se spárami;
- vazníky a světla v hale visí tam, kde má hra lampy;
- žluté sloupky u vrat stojí tam, kde má hra své.

Jednou ve Studiu (s hrou otevřenou jako obvykle):
1. *File → Import 3D* (nebo karta *Home → Import 3D*) a vyber `design/blender-warehouse/roblox/ZDCWarehouseArt.fbx`.
2. Nastavení nech, jak je, a dej **Insert / Import**. Ve Workspace se objeví model `ZDCWarehouseArt` (všech pět
   levelů vedle sebe). Může zůstat, kde je: hra si ho při spuštění sama schová do ServerStorage. Nebo ho v Exploreru
   přetáhni do **ServerStorage** sám. **Nepřejmenovávej ho.**
3. Ulož místo (*File → Save*, Ctrl + S) a *File → Publish to Roblox*, ať ho má i hra na Robloxu.

Vyzkoušení: dej **Play** a na úvodní obrazovce **PLAY**. Stojíš u svého skladu. Vejdi vraty dovnitř a projdi se mezi
stojany. Nebo: **P** (admin panel) → záložka **SANDBOX** → **📍 TO WAREHOUSE**.

### Od verze 8.3: sklad se vylepšuje (level 1 → 5)

Tvůj nápad je ve hře. Každý hráč má svůj sklad na levelu 1 až 5 a u pultu **UPGRADES** ve skladu je první karta
**🏗️ Warehouse**:

| Level | Budova | Stojanů | Cena |
| --- | --- | --- | --- |
| 1 | Garage (garáž) | 2 | start |
| 2 | Workshop (dílna) | 4 | $1 500 |
| 3 | Warehouse (sklad) | 8 | $5 000 |
| 4 | Big warehouse (velký sklad) | 12 | $12 000 |
| 5 | Logistics centre (logistické centrum) | 20 | $30 000 |

- Nový hráč začíná v garáži se 2 stojany. Hráč, který už hrál, dostane jednou level 4 (dnešní sklad s 12 stojany),
  a kdo si koupil „More stands“, rovnou level 5 s 20 stojany. Nikdo nepřijde o stojan ani o věc na něm.
- „More stands“ už v UPGRADES není: víc stojanů teď dává větší sklad.
- Po koupi se sklad na pozemku postaví znovu, větší, na stejném místě. Věci zůstanou na svých stojanech, dodávka,
  místo UNLOAD HERE i nástěnka se zakázkami se nehnou. Kdo by stál ve zdi nebo na novém stojanu, ocitne se ve vratech.
- Každý level má z Blenderu svůj vzhled: hra pozná level skladu a oblékne ho tím správným levelem z modelu.
- Rozměry, ceny a stojany každého levelu jsou v `Config.WarehouseLevels` (soubor `src/shared/Config.luau`).
- Na zkoušku: **P** (admin panel) → **SANDBOX** → skupina **Upgrades** → **🏗 LV 1** … **🏗 LV 5**.

Když sklad v Blenderu změníš: nastav `EXPORT = True`, ulož `.blend` (Ctrl + S) a spusť skript. Ve Studiu pak smaž
starý `ZDCWarehouseArt` a naimportuj nový `roblox/ZDCWarehouseArt.fbx` (krok 1 až 3). U žádného levelu neměň rozměry
(`W`, `D`, `H`, `door`, `rise`) jen v Blenderu: hra má stejné rozměry v `Config.WarehouseLevels` a level jiné velikosti by odmítla.
Když chceš jinou velikost, řekni Claudovi. Kontroly v kroku „pro AI pomocníky“ řeknou, jestli pořád
sedí. Barvy ve hře nastavuje tabulka `LOOKS` v `src/server/WarehouseMesh.luau`, ne Blender: když v Blenderu změníš
barvu, řekni Claudovi.

## Pro AI pomocníky
`pip install bpy` (Python 3.13) a z této složky:
```
python warehouse.py -- --save warehouse.blend --export roblox --render /tmp/warehouse-renders --samples 64
```
Render udělá `levels.png` (řada) a `level-1.png` … `level-5.png`, z nich je složený `warehouse-levels.png`.

V `roblox/ZDCWarehouseArt.json`:
- každý level má velikost, vrata, návrh stojanů a `collide` (zdi, se kterými by hra kolidovala) a `details` (každý
  díl);
- souřadnice jsou v ose hry od středu vrat na zemi (x doprava, y nahoru, z dovnitř);
- díly ve FBX se jmenují `lvl<N>_<povrch>` a značky `mark_o/x/y/z` a `mark_lvl<N>` (počátek levelu);
- 8.2: `mark_lvl<N>_box` (roh budovy: W / 2, H, D), `mark_lvl<N>_door` (roh vrat) a `mark_lvl<N>_top` (vršek střechy)
  říkají hře, jak velký level je; krabice `collide_lvl<N>_<k>` jsou neviditelné bloky věcí mimo zdi (kancelář, palety,
  rampy…). V JSON k nim patří `marks`, `solids` a `floorTop` u každého levelu.

`python3 zombie-delivery/tools/warehouse-art/check.py <luau>` ověří proti `shared/SandboxMap.luau` a 8.3
`Config.WarehouseLevels`:
- každý level má rozměry, vrata a střechu z `Config.WarehouseLevels`; level 4 = sklad z verze 8.0;
- každý level je větší;
- všechno je na pozemku a mimo místa, která pozemek potřebuje, i mimo stojany hry na tom levelu.

8.2: `python3 zombie-delivery/tools/warehouse/mesh-check.py <luau>` (spouští ho i `tests/run_tests.py`) naimportuje model
podle JSON a oblékne s ním sklady, které staví skutečný `src/server/Warehouse.luau`, na všech čtyřech pozemcích (8.3:
levely 1 až 4, pak všechny vyrostou na level 5 a obléknou se znovu):
- každý díl na svém místě, ukotvený a bez fyziky;
- schované jsou jen díly, které jsou jen vzhled; kolize, stojany, pult, cedule a výzvy zůstávají;
- zdi, střecha, podlaha a lampy modelu sedí na dílech hry;
- nic z modelu nezasahuje do stojanů, vrat ani místa UNLOAD HERE;
- bez importu, s jinak velkým skladem nebo levelem se nic nezmění.

Náhled `warehouse-preview.png` (level 4 s díly hry, zvenku a zevnitř) z kořene `zombie-delivery/`:
```
python tools/warehouse/preview.py -- --samples 96
```
