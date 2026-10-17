# Výkon a mobily: návod pro majitele

Hodně hráčů hraje na telefonu. Hra je proto lehká: lobby má asi 1 300 dílů, malé nápisy se kreslí jen zblízka a sklady
se se streamováním načítají vždy celé. Podrobnosti pro Clauda jsou v [`REPORT.md`](REPORT.md).

(10.5: návod ke starému městu, jeho denní době a jeho místům je pryč i s městem; zůstává v historii Gitu do verze 10.4.)

## Krok 1: zapni streamování (jednou, ve Studiu)

Rojo (`node tools/rojo-sync.js zombie-delivery`) synchronizuje jen skripty. Nastavení Workspace je uložené přímo v
místě (place), proto se zapíná ve Studiu:

1. Ve Studiu otevři místo, které publikuješ.
2. V okně **Explorer** klikni na **Workspace**.
3. V okně **Properties** najdi skupinu **Streaming** a nastav tyto hodnoty:

   | Vlastnost | Hodnota |
   |---|---|
   | StreamingEnabled | ✔ (zaškrtnuto) |
   | StreamingMinRadius | 128 |
   | StreamingTargetRadius | 512 |
   | StreamOutBehavior | Opportunistic |
   | StreamingIntegrityMode | PauseOutsideLoadedArea |
   | ModelStreamingBehavior | Improved (pokud tam je) |

4. Volitelně: klikni v Exploreru na **Lighting** a podívej se na **Technology**. Pokud je tam **Future**, zkus
   **ShadowMap**: na telefonech bývá rychlejší. Porovnej FPS v přehledu (krok 2). Když se ti vzhled nebude líbit, vrať
   to zpátky.
5. Ulož a publikuj (**File → Publish to Roblox**).
6. Kontrola: po **Play** ve Studiu nesmí být v Output řádek `[Server] workspace.StreamingEnabled is off …`.

## Krok 2: zapni přehled výkonu

Přehled vidí jen admin. Tvůj účet admin je, protože jsi tvůrce hry; další admini jsou v `Config.Admin.UserIds`.
- **Na počítači:** stiskni **P** a klikni na **PERFORMANCE · OFF** (přepne se na ON; ve verzi 10.4 je v záložce
  **WORLD**).
- **Na telefonu:** po startu klepni vpravo nahoře na **🛠 ADMIN** a pak na **PERFORMANCE**.

Malé okno se objeví nahoře uprostřed. Zůstane tam, i když admin panel zavřeš, a klepnutí jím projdou do hry. Tlačítko
**✕** přehled vypne. Tlačítko **LITE** přepíná úsporný režim: telefon ho má zapnutý sám, na počítači si ho můžeš
vyzkoušet.

## Krok 3: test na telefonu

1. Telefon nabij (ne úsporný režim baterie), připoj na Wi-Fi a zavři ostatní aplikace.
2. Otevři **veřejnou hru** v aplikaci Roblox. Poznamenej si kvalitu grafiky v nastavení Roblox (nejlépe nech
   „Automaticky“).
3. Spusť hru a zapni přehled (krok 2).
4. Udělej screenshot na každém z těchto míst. Na každém nejdřív počkej asi 10 sekund, ať se čísla ustálí:
   1. v lobby na náměstí;
   2. ve svém skladu mezi plnými stojany;
   3. v domě při běhu (nejlépe velký dům, The Old Farmstead);
   4. v běhu na **Hard** nebo těžší, když jsou kolem zombie;
   5. na jednom místě dvakrát: s **LITE · ON** a s **LITE · OFF**.
5. **Pošli mi:**
   - ty screenshoty;
   - model telefonu;
   - kvalitu grafiky v nastavení Roblox;
   - jestli to bylo plynulé, nebo se to sekalo (a kde).

Ve Studiu ukazuje přehled čísla tvého počítače. Opravdová čísla jsou jen z telefonu. Emulátor zařízení ve Studiu (Test
→ Device) se hodí jen na kontrolu rozložení tlačítek.

## Co čísla znamenají

| Řádek | Dobré | Špatné | Co to je |
|---|---|---|---|
| **FPS** | 55–60 výborné, 40–55 dobré | pod 30 | snímky za sekundu (posledních 0,5 s) |
| **worst 5 s** | nad 30 | pod 20 = záseky | nejhorší snímek za posledních 5 s, převedený na FPS |
| **CPU / GPU ms** | pod 16 ms (60 FPS), pod 33 ms (30 FPS) | nad 33 ms | ms na snímek; viz poznámka pod tabulkou |
| **draws** | pod ~1 500 | nad ~3 000 | kolik věcí grafika kreslí zvlášť |
| **MEMORY** | pod ~900 MB | nad ~1 400 MB (slabší telefon může spadnout) | paměť hry v telefonu; v závorce Lua (skripty) |
| **PING** | pod 100 ms | nad 250 ms | odezva serveru; je to síť, ne telefon |
| **PARTS** | | | díly, které telefon právě drží (se streamováním jen okolí) |
| **SHADOWS** | čím méně, tím lépe | | díly kolem tebe, které vrhají stín |
| **LIGHTS on / all** | | | kolik světel právě svítí (lampy ve skladu, v domě, v dodávce) |
| **STREAMING** | ON | OFF (červeně): udělej krok 1 | jestli je streamování zapnuté |
| **PHONE · LITE** | na telefonu LITE | | úsporný režim zařízení |
| **QUALITY** | | | kvalita grafiky v nastavení Roblox (AUTO = volí Roblox) |
| **v…** | nejnovější verze | starší = telefon nemá novou verzi | verze hry |

**CPU, nebo GPU?** Vyšší z těch dvou čísel je brzda:
- **GPU** = grafika: stíny, světla, počet dílů na obrazovce.
- **CPU** = skripty a fyzika.

Podle toho se rozhodne další krok, proto prosím pošli screenshot s oběma čísly.
