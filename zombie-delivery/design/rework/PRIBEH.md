# Příběh: „Poslední stěhování“ (The Last Move)

Toto je český přehled příběhu stěhování (Zombie Delivery 7.0), aby se dal pohodlně přečíst a případně upravit.
Ve hře jsou všechny texty anglicky a žijí v jednom souboru: `src/shared/MoveStory.luau`. Návrh, ze kterého příběh
vychází, je v `NAVRH.md` (kapitola 1).

## O čem to je

Město se evakuuje čtvrť po čtvrti. Armáda kapitánky Marie staví kolem bezpečné zóny **Zeď**. Za Zeď smí každý jen
s tím, co se vejde do jednoho auta; co zůstane venku, patří mrtvým. Lidé už nepotřebují balíky, potřebují náklaďák.
Marge proto přestaví rozvážkovou firmu na **ZDC Moving & Evacuation** s heslem
*„We move your life. The rest they eat.“* (Stěhujeme váš život. Zbytek sežerou oni.)

Klienty jsou postavy, které už ve hře jsou (z misí). Každá kapitola je stěhování jednoho jejich světa: domu, ranče,
kliniky, hotelu, vily, laboratoře, muzea a nakonec vlastního depa. Tón je stejný jako v misích: krátké věty, suchý
humor, trochu černého humoru, ale postavy to se svými věcmi myslí vážně.

**Padouši:** Big Move Movers, bývalá stěhovací firma (ve hře už mají budovu a u jejich tabule stojí šéfová **Dana**).
Z firmy se stal gang zlodějů: číhají u domů, kradou náklad z aut a před každou akcí se ozvou vysílačkou s posměškem.
V páté kapitole vyjde najevo proč.

## Jak se příběh ve hře ukazuje

1. **Úvod od Marge.** Když poprvé otevřete tabuli „Moving contracts“ v depu, objeví se filmové karty (černé pruhy
   nahoře a dole, portrét mluvčího, jeho jméno a věta). Marge ve čtyřech kartách vysvětlí evakuaci, Zeď a nové jméno
   firmy; druhou kartu říká kapitánka Maria. Úvod se ukáže jen jednou: uloží se do profilu (i u starých uložených
   her, takže ho uvidí každý jednou).
