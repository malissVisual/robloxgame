# Nahrát nové zvuky (sfx4.ogg, verze 7.1 a 8.1)

Hra má 36 nových zvuků pro stěhování, pro hory a pro sandbox. Jsou v jednom souboru `art/audio/sfx4.ogg`
(111 s, asi 0,9 MB):

- **nábytek:** zvednutí, položení, těžký pád, rozbití skla, šoupání těžkého kusu po zemi, šustění krabice;
- **náklaďák:** rampa a zadní dveře, kus zajíždějící do korby, utahování popruhu;
- **dům:** vrzání domovních dveří;
- **úchop těžkého kusu:** tiknutí, varování, vyklouznutí;
- **stěhování:** znělka na začátku, znělka úspěchu a neúspěchu, vzdálená siréna hordy, závora na kontrolním stanovišti u Zdi;
- **hory:** kukačkové hodiny, kravský zvonec, ptáci na louce, vítr na vrcholcích, potok;
- **sandbox (8.1):**
  - venku klidný alpský den místo městského provozu: jemný vánek a ptáci, občas v dálce kravský zvonec;
  - ve skladu tiché bzučení světel a vzduch haly (a lehká ozvěna);
  - v chalupě tichý pokoj s tikajícími hodinami;
  - kus postavený na stojan (tlumené žuchnutí a zatřpytění), sundaný ze stojanu, prodaný (pokladna „ka-ching“);
  - cesta domů: kusy uložené ve skladu (malá fanfára);
  - dodávka Sprinter: zadní dveře (otevřou se až k bokům a vyklopí se schůdek), posuvné boční dveře
    (otevření a zabouchnutí), krok na schůdek.

Dokud soubor nenahrajete, hra místo nich přehrává podobné starší zvuky:

- venku v sandboxu hraje jen jemný vánek (bez ptáků), ve skladu tiché hučení;
- stojany, pokladna, fanfára, dveře Sprinteru a schůdek mají starší náhradní zvuky.

Do té doby mlčí: šoupání těžkého kusu, vzdálený kravský zvonec a tichý pokoj v chalupě.

Ostatní soubory (`sfx.ogg`, `sfx2.ogg`, `sfx3.ogg`, `music.ogg`) jsou **stejné jako dřív**. Znovu je nahrávat nemusíte.

**Pozor:** pokud jste už někdy nahráli starší `sfx4.ogg` (verze 7.1, 50 s), nepoužívejte ho. Nahrajte tento nový
soubor. Obsahuje všechny staré zvuky i ty nové.

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

1. Otevřete `zombie-delivery/src/shared/SoundSheet.luau` a najděte řádek 22:

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

### Sandbox (verze 8.1, `Config.Sandbox.On = true`)

- Projděte se po louce: vánek a ptáci, žádný provoz. Asi jednou za půl minuty až minutu zazní někde v dálce kravský
  zvonec (pokaždé z jiné strany).
- Vejděte do svého skladu: louka ztichne, ozve se tiché bzučení světel a kroky mají lehkou ozvěnu. Venku ozvěna zmizí.
- Ve skladu u stojanu (E) vyberte kus a dejte DISPLAY: tlumené žuchnutí a zatřpytění. TAKE DOWN: kus se sundá
  (krátký zvuk zvednutí). SELL: pokladna „ka-ching“.
- Když jsou kusy na stojanech a okno skladu je zavřené, příjem zacinká tichou mincí, nejvýš jednou za 10 sekund.
- U Sprinteru otevřete zadní dveře (E): dveře se otevřou až k bokům a cvakne vyklopený schůdek. Zavřete je: dvě
  bouchnutí. Posuvné boční dveře: zarachotí a dorazí, při zavření zabouchnou.
- Vystupte po schůdku do dodávky: dutý kovový krok a dodávka se lehce zhoupne.
- Stěhování: vejděte dveřmi do chalupy: venkovní zvuky utichnou a ozve se tichý pokoj s hodinami. Odvezte náklad
  domů do skladu: malá fanfára (po poslední cestě hraje místo ní znělka výsledkové karty).

### Stěhování ve městě (verze 7.1, `Config.Sandbox.On = false`)

- V depu u kiosku **Moving contracts** spusťte stěhování (START, pak LAUNCH): zazní krátká znělka.
- U domu projděte dveřmi dovnitř a ven: dveře vrznou.
- Zvedněte kus nábytku (dřevěné ťuknutí) a krabici (šustění). Položte je klávesou G (tlumené žuchnutí).
- Kus pro dva lidi táhněte sami (s jinou rolí než Mover): při chůzi šoupe po podlaze.
- U náklaďáku otevřete a zavřete zadní dveře (řinčení rampy). Naložte kus klávesou E: zajede do korby.
- Seskočte s kusem v rukou z výšky: těžká rána. Křehký kus, který se rozbije, se roztříští jako sklo.
- Ve 3:00 do konce začne v dálce houkat siréna hordy.
- Dojeďte ke kontrolnímu stanovišti u Zdi: zabzučí bzučák a zvedne se závora.

Zvuky popruhu, znělky výsledku a zvuky hor (kukačka, zvonec zblízka, ptáci, vítr na vrcholcích, potok) jsou
připravené pro další části hry. Zatím se nikde nepřehrávají.

Když se některý zvuk změní a skript `art/audio/make_audio.py` se spustí s `--sheets sfx4`, vznikne nový soubor.
Ten je potřeba nahrát znovu a vyměnit číslo.
