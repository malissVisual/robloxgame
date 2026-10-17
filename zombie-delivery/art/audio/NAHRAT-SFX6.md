# Nahrát zvuky intra a menu (sfx6.ogg, verze 10.1)

Intro, úvodní menu se sloty a tvorba postavy dostaly vlastní zvuky. Je jich 10 a jsou v jednom souboru
`art/audio/sfx6.ogg` (12 s):

- **Intro:**
  - přijíždějící dodávka (motor zpomaluje, pneumatiky, jemná brzda, karoserie dosedne na pérování);
  - znělka loga DELIVEROS (měkké „pop“, rychlé stoupající tóny a jiskřivý akord, který dozní spolu s nápisem
    MOVE · FIND · GROW);
  - odjíždějící dodávka, když intro mizí.
- **Úvodní menu:**
  - výběr uložené hry (CONTINUE);
  - start hry, když se uložená hra načte (s ním začne zatmívání);
  - otázka START OVER (dva hlubší tóny) a CANCEL nebo BACK (dva klesající tóny).
- **Tvorba postavy:**
  - otevření okna (jemné švihnutí);
  - výběr barvy nebo stylu (malé „pop“, pokaždé trochu jinak vysoko);
  - 🎲 RANDOM (chrastění kostek a cinknutí).

Dokud soubor nenahrajete, hra místo nich přehrává podobné starší zvuky:

- znělka loga: starý zvuk postupu na další úroveň;
- výběr v menu a otevření tvorby postavy: běžné otevření okna;
- start hry: znělka splněného úkolu;
- otázka START OVER: obvyklé cinknutí oznámení, BACK: klik;
- výběr barvy a kostky: tiché ťuknutí.

Do té doby mlčí přijíždějící a odjíždějící dodávka v intru (žádný starší zvuk se k nim nehodí).

Ostatní soubory (`sfx.ogg` až `sfx5.ogg`, `music.ogg`) jsou **stejné jako dřív**. Znovu je nahrávat nemusíte.
Číslo `sfx5.ogg` (100303087856022) už je ve hře.

## Postup

### 1. Nahrát soubor

1. Otevřete hru v Roblox Studiu.
2. **View → Asset Manager**, nahoře **Import**. Vyberte soubor `zombie-delivery/art/audio/sfx6.ogg`.
3. Počkejte, až Roblox zvuk zkontroluje a schválí (obvykle pár minut).
4. Ve složce **Audio** klikněte na nový zvuk pravým tlačítkem → **Copy Asset ID**.

**Pozor:** pokud hra patří skupině (Group), nahrajte zvuk pod tou skupinou. Zvuk nahraný pod jiným vlastníkem hra
nesmí přehrát a zůstane potichu.

### 2. Číslo do hry

Pošlete Claudovi jen to číslo („Sfx6 id je 123456789012345“) a doplní ho za vás. Ručně: v souboru
`zombie-delivery/src/shared/SoundSheet.luau` na řádku `SoundSheet.Sfx6Id = ""` vložte do uvozovek
`rbxassetid://` a vaše číslo.

## Jak to vyzkoušet

- Spusťte hru: v intru přijede dodávka (zvuk motoru), při objevení loga zazní znělka a když intro mizí, dodávka odjede.
- V menu dejte u slotu CONTINUE: krátké potvrzení, a jakmile se hra načte, startovní akord.
- Dejte START OVER: otázka zazní dvěma hlubšími tóny, CANCEL dvěma klesajícími.
- Dejte NEW GAME: okno tvorby postavy se otevře se švihnutím, každá barva a styl ťukne, 🎲 RANDOM zachrastí kostkami.

Když se některý zvuk změní a skript `art/audio/make_audio.py` se spustí s `--sheets sfx6`, vznikne nový soubor.
Ten je potřeba nahrát znovu a vyměnit číslo.
