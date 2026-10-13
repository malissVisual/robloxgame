# Dodávka ZDC v Blenderu a ve hře

![Dodávka](van-preview.png)

Tvůj model dodávky pro Zombie Delivery. Ve hře je to auto **ZDC Van** z autobazaru Dead End Motors. Má rozměry Old Vanu
(13 × 6,6 studu, kola na stejných místech). Postavil ho skript `van.py`, takže každou barvu, nápis i míru můžeš změnit
a nechat dodávku postavit znovu.

| Soubor | Co to je |
| --- | --- |
| `van.blend` | Hotová scéna: dodávka, světla, kamera. Stačí ji otevřít. |
| `van.py` | Skript, který dodávku postaví (je přibalený i uvnitř `van.blend`). |
| `roblox/ZDCVanArt.fbx` | **Model pro hru**: karoserie, čtvery dveře, kolo a výbava zvlášť (krok 4). |
| `roblox/ZDCVanArt.json` | Seznam dílů modelu pro hru (podle něj kontrola `mesh-check.py` ověří, že model ve hře sedí). |
| `roblox/van.fbx` + `van_palette.png` | Dodávka jako jeden obyčejný model (třeba na ozdobu do mapy). |
| `van-preview.png` | Náhled z Blenderu (Cycles). |

## 1. Otevři ji v Blenderu
Dvakrát klikni na `van.blend` (nebo *File → Open*). Je uložená v Blenderu 5.2. Pokud ji tvoje verze neotevře,
otevři prázdný Blender a spusť `van.py` (krok 3): postaví ti úplně stejnou dodávku.

Ovládání v 3D okně:
- **prostřední tlačítko myši** = otáčení, **Shift + prostřední** = posun, **kolečko** = přiblížení;
- **Home** = ukáže celou dodávku, **Numpad 1 / 3 / 7** = zepředu / z boku / shora;
- **Z** = způsob zobrazení (Material Preview ukazuje barvy, Rendered ukazuje světla);
- **F12** = render přes kameru (obrázek se otevře v novém okně).

## 2. Prohlédni si, jak je postavená
Vpravo nahoře je **Outliner**. Dodávka je rozdělená do kolekcí:
- **Van_Body**: karoserie `Body` a všechno, co je na ní (nárazníky, zrcátka, kliky, nápisy, lemy podběhů) i uvnitř
  (sedadla, palubní deska, volant, podlaha nákladového prostoru);
- **Van_Wheels**: 4 kola (`Wheel_FL` = přední levé …);
- **Van_Lights**: světla (svítivý materiál);
- **Van_Kit**: výbava na apokalypsu (rám vpředu, střešní nosič, rezerva, kanystry, bedna, světla na střeše);
- **Van_Cutters**: schované tvary, které do karoserie **vyřezávají okna, spáry dveří a dutou kabinu s nákladovým
  prostorem**.

Na čem se dá učit:
1. Klikni na `Body` a otevři panel **Modifiers** (ikona klíče vpravo). **Bevel** zakulacuje hrany: zkus změnit
   *Amount* nebo *Segments*. **Boolean** vyřezává okna a spáry: vypni ho ikonou monitoru a uvidíš karoserii bez nich.
2. V Outlineru zapni oko u **Van_Cutters**, klikni na jeden řez okna, zmáčkni **G** a posuň ho. Okno se posune s ním.
3. Klikni na libovolný díl a zmáčkni **Tab**. Jsi v režimu úprav (Edit Mode), kde **G / R / S** posouvá, otáčí
   a zvětšuje vybrané body. **Tab** tě vrátí zpátky.
4. Barvu změníš v panelu **Material** (červená koule vpravo), položka *Base Color*.

## 3. Změň ji skriptem a postav znovu
Nahoře klikni na záložku **Scripting**. V textovém editoru vyber `van.py` (nebo *Open* a vyber soubor `van.py`).
Úplně nahoře je část **NASTAVENÍ**:

```python
PAINT = "#D9CCB0"      # lak karoserie
STRIPE = "#B3261E"     # pruh a logo
LOGO, NAME, SLOGAN = "ZDC", "ZOMBIE DELIVERY CO.", "WE DELIVER. THEY DON'T."
PLATE = "ZDC 01"
KIT = True             # False = dodávka bez výbavy na apokalypsu
EXPORT = False         # True = uloží i modely pro Roblox do složky roblox
```

