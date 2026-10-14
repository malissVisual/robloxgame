# 8.3 SANDBOX: kontrola v Roblox Studiu

Automatický test `tests/sandbox_e2e_runtime_test.luau` projde celou smyčku se skutečnými moduly hry, jen bez Robloxu
a bez fyziky. Spouští se spolu s ostatními testy (`python3 tests/run_tests.py <cesta k luau>`). Tento seznam je to,
co test ověřit nedokáže: jak hra vypadá a jak se hraje ve Studiu.

**Příprava**
- Studio → karta **Test** → **Clients and Servers**: *Local Server* a **2 hráči** (body 1–14). Pro bod 15 pět hráčů.
- Od 8.3 začíná nový hráč v garáži (level 1, 2 stojany). Body 8 a 10 proto zkoušejte na levelu 4: admin → SANDBOX →
  **💰 +$10K** a u pultu UPGRADES kupte **ZDC Warehouse** až do levelu 4 (nebo **⬆ MAX UPGRADES**). Úrovně skladu: bod 18.
- Okno serveru nechte otevřené. Do jeho Output se píšou chyby. Na konci v něm nesmí být žádná červená chyba.
- Hráče níže jmenujeme **A** (první okno) a **B** (druhé okno).
- Pro bod 13 (ukládání): Game Settings → Security → **Enable Studio Access to API Services** zapnuto, jinak se nic
  neuloží.

Zaškrtněte, co sedí. Když něco nesedí, poznamenejte číslo bodu a co jste viděli.

## 1. Připojení
- [ ] A dostane pozemek 1, B pozemek 2. Na nápisu každého skladu je jméno jeho hráče. Pozemky 3 a 4 mají **FOR RENT**.
- [ ] Oba mají v pravém horním seznamu hráčů sloupce **💰 $**, **📈 $/min** a **⭐ Collection**. Nové uložení začíná na $500.

## 2. PLAY
- [ ] Po PLAY stojíte u svého skladu. Van stojí na svém místě, čumákem k silnici a zadními dveřmi k vratům skladu.
- [ ] Van hráče B stojí u skladu 2, ne u skladu 1.

## 3. Zakázka
- [ ] U kiosku (tabule) na svém pozemku: E → karta zakázky „The Old Chalet“ → **START** → **LAUNCH**. Danny čeká u vanu.
- [ ] B jde ke kiosku hráče A: dostane jen **svou** zakázku. Zakázku hráče A spustit nemůže.

## 4. K domu a dovnitř
- [ ] Dojeďte k chatě a zastavte u chodníku. Otevřete zadní dveře vanu.
- [ ] Postavte se před vchodové dveře a dívejte se na ně. Za chvilku (čtvrt vteřiny) obrazovka ztmavne a jste uvnitř.
      Žádný prompt nemačkáte.

## 5. Zvednutí (grip)
- [ ] Těžký kus, který se nese oběma rukama: **Pick up** otevře lištu s ručičkou a zelenou zónou.
- [ ] Zmáčkněte (myš, F nebo TAP) **mimo** zónu: kus sklouzne zpět, zkusíte to znovu.
- [ ] Zmáčkněte **v zóně**: kus zvednete a jdete vyrovnaně.
- [ ] Při chůzi přijde **WOBBLE!**. Trefa = klid. Netrefíte se = zakopnutí a chvíli jdete pomaleji.
- [ ] Zkuste to s pingem (Studio → File → Studio Settings → Network → Incoming Replication Lag, např. 0.2 s). Trefa
      v zóně se musí počítat i tak.

## 6. Naložení
- [ ] Vyneste kus dveřmi ven a naložte ho u zadních dveří vanu (prompt u dveří).
- [ ] Malý kus (jedna ruka) naložte zevnitř: vejděte do vanu a naložte v nákladovém prostoru.

## 7. Domů: trip
- [ ] Zajeďte na pozemek **hráče B**: nic se nevyloží.
- [ ] Zacouvejte zádí do kruhu **na svém** pozemku. Zpráva „🏠 Trip 1 home: …“, kusy zmizí z vanu a jsou ve skladu (B =
      seznam STOCK).
