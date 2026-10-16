# Deliveros: logo, náhledovky a ikony

Logo hry **Deliveros**, čtyři náhledovky (thumbnails) a dvě ikony pro stránku hry na Robloxu. Ukazují hru, jak je
teď: **stěhování**, **vzácné věci, které najdeš při jízdě**, a **byznys se skladem**. Postavy, dodávka, chata, sklad
i sběratelské kousky jsou skutečné modely hry z Blenderu (`design/blender-*`). Stará zombie grafika (`art/promo/`)
patří ke staré hře a už se nepoužívá.

| Soubor (`art/store/`) | Velikost | Co to je |
| --- | --- | --- |
| `deliveros-logo.png` | průhledné | Logo DELIVEROS: 3D zlatá písmena s červeným bokem a tmavým obrysem |
| `deliveros-logo-tagline.png` | průhledné | Totéž s červenou stuhou MOVE · FIND · GROW |
| `thumbnail-0-title.png` | 1920 × 1080 | Titulní: velké logo nad Logistickým centrem, dodávka vykládá, parta nese legendární T-Rex lebku |
| `thumbnail-1-move.png` | 1920 × 1080 | MOVE HOUSES: parta nosí gauč a krabice z chaty do dodávky pod Alpami |
| `thumbnail-2-find.png` | 1920 × 1080 | FIND RARE TREASURES: z krabice září legendární trofej, kolem štítky vzácnosti |
| `thumbnail-3-warehouse.png` | 1920 × 1080 | BUILD YOUR WAREHOUSE EMPIRE: sbírka na podstavcích vydělává „+$/min“ |
| `icon.png` | 512 × 512 | Ikona A: kurýr zvedá legendární trofej, dole DELIVEROS |
| `icon-box.png` | 512 × 512 | Ikona B: otevřená zářící krabice s trofejí, nahoře DELIVEROS |

Barvy vzácnosti jsou přesně ty ze hry (`Config.Collection.Tiers`), výdělky odpovídají legendárnímu kousku (1,5 % ceny
za minutu).

## Nahrání na Roblox
1. Otevři https://create.roblox.com → **Creations** → svoje hra.
2. V nastavení hry (startovní místo, *Place*) najdi **Icon** a **Thumbnails**.
3. Ikona: nahraj `icon.png` (nebo `icon-box.png`, podle toho, která se ti líbí víc). Náhledovky: nahraj
   `thumbnail-0-title.png`, `thumbnail-1-move.png`, `thumbnail-2-find.png`, `thumbnail-3-warehouse.png` v tomhle pořadí
   (první se ukazuje nejvíc). Staré zombie náhledovky smaž.
4. Název hry přepiš na **Deliveros** (Basic Info → Name).
5. Roblox obrázky schvaluje (moderace), chvíli trvá, než se ukážou.

## Jak je vyrobit znovu (pro AI pomocníky)
`pip install bpy pillow` (Python 3.13, Blender 5.x jako modul; renderuje Cycles na CPU, GPU netřeba) a z této složky:
```
python logo.py -- --res 2400 960 --samples 64 --out out/logo_raw.png
python post.py logo out/logo_raw.png ../../art/store/deliveros-logo.png
python post.py logo-tagline out/logo_raw.png ../../art/store/deliveros-logo-tagline.png
python t0_key.py -- --res 1920 1080 --samples 128 --out out/t0_raw.png
python t1_move.py -- --res 1920 1080 --samples 96 --out out/t1_raw.png
python t2_find.py -- --res 1920 1080 --samples 128 --out out/t2_raw.png
python t3_shop.py -- --res 1920 1080 --samples 128 --out out/t3_raw.png
python icon.py -- --res 1024 1024 --samples 128 --out out/icon_raw.png
python icon_box.py -- --res 1024 1024 --samples 96 --out out/iconbox_raw.png
python post.py t0 out/t0_raw.png ../../art/store/thumbnail-0-title.png
python post.py t1 out/t1_raw.png ../../art/store/thumbnail-1-move.png
python post.py t2 out/t2_raw.png ../../art/store/thumbnail-2-find.png
python post.py t3 out/t3_raw.png ../../art/store/thumbnail-3-warehouse.png
python post.py icon out/icon_raw.png ../../art/store/icon.png
python post.py icon-box out/iconbox_raw.png ../../art/store/icon-box.png
```
- `zdk.py`: společná sada: obloha, louka, hory, smrky, stěhovací krabice, kostičková postava (Roblox styl) v oblečení
  ZDC a načítání modelů hry z `.blend` souborů (dodávka, chata, sklad, nábytek a sběratelské kousky).
- `logo.py`: 3D nápis DELIVEROS (vysunutá písmena, zlatá tvář, červený bok, mírný oblouk), průhledné pozadí.
- `t0_key.py`, `t1_move.py`, `t2_find.py`, `t3_shop.py`, `icon.py`, `icon_box.py`: scény. Každá k obrázku zapíše i
  `.json` s místy kousků na obrázku (podle nich `post.py` dá štítky přesně nad ně); `-- --marks-only` jen spočítá
  místa, nerenderuje.
- `post.py`: barvy, záře (bloom), paprsky, nápisy, štítky vzácnosti, „+$/min“, obrys a stuha loga a jeho umístění.
- Písma: Luckiest Guy (Apache 2.0) a Lilita One (SIL OFL), obě z Google Fonts, licence ve `fonts/`.
- Pozor: pomocný skript se nesmí jmenovat jako modul Pythonu (`inspect.py` shodí import `bpy`).
