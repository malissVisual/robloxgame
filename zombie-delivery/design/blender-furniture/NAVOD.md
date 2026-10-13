# Nábytek pro stěhování v Blenderu a ve hře

![Obývák](room-preview.png)

Hezčí modely všech **36 věcí, které se ve stěhování (7.0 MOVES) odnášejí z domu**: od gauče, piana a ledničky po
houpacího koně, kolo a krabici s nádobím. Každý kus má **přesně rozměry ze hry** (neviditelná krabice `Root`, kterou
hráči nosí a skládají do auta), takže se ve hře nic nezmění, jen vzhled. Vedle katalogu je zařízený **obývák**
(obrázek nahoře). Všechno postavil skript `furniture.py`, takže každou barvu a tvar můžeš změnit a nechat postavit znovu.

![Všech 36 kusů](furniture-preview.png)

| Soubor | Co to je |
| --- | --- |
| `furniture.blend` | Hotová scéna: 36 kusů v mřížce, obývák, světla, kamera. Stačí ji otevřít. |
| `furniture.py` | Skript, který všechno postaví (je přibalený i uvnitř `furniture.blend`). |
| `roblox/ZDCFurnitureArt.fbx` | **Model pro hru**: každý kus rozdělený podle povrchu (krok 4). |
| `roblox/ZDCFurnitureArt.json` | Seznam dílů (podle něj kontrola `mesh-check.py` ověří, že nábytek ve hře sedí). |
| `furniture-preview.png`, `room-preview.png` | Náhledy z Blenderu (Cycles). |

## 1. Otevři ho v Blenderu
Dvakrát klikni na `furniture.blend` (nebo *File → Open*). Je uložený v Blenderu 5.2. Pokud ho tvoje verze neotevře,
otevři prázdný Blender a spusť `furniture.py` (krok 3): postaví úplně stejnou scénu.

Ovládání v 3D okně:
- **prostřední tlačítko myši** = otáčení, **Shift + prostřední** = posun, **kolečko** = přiblížení;
- klikni na kus a zmáčkni **Numpad .** (tečka) = přiblíží se na něj, **Home** = ukáže všechno;
- **Numpad 1 / 3 / 7** = zepředu / z boku / shora, **Numpad 0** = pohled kamery (celý katalog);
- **Z** = způsob zobrazení (Material Preview ukazuje barvy, Rendered ukazuje světla);
- **F12** = render přes aktivní kameru. Obývák má vlastní kameru: v Outlineru klikni na `Room camera` a zmáčkni
  **Ctrl + Numpad 0** (teď je aktivní ona), pak F12. Hezčí obrázek dá *Render Engine: Cycles* v panelu Render.

## 2. Prohlédni si, jak je postavený
Vpravo nahoře je **Outliner**:
- kolekce **Furniture** má pro každý kus vlastní kolekci `F_sofa`, `F_piano`, `F_fridge` … (36 kusů v řadách po 6,
  10 studů od sebe). Spodek kusu je na zemi, předek míří k tobě (na −Y), 1 jednotka v Blenderu = 1 stud ve hře;
- kolekce **Room** je obývák: podlaha z prken, tapeta, lišty, okno se záclonami, koberec, světla, kamera a kopie
  kusů z katalogu. Kopie sdílí tvar i materiály s katalogem: když v katalogu upravíš tvar gauče (Edit Mode),
  změní se i v obýváku.

Na čem se dá učit:
1. Klikni na díl (třeba polštář gauče) a otevři panel **Modifiers** (ikona klíče). **Bevel** zakulacuje hrany: zkus
   změnit *Amount* nebo *Segments*.
2. Zmáčkni **Tab**. Jsi v režimu úprav (Edit Mode), kde **G / R / S** posouvá, otáčí a zvětšuje vybrané body.
   **Tab** tě vrátí zpátky.
3. Barvu změníš v panelu **Material** (červená koule), položka *Base Color*. Materiály se jmenují podle povrchu
   (`F wood`, `F fabric`, `F brass` …) a sdílí je všechny kusy: změna `F wood` přebarví všechno dřevo.

## 3. Změň ho skriptem a postav znovu
Nahoře klikni na záložku **Scripting**, v textovém editoru vyber `furniture.py` (nebo *Open* a soubor `furniture.py`).
Nahoře je **NASTAVENÍ** a pod ním seznam povrchů:

```python
EXPORT = False   # True = uloží ZDCFurnitureArt.fbx pro hru do složky "roblox"
FINISHES = {
    "fabric": ("#367C80", 0.9, 0, 0),   # barva, drsnost, kov, záře
    "wood": ("#B08052", 0.55, 0, 0),
    ...
```

