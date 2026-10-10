# Světlo a atmosféra: návod pro majitele (6.16)

Verze 6.16 mění vzhled hry podle denní doby:
- **Ráno za šera** je modré a chladné, **východ a západ slunce** zlatý a teplý (sluneční paprsky, prach ve světle),
  **poledne** čisté a ostré, **soumrak** fialovomodrý a **noc** modrá, tmavá, ale pořád čitelná: zombie je vidět vždycky.
- **Obloha:** menší a ostřejší slunce, větší měsíc, nejvíc hvězd a pohyblivé mraky. V dešti mraky zhoustnou, při západu
  slunce zezlátnou, při Krvavém měsíci zčervenají.
- **Světla v noci:** lampy, okna a světlomety jemně září (bloom). Kolem nejbližších pouličních lamp je slabý opar.
- **Jemné rozmazání v dálce:** jen velmi daleko. Při míření, na telefonu a při nízké kvalitě grafiky je vypnuté.
- **Prach ve vzduchu:** pár drobných zrnek kolem kamery, hlavně ve zlatém světle. V noci, v dešti, v mlze, ve sněhu a se
  zapnutým Reduced Motion se neukazuje.

Všechno to dělají skripty na každém počítači a telefonu zvlášť. Rojo (`node tools/rojo-sync.js zombie-delivery`) ale
synchronizuje jen skripty. Pár věcí jde nastavit jen ve Studiu, a to popisuje tento návod.

## Krok 1: zapněte osvětlení Future (jednou, ve Studiu)

S osvětlením **Future** vrhají lampy a světlomety skutečné světlo a stíny a noc vypadá mnohem lépe. Skript tuhle
vlastnost nastavit nemůže.

1. Ve Studiu otevřete místo (place) Zombie Delivery, které publikujete.
2. V okně **Explorer** klikněte na **Lighting**.
3. V okně **Properties** nastavte:

   | Vlastnost | Hodnota | Proč |
   |---|---|---|
   | Technology | **Future** | skutečná světla lamp a světlometů, hezčí noc |
   | LightingStyle (pokud tam je) | **Realistic** | ostřejší stíny a hloubka |
   | PrioritizeLightingQuality (pokud tam je) | ✔ (zaškrtnuto) | světla vypadají dobře i při nižší kvalitě grafiky |

4. Ostatní hodnoty v **Lighting** (Ambient, OutdoorAmbient, Brightness, ColorShift, EnvironmentDiffuseScale,
   EnvironmentSpecularScale, ShadowSoftness, ExposureCompensation, GlobalShadows) **neměňte**. Nastavují je skripty podle
   denní doby a vaše hodnota by se po spuštění hry stejně přepsala.

## Krok 2: vypněte efekty navíc v Lighting

Skripty si vytvářejí vlastní efekty. Pokud místo vzniklo ze šablony, můžou v **Lighting** být ještě další a obraz by se
pak upravoval dvakrát (příliš jasný, rozmazaný nebo přebarvený).

1. V **Exploreru** rozbalte **Lighting** (šipka vlevo).
2. Tyto položky **nechte**: `Sky`, `Atmosphere`, `ZombieGrade`. Skripty je používají.
3. Pokud tam vidíte jiný **Bloom**, **DepthOfField**, **SunRays**, **ColorCorrection** nebo **Blur** (bez slova
   Zombie nebo Night v názvu), klikněte na něj a v **Properties** zrušte zaškrtnutí **Enabled**.
4. Za běhu hry se v Lighting objeví i `NightBloom`, `ZombieSunRays` a `ZombieFarBlur`. Ty patří ke hře a jsou v pořádku.

## Krok 3: uložte a publikujte

**File → Publish to Roblox.**

## Krok 4: vyzkoušejte všechny denní doby

1. Ve Studiu stiskněte **Play**.
2. Stiskněte **P** (na telefonu **🛠 ADMIN**) a otevřete záložku **WORLD**.
3. V části **Time of day** postupně klikněte na tlačítka a dívejte se na město. Co má být vidět:

   | Tlačítko | Co hledat |
   |---|---|
   | 05:30 Dawn | chladné modré šero, lampy ještě svítí |
   | 06:30 Sunrise | zlaté nízké slunce, paprsky, teplý opar, prach ve světle |
   | 08:30 Morning | svěží, jasné ráno |
   | 12:30 Noon | čisté barvy, ostré stíny, nejmíň oparu |
   | 16:12 Afternoon | barvy se pomalu oteplují |
   | 17:42 Sunset | nejteplejší, oranžový opar, záře slunce, paprsky |
   | 18:54 Dusk | fialovomodrý soumrak, rozsvěcují se lampy |
   | 20:18 Night a 00:00 Midnight | modrá noc: lampy, okna a světlomety září, kolem lamp je slabý opar, zombie je vidět |

4. V řádku **Weather (whole server)** zkuste **RAIN** a **FOG**. Obloha zešedne, mraky zhoustnou, stíny změknou a prach
   zmizí. **CLEAR** vrátí jasno.
5. V záložce **EVENTS** spusťte **Blood Moon**. Obloha, mlha, mraky a měsíční světlo zčervenají a noc musí zůstat
   čitelná.
6. Zamiřte zbraní (pravé tlačítko myši). Jemné rozmazání v dálce na chvíli zmizí.

## Krok 5: kvalita grafiky a telefon

1. Ve hře stiskněte **Esc → Settings** a nastavte **Graphics Mode** na **Manual**. Pak posouvejte **Graphics Quality**:
   - na **plné kvalitě** je vidět všechno;
   - na **nejnižších stupních** zmizí paprsky, mlha nad řekou a rozmazání v dálce a prachu je méně.
2. Telefon si můžete vyzkoušet na počítači dvěma způsoby:
   - ve Studiu v **Test → Device** vyberte telefon;
   - nebo v **P → WORLD → PERFORMANCE** zapněte přehled výkonu a přepněte **LITE**.

   V režimu LITE není rozmazání v dálce ani opar kolem lamp a prachu je méně.
3. Pokud na skutečném telefonu FPS v přehledu výkonu klesne (pod 30), zkuste **Technology = ShadowMap** (návod
   `design/performance/NAVOD.md`, krok 1). Případně v `src/shared/Config.luau` u `Config.Atmosphere.Clouds` nastavte
   `Lite = false`: telefony pak nebudou mít mraky.

## Volitelně: vlastní obloha

Hra používá vestavěnou oblohu Robloxu, nic se nenahrává. Pokud chcete vlastní obrázky oblohy, vložte jejich čísla
(`rbxassetid://…`) do `Config.Atmosphere.Sky` v `src/shared/Config.luau`:
- **Skybox:** všech šest stran (`Bk`, `Dn`, `Ft`, `Lf`, `Rt`, `Up`). Když jedna chybí, zůstane vestavěná obloha.
- **Sun** a **Moon:** obrázek slunce a měsíce.

Prázdné uvozovky `""` znamenají vestavěnou oblohu. Tam lze nastavit i velikost slunce (`SunSize`), měsíce (`MoonSize`)
a počet hvězd (`Stars`, nejvýš 5000).

## Ladění barev

Barvy každé denní doby jsou v `Config.Atmosphere.Looks` (`src/shared/Config.luau`). Nad každou je popis, co která
hodnota dělá. Test `tests/skygrade_test.luau` hlídá, aby noc nikdy nebyla tak tmavá, že by zombie nebyla vidět. Pokud
hodnoty změníte a test spadne, noc je moc tmavá.