Změň, co chceš (například `PAINT = "#2F5D3A"` pro vojenskou zelenou nebo `PLATE = "MALIS 1"`), a zmáčkni
**Run Script** (▶ nebo Alt + P). Stará dodávka se smaže a postaví se nová.

Rozměry (`LENGTH`, `WIDTH`, `HEIGHT`, `WHEEL`) a míry dveří nahoře ve skriptu měň jen pro Blender. Hra má stejné
míry zapsané v kódu (`STYLES.zdcvan` v `src/server/Vehicles.luau`), a kdyby nesouhlasily, dveře by se otvíraly
vedle. Kdybys je chtěl změnit i ve hře, řekni Claudovi.

## 4. Dodávka ve hře: ZDC Van
Ve hře už ZDC Van je: koupíš ho v autobazaru Dead End Motors, jakmile dokončíš misi **Price War** (kapitola Empty
Shelves, mise 5). Jezdí, vozí 4 kusy nákladu, má otvírací přední i zadní dveře, svítí, dá se přelakovat a na
střešní nosič jde dát kulomet.

Svůj vzhled z Blenderu dostane, až model jednou nahraješ do Roblox Studia. Udělat to musíš ty: Roblox zobrazí
3D model jen tehdy, když je nahraný pod tvým účtem, a k tvému účtu se nepřihlásím. Do té doby jezdí ZDC Van
v náhradním vzhledu z dílů, jako ostatní dodávky.

Jednou ve Studiu (s hrou otevřenou jako obvykle):
1. *File → Import 3D* (nebo karta *Home → Import 3D*) a vyber `design/blender-van/roblox/ZDCVanArt.fbx`.
2. Nastavení nech, jak je, a dej **Insert / Import**. Ve Workspace se objeví model `ZDCVanArt`. Může zůstat, kde
   je: hra ho při spuštění sama schová a postaví z něj každou ZDC dodávku.
3. *File → Publish to Roblox*, ať ho má i hra na Robloxu.

Vyzkoušení: dej **Play**, zmáčkni **P** (admin panel), v seznamu aut vyber **ZDC Van** a objeví se vedle tebe.
**E** u dveří řidiče = jet, **E** vzadu = otevřít zadní dveře a nakládat.

Když dodávku v Blenderu změníš: nastav `EXPORT = True`, ulož `.blend` (Ctrl + S) a spusť skript. Pak ve Studiu
smaž starý `ZDCVanArt` a naimportuj nový `roblox/ZDCVanArt.fbx` (krok 1 až 3).

### Jak to funguje (pro zvědavé)
- Model je rozdělený na skupiny `body` (karoserie a vše na ní), `doorL` a `doorR` (přední dveře), `rearL` a `rearR`
  (zadní dveře), `wheel` (jedno kolo, hra ho dá na všechna čtyři) a `kit` (výbava). Každá skupina je rozdělená podle
  povrchu (`paint` = lak, `glass` = sklo …), takže hra každému dílu nastaví barvu a materiál a lak přebarví.
- Malé kostičky `mark_o`, `mark_x`, `mark_y`, `mark_z` a `mark_w` ukazují hře, jak Roblox model při importu otočil
  a zvětšil. Proto na nastavení importu nezáleží.
- Hra (`src/server/VanMesh.luau`) přidělá dveře na panty, kola na točící se kola a karoserii na pérující tělo auta.
  Fyzika, sedadla, nakládání a světla zůstávají ze hry.

## Bez Blenderu (pro AI pomocníky)
`pip install bpy` (Python 3.13) a z této složky:
```
python van.py -- --save van.blend --export roblox --render /tmp/van-renders --samples 128
```
Náhled `van-preview.png` je složený ze tří renderů (`van-front.png`, `van-rear.png`, `van-side.png`).
Po změně modelu spusť z kořene repozitáře `python3 zombie-delivery/tools/vehicle-preview/mesh-check.py <luau>`
(simuluje import do hry a ověří, že díly sedí, dveře jsou na pantech a kola na kolech).
