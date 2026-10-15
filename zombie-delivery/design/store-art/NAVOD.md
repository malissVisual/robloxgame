# Náhledovky a ikona hry (8.3)

Tři náhledovky (thumbnails) a ikona pro stránku hry na Robloxu. Ukazují hru, jak je teď: **stěhování**, **vzácné
věci, které najdeš při jízdě**, a **byznys se skladem**. Postavy, dodávka, chata, sklad i sběratelské kousky jsou
skutečné modely hry z Blenderu (`design/blender-*`). Stará zombie grafika (`art/promo/`) patří ke staré hře a už se
nepoužívá.

| Soubor (`art/store/`) | Velikost | Co ukazuje |
| --- | --- | --- |
| `thumbnail-1-move.png` | 1920 × 1080 | MOVE HOUSES: parta nosí gauč a krabice z chaty do ZDC Sprinteru pod Alpami |
| `thumbnail-2-find.png` | 1920 × 1080 | FIND RARE TREASURES: z krabice září legendární Zlatá lyžařská trofej, kolem trezor, kytara, gramofon se štítky vzácnosti |
| `thumbnail-3-warehouse.png` | 1920 × 1080 | BUILD YOUR WAREHOUSE EMPIRE: v Logistickém centru stojí sbírka na podstavcích a vydělává „+$/min“ |
| `icon.png` | 512 × 512 | Ikona: kurýr ZDC zvedá legendární trofej nad otevřenou krabicí |

Barvy vzácnosti jsou přesně ty ze hry (`Config.Collection.Tiers`), výdělky odpovídají legendárnímu kousku (1,5 % ceny
za minutu).

## Nahrání na Roblox
1. Otevři https://create.roblox.com → **Creations** → svoje hra.
2. V nastavení hry (startovní místo, *Place*) najdi **Icon** a **Thumbnails**.
3. Ikona: nahraj `icon.png`. Náhledovky: nahraj `thumbnail-1-move.png`, `thumbnail-2-find.png`,
   `thumbnail-3-warehouse.png` (v tomhle pořadí; první se ukazuje nejvíc). Staré zombie náhledovky smaž.
4. Roblox obrázky schvaluje (moderace), chvíli trvá, než se ukážou.

## Jak je vyrobit znovu (pro AI pomocníky)
`pip install bpy pillow` (Python 3.13, Blender 5.x jako modul; renderuje Cycles na CPU, GPU netřeba) a z této složky:
```
python t1_move.py -- --res 1920 1080 --samples 96 --out out/t1_raw.png
python t2_find.py -- --res 1920 1080 --samples 128 --out out/t2_raw.png
python t3_shop.py -- --res 1920 1080 --samples 128 --out out/t3_raw.png
python icon.py -- --res 1024 1024 --samples 128 --out out/icon_raw.png
python post.py t1 out/t1_raw.png ../../art/store/thumbnail-1-move.png
python post.py t2 out/t2_raw.png ../../art/store/thumbnail-2-find.png
python post.py t3 out/t3_raw.png ../../art/store/thumbnail-3-warehouse.png
python post.py icon out/icon_raw.png ../../art/store/icon.png
```
- `zdk.py`: společná sada: obloha, louka, hory, smrky, stěhovací krabice, kostičková postava (Roblox styl) v oblečení
  ZDC a načítání modelů hry z `.blend` souborů (dodávka, chata, sklad, nábytek a sběratelské kousky).
- `t1_move.py`, `t2_find.py`, `t3_shop.py`, `icon.py`: scény. Každá k obrázku zapíše i `.json` s místy kousků na
  obrázku (podle nich `post.py` dá štítky přesně nad ně); `-- --marks-only` jen spočítá místa, nerenderuje.
- `post.py`: barvy, záře (bloom), paprsky, nápisy, štítky vzácnosti, „+$/min“ a odznak ZDC.
- Písma: Luckiest Guy (Apache 2.0) a Lilita One (SIL OFL), obě z Google Fonts, licence ve `fonts/`.
- Pozor: pomocný skript se nesmí jmenovat jako modul Pythonu (`inspect.py` shodí import `bpy`).
