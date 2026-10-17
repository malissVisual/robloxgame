# Analytika: kde uvidíš, co hráči ve hře dělají

Hra posílá Robloxu krátké zprávy o tom, co hráči dělají: kam až noví hráči dojdou, kde odpadnou, za co utrácejí
peníze a kde se hra rozbije. Nic osobního: jen počty a krátká slova (např. „solo“, „legendary“). Roblox z toho kreslí
grafy na tvé stránce pro tvůrce.

Nic z toho nemusíš zapínat. Stačí hru zveřejnit a hrát. Celou analytiku vypneš v `src/shared/Config.luau`:
`Config.Analytics.Enabled = false`.

(10.6: popis starého města, jeho cesty nového hráče, zakázek, misí a jeho peněz je pryč i s městem; zůstává
v historii Gitu do verze 10.5. Když vybíráš období grafu, začni až dnem, kdy jsi zveřejnil sandbox (8.2 nebo novější):
kroky 3 až 10 dřív znamenaly něco jiného.)

## Kde to najdeš

1. Otevři **create.roblox.com** a přihlas se.
2. Nahoře klikni na **Creations** a vyber svoji hru.
3. V levém menu najdi sekci **Analytics**:
   - **Funnels** → **Onboarding**: cesta nového hráče (10 kroků, viz níže).
   - **Economy**: odkud peníze přicházejí a kam odcházejí. Měna se jmenuje **Cash**: příjmy ze stojanů
     (**CollectionIncome**), prodeje (**CollectionSale**) a nákupy vylepšení (**Upgrade**).
   - **Custom events** (vlastní události): krátký seznam věcí, které hra počítá navíc.
4. Chyby najdeš v levém menu pod **Monitoring** → **Error Report** (hlášení chyb).

Roblox stránky občas přejmenuje nebo přesune. Když něco nenajdeš, hledej slova **Funnels**, **Economy**,
**Custom events** a **Error Report**.

Nahoře na každé stránce si vybereš **období** (např. posledních 7 dní). Když se díváš na novou věc, vyber krátké
období, ať ti ji nepřekryjí starší dny.

## Jak dlouho trvá, než se čísla objeví

- **Ve Studiu se neposílá nic.** Grafy plní jen opravdoví hráči na zveřejněné hře.
- První čísla se obvykle ukážou **za několik hodin**, celé grafy **za 1 až 2 dny**. Když dnes něco změníš, hodnoť to
  až pozítří.
- Některé grafy Roblox ukáže, až když hru hraje **dost lidí**. Při pár hráčích denně můžou být chvíli prázdné. To je
  v pořádku.

## Cesta nového hráče (Funnels → Onboarding, 10 kroků)

| Krok | Název v grafu | Co to znamená |
|---|---|---|
| 1 | Joined | Hráč přišel a jeho uložená hra se načetla. |
| 2 | PressedPlay | Na úvodní obrazovce vybral uloženou hru a začal hrát. |
| 3 | FirstContract | Začalo jeho první stěhování (od 10.0 první běh z portálu v lobby). |
| 4 | EnteredHouse | Poprvé vešel do domu, který se vyklízí. |
| 5 | FirstPieceInVan | Poprvé naložil věc do vanu. Počítá se i věc, kterou do jeho vanu naloží Danny nebo parťák. |
| 6 | FirstTripHome | Poprvé se mu náklad dostal domů do skladu. |
| 7 | FirstPieceOnShow | Poprvé dal věc na stojan ve skladu. |
| 8 | FirstIncome | Stojany mu poprvé vydělaly peníze. |
| 9 | FirstSale | Poprvé prodal věc ze sbírky. |
| 10 | FirstUpgrade | Poprvé koupil vylepšení u pultu UPGRADES. |

Pravidla, ať tě graf nepřekvapí:
- Každý krok se počítá **jednou za celý život hráče** a hra si ho pamatuje v uložené hře. Když hráč odejde a vrátí se,
  pokračuje tam, kde skončil. Nic se nepočítá dvakrát.
- Kroky se počítají **popořadě**. Když hráč koupí vylepšení (krok 10) hned po startu, započítá se, až projde kroky
  3 až 9. Stejně tak prodej před prvním vystavením čeká na vystavení a na první příjem. Proto graf nikdy neukáže víc
  hráčů na pozdějším kroku než na dřívějším.
- Parťák, který vejde do domu na cizím stěhování, má krok 4 schovaný, dokud nezačne vlastní stěhování (krok 3).
- Počítají se jen **noví hráči**. Kdo hrál sandbox před verzí 8.2 (ty a testeři), se nepočítá. Když si cestu chceš
  projít sám, dej v admin panelu (P) **RESET MY SAVE**. Pozor, smaže to celou uloženou hru, kterou právě hraješ.

Jak číst schody:
- **1 → 2**: hráči odejdou ještě před PLAY. Hra se možná načítá moc dlouho.
- **2 → 3**: po startu nevědí, co dělat. Najdou portály v lobby?
- **3 → 4**: běh začal, ale do domu nevešli. Najdou dveře?
- **4 → 5**: v domě jsou, ale nic nenaložili. Nosit věci je moc těžké. Podívej se na **GripCheck** (níže).
- **5 → 6**: naložili, ale domů nedovezli. Podívej se na **MoveGaveUp** a na pole 02 („kam došli“).
- **6 → 7**: věci jsou ve skladu, ale nevystavili je. Stojany nejsou vidět, nebo není jasné, k čemu jsou.
- **7 → 8**: stojany platí samy, ale levná věc vydělá první dolar třeba až za pár minut. Velký schod znamená, že
  hráči odešli dřív, než jim stojany něco vydělaly.
