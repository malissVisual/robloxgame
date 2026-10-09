# Jak nahrát obrázky prací do hry

Ve hře je teď v seznamu prací (v telefonu v aplikaci JOBS a na velké tabuli pod klávesou J) u každé práce úzký
proužek se jménem podniku, například **🍕 LUIGI'S PIZZA**. Až nahraješ obrázky, objeví se místo proužku obrázek
podniku. Stačí to udělat jednou.

Potřebuješ: Roblox Studio a hru otevřenou v něm. Hra musí být uložená na Robloxu (**File → Publish to Roblox**),
jinak nahrávání nejde.

## 1. Nahraj obrázky

1. V Roblox Studiu klikni nahoře na **View** a potom na **Asset Manager**. Otevře se okno se soubory hry.
2. V okně Asset Manager klikni na tlačítko **Bulk Import** (nahrát víc souborů najednou).
3. Otevře se okno pro výběr souborů. Najdi složku s obrázky:
   - **Windows:** `C:\Users\malis\Documents\robloxgame\zombie-delivery\art\job-thumbnails`
   - **Mac:** `~/Documents/robloxgame/zombie-delivery/art/job-thumbnails`
     (na Macu v okně zmáčkni **Cmd + Shift + G** a cestu tam vlož)
4. Vyber všech **25 obrázků** (soubory končící na `.png`). Nejrychleji: klikni na první obrázek a zmáčkni
   **Ctrl + A** (na Macu **Cmd + A**). Soubor `manifest.json` nevybírej, to není obrázek.
5. Klikni na **Open** (Otevřít) a počkej, až se nahrají. Roblox je chvíli kontroluje. Pak je uvidíš v Asset Manageru
   ve složce **Images**. Jmenují se stejně jako soubory, například `pizzeria`, `bakery`, `post`.

## 2. Zjisti čísla obrázků (snadná cesta)

Každý nahraný obrázek má své číslo, které vypadá takhle: `rbxassetid://123456789`. Tato čísla potřebuje Claude.

1. V Asset Manageru otevři složku **Images** a označ všech 25 nových obrázků: klikni na první, podrž **Shift** a klikni
   na poslední.
2. Klikni na ně pravým tlačítkem a vyber **Insert** (vložit). Nebo je přetáhni myší na nějaký díl ve hře. Obrázky se
   objeví ve hře (v okně Explorer pod Workspace).
3. Otevři příkazový řádek: nahoře **View → Command Bar**. Dole se objeví dlouhé políčko.
4. Do políčka vlož tento řádek a zmáčkni **Enter**:

   ```lua
   for _, d in workspace:GetDescendants() do if d:IsA("Decal") then print(d.Name, d.Texture) end end
   ```

5. Otevři okno **Output** (nahoře **View → Output**). Uvidíš 25 řádků, například:

   ```
   pizzeria rbxassetid://123456789
   bakery rbxassetid://234567890
   ```

6. Označ všechny tyto řádky myší, zkopíruj je (**Ctrl + C**, na Macu **Cmd + C**) a pošli je Claudovi.
7. Vložené obrázky zase smaž: zmáčkni **Ctrl + Z** (na Macu **Cmd + Z**), dokud nezmizí. Nebo je v okně Explorer
   označ a zmáčkni **Delete**. Na nahrané obrázky v Asset Manageru to nemá vliv, ty zůstanou.

Když jsou na začátku řádků místo jmen jen slova `Decal`, jména se ztratila. Pak to udělej druhou cestou níže.

## 3. Druhá cesta: po jednom

Když snadná cesta nejde, zkopíruj čísla po jednom:

1. V Asset Manageru ve složce **Images** klikni pravým tlačítkem na obrázek a vyber **Copy Asset ID**.
2. Do zprávy pro Clauda napiš jméno obrázku a za něj vlož číslo, například: `pizzeria 123456789`
3. Opakuj pro všech 25 obrázků. Každý obrázek na nový řádek.

## Co bude dál

Claude čísla doplní do hry (spustí `tools/job-thumbnails/fill-ids.py`) a řekne ti, kdyby nějaké chybělo. V další
verzi hry už v seznamu prací uvidíš obrázky podniků.

Seznam všech 25 obrázků a ke kterým pracím patří je v souboru `index.html` v této složce (otevři ho v prohlížeči).