- [ ] Toast „📖 New in your book: …“. V knize (C) je ten kus nalezený.
- [ ] Druhý trip: tentokrát vjeďte do kruhu **čumákem napřed**. Také se vyloží.
- [ ] B zemře, když nese kus. Objeví se znovu u svého vanu a kus jde zvednout znovu.

## 8. Sklad: vystavení
- [ ] Prázdný stojan → **Display** (E) otevře výběr. Vyberte kus → **DISPLAY**. Na stojanu se objeví jeho 3D model
      a cedulka $/min.
- [ ] Přesun na jiný stojan a **Take down** fungují.
- [ ] Velký kus na malý stojan nejde. Stojan, který už něco ukazuje, nejde. Hlášky jsou srozumitelné.

## 9. Příjem
- [ ] Počkejte minutu. Peníze rostou zhruba o $/min (výplata každých pár sekund). Sloupec **📈 $/min** v seznamu
      hráčů sedí s HUD.
- [ ] Tabule **TOP MOVERS** na křižovatce: oba hráči, seřazení podle hodnoty sbírky. Kdo má víc, je první.

## 10. UPGRADES
- [ ] Pult **Upgrades** vzadu ve skladu. Bez peněz koupě nejde (hláška „costs …“).
- [ ] S penězi (admin → SANDBOX → peníze) na levelu 4: **More stands** → přibude stojan 13 a jde na něj vystavit.
- [ ] **Showroom lights**: cedulky $/min ukazují víc (× 1,1).

## 11. Prodej
- [ ] U vystaveného kusu podržte **F (Sell)**: kus zmizí, peníze přibudou.
- [ ] Seznam STOCK (B): **TAKE ALL DOWN** sundá vše, **SELL…** prodá duplikáty, **⭐ FILL BEST** zaplní volné stojany
      nejvýdělečnějšími kusy. Když už nic nejde, tlačítko řekne proč.

## 12. FINISH
- [ ] **FINISH**: karta výsledku ukáže „N PIECES CAME HOME · WORTH $…“: kolik kusů je doma a jakou mají hodnotu.
- [ ] **📋 TASKS (J)**: úkol na tripy, na prodej a týdenní na příjem se posunuly. Hotový úkol jde **CLAIM** jen jednou.

## 13. Odejít a vrátit se
- [ ] A opustí hru (zavřete jeho okno). Pozemek 1 je **FOR RENT** a jeho kusy ze skladu zmizí.
- [ ] Ukončete test (Cleanup) a spusťte ho znovu: A má znovu pozemek 1, stejné kusy na stejných stojanech (i stojan
      13), upgrady, knihu, úkoly i peníze.
- [ ] **Van engine**: van po PLAY i nový van z CAR jede rychleji.

## 14. Cizí sklad
- [ ] B ve skladu hráče A: **Display**, **Take down**, **Sell** ani pult **Upgrades** nefungují. Hláška říká, že to
      není jeho.

## 15. Plný server (5 hráčů)
- [ ] Pátý hráč nemá pozemek. Stojí na Depot Row, upgrady ani START nejdou („no warehouse“).
- [ ] Pátý hráč (admin → FILL STOCK) dá v seznamu STOCK (B) **⭐ FILL BEST**: hláška „Displays are for a warehouse of
      your own…“, nic se nevystaví a nic nevydělává (opraveno v 8.2).
- [ ] Když někdo odejde, pátý hráč dostane jeho pozemek a na skladu je jeho jméno.

## 16. Plný sklad
- [ ] (Před spuštěním testu dočasně nastavte `Config.Collection.MaxStock` na malé číslo, např. 3; potom ho vraťte na
      300.) Trip s plným skladem: „⚠ 1 could not be stored“ a „warehouse is full“.
