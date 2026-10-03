#!/bin/bash
# Dvojklik na tento soubor (Mac): stáhne nejnovější verzi z GitHubu a spustí synchronizaci hry Zombie Delivery do Studia.
# Ve Studiu otevři NOVÝ prázdný place (Baseplate), pak Rojo → Connect → Play. Okno nech běžet.
cd "$(dirname "$0")/.." || exit 1
echo "== Stahuji nejnovější verzi z GitHubu =="
git pull || { echo; echo "git pull selhal, pošli tenhle výpis Claudovi."; read -r -p "Enter zavře okno"; exit 1; }
echo
echo "== Spouštím synchronizaci Zombie Delivery do Roblox Studia (nech toto okno otevřené) =="
node tools/rojo-sync.js zombie-delivery