Každý kus má vlastní funkci (`def sofa`, `def piano`, `def fridge` …), kde jsou jeho díly: `box` (kvádr se
zaoblenými hranami), `cyl` (válec), `ball` (koule), `tube` (trubka), `lathe` (soustružený tvar jako váza nebo noha
lampy) a `torus` (prstenec). Změň, co chceš, a zmáčkni **Run Script** (▶ nebo Alt + P). Stará scéna se smaže
a postaví se nová. Když kus vyleze ze své krabice, skript to vypíše (*sticks out*).

Rozměry kusů v seznamu `ITEMS` neměň: hra má stejné rozměry v `src/shared/FurnitureLooks.luau` a kontrola hlídá,
že sedí. Kdybys chtěl kus větší nebo menší i ve hře, řekni Claudovi.

## 4. Nábytek ve hře
Hra tyhle modely použije v každém domě při stěhování (Marge's House). Hráči nosí pořád stejnou krabici `Root`
(kolize, nošení, nakládání do auta i poškození zůstávají), jen místo kostiček z dílů uvidí model z Blenderu. Barvy
látek, dřeva a laku se mění podle varianty kusu, takže dva gauče v různých domech nejsou stejné. Nápisy na krabicích
(FRAGILE · KITCHEN, TOYS, FAMILY PHOTOS, THIS SIDE UP) zůstávají.

Nový vzhled se objeví, až model jednou nahraješ do Roblox Studia. Udělat to musíš ty: Roblox zobrazí 3D model jen
tehdy, když je nahraný pod tvým účtem, a k tvému účtu se nepřihlásím. Do té doby má nábytek dosavadní vzhled z dílů.

Jednou ve Studiu (s hrou otevřenou jako obvykle):
1. *File → Import 3D* (nebo karta *Home → Import 3D*) a vyber `design/blender-furniture/roblox/ZDCFurnitureArt.fbx`.
2. Nastavení nech, jak je, a dej **Insert / Import**. Ve Workspace se objeví model `ZDCFurnitureArt` (velká mřížka
   nábytku). Může zůstat, kde je: hra ho při spuštění sama schová a oblékne z něj každý kus v domě.
3. Ulož místo (*File → Save*) a *File → Publish to Roblox*, ať ho má i hra na Robloxu.

Vyzkoušení: dej **Play**, zmáčkni **P** (admin panel), v sekci **Moves** dej **▶ MOVE: START NOW** a pak **MOVE: GO
TO THE HOUSE**. Dveře domu jsou zamčené: vykopni je (*Kick door*, Technician je odemkne: *Pick lock*) a dej
*Enter house*. Uvnitř uvidíš nový nábytek.

Když nábytek v Blenderu změníš: nastav `EXPORT = True`, ulož `.blend` (Ctrl + S) a spusť skript. Pak ve Studiu smaž
starý `ZDCFurnitureArt` a naimportuj nový `roblox/ZDCFurnitureArt.fbx` (krok 1 až 3).

### Jak to funguje (pro zvědavé)
- Každý kus je rozdělený podle povrchu: díl `sofa_fabric` je všechna látka gauče, `sofa_wood2` jeho nohy. Hra
  (`src/server/FurnitureMesh.luau`) dá každému dílu barvu a materiál Robloxu (látka = Fabric, dřevo = Wood, mosaz
  = Metal, sklo = Glass …). 185 dílů má dohromady asi 85 000 trojúhelníků.
- Malé kostičky `mark_o`, `mark_x`, `mark_y`, `mark_z` ukazují hře, jak Roblox model při importu otočil a zvětšil,
  a `mark_sofa`, `mark_piano` … kde stojí který kus. Proto na nastavení importu nezáleží.
- Dům staví `src/server/HouseInterior.luau`: každý kus postaví jako dřív a hned ho oblékne do modelu z Blenderu.
  Kus z modelu má méně dílů než ten původní, takže je dům i lehčí.

## Bez Blenderu (pro AI pomocníky)
`pip install bpy` (Python 3.13) a z této složky:
```
python furniture.py -- --save furniture.blend --export roblox --render /tmp/furniture-renders --samples 64
```
Render udělá `item-NN-<id>.png` pro každý kus a `room.png` (obývák). Náhled `furniture-preview.png` je z nich složený
arch. Po změně modelu spusť z kořene repozitáře `python3 zombie-delivery/tools/furniture/mesh-check.py <luau>`
(simuluje import do hry a ověří, že každý díl sedí ve své krabici, je přivařený k Root a nic nekoliduje).
