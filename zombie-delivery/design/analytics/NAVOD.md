# Analytika: kde uvidíš, co hráči ve hře dělají

Od verze 6.13 hra posílá Robloxu krátké zprávy o tom, co hráči dělají: kam až noví hráči dojdou, kde odpadnou, za
co utrácejí peníze, jak rychle rostou a kde se hra rozbije. Nic osobního: jen počty a krátká slova (např. „car“,
„3 hvězdy“). Roblox z toho kreslí grafy na tvé stránce pro tvůrce.

Nic z toho nemusíš zapínat. Stačí hru zveřejnit a hrát.

## Kde to najdeš

1. Otevři **create.roblox.com** a přihlas se.
2. Nahoře klikni na **Creations** a vyber **Zombie Delivery**.
3. V levém menu najdi sekci **Analytics**. Tam jsou stránky, které tě zajímají:
   - **Funnels** → **Onboarding**: cesta nového hráče (ve městě 9 kroků, v sandboxu 10 kroků, viz níže).
   - **Funnels** → **Recurring** (opakované): rozvoz zakázek (**Delivery**) a mise (**Mission**).
   - **Economy**: odkud peníze přicházejí a kam odcházejí. Měna se jmenuje **Cash**.
   - **Progression**: růst úrovně řidiče (**DriverLevel**) a mise v příběhu (**Missions**).
   - **Custom events** (vlastní události): krátký seznam věcí, které hra počítá navíc.
4. Chyby najdeš v levém menu pod **Monitoring** → **Error Report** (hlášení chyb).

Roblox stránky občas přejmenuje nebo přesune. Když něco nenajdeš, hledej slova **Funnels**, **Economy**,
**Progression**, **Custom events** a **Error Report**.

Nahoře na každé stránce si vybereš **období** (např. posledních 7 dní). Když se díváš na novou věc, vyber krátké
období, ať ti ji nepřekryjí starší dny.

## Jak dlouho trvá, než se čísla objeví

- **Ve Studiu se neposílá nic.** Grafy plní jen opravdoví hráči na zveřejněné hře.
- První čísla se obvykle ukážou **za několik hodin**, celé grafy **za 1 až 2 dny**. Když dnes něco změníš, hodnoť to
  až pozítří.
- Některé grafy Roblox ukáže, až když hru hraje **dost lidí**. Při pár hráčích denně můžou být chvíli prázdné. To je
  v pořádku.

## Sandbox (od 8.2): kde hráči odpadají v testovacím světě

Tohle platí, dokud je zapnutý sandbox (`Config.Sandbox.On = true`, malý alpský svět se skladem a jedním domem).

### Kde to najdeš

1. **create.roblox.com** → **Creations** → **Zombie Delivery** → v levém menu **Analytics** → **Funnels** →
   **Onboarding**.
2. Nahoře vyber **období ode dne, kdy jsi zveřejnil verzi 8.2** (nebo novější). Roblox má pro jednu hru jen
   **jednu** cestu nového hráče a kroky řadí podle čísla. Kroky 1 a 2 jsou stejné jako ve městě, od kroku 3 jsou jiné.
   Kdyby období zasahovalo do dnů, kdy běželo město, smíchaly by se v grafu kroky města s kroky sandboxu.
3. Vlastní události sandboxu (tabulka níže) najdeš v **Analytics** → **Custom events**. Peníze v **Economy**:
   příjmy ze stojanů (**CollectionIncome**), prodeje (**CollectionSale**) a nákupy vylepšení (**Upgrade**).

### Cesta nového hráče v sandboxu (10 kroků)

