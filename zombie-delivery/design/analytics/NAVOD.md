# Analytika: kde uvidíš, co hráči ve hře dělají

Od verze 6.13 hra posílá Robloxu krátké zprávy o tom, co hráči dělají: kam až noví hráči dojdou, kde odpadnou, za
co utrácejí peníze, jak rychle rostou a kde se hra rozbije. Nic osobního: jen počty a krátká slova (např. „car“,
„3 hvězdy“). Roblox z toho kreslí grafy na tvé stránce pro tvůrce.

Nic z toho nemusíš zapínat. Stačí hru zveřejnit a hrát.

## Kde to najdeš

1. Otevři **create.roblox.com** a přihlas se.
2. Nahoře klikni na **Creations** a vyber **Zombie Delivery**.
3. V levém menu najdi sekci **Analytics**. Tam jsou stránky, které tě zajímají:
   - **Funnels** → **Onboarding**: cesta nového hráče (9 kroků, viz níže).
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

## Cesta nového hráče (Onboarding, 9 kroků)

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
