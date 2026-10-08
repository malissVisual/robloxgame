# Nahrát nové zvuky (sfx3.ogg, verze 6.12)

Hra má nové zvuky (dveře aut, zadní dveře dodávek, klakson H, kroky podle povrchu, šplouchnutí, ambience dne a noci,
vítr na střechách, fontána v parku, zvuky úkolů a nákupu). Jsou v jednom souboru `art/audio/sfx3.ogg` (62,5 s).
Dokud ho nenahraješ, hra hraje místo nich starší zvuky nebo ticho.

Ostatní soubory (`sfx.ogg`, `sfx2.ogg`, `music.ogg`) jsou **stejné jako dřív**, ty znovu nahrávat nemusíš.

## Postup

1. Otevři hru v Roblox Studiu.
2. **View → Asset Manager → Import / Bulk Import** (nebo na webu **Creator Dashboard → Development Items → Audio →
   Upload Asset**)
   a vyber soubor `zombie-delivery/art/audio/sfx3.ogg`.
3. Počkej, až Roblox zvuk schválí. Pak na něm klikni pravým tlačítkem → **Copy Asset ID** (je to číslo, např.
   `123456789012345`).
4. Otevři `zombie-delivery/src/shared/SoundSheet.luau` a řádek 16

   ```lua
   SoundSheet.Sfx3Id = "" -- "rbxassetid://…" of art/audio/sfx3.ogg (6.12)
   ```

   změň na (místo `123456789012345` dej svoje číslo):

   ```lua
   SoundSheet.Sfx3Id = "rbxassetid://123456789012345" -- "rbxassetid://…" of art/audio/sfx3.ogg (6.12)
   ```

5. Ulož, synchronizuj (`node tools/rojo-sync.js zombie-delivery`) a spusť hru.

**Jednodušší:** pošli Claudovi jen to číslo („Sfx3 id je 123456789012345“) a on řádek upraví za tebe.

## Jak to vyzkoušet

- Choď po chodníku, po trávníku v Central Parku, po dřevěném mostku k fontáně a v altánu, po kovové plošině lanovky
  a lez po žebříku: každý povrch zní jinak. Skoč do jezírka: šplouchne to.
- Nastup do auta a vystup (cvaknutí zámku, bouchnutí dveří), otevři a zavři zadní dveře dodávky (podrž E vzadu).
- Za volantem zmáčkni **H**: klakson (kolo zvoní zvonkem, koloběžka pípá). Druhý hráč poblíž ho slyší taky.
- Ve dne ptáci a vzdálený provoz, v noci vítr, cvrčci a vzdálené sténání. Na střeše fouká vítr. U fontány šumí voda.

Když se zvuk změní a skript `art/audio/make_audio.py` se spustí s `--sheets sfx3`, vznikne nový soubor a je potřeba ho
nahrát znovu (a vyměnit číslo).