| Krok | Název v grafu | Co to znamená |
|---|---|---|
| 1 | Joined | Hráč přišel a jeho uložená hra se načetla. |
| 2 | PressedPlay | Zmáčkl **PLAY** na úvodní obrazovce (u skladu na něj čeká van). |
| 3 | FirstContract | Vzal si první zakázku na stěhování (LAUNCH u tabule u skladu). |
| 4 | EnteredHouse | Poprvé vešel do domu (The Old Chalet). |
| 5 | FirstPieceInVan | Poprvé naložil věc do vanu. Počítá se i věc, kterou do jeho vanu naloží Danny nebo parťák. |
| 6 | FirstTripHome | Poprvé dovezl náklad domů ke skladu (věci šly do skladu). |
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
- Parťák, který vejde do domu na cizím stěhování, má krok 4 schovaný, dokud si nevezme vlastní zakázku (krok 3).
- Počítají se jen **noví hráči**. Kdo hrál sandbox před verzí 8.2 (ty a testeři), se nepočítá. Když si cestu chceš
  projít sám, dej v admin panelu (P) → **PLAYER** → **RESET MY SAVE**. Pozor, smaže to celou tvou uloženou hru
  v sandboxu.

Jak číst schody:
- **1 → 2**: hráči odejdou ještě před PLAY. Hra se možná načítá moc dlouho.
- **2 → 3**: po startu nevědí, co dělat. Najdou tabuli se zakázkou u skladu?
- **3 → 4**: zakázku vzali, ale k domu nedojeli. Cesta k domu je moc dlouhá, nebo se ztratí.
- **4 → 5**: v domě jsou, ale nic nenaložili. Nosit věci je moc těžké. Podívej se na **GripCheck** (níže).
- **5 → 6**: naložili, ale domů nedovezli. Podívej se na **MoveGaveUp** a na pole 02 („kam došli“).
- **6 → 7**: věci jsou ve skladu, ale nevystavili je. Stojany nejsou vidět, nebo není jasné, k čemu jsou.
- **7 → 8**: stojany platí samy, ale levná věc vydělá první dolar třeba až za pár minut. Velký schod znamená, že
  hráči odešli dřív, než jim stojany něco vydělaly.
- **8 → 9 → 10**: hra je baví, ale prodej nebo vylepšení nenajdou nebo na ně nemají.
- Porovnej s **SessionLength**. V sandboxu je **New**, kdo ještě neprošel všech 10 kroků.

### Vlastní události sandboxu

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
- **Kam došli** (02 u MoveGaveUp): `started` = jen vzali zakázku, `house` = byli v domě, `van` = něco naložili,
  `home` = něco dovezli (to by tu být nemělo).
- **Výsledek úchopu** (01 u GripCheck): `balanced` = zvedl v rovnováze, `knock` = zvedání se nepovedlo (věc ťukla
  o zem), `steady` = zakolísání ustál, `stagger` = zavrávoral, `drop` = věc upadla.
- **GripCheck je jen vzorek**: posílá se jedna zkouška z každých deseti u každého hráče. Počet událostí krát 10
  (nebo součet hodnot) je zhruba počet všech zkoušek. Poměr výsledků (kolik `drop`, kolik `steady`) platí i tak.
  Hodně `drop` a `knock` znamená, že je nošení moc těžké.

Dál zůstávají události sandboxu z dřívějška: **UpgradeBought** (koupené vylepšení: hodnota úroveň, 01 které),
**CollectionAdded** / **CollectionDisplayed** / **CollectionSold** (sklad) a **MoveDone** (hvězdy stěhování).

### Jak to vyzkoušet ve Studiu

Ve Studiu se nic neposílá, ale hra to počítá. Spusť hru, zmáčkni **P** → **WORLD** a dívej se na řádek **Analytics**.
Číslo **onboarding** stoupne po každém novém kroku (ve Studiu bez ukládání začínáš vždycky jako nový hráč), číslo
**custom** po každé události. Na konci řádku je poslední událost, např. `last: Onboarding 4 EnteredHouse` nebo
`last: MoveFinished`.

## Cesta nového hráče ve městě (Onboarding, 9 kroků)

