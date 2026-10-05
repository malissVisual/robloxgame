# Zombie Delivery

Aktivní hra tohoto repozitáře je **Zombie Delivery**. Zdrojové soubory, grafika a podrobný popis jsou v [zombie-delivery/README.md](zombie-delivery/README.md). Výchozí projekt Rojo nyní načítá tuto hru.

## Spuštění

Z kořene repozitáře:

```bash
node tools/rojo-sync.js zombie-delivery
```

Ve svém Roblox Studiu otevři prázdný Baseplate, připoj plugin Rojo 7.7.0 a spusť Play. Na Macu lze spustit `aktualizuj-a-spust.command`; tento spouštěč pouze zapíná synchronizaci. Aktualizaci z Gitu proveď samostatně po uložení vlastních změn.

Bez argumentu (`node tools/rojo-sync.js`) se také spustí Zombie Delivery přes výchozí projekt.

Pravidla spolupráce Codex / Claude jsou v [AGENTS.md](AGENTS.md) a [zombie-delivery/AGENTS.md](zombie-delivery/AGENTS.md); před prací si přečti [sdílenou tabuli COLLAB.md](zombie-delivery/COLLAB.md).

## Testy a sestavení

```bash
python3 zombie-delivery/tests/run_tests.py /workspace/.cloud-tools/luau-0.741/luau
/workspace/.cloud-tools/rojo-7.4.4/rojo build default.project.json -o build/ZombieDelivery.rbxlx
```

Cloudové prostředí ověřuje logiku, kompilaci a synchronizaci. Hraní, fyzika, vykreslování a ukládání do Roblox DataStore vyžadují Roblox Studio nebo Roblox server.

## Archiv

Slučovací hra **Merge Blades** je celá zachovaná v [archive/merge-blades](archive/merge-blades/README.md), včetně původního projektu, modelů, nástrojů a testů. Výchozí synchronizace ji nenačítá. Historické Mac spouštěče v archivu mohou přepínat větev nebo stahovat změny; pro archivní hru použij z kořene repozitáře:

```bash
node tools/rojo-sync.js archive/merge-blades
```
