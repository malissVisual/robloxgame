# Evropský dům místo chaty (Blender a hra)

![Evropský dům v sandboxu](house-preview.png)

Dům, ze kterého se stěhuje, jako **klasický evropský rodinný dům**. V testovacím světě (sandbox) nahradí starou alpskou
chatu, dnes statek **The Old Farmstead** (do plánu Jinočan The Old Chalet; rodina Novákových na konci Pražské):
- krémová omítka, šedý sokl, světlé rohové kvádry a bílé římsy mezi patry a pod střechou;
- dvě patra oken s bílým křížem, šambránami, kamennými parapety a záclonkami;
- truhlíky s červenými muškáty pod okny;
- dvoukřídlé zelené dveře v kamenném portálu se schodem a lucernou;
- sedlová střecha z pálených tašek (esovky) se třemi vikýři, hřebenáči a dvěma komíny, okapy a svody, keře u rohů.

Dům má **přesně rozměry chaty ve hře** (44 × 14,5 × 34 studu) a střecha nepřesahuje výšku 26, jako chata. Kolize,
dveře s nápisem *Enter house* i zahrada zůstávají stejné, mění se jen vzhled. Před dveřmi stojí vítající postava a
zahradní truhlíky, okna i lucerna jsou rozmístěné tak, aby se s nimi nepotkaly.

| Soubor | Co to je |
| --- | --- |
| `house.blend` | Hotová scéna: dům, trávník, cesta, slunce a dvě kamery. Stačí ji otevřít. |
| `house.py` | Skript, který dům postaví (je přibalený i uvnitř `house.blend`). |
| `roblox/ZDCHouseArt.fbx` | **Model pro hru**: dům rozdělený podle povrchu (krok 4). |
| `roblox/ZDCHouseArt.json` | Seznam dílů (podle něj kontrola `check.py` ověří, že dům ve hře sedí). |
| `house-preview.png` | Náhled z Blenderu (Cycles): ze strany a z ulice. |

## 1. Otevři ho v Blenderu
Dvakrát klikni na `house.blend` (nebo *File → Open*). Je uložený v Blenderu 5.2. Pokud ho tvoje verze neotevře,
otevři prázdný Blender a spusť `house.py` (krok 3): postaví úplně stejný dům.

Ovládání v 3D okně:
- **prostřední tlačítko myši** = otáčení, **Shift + prostřední** = posun, **kolečko** = přiblížení;
- **Home** = ukáže celý dům, **Numpad 1 / 3 / 7** = zepředu / z boku / shora;
- **Numpad 0** = pohled kamery `Kamera` (dům ze strany). Druhá kamera `Kamera ulice` ukazuje dům z ulice: klikni na
  ni v Outlineru a zmáčkni **Ctrl + Numpad 0**;
- **Z** = způsob zobrazení (Material Preview ukazuje barvy, Rendered světla);
- **F12** = render přes aktivní kameru. Hezčí obrázek dá *Render Engine: Cycles* v panelu Render.

## 2. Prohlédni si, jak je postavený
V Outlineru je kolekce **House** a v ní všechny díly s českými jmény: `Zdi`, `Sokl`, `Štíty`, `Okno rám`,
`Okno šambrána`, `Tašky`, `Hřebenáč`, `Vikýř`, `Komín`, `Svod` …

Okna a dveře jsou do zdí **vyříznuté**: schovaná kolekce **House cutters** obsahuje kvádry, které modifikátor
**Boolean** odečte ze zdí, soklu, štítů a vikýřů.

Na čem se dá učit:
1. Klikni na `Zdi` a otevři panel **Modifiers** (ikona klíče). Vypni Boolean ikonou monitoru a okna zmizí.
2. V Outlineru zapni oko u **House cutters**, klikni na jeden řez okna, zmáčkni **G** a posuň ho. Otvor v omítce se
   posune s ním (rám a sklo ne, ty jsou samostatné díly).
3. Klikni na díl a zmáčkni **Tab**. Jsi v režimu úprav (Edit Mode), kde **G / R / S** posouvá, otáčí a zvětšuje
   vybrané body. **Tab** tě vrátí zpátky.
4. Barvu změníš v panelu **Material** (červená koule), položka *Base Color*. Materiály se jmenují podle povrchu
   (`H plaster` = omítka, `H tile` = tašky, `H door` = dveře …) a změna přebarví všechno s tím povrchem.

## 3. Změň ho skriptem a postav znovu
Nahoře klikni na záložku **Scripting** a v textovém editoru vyber `house.py`. Nahoře je **NASTAVENÍ**:

```python
TARGET = "sandbox"   # "sandbox" = The Old Farmstead v sandboxu, "city" = dům Marge ve městě
TARGETS = {
    "sandbox": {"box": (44.0, 14.5, 34.0), ..., "front": [-19.0, -13.0, -7.0, 7.0, 13.0, 19.0],
                "dormers": [-13.0, 0.0, 13.0], "chimneys": [(-15.0, 6.0), (12.0, 6.0)], ...},
    "city": {...},
}
FINISHES = {"plaster": ("#E8D3A2", 0.85, 0, 0), ...}   # barvy povrchů
```

