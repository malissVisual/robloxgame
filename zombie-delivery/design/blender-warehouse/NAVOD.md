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

## 3. Ve hře
**Zatím nejsou zapojené do hry.** Levely skladu ve hře ještě nejsou a sklad dnes staví `src/server/Warehouse.luau`
z dílů. Až budeš chtít vylepšování skladu:
- kolik co stojí;
- co každý level přidá (víc stojanů, víc místa);
- jak se vylepšuje.

…řekni a napojíme to stejně jako dodávku, nábytek a dům. Model `ZDCWarehouseArt.fbx` jednou naimportuješ ve Studiu a
hra postaví sklad podle tvého levelu. **Zatím ho do Studia neimportuj**, protože ho ještě nic nepoužívá.

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
- díly ve FBX se jmenují `lvl<N>_<povrch>` a značky `mark_o/x/y/z` a `mark_lvl<N>` (počátek levelu).

`python3 zombie-delivery/tools/warehouse-art/check.py <luau>` ověří proti `shared/SandboxMap.luau` a `Config.Warehouse`:
- level 4 = dnešní sklad;
- každý level je větší;
- všechno je na pozemku a mimo místa, která pozemek potřebuje.
