# Výkon a mobily: návod pro majitele (6.13.1)

Hra je veřejná a hodně hráčů hraje na telefonu. Verze 6.13.1 je zrychlila:
- **Méně stínů.** Stín vrhají jen díly, u kterých ho je vidět: ve městě ~14 100 dílů místo ~18 200. Sloupy lamp,
  stříšky a palmy ho mají dál.
- **Méně světel.** V noci svítí jen nejbližší světla: 40 na počítači, 16 na telefonu. Ostatní lampy dál září, jen
  neosvětlují okolí. Světla se plynule rozsvěcují a zhasínají a obě světla auta svítí vždy spolu.
- **Zaparkované auto drží server.** Když nikdo nesedí za volantem, auto nespadne skrz zem, ani když jsi daleko.
- **Telefon šetří.** Animuje jen bližší postavy, auta a zvířata.
- **Méně textu v dálce.** Malé texty (čísla domů, cedule) se kreslí jen zblízka.
- **Přehled výkonu pro admina,** aby šel výkon změřit přímo na telefonu.

Podrobnosti pro Clauda jsou v [`REPORT.md`](REPORT.md).

## Krok 1: zapni streamování (jednou, ve Studiu)

Rojo (`node tools/rojo-sync.js zombie-delivery`) synchronizuje jen skripty. Nastavení Workspace je uložené přímo v
místě (place), proto se zapíná ve Studiu:

1. Ve Studiu otevři místo Zombie Delivery, které publikuješ.
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
- **Na počítači:** stiskni **P**, otevři záložku **WORLD** a klikni na **PERFORMANCE · OFF** (přepne se na ON).
- **Na telefonu:** po PLAY klepni vpravo nahoře na **🛠 ADMIN**, pak **WORLD** a **PERFORMANCE**.

Malé okno se objeví nahoře uprostřed. Zůstane tam, i když admin panel zavřeš, a klepnutí jím projdou do hry. Tlačítko
**✕** přehled vypne. Tlačítko **LITE** přepíná úsporný režim: telefon ho má zapnutý sám, na počítači si ho můžeš
vyzkoušet.

## Krok 3: test na telefonu

1. Telefon nabij (ne úsporný režim baterie), připoj na Wi-Fi a zavři ostatní aplikace.
2. Otevři **veřejnou hru** v aplikaci Roblox. Poznamenej si kvalitu grafiky v nastavení Roblox (nejlépe nech
   „Automaticky“).
3. Dej PLAY a zapni přehled (krok 2).
4. Udělej screenshot na každém z těchto míst. Na každém nejdřív počkej asi 10 sekund, ať se čísla ustálí:
   1. u depa (spawn), ve dne;
   2. za jízdy autem centrem města (Downtown, mezi věžemi);
   3. v noci v centru (admin panel → **WORLD** → **22:00 Night**);
   4. u parku a Lantern Garden;
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
| **PARTS** | se streamováním jen okolí (pár tisíc) | ~23 000 = streamování nejede | díly, které telefon právě drží |
| **SHADOWS** | čím méně, tím lépe | | díly kolem tebe, které vrhají stín |
| **LIGHTS on / all** | v noci na telefonu kolem 16 + pár stálých (interiéry) | desítky na telefonu | kolik světel právě svítí |
| **NIGHT LIGHTS** | do 16 na telefonu, do 40 na počítači | | noční světla z rozpočtu: svítí / známá |
| **STREAMING** | ON | OFF (červeně): udělej krok 1 | jestli je streamování zapnuté |
| **PHONE · LITE** | na telefonu LITE | | úsporný režim zařízení |
| **QUALITY** | | | kvalita grafiky v nastavení Roblox (AUTO = volí Roblox) |
| **v…** | 6.13.1 nebo novější | starší = telefon nemá novou verzi | verze hry |

**CPU, nebo GPU?** Vyšší z těch dvou čísel je brzda:
- **GPU** = grafika: stíny, světla, počet dílů na obrazovce.
- **CPU** = skripty a fyzika.

Podle toho se rozhodne další krok, proto prosím pošli screenshot s oběma čísly.
