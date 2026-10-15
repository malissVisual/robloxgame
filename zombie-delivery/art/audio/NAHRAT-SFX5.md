# Nahrát nové zvuky (sfx5.ogg, verze 8.9)

Nejnovější části hry dostaly vlastní zvuky. Je jich 13 a jsou v jednom souboru `art/audio/sfx5.ogg` (11 s, asi 60 kB):

- **Dannyho psací deska (8.5):**
  - vytažení desky (šustnutí papíru a cvaknutí klipu) a její schování;
  - odškrtnutí propiskou, když Dannymu dáte kus, a přeškrtnutí, když si ho vezmete zpět;
  - tiché „kdepak“, když hra výběr odmítne.
- **Dannyho příkazy (8.6):** krátké potvrzující cvrlikání, když Danny příkaz poslechne, a hvizd, když jeho bublina
  zoranžoví, protože vás potřebuje.
- **obchodování mezi hráči (8.7):** mince „ka-ching“ za prodej, zvonek na pultu za nabídku od jiného hráče a tiché
  šustnutí cenovky při nastavení ceny.
- **aukce (8.8):** úder kladívka, zvonek „prodáno!“ a tiché ťuknutí při každém příhozu.

Všechny jsou tiché, jsou to zvuky rozhraní. Odpovědi na vaše kliknutí (odškrtnutí, přeškrtnutí, „kdepak“, Dannyho
potvrzení) hrají místo obecného cinknutí oznámení, ne spolu s ním.

Dokud soubor nenahrajete, hra místo nich přehrává podobné starší zvuky:

- vytažení a schování desky: běžné zvuky rozhraní (otevření a klik);
- odškrtnutí: tiché ťuknutí, přeškrtnutí: klik;
- „kdepak“: obvyklé cinknutí oznámení (stejně jako dosud);
- Dannyho potvrzení: krátké stoupající pípnutí;
- prodej: pokladna ze skladu, nabídka a „prodáno!“: starší zvonek, kladívko: klepání na dveře, příhoz: tiché ťuknutí.

Do té doby mlčí: Dannyho hvizd a šustnutí cenovky. U obou už teď cinkne oznámení, které hra zároveň ukáže.

Ostatní soubory (`sfx.ogg`, `sfx2.ogg`, `sfx3.ogg`, `sfx4.ogg`, `music.ogg`) jsou **stejné jako dřív**. Znovu je
nahrávat nemusíte.

## Postup

### 1. Nahrát soubor (jedna z cest)

**A) V Roblox Studiu (Asset Manager):**

1. Otevřete hru v Roblox Studiu.
2. **View → Asset Manager**, nahoře **Bulk Import** (nebo **Import**). Vyberte soubor
   `zombie-delivery/art/audio/sfx5.ogg`.
3. Počkejte, až Roblox zvuk zkontroluje a schválí (obvykle pár minut).
4. Ve složce **Audio** klikněte na nový zvuk pravým tlačítkem → **Copy Asset ID**.

**B) Na webu (Creator Hub):**

1. Otevřete <https://create.roblox.com> → **Creations** → **Development Items** → **Audio**.
2. Klikněte na **Upload Asset** (někde se tlačítko jmenuje **Import Asset**) a vyberte `sfx5.ogg`. Název může být
   třeba `ZD sfx5`.
3. Počkejte na schválení. Pak u zvuku klikněte na tři tečky → **Copy Asset ID**.

Asset ID je číslo, např. `123456789012345`.

**Pozor:** pokud hra patří skupině (Group), nahrajte zvuk pod tou skupinou (v Creator Hubu nahoře přepněte vlastníka
na skupinu). Zvuk nahraný pod jiným vlastníkem hra nesmí přehrát a zůstane potichu.

### 2. Vložit číslo do hry

1. Otevřete `zombie-delivery/src/shared/SoundSheet.luau` a najděte řádek 26:

   ```lua
   SoundSheet.Sfx5Id = "" -- "rbxassetid://…" of art/audio/sfx5.ogg (8.9)
   ```

2. Změňte ho na (místo `123456789012345` dejte svoje číslo):

   ```lua
   SoundSheet.Sfx5Id = "rbxassetid://123456789012345" -- "rbxassetid://…" of art/audio/sfx5.ogg (8.9)
   ```

   Měňte jen to, co je v uvozovkách. Zbytek řádku nechte, jak je.

3. Uložte, synchronizujte (z kořene repozitáře `node tools/rojo-sync.js zombie-delivery`) a spusťte hru.
   V okně **Output** už nebude řádek `[Sounds] 8.9: art/audio/sfx5.ogg is not uploaded yet`.

**Jednodušší:** pošlete Claudovi jen to číslo („Sfx5 id je 123456789012345“) a řádek upraví za vás.

## Jak to vyzkoušet (sandbox, `Config.Sandbox.On = true`)

- Na stěhování si najměte Dannyho. Stiskněte Q: zašustí papír a cvakne klip. Znovu Q: deska se schová (tišší
  šustnutí). Totéž platí pro tlačítko 📋 a pro 📋 CLIPBOARD v Dannyho kartě.
- S deskou v ruce klikněte na kus nábytku: propiska ho odškrtne (Danny ho odnese). Klikněte na něj znovu: přeškrtnutí
  (vzali jste si ho zpět). Klikněte na kus, který dát nejde (třeba je už v dodávce): tiché „kdepak“ místo obvyklého
  cinknutí oznámení. Když desku vytáhnout nejde (máte plné ruce), zazní také „kdepak“.
- S deskou klikněte na Dannyho a v menu příkazů dejte ⬇ PUT IT DOWN nebo 🚪 GET OUT: když Danny poslechne, krátce
  cvrlikne. Když nemůže (třeba dodávka ještě jede), zazní „kdepak“.
- Dejte Dannymu na seznam kus pro dva. Až u něj čeká a jeho bublina zoranžoví („Needs you“), hvizdne. Hvízdá nejvýš
  jednou za 8 sekund.
- Dveře dodávky zněly, když Danny nastupuje a vystupuje, už dřív. Je to stejné cvaknutí a bouchnutí jako u hráče, nic
  dalšího nebylo potřeba.
- Aukce je zatím vypnutá (`Config.Auction.On = false`). Až se zapne, uslyšíte při otevřeném okně aukce ťuknutí při
  každém příhozu. Když položka skončí, udeří kladívko a zazní „prodáno!“. Když se prodal váš kus nebo jste něco
  koupili, zvonek zní hlasitěji, a to i se zavřeným oknem.
- Zvuky obchodování jsou připravené, ale hra je zatím nepřehrává. Zapojí je kód obchodování, až v něm budou hotové
  opravy.

Když se některý zvuk změní a skript `art/audio/make_audio.py` se spustí s `--sheets sfx5`, vznikne nový soubor.
Ten je potřeba nahrát znovu a vyměnit číslo.