- **8 → 9 → 10**: hra je baví, ale prodej nebo vylepšení nenajdou nebo na ně nemají.
- Porovnej s **SessionLength** (jak dlouho hrají): **New** je, kdo ještě neprošel všech 10 kroků.

## Vlastní události (Custom events)

| Událost | Kdy se zapíše | Hodnota a údaje |
|---|---|---|
| MoveStarted | začalo stěhování | hodnota: kolikáté stěhování v této hře (1 = první), 01: `solo` nebo `crew` |
| MoveFinished | stěhování skončilo a domů se něco dovezlo | hodnota: minuty, 01: jak skončilo, 02: kolik jízd domů, 03: kolik věcí domů |
| MoveFinishedValue | to samé stěhování: kolik má dovezené cenu | hodnota: cena dovezených věcí ($), 01: jak skončilo, 02: kolik věcí, 03: `solo` / `crew` |
| MoveGaveUp | stěhování skončilo a **domů se nedovezlo nic** | hodnota: minuty, 01: jak skončilo, 02: kam došli, 03: `solo` / `crew` |
| GripCheck | výsledek zkoušky úchopu při nošení (jen každá desátá) | hodnota: 10, 01: výsledek, 02: `lift` (zvedání) / `wobble` (zakolísání), 03: `fragile` (křehké) / `sturdy` |
| CollectibleFound | sběratelský kousek se dovezl domů do skladu | hodnota: jeho cena ($), 01: vzácnost (`uncommon`, `rare`, `epic`, `legendary`), 02: který kousek |

Co znamenají slova v údajích:
- **Jak skončilo** (01 u MoveFinished a MoveGaveUp): `finish` = zmáčkl FINISH, `all` = dovezl všechno, `time` = došel
  čas, `giveup` = vzdal to (GIVE UP), `left` = odešel ze hry, `admin` = ukončeno z admin panelu.
- **Kolik jízd** (02 u MoveFinished): `1` až `5`, víc je `6plus`.
- **Kolik věcí** (03 u MoveFinished, 02 u MoveFinishedValue): po pěti, `0-4`, `5-9` … `25-29`, víc je `30plus`.
- **Kam došli** (02 u MoveGaveUp): `started` = jen začali, `house` = byli v domě, `van` = něco naložili,
  `home` = něco dovezli (to by tu být nemělo).
- **Výsledek úchopu** (01 u GripCheck): `balanced` = zvedl v rovnováze, `knock` = zvedání se nepovedlo (věc ťukla
  o zem), `steady` = zakolísání ustál, `stagger` = zavrávoral, `drop` = věc upadla.
- **GripCheck je jen vzorek**: posílá se jedna zkouška z každých deseti u každého hráče. Počet událostí krát 10
  (nebo součet hodnot) je zhruba počet všech zkoušek. Poměr výsledků (kolik `drop`, kolik `steady`) platí i tak.
  Hodně `drop` a `knock` znamená, že je nošení moc těžké.

Dál zůstávají události sandboxu z dřívějška: **UpgradeBought** (koupené vylepšení: hodnota úroveň, 01 které),
**CollectionAdded** / **CollectionDisplayed** / **CollectionSold** (sklad) a **MoveDone** (hvězdy stěhování).

Dál se zapisují i obecné události: **SessionLength** (hráč odešel: hodnota minuty hraní, 01 `New` nebo `Veteran`),
**ServerError** a **ClientError** (chyba ve skriptu: 01 jméno skriptu, viz níže).

## Chyby (Error Report)

- **Error Report** sbírá Roblox sám: celé chybové hlášky ze serverů i ze zařízení hráčů, kolikrát se staly a kdy.
  Tam je hledej jako první.
- Hra k tomu počítá **ServerError** a **ClientError** podle jména skriptu, takže rychle uvidíš, který skript zlobí
  nejvíc. (Roblox chce u každé události hráče, proto se chyba serveru zapíše k jednomu z hráčů na tom serveru.)
- V okně **Output** (ve Studiu i v konzoli živého serveru, klávesa F9) uvidíš řádky jako
  `[Analytics] ServerError in Runs:123 (…)`. Nejvýš 6 za minutu od každého druhu (ServerError, ClientError), aby
  Output nezahltily. Jeden hráč pošle hlášení o chybě nejvýš jednou za 20 sekund.

## Jak to vyzkoušet ve Studiu

Ve Studiu se nic neposílá, ale hra to počítá. Spusť hru, zmáčkni **P** a dívej se na řádek **Analytics** (ve verzi
10.4 v záložce **WORLD**). Číslo **onboarding** stoupne po každém novém kroku (ve Studiu bez ukládání začínáš vždycky
jako nový hráč), číslo **custom** po každé události. Na konci řádku je poslední událost, např. `last: Onboarding 4 EnteredHouse` nebo
`last: MoveFinished`.

## Co poslat Claudovi, když něco nesedí

- **Snímek obrazovky** grafu i s vybraným obdobím (datum od–do) a s filtry, které máš zapnuté.
- **Co čekáš a co vidíš**, jednou větou (např. „FirstTripHome je skoro nula, ale hráči nosí věci domů“).
- Řádek **Analytics** z admin panelu (P) na živém serveru.
- Řádky z **Output**, které začínají `[Analytics]` (i varování kolem nich).
- Z **Error Reportu**: jméno skriptu, celé hlášení chyby a kolikrát se stala.
- **Verzi hry** (je v Output, např. `[Server] … 10.6 is running`) a jestli se to stalo ve Studiu, nebo na zveřejněné hře.