- [ ] Kus, který se do plného skladu nevešel, se ztratil (domů nedorazil). Když nic jiného domů nedorazilo, FINISH
      řekne „Nothing delivered yet“ a zakázku ukončíte přes GIVE UP (opraveno v 8.2).

## 17. Odchod uprostřed zakázky
- [ ] Hráč s kusem ve vanu odejde. Jeho dům zmizí. Po návratu má jen to, co už bylo doma; kus z vanu je pryč. Zakázka
      neběží.

## 18. Úrovně skladu (8.3)
Pro tento bod stačí jeden hráč. Uložení začněte jako nový hráč: buď s vypnutým *Enable Studio Access to API Services*
(nic se nenačte), nebo admin → SANDBOX → **↺ RESET UPGRADES**.
- [ ] **Nový hráč je v garáži** (level 1): malá omítnutá budova s pultovou střechou a vraty uprostřed přední zdi,
      uvnitř **2 stojany** u zadní zdi. Mezi nimi stojí menší pult UPGRADES (jde na něj E), nad ním cedule UPGRADES.
      Tabule STOCK visí na levé (západní) zdi. Volné pozemky 3 a 4 jsou také garáže s **FOR RENT**.
- [ ] Van, kruh na vykládání, UNLOAD HERE, kiosk a místo, kde se objevíte, jsou tam, kde byly. Vrata garáže míří na van.
- [ ] Okno UPGRADES: první karta **ZDC Warehouse** 🏭 (Garage · 2 stands → Workshop · 4 stands, **$1,000**).
      **More stands** je zamčená, šedá, s nápisem „Needs the Big Warehouse“, a koupit nejde.
- [ ] Bez peněz koupě nejde. Admin → SANDBOX → **💰 +$10K** (několikrát) a kupujte level po levelu. Po každé koupi se
      sklad hned přestaví na větší budovu a přibudou stojany:
  - [ ] level 2 **Workshop** ($1,000): plechová dílna se sedlovou střechou, palety a sudy venku, **4 stojany**;
  - [ ] level 3 **Storehouse** ($7,500): betonový sokl, světlíky ve střeše, žluté sloupky u vrat, **8 stojanů**;
  - [ ] level 4 **Big Warehouse** ($30,000): dnešní velký sklad s kanceláří na boku, **12 stojanů**. **More stands** jde
        koupit (po dvou malých stojanech, nejvýš 20);
  - [ ] level 5 **Logistics Center** ($100,000): klenutá střecha se solárními panely, rampy, **24 stojanů** (s More stands
        až 32). Karta ZDC Warehouse je na maximu.
- [ ] Kus vystavený před koupí zůstane po přestavbě na stejném stojanu (číslo i cedulka $/min sedí). Tabule STOCK
      ukazuje správný počet stojanů.
- [ ] V každém levelu: projděte vraty (nic neviditelného nepřekáží, hlavou nenarazíte do střechy), obejděte budovu zvenku
      (žádná neviditelná zeď mimo budovu, do popelnice / palet / kanceláře / ramp narazíte). Světla v hale svítí
      z lamp modelu. Stojany, pult, tabule STOCK a cedule nad vraty nejsou zarostlé do modelu.
- [ ] Bez naimportovaného `ZDCWarehouseArt` stojí každý level z kostiček, stejně velký a se stejnými stojany.
- [ ] Admin → SANDBOX → **⬆ MAX UPGRADES**: level 5 a všechno naplno. **↺ RESET UPGRADES**: zpět garáž se 2 stojany.
      Kusy ze stojanů, které zmizely, jsou zpět ve STOCK (seznam B).
- [ ] **Staré uložení** (hráč, který hrál před 8.3, s penězi v uložení): po připojení má **level 4** (Big Warehouse,
      12 stojanů a své malé stojany z More stands), kusy na stejných stojanech. Zkouška: místo uložené ve verzi 8.2
      (s API Services zapnutými), pak tato verze.
- [ ] Odejít a vrátit se (bod 13): level skladu zůstane, jaký byl.

## Na konci
- [ ] V Output serveru není žádná červená chyba ani „failed to start“.