- `front`, `back`, `side` = kde podél zdi jsou okna, `dormers` = vikýře, `chimneys` = komíny, `bushes` = keře;
- `FINISHES` = barvy, třeba omítku na bílou `"#F2F0EA"` nebo dveře na modré `"#2E4A78"`;
- `TARGET = "city"` postaví menší dům Marge pro město (pro dobu, kdy se sandbox vypne).

Pak zmáčkni **Run Script** (▶ nebo Alt + P). Starý dům se smaže a postaví se nový.

Pozor na dvě věci:
- `box` (rozměry) neměň: jsou to rozměry domu ve hře. Hra by dům odmítla a zůstala by chata. Když změníš výšku
  střechy (`top`), změní se i její sklon: řekni Claudovi, musí ho přepsat i v `SandboxScenery.Chalet.Pitch`
  (kontrola `check.py` to pozná).
- **Barvy ve hře** nastavuje tabulka `LOOKS` v `src/server/HouseMesh.luau`, ne Blender (Roblox si barvy ze souboru
  nebere). Když změníš barvu v Blenderu a chceš ji i ve hře, řekni Claudovi.

## 4. Dům ve hře
Chata dostane vzhled z Blenderu, až model jednou nahraješ do Roblox Studia. Udělat to musíš ty: Roblox zobrazí 3D
model jen tehdy, když je nahraný pod tvým účtem, a k tvému účtu se nepřihlásím.

**Máš už ve Studiu starý `ZDCHouseArt` (malý dům Marge z verze 8.1)?** Smaž ho (v Exploreru ho najdeš ve Workspace
nebo v ServerStorage). Sandbox má teď zase velký dům, takže malý model by hra nepoužila.

Jednou ve Studiu (s hrou otevřenou jako obvykle):
1. *File → Import 3D* (nebo karta *Home → Import 3D*) a vyber `design/blender-house/roblox/ZDCHouseArt.fbx`.
2. Nastavení nech, jak je, a dej **Insert / Import**. V Exploreru přetáhni nový model `ZDCHouseArt` do
   **ServerStorage**. Hra by si ho schovala i sama, ale takhle je to jistota.
3. Ulož místo (*File → Save*) a *File → Publish to Roblox*, ať ho má i hra na Robloxu.

Vyzkoušení: **Play**, dej **PLAY** a dojeď dodávkou po Pražské na jih až na konec, k domu za otočkou (nebo
rovnou **P** → záložka **SANDBOX** → **📍 TO HOUSE**). Místo chaty tam stojí evropský dům. Dveře, *Enter house*,
vítající postava i zahrada fungují jako dřív.

### Jak to funguje (pro zvědavé)
- Dům je rozdělený podle povrchu (díl `house_plaster` je všechna omítka, `house_tile` a `house_tile2` tašky …).
  Hra (`src/server/HouseMesh.luau`) dá každému dílu barvu a materiál. Dílů je 21, dohromady asi 65 000 trojúhelníků.
- Malé kostičky `mark_o`, `mark_x`, `mark_y`, `mark_z` ukazují hře, jak Roblox model při importu otočil a zvětšil,
  `mark_box` velikost domu, pro který je model udělaný. Proto na nastavení importu nezáleží.
- Chatu staví `src/server/SandboxWorld.luau` a hned ji oblékne do modelu z Blenderu. Původní chata zůstává
  neviditelná: do jejích zdí pořád narážíš a její dveře drží *Enter house*. Její neviditelná střecha se otočí podle
  střechy z Blenderu (hřeben zleva doprava, sklon 31°, `SandboxScenery.Chalet.Pitch`), takže netrčí skrz novou střechu.
- Když se model nehodí (jiné rozměry, chybí značky, rozházené díly), hra ho nepoužije, napíše proč do Outputu a chata
  zůstane, jak byla.
- Dům Marge ve městě má jiné rozměry, takže tenhle model nosí jen chata v sandboxu. Pro město by se exportoval
  `TARGET = "city"` (hra má jen jeden `ZDCHouseArt`).

## Bez Blenderu (pro AI pomocníky)
`pip install bpy` (Python 3.13) a z této složky:
```
python house.py -- --save house.blend --export roblox --render /tmp/house-renders --samples 96
```
Render udělá `house-34.png` (ze strany) a `house-front.png` (z ulice), náhled `house-preview.png` je z nich složený.

Po změně modelu spusť z kořene repozitáře `python3 zombie-delivery/tools/house-art/check.py <luau>`. Podle
`"target"` v manifestu simuluje import do hry na chatě postavené jako ve `SandboxWorld.luau`, nebo na domě Marge jako
ve `World.luau`. Ověří, že:
- díly sedí a zdi stojí na kolizích;
- neviditelná střecha chaty je celá pod střechou z Blenderu;
- nic nepřekáží zahradě, vítající postavě, dveřím ani věcem ze stěhování.
