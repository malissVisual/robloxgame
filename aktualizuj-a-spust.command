#!/bin/bash
# Dvojklik na tento soubor (Mac): stáhne nejnovější verzi hry z GitHubu a spustí synchronizaci do Studia.
# Okno, které se otevře, nech běžet (je to ta synchronizace). Ve Studiu pak: Rojo → Disconnect → Connect → Play.
cd "$(dirname "$0")" || exit 1
echo "== Stahuji nejnovější verzi z GitHubu =="
git pull || { echo; echo "git pull selhal, pošli tenhle výpis Claudovi."; read -r -p "Enter zavře okno"; exit 1; }
echo
echo "== Spouštím synchronizaci do Roblox Studia (nech toto okno otevřené) =="
node tools/rojo-sync.js
