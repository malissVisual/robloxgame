#!/bin/bash
# Spouštěč aktivní hry Zombie Delivery pro Mac.
set -e
cd "$(dirname "$0")"
if ! command -v node >/dev/null 2>&1; then
  echo "Nainstaluj Node.js LTS z https://nodejs.org a spusť tento soubor znovu."
  exit 1
fi
echo "Ve Studiu přidej plugin Rojo 7.7.0, otevři prázdný Baseplate a připoj synchronizaci."
exec node tools/rojo-sync.js