Tohle platí pro velké město (`Config.Sandbox.On = false`).

Každý krok se počítá **jednou za celý život hráče**. Počítají se jen **noví hráči** (kdo hrál před verzí 6.13, se
do téhle cesty nepočítá). Graf ukazuje, kolik hráčů došlo na každý krok. Kde je velký schod dolů, tam hráči odpadají.

| Krok | Název v grafu | Co to znamená |
|---|---|---|
| 1 | Joined | Hráč přišel a jeho uložená hra se načetla. |
| 2 | PressedPlay | Zmáčkl **PLAY** na úvodní obrazovce (hra se dohrála a začal hrát). |
| 3 | WelcomeSeen | Viděl uvítání od Marge (dispečerky u tabule prací). |
| 4 | FirstJob | Vzal si první práci (z tabule, z telefonu, od zaměstnavatele). |
| 5 | FirstDelivery | Poprvé doručil a dostal zaplaceno. |
| 6 | Level2 | Dosáhl úrovně řidiče 2. |
| 7 | FirstVehicle | Má první vlastní kolo nebo auto (koupené nebo darované). |
| 8 | FirstMission | Spustil první misi. |
| 9 | FirstChapter | Dokončil celou první kapitolu misí (její poslední misi). |

Dvě věci, ať tě graf nepřekvapí:
- Kroky se počítají **popořadě**. Když hráč koupí kolo (krok 7) dřív, než dosáhne úrovně 2 (krok 6), kolo se
  započítá, až úroveň 2 přijde. Proto graf nikdy neukáže víc hráčů na pozdějším kroku než na dřívějším.
- Kroky 1 až 3 se doplní samy, když hráč udělá něco pozdějšího (třeba vezme práci dřív, než Marge stihne promluvit).

Jak číst schody:
- **1 → 2** velký schod: hráči odcházejí ještě před PLAY. Hra se možná načítá moc dlouho.
- **2 → 3**: odejdou hned po startu, než promluví Marge.
- **3 → 4**: Marge je přivítala, ale práci si nevzali. Úvod možná není jasný.
- **4 → 5**: práci vzali, ale první doručení nezvládli. Podívej se do **Delivery** a na události **JobFailed…**.
- **5 → 6** a dál: hra je baví, ale přestanou dřív, než se dostanou dál. Porovnej s **SessionLength** (jak dlouho hrají).

## Rozvoz a mise (Funnels → Delivery a Mission)

**Delivery** sleduje každou zakázku zvlášť:
1. **Taken**: zakázka přijata.
2. **PickedUp**: náklad naložen (zakázka, která začíná s nákladem v autě, je naložená hned).
3. **Delivered**: doručeno a zaplaceno.

U každé zakázky jsou tři krátké údaje (v grafu je najdeš jako **CustomField01 až 03**, dají se podle nich filtrovat):
- **01 = jak**: `foot` (pěšky), `bike` (kolo), `car` (auto),
- **02 = hvězdy** (obtížnost): `1` až `4`,
- **03 = druh**: `Board` (běžná z tabule), `Special` (zvláštní práce), `Employer` (od zaměstnavatele), `Tutorial` (první práce od Marge).

Zakázka, která se nepovede, v tomhle grafu prostě skončí na kroku, kam došla. Proč se nepovedla, říkají vlastní
události **JobFailedTime**, **JobFailedCargo**, **JobGaveUp** a **JobFailedOther** (níže).

**Mission** sleduje každé spuštění mise: **Started** (spuštěna) → **Completed** (dokončena). Údaj **01** je kapitola
(např. `dispatch` = Marge, First Shift), údaj **02** říká `First` (poprvé) nebo `Replay` (znovu).

## Peníze (Economy)

Měna je **Cash**. Každý pohyb peněz má **důvod** a u nákupů i **věc** (v grafu „item SKU“: např. `van` = Old Van).
Roblox ukazuje i stav peněz hráče po každém pohybu, takže uvidíš, jestli hráči peníze hromadí, nebo jim chybí.

