# Nahrát nové zvuky (sfx4.ogg, verze 7.1)

Hra má 23 nových zvuků pro stěhování a pro hory. Jsou v jednom souboru `art/audio/sfx4.ogg` (50 s, asi 370 kB):

- **nábytek:** zvednutí, položení, těžký pád, rozbití skla, šoupání těžkého kusu po zemi, šustění krabice;
- **náklaďák:** rampa a zadní dveře, kus zajíždějící do korby, utahování popruhu;
- **dům:** vrzání domovních dveří;
- **úchop těžkého kusu:** tiknutí, varování, vyklouznutí;
- **stěhování:** znělka na začátku, znělka úspěchu a neúspěchu, vzdálená siréna hordy, závora na kontrolním stanovišti u Zdi;
- **hory:** kukačkové hodiny, kravský zvonec, ptáci na louce, vítr na vrcholcích, potok.

Dokud soubor nenahrajete, hra místo nich přehrává podobné starší zvuky. Šoupání, kukačka, zvonec a ptáci do té doby mlčí.

Ostatní soubory (`sfx.ogg`, `sfx2.ogg`, `sfx3.ogg`, `music.ogg`) jsou **stejné jako dřív**. Znovu je nahrávat nemusíte.

## Postup

### 1. Nahrát soubor (jedna z cest)

**A) V Roblox Studiu (Asset Manager):**

1. Otevřete hru v Roblox Studiu.
2. **View → Asset Manager**, nahoře **Bulk Import** (nebo **Import**). Vyberte soubor
   `zombie-delivery/art/audio/sfx4.ogg`.
3. Počkejte, až Roblox zvuk zkontroluje a schválí (obvykle pár minut).
4. Ve složce **Audio** klikněte na nový zvuk pravým tlačítkem → **Copy Asset ID**.

**B) Na webu (Creator Hub):**

1. Otevřete <https://create.roblox.com> → **Creations** → **Development Items** → **Audio**.
2. Klikněte na **Upload Asset** (někde se tlačítko jmenuje **Import Asset**) a vyberte `sfx4.ogg`. Název může být
   třeba `ZD sfx4`.
3. Počkejte na schválení. Pak u zvuku klikněte na tři tečky → **Copy Asset ID**.

Asset ID je číslo, např. `123456789012345`.

**Pozor:** pokud hra patří skupině (Group), nahrajte zvuk pod tou skupinou (v Creator Hubu nahoře přepněte vlastníka
na skupinu). Zvuk nahraný pod jiným vlastníkem hra nesmí přehrát a zůstane potichu.

### 2. Vložit číslo do hry

1. Otevřete `zombie-delivery/src/shared/SoundSheet.luau` a najděte řádek 21:

   ```lua
   SoundSheet.Sfx4Id = "" -- "rbxassetid://…" of art/audio/sfx4.ogg (7.1)
   ```

2. Změňte ho na (místo `123456789012345` dejte svoje číslo):

   ```lua
   SoundSheet.Sfx4Id = "rbxassetid://123456789012345" -- "rbxassetid://…" of art/audio/sfx4.ogg (7.1)
   ```

   Měňte jen to, co je v uvozovkách. Zbytek řádku nechte, jak je.

3. Uložte, synchronizujte (z kořene repozitáře `node tools/rojo-sync.js zombie-delivery`) a spusťte hru.
   V okně **Output** už nebude řádek `[Sounds] 7.1: art/audio/sfx4.ogg is not uploaded yet`.

**Jednodušší:** pošlete Claudovi jen to číslo („Sfx4 id je 123456789012345“) a řádek upraví za vás.

## Jak to vyzkoušet

- V depu u kiosku **Moving contracts** spusťte stěhování (START, pak LAUNCH): zazní krátká znělka.
- U domu projděte dveřmi dovnitř a ven: dveře vrznou.
- Zvedněte kus nábytku (dřevěné ťuknutí) a krabici (šustění). Položte je klávesou G (tlumené žuchnutí).
- Kus pro dva lidi táhněte sami (s jinou rolí než Mover): při chůzi šoupe po podlaze.
- U náklaďáku otevřete a zavřete zadní dveře (řinčení rampy). Naložte kus klávesou E: zajede do korby.
- Seskočte s kusem v rukou z výšky: těžká rána. Křehký kus, který se rozbije, se roztříští jako sklo.
- Ve 3:00 do konce začne v dálce houkat siréna hordy.
- Dojeďte ke kontrolnímu stanovišti u Zdi: zabzučí bzučák a zvedne se závora.

Zvuky úchopu, popruhu, znělky výsledku a zvuky hor jsou připravené pro další části hry (úchop těžkého kusu,
výsledková karta, horské kapitoly). Zatím se nikde nepřehrávají.

Když se některý zvuk změní a skript `art/audio/make_audio.py` se spustí s `--sheets sfx4`, vznikne nový soubor.
Ten je potřeba nahrát znovu a vyměnit číslo.