2. **CHAPTERS na kartě zakázky.** Pod tlačítkem START je „cesta příběhem“: řada dlaždic, která jde posouvat do
   stran. Prolog má ▶ PLAY, kapitola 1 (Walt's Farm) 🔒 LOCKED, dokud nedokončíte prolog, a potom ▶ PLAY; zbylých
   šest dílů má 🔒 SOON. Každá dlaždice má portrét klienta, název a jméno klienta. Klepnutím na dlaždici se pod řadou
   ukáže, o čem díl je (u zamčené i co je potřeba dokončit dřív); klepnutím na ▶ PLAY se otevře karta té zakázky.
   Nad cestou je řada zakázek z tabule (Marge's House, 🐴 Walt's Farm, zamčená s 🔒 a důvodem).
3. **Briefing.** Po stisku START promluví Marge a klient (3–5 karet); poslední karta je vysílačka Big Move Movers
   s Daniným posměškem. Tlačítko ▶ START THE MOVE nebo SKIP stěhování spustí, ✕ vrátí kartu zakázky. Briefing se
   v jedné hře ukáže jednou pro každou kapitolu, další START už spustí stěhování hned.
4. **Zprávy v telefonu (MESSAGES).** Na začátku stěhování napíše Marge celé partě (u prologu:
   *„Grandpa's clock is in the living room. Don't you dare drop it.“*), po konci pošle shrnutí podle výsledku, které
   zároveň navede na další kapitolu.
5. **Poděkování na výsledkové kartě.** Klient s malým portrétem řekne jednu větu podle výsledku.
6. **Postavy, které vás vítají** (texty v sekci greeters v `MoveStory.luau`, kód `server/MoveGreeters.luau`):
   - **Marge na verandě** svého domu stojí u dveří od začátku stěhování. Když k domu jako první dojde někdo z party,
     otočí se tím směrem, zamává a v bublině řekne *„Oh thank heavens, ZDC!“*, pak ukáže na otevřené dveře a připomene
     dědečkovy hodiny. Během stěhování občas něco řekne: když jde kolem ★ věc (*„Careful with that!“*), když přijde
     horda (*„They're coming! Hurry!“*) a když naložený náklaďák odjíždí (*„Thank you… see you behind the Wall.“*;
     tahle věta přijde partě i jako oznámení). Zombíci si jí nevšímají a s koncem stěhování odejde.
   - **Walt u statku** (kapitola 1) stojí u dveří svého statku: kovbojský klobouk, kostkovaná košile, knír. Přivítá
     vás (*„Howdy, ZDC! About time.“*), u každé ★ věci má vlastní větu (*„Easy with Thunder's saddle!“*), zakřičí na
     hordu (*„Here they come! Saddle up!“*) a rozloučí se (*„Much obliged. See you behind the Wall.“*).
   - **Voják u Zdi** stojí u budky kontrolního stanoviště. Když tam doručíte náklad (každou jízdu), zamává a řekne
     *„Welcome to the safe zone. Unload over there.“*
   - **Marge u stánku Moving contracts** je ta samá Marge z tutoriálu, co stojí v depu u tabule s joby (žádná druhá
     Marge). Když ke stánku přijdete pěšky a zrovna nestěhujete, otočí se k vám a řekne *„New contract, sweetie?“*
     (bublina a oznámení), každému hráči nejvýš jednou za tři minuty.

Výsledek stěhování se pro příběh počítá takto: **skvělé** = doručeno se 4–5 hvězdami, **dobré** = doručeno s méně
hvězdami, **pozdě** = vypršel čas, **nepovedlo se** = stěhování bylo zrušeno nebo ke Zdi nedorazilo nic.

Kapitola se počítá jako dokončená (a odemkne další), když skončí doručením nebo pozdě a ke Zdi dorazila aspoň jedna
věc. Uloží se do profilu (příznak `done:<kapitola>` v `profile.story`) jen u skutečně ukládané hry.

**Stěhuje se vaší vlastní dodávkou** (ZDC Van; dřív se půjčoval náklaďák Moving Truck). Do dodávky se toho vejde méně,
proto se jezdí víckrát: u Zdi se vyloží všechno, co v ní je (jedna jízda, „TRIP“), a stěhování pokračuje, dokud
nevyprší čas nebo dokud majitel zakázky nestiskne FINISH. Platí se za všechno doručené ze všech jízd. Když se dodávka
rozbije nebo zmizí, co v ní bylo, je ztracené, ale stěhování běží dál a za 20 s ji přivolá CAR znovu.

## Postavy

- **Marge** – dispečerka a šéfová ZDC. Suchá, neochotně dojatá, hráči říká *rookie* (nováčku).
- **Kapitánka Maria** – velí armádě a staví Zeď. Mluví krátce a rozkazem.
- **Klienti kapitol** – Walt, doktorka Ellie, Raj, dvojčata Rosa a Rico, inženýr Ivan s doktorem Hirem, starostka
  Ruth. Mluví stejně jako ve svých misích.
- **Dana, Big Move Movers** – šéfová gangu. Do příběhu vstupuje jen vysílačkou, posměšně a sebevědomě.

## Kapitoly

### Prolog – „Everything Must Go“ (Všechno musí pryč) · hratelné teď

- **Klient:** Marge · **Místo:** 155 Willow Ln, předměstí (zakázka „Marge's House“)
- **O čem:** Zeď se dnes v noci zavře nad Willow Lane a dům Marginy rodiny zůstane na špatné straně. Čtyřicet let
  jejího života, jeden náklaďák, dvanáct minut. Vaše první stěhování a klientkou je vaše vlastní šéfová.
- **Cennosti ★:**
  - *Dědečkovy hodiny* – postavil je Margin otec v roce, kdy se narodila. Nikdy nešly přesně.
  - *Maminčin gramofon* – maminka na něj každou neděli tančila. Zbyla jedna deska a nikdo neví která.
  - *Houpací kůň* – Marge na něm jezdila jako holka. Ucho ztratil při „úprku stáda“, který dodnes nevysvětlila.
  - (*Rodinné fotky* – čtvrtá cennost; v tomhle domě mezi ★ věcmi nejsou, jiný plán domu je může vybrat.)
- **Briefing:** Marge s úsměvem připomene, že klientkou je ona („žádný tlak“), a vysvětlí základy: dojet k domu,
  vynést věci, naložit je dozadu. ★ věci jsou nejdůležitější (nábytek se dá koupit znovu, tohle ne). Velké věci nesou
  dva, těžké dospod, křehké nahoru. Tři minuty před koncem přijdou mrtví na večeři.
- **Dana:** „Pěkný domeček, Marge. Škoda, kdyby tvému nováčkovi cestou ke Zdi trochu ubylo nákladu.“
- **Konec:** Skvěle – hodiny tikají za Zdí (pořád špatně) a Walt volá, že jeho ranč je další na Mariině mapě.
  Dobře – většina jejího života to zvládla. Pozdě – Zeď se zavřela nad půlkou kuchyně. Nepovedlo se – dům patří
  mrtvým („ať si platí hypotéku“) a zkouší se to znovu.

### Kapitola 1 – „Hold Your Horses“ (Držte koně) · hratelné teď

- **Klient:** Walt · **Místo:** Waltův statek na místě Old Farm (zakázka „Walt's Farm“; odemkne se po prologu)
- **O čem:** Zeď končí míli před statkem a Walt nenechá vzadu ani jedno sedlo. Statek, stodola plná krmiva a vůz na
  seno, který projde jen vraty stodoly. Těžké, hlučné a po prašné cestě.
- **Hraje se:** 14 minut, horda 3:30 před koncem, výplata × 1,25. Dovnitř se jde dvěma cestami: dveřmi statku
  a vraty stodoly. Vůz na seno projde jen vraty stodoly (u dveří statku hra řekne „Too big — use the barn doors“)
  a do dodávky se nevejde, jede zapřažený za ní. Kolem statku jsou krabice, přívěs na koně, balíky sena a cedule ZDC.
- **Cennosti ★:** Thunderovo sedlo (starý hřebec bez něj nikoho nepustí na hřbet, někdy ani s ním), cejch
  (značka Silver Spur od roku 1921, ukoval ho Waltův děda), babiččina máselnice (šedesát let v ní každé ráno tloukla
  máslo). Čtvrtá cennost jsou kravské zvonce (jiný plán statku je může vybrat). Ve hře platí plán 1921: ★ jsou sedlo,
  cejch a máselnice.
- **Briefing:** Když Zeď nepřijde ke statku, statek půjde ke Zdi. ★ věci jedou s Waltem: Thunderovo sedlo, cejch
  a babiččina máselnice. Marge: dvě cesty dovnitř, dům a stodola; vůz na seno projde jen vraty stodoly a jede
  zapřažený za dodávkou. Kolem stodoly slídí Rust Riders a nějací „stěhováci“ v oranžových náklaďácích.
- **Dana:** „Pěkní koně, kovboji. Bereme všechno, co má nohy a cenovku.“
- **Konec:** Walt je spokojený nebo pohřbívá traktor; v každém případě volá doktorka Ellie, klinika nepočká.

### Kapitola 2 – „Handle With Care“ (Opatrně, křehké) · brzy

- **Klient:** doktorka Ellie · **Místo:** City Clinic
- **O čem:** Poslední nemocnice mimo Zeď. Každý skener, lednice i pacient se musí přestěhovat bez otřesu a bez
  bakterií. Všechno je křehké a mrtví cítí krevní banku.
- **Cennosti ★:** starý rentgen (starší než Ellie, hlasitější než náklaďák), kávovar (Ellie na něm klinika jede,
  netestovat), květina sestry Ady (přežila nákazu, dva požáry i Rica).
- **Briefing:** Lednice zůstanou v zásuvce do poslední chvíle, krvi je časovač jedno. Pacienti odejdou sami, vy nesete
  všechno ostatní. Kdo uslyší kašel, ať nejdřív ověří, že jde o pacienta, a teprve potom střílí.
- **Dana:** „Nemocniční vybavení se prodá za trojnásobek, doktorko. Díky, že jste ho tak hezky zabalili.“
- **Konec:** Ellie otevře kliniku za Zdí (a poprvé řekne „dobrá práce“) nebo přijde o krevní lednici. Ozve se Raj.

### Kapitola 3 – „Room Service“ (Pokojová služba) · brzy

- **Klient:** Raj · **Místo:** Grand Hotel
- **O čem:** Když FreshMart zavřel, Raj odnesl regály a čtyřicet sousedů do Grand Hotelu. Teď se Zeď posouvá a hotel
  ne. Šest pater, mrtvý výtah a hosté zabarikádovaní v pokojích, kteří nikomu neotevřou.
- **Cennosti ★:** cedule FreshMartu (32 let visela nad Rajovými dveřmi, nahoru ji vynesl na zádech), hotelové piano
  (Raj neumí hrát, jen se mu líbí, že by někdo mohl), Rajova kniha dluhů (všechny dluhy ulice od roku 1993; minulý
  týden je všechny odpustil).
- **Briefing:** Check-in je zavřený, check-out je dnes a peníze se nevrací. Výtah potřebuje proud, proud je ve sklepě
  a ve sklepě jsou „hosté“, ne ti platící. Zabarikádovaným hostům se klepe dvakrát a řekne se heslo „Raj sent me“,
  jinak házejí nábytek. Šest pater po schodech: lehké věci snést, těžké spustit, s žádnou nespadnout.
- **Dana:** „Šest pater kořisti a jeden unavený nováček, Raji. Vezmeme to po schodech. I se vším, co na nich je.“
- **Konec:** Raj otevře FreshMart za Zdí (první zákazníci jsou jeho hosté, banány zdarma), nebo počítá, kdo zůstal
  v pátém a šestém patře. Volají dvojčata.

### Kapitola 4 – „Hot Property“ (Horké zboží) · brzy

- **Klient:** Rosa a Rico · **Místo:** Vinnieho vila
- **O čem:** Vinnie odplul na jachtě a vilu nechal dvojčatům, bez kódů od alarmu. Obrazy, trezor, který sám nikdo
  neunese, a galerie věcí, které možná byly kradené. Big Move Movers je chtějí dřív.
- **Cennosti ★:** portrét Vinnieho matky (jediný obraz, který prý opravdu zaplatil), trezor (kód nikdo nezná, Rico
  tvrdí, že ho otevře, a nikdo ho k tomu nepustí), jukebox (první společná zakázka dvojčat, stěhovali ho dvakrát
  a pořád hraje).
- **Briefing:** Vinnie chce za Zdí obrazy, trezor a matčin portrét. Alarm funguje, strážní ne: jsou z nich zombíci,
  „takže technicky tu pořád pracují“. Dva nesou trezor, jeden drží dveře, jeden hlídá bránu. Marge: „Jestli je ve
  vile něco kradené, my to neviděli. My to jen stěhujeme.“
- **Dana:** „Ta vila je naše, dvojčata. Všechno v ní už jednou někdo ukradl. My jen držíme tradici.“
- **Konec:** Vinnie pošle z jachty pohlednici „grazie“ na drahém papíře, nebo visí jeho obrazy v kanceláři Big Move.
  Volá inženýr Ivan a zní vyděšeně.

### Kapitola 5 – „The Zero Files“ (Spisy Nula) · brzy · zvrat příběhu

- **Klient:** inženýr Ivan a doktor Hiro · **Místo:** elektrárna a Biotech Lab
- **O čem:** Ivan musí odstavit elektrárnu dřív, než se Zeď zavře, a Hirova laboratoř se stěhuje s ní. Díly turbíny,
  mrazáky, výzkum. Pak se objeví Hirovy spisy o Pacientce nula a příběh nákazy se změní.
- **Cennosti ★:** Mrož, jádro turbíny (třicet let napájel město a pořád brouká, když na něj Ivan mluví), vzorky léku
  (zmražená krev Pacientky nula, jediný důvod, proč lék existuje), spisy Nula (první den, sepsaný; Hiro je schoval
  z dobrého důvodu).
- **Briefing:** Jakmile Ivan elektrárnu odstaví, zhasne celé město až ke Zdi, takže se jede rychle a Mrož první.
  Mrazáky se odpojí naposled a nikdy se neotevírají. Hiro prosí, ať krabici se spisy přivezete, ale nečtete.
  Marge: „Když vědec prosí, ať něco nečtete, je to ten nejlepší důvod si to přečíst.“
- **Zvrat:** Spisy říkají, že první den nákazy převážel náklaďák Big Move Movers bednu z Hirovy laboratoře a upustil
  ji. Řidičkou byla Pacientka nula, žena, kterou kousli první den a nikdy se nezměnila (známe ji z misí). Dana to
  věděla. Proto se z firmy stal gang: kradou a zametají stopy.
- **Dana:** „Nech ty papíry být, Hiro. Některé příběhy patří do krabice. Třeba ten náš.“
- **Konec:** Marge spisy přečte a pravda je venku, nebo je Danini lidé chtějí spálit. Volá starostka Ruth.

### Kapitola 6 – „Heavy History“ (Těžká historie) · brzy

- **Klient:** starostka Ruth · **Místo:** městské muzeum
- **O čem:** Ruth nenechá paměť města za Zdí. Muzeum má bronzového zakladatele, kostru dinosaura a sál obrazů a akce
  běží v noci. Nejtěžší stěhování a Big Move Movers znají cestu dovnitř.
- **Cennosti ★:** socha zakladatele (dvě tuny bronzu, první starosta a Ruthin prapradědeček), Rex (kostra dinosaura,
  každé dítě ve městě s ním má fotku), městská listina (podepsaná roku 1871 lidmi, kteří si mysleli, že město vydrží
  navždy).
- **Briefing:** V muzeu je všechno, čím město kdy bylo. Jede se v noci, kdy jsou ulice nejtišší (relativně). Socha
  potřebuje jeřáb, dinosaurus deset lidí a listina jednoho, kdo nekýchá. Big Move Movers prodávají muzejní kusy
  každému, kdo má loď; dnes nedostanou ani kost.
- **Dana:** „Dinosauří kosti, paní starostko. Kupci s loděmi platí od kila. Díky, že vybíráte ty těžké.“
- **Konec:** Rex stojí za Zdí a děti se s ním zase fotí, nebo zbyla půlka muzea. Maria hlásí, že se Zeď za úsvitu
  zavře nadobro.

### Finále – „Last One Out“ (Poslední zhasne) · brzy

- **Klient:** celá ZDC · **Místo:** depo ZDC
- **O čem:** Zeď se zavře za úsvitu a depo ZDC je na špatné straně. Na dvoře čeká každý náklaďák, každá trofej
  a všichni klienti z předchozích kapitol. Big Move Movers jdou po spisech a po vás.
- **Cennosti ★:** Margin stůl (dispečerský stůl od prvního dne: stěhuje se s ní, nebo se nestěhuje ona), police
  trofejí (cennosti z celé hry: sedlo, jukebox, Rexův zub), cedule ZDC (dvakrát přemalovaná: Dead End Dispatch,
  pak ZDC Moving; ještě jeden nátěr).
- **Briefing:** Maria: brána se zavře a už se neotevře, pro nikoho. Marge: všichni, komu se stěhovalo, čekají za ní;
  teď je řada na nás. Dana přijde dnes v noci se vším, co má. „Balíme, zvedáme, nakládáme, jedeme. Poslední zhasne,
  nováčku.“
- **Dana:** „Zhasnuto, Marge. Tvoje spisy, tvoje náklaďáky, tvoje Zeď. Stěhujeme se k vám.“
- **Konec:** Skvěle – brána je zavřená, všichni jsou na správné straně a za Zdí visí cedule ZDC („některé věci se
  nestěhují“). Hůř – náklaďáky zůstaly venku, ale lidi jsou uvnitř. Nepovedlo se – Dana odjela s náklaďáky, ale
  všichni žijí a Zeď pořád má bránu.

## Co je teď hratelné a co dál

- Hrát jde **prolog** (zakázka „Marge's House“) a **kapitola 1** (zakázka „Walt's Farm“, po dokončení prologu).
  Ostatní kapitoly jsou zatím jen příběh a na kartě mají 🔒 SOON; každá má připravené všechny texty a jakmile pro ni
  vznikne místo a zakázka, stačí v `MoveStory.luau` doplnit `contract` a smazat `soon = true`.
- Kapitoly se odemykají po řadě (každá potřebuje tu předchozí, finále všechny).
- Délky textů hlídají testy (`tests/movestory_test.luau`) podle limitů v `Config.MoveStory`, aby se každá věta
  vešla na svou kartu, i na telefonu.