Odkud peníze přicházejí (**Sources**):

| Důvod | Co to je |
|---|---|
| DeliveryPay | výplata za zakázku (řidič) |
| CrewPay | podíl člena posádky |
| Tip | spropitné (hod, PERFECT, zachránce, svezení přeživšího) |
| KillReward | odměna za zombie a bandity |
| CrateLoot | peníze z bedny se zásobami |
| MissionReward | odměna za misi a za kapitolu |
| ChallengeReward | výzvy a ztracené balíky |
| LevelReward | odměna za novou úroveň |
| CompanySafe | výběr ze sejfu tvé firmy |
| TaskReward | denní a týdenní úkoly |
| TutorialReward | odměna od Marge za první doručení |
| Refund | vrácené peníze (odtah, který nepřijel, koloběžka, vyřazené vybavení) |
| PropertySale | prodej nemovitosti |
| Admin | peníze z admin panelu (tvoje testování; ve skutečné hře by neměly být) |

Kam peníze odcházejí (**Sinks**):

| Důvod | Co to je |
|---|---|
| Car, Bike | auta a kola (i Earlova dodávka) |
| Gun, CarGun | zbraně do ruky a na střechu auta |
| Item, Kit, Gear | věci, osobní vybavení, výbava auta |
| Paint, Stage, Upgrade | lak, stupně auta, vylepšení |
| Style | oblečení a vzhled |
| RealEstate | nemovitosti |
| Company | kurýři a vylepšení tvé firmy |
| Fuel, Tow, Repair | benzín, odtah, oprava |
| Reroll | nové nabídky na tabuli prací |
| Rental | půjčení koloběžky (teď zdarma) |

Malé časté částky (**KillReward**, **Fuel**, **Tip**) se sčítají a posílají jednou za minutu za hráče, aby jich nebyly
tisíce. Důvod **Other** znamená pohyb peněz, který hra nepojmenovala; když ho uvidíš hodně, řekni Claudovi.

## Růst (Progression)

- **DriverLevel**: „Level 3 Complete“ znamená, že hráč dokončil úroveň 3, tedy dosáhl úrovně 4. Kde čísla prudce
  klesnou, tam se hráčům růst zasekává.
- **Missions**: číslo úrovně je pořadí mise v příběhu (1 = první mise první kapitoly), jméno je kód mise
  (např. `dispatch_1`). **Start** = spuštěna, **Complete** = dokončena, **Fail** = nepovedla se. Počítá se hráči,
  který misi spustil (ne celé posádce). Mise s hodně Fail je moc těžká.

## Vlastní události (Custom events)

| Událost | Kdy se zapíše | Hodnota a údaje |
|---|---|---|
| DeathOnJob | hráč zemřel na zakázce nebo misi (i jako člen posádky) | 01: `Job` nebo `Mission` |
| JobFailedTime | zakázce došel čas | 01 jak, 02 hvězdy, 03 kam došla (`Taken` / `PickedUp`) |
| JobFailedCargo | náklad je pryč (ukradený, zničený, rozbitý) | stejně jako výše |
| JobGaveUp | hráč to sám vzdal (GIVE UP) | stejně jako výše |
| JobFailedOther | jiný konec (odešel parťák, výbuch při misi bez střílení, admin) | stejně jako výše |
| QueueAddAll | tlačítko ADD ALL na tabuli prací | hodnota: kolik prací přidal |
| ZipRide | jízda na lanovce | 01: číslo lanovky |
| BusRide | nástup do autobusu | 01: linka |
| ScooterRental | půjčení koloběžky ZDC RIDE | 01: stanice |
| StylePurchase | nákup oblečení / vzhledu | hodnota: cena, 01: místo (`hat`, …) |
| SessionLength | hráč odešel ze hry | hodnota: minuty hraní, 01: `New` (ještě neprošel všech 9 kroků) nebo `Veteran` |
| ServerError | chyba ve skriptu na serveru | 01: jméno skriptu |
| ClientError | chyba ve skriptu u hráče v zařízení | 01: jméno skriptu |
| GoldenOffered | (6.14) na tabuli se objevila ZLATÁ ZAKÁZKA | hodnota: hvězdy, 01: jak (`car` / `bike` / `foot`) |
| GoldenTaken | (6.14) hráč zlatou zakázku vzal | stejně jako výše |
| GoldenDone | (6.14) zlatá zakázka doručena a zaplacena | stejně jako výše |
| GoldenExpired | (6.14) zlaté zakázce došel čas dřív, než ji hráč vzal | stejně jako výše, 02: kde (`board` / `queue`) |
| RegularTierUp | (6.14) hráč je u firmy stálým zákazníkem o stupeň výš | hodnota: stupeň (1–4), 01: stupeň (`bronze` …), 02: firma (`pizzeria` …) |

