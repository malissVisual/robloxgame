#!/bin/bash
# Spustí aktivní hru Zombie Delivery; aktualizace Gitu se provádí samostatně.
set -e
cd "$(dirname "$0")"
exec node tools/rojo-sync.js
