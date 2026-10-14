# 8.2 SANDBOX: kontrola v Roblox Studiu

Automatický test `tests/sandbox_e2e_runtime_test.luau` projde celou smyčku se skutečnými moduly hry, jen bez Robloxu
a bez fyziky. Spouští se spolu s ostatními testy (`python3 tests/run_tests.py <cesta k luau>`). Tento seznam je to,
co test ověřit nedokáže: jak hra vypadá a jak se hraje ve Studiu.

**Příprava**
- Studio → karta **Test** → **Clients and Servers**: *Local Server* a **2 hráči** (body 1–14). Pro bod 15 pět hráčů.
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
- [ ] Toast „📖 New in your book: …“. V knize (K) je ten kus nalezený.
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
- [ ] S penězi (admin → SANDBOX → peníze): **More stands** → přibude stojan 13 a jde na něj vystavit.
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
- [ ] ⚠ **Známá chyba 1**: pátý hráč (admin → FILL STOCK) dá v seznamu STOCK (B) **⭐ FILL BEST**. Dnes se mu kusy
      vystaví a vydělávají, i když sklad nemá. Správně: hláška, nic se nevystaví.
- [ ] Když někdo odejde, pátý hráč dostane jeho pozemek a na skladu je jeho jméno.

## 16. Plný sklad
- [ ] (Před spuštěním testu dočasně nastavte `Config.Collection.MaxStock` na malé číslo, např. 3; potom ho vraťte na
      300.) Trip s plným skladem: „⚠ 1 could not be stored“ a „warehouse is full“.
- [ ] ⚠ **Známá chyba 2**: karta po FINISH dnes ukáže „1 PIECES CAME HOME“, i když se nic neuložilo. Správně: 0.

## 17. Odchod uprostřed zakázky
- [ ] Hráč s kusem ve vanu odejde. Jeho dům zmizí. Po návratu má jen to, co už bylo doma; kus z vanu je pryč. Zakázka
      neběží.

## Na konci
- [ ] V Output serveru není žádná červená chyba ani „failed to start“.