## Chyby (Error Report)

- **Error Report** sbírá Roblox sám: celé chybové hlášky ze serverů i ze zařízení hráčů, kolikrát se staly a kdy.
  Tam je hledej jako první.
- Hra k tomu počítá **ServerError** a **ClientError** podle jména skriptu, takže rychle uvidíš, který skript zlobí
  nejvíc. (Roblox chce u každé události hráče, proto se chyba serveru zapíše k jednomu z hráčů na tom serveru.)
- V okně **Output** (ve Studiu i v konzoli živého serveru, klávesa F9) uvidíš řádky jako
  `[Analytics] ServerError in Jobs:123 (…)`. Nejvýš 6 za minutu od každého druhu (ServerError, ClientError), aby
  Output nezahltily. Jeden hráč pošle hlášení o chybě nejvýš jednou za 20 sekund.

## Jak to vyzkoušet ve Studiu

Ve Studiu se nic neposílá, ale hra počítá, co by poslala:
1. Spusť hru (Play) a zmáčkni **P** (admin panel) → záložka **WORLD**.
2. Nahoře je řádek **Analytics**, např.
   `OFF in Studio (counted, not sent) · onboarding 3 · funnel 0 · economy 1 · progression 0 · custom 0 · error 0 · last: …`
3. Udělej něco a zmáčkni **REFRESH**: vezmi práci (stoupne **funnel** a **onboarding**), doruč ji (stoupne
   **economy** a **funnel**), kup něco (stoupne **economy**, na konci řádku je `last: Economy Sink …`).
   Ve Studiu bez ukládání začínáš jako nový hráč, takže uvidíš i kroky cesty nového hráče.
4. V Output je na začátku jednou řádek `[Analytics] off in Studio: nothing is sent…`.

Na zveřejněné hře tam místo „OFF in Studio“ stojí **ON, sending**. Když tam je **dropped** nebo **failed**, Roblox
některé zprávy nepřijal (bylo jich moc najednou, nebo chyba). Napiš to Claudovi.

Celou analytiku vypneš v `src/shared/Config.luau`: `Config.Analytics.Enabled = false`.

## Co poslat Claudovi, když něco nesedí

- **Snímek obrazovky** grafu i s vybraným obdobím (datum od–do) a s filtry, které máš zapnuté.
- **Co čekáš a co vidíš**, jednou větou (např. „Delivered je skoro nula, ale hráči doručují“).
- Řádek **Analytics** z admin panelu (P → WORLD) na živém serveru.
- Řádky z **Output**, které začínají `[Analytics]` (i varování kolem nich).
- Z **Error Reportu**: jméno skriptu, celé hlášení chyby a kolikrát se stala.
- **Verzi hry** (je na úvodní obrazovce, např. 6.13) a jestli se to stalo ve Studiu, nebo na zveřejněné hře.
