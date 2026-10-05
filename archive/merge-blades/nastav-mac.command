#!/bin/bash
# Jednorázové nastavení na Macu (dvojklik): zkontroluje Git a Node, nainstaluje Rojo plugin do Roblox Studia,
# stáhne nejnovější verzi hry z GitHubu a spustí synchronizaci do Studia. Potom už stačí
# "aktualizuj-a-spust.command".
cd "$(dirname "$0")" || exit 1
ROJO_VERSION="7.7.0"
PLUGINS_DIR="$HOME/Documents/Roblox/Plugins"

echo "================ MERGE BLADES — nastavení Macu ================"
echo

# 1) Git (na Macu je součástí Xcode Command Line Tools; bez nich se nabídne instalace)
if ! xcode-select -p >/dev/null 2>&1; then
	echo "1) Git chybí. Mac teď nabídne instalaci nástrojů příkazové řádky: klikni na Instalovat,"
	echo "   počkej, až doběhne, a pak na tento soubor klikni znovu."
	xcode-select --install
	read -r -p "Enter zavře okno"
	exit 1
fi
echo "1) Git: $(git --version)"

# 2) Node.js (synchronizace do Studia běží v Node)
if ! command -v node >/dev/null 2>&1; then
	echo "2) Node.js chybí. Stahuji instalátor..."
	PKG=$(curl -s https://nodejs.org/dist/latest-v22.x/ | grep -o 'node-v[0-9.]*\.pkg' | head -1)
	if [ -z "$PKG" ]; then
		echo "   Stažení se nepovedlo. Nainstaluj Node.js ručně z https://nodejs.org (tlačítko LTS) a klikni na tento soubor znovu."
		read -r -p "Enter zavře okno"
		exit 1
	fi
	curl -L -o "/tmp/$PKG" "https://nodejs.org/dist/latest-v22.x/$PKG"
	echo "   Otevírám instalátor: proklikej ho (Pokračovat → Instalovat), pak na tento soubor klikni znovu."
	open "/tmp/$PKG"
	read -r -p "Enter zavře okno"
	exit 1
fi
echo "2) Node.js: $(node -v)"

# 3) Rojo plugin do Roblox Studia (složka lokálních pluginů na Macu)
mkdir -p "$PLUGINS_DIR"
if [ ! -f "$PLUGINS_DIR/Rojo.rbxm" ]; then
	echo "3) Stahuji Rojo plugin $ROJO_VERSION do Roblox Studia..."
	if curl -L -f -o "$PLUGINS_DIR/Rojo.rbxm" "https://github.com/rojo-rbx/rojo/releases/download/v$ROJO_VERSION/Rojo.rbxm"; then
		echo "   Plugin je v $PLUGINS_DIR (ve Studiu se objeví v záložce Plugins po restartu Studia)."
	else
		echo "   Stažení pluginu se nepovedlo (není internet?). Ve Studiu ho jde nainstalovat i z Toolboxu: hledej 'Rojo'."
		rm -f "$PLUGINS_DIR/Rojo.rbxm"
	fi
else
	echo "3) Rojo plugin už je nainstalovaný ($PLUGINS_DIR/Rojo.rbxm)."
fi

# 4) Git: jméno pro commity (jen když chybí) a správná větev
if [ -z "$(git config user.name)" ]; then
	git config --global user.name "malissVisual"
	git config --global user.email "malispavel2@gmail.com"
	echo "4) Git jméno nastaveno."
fi
BRANCH="claude/cloud-credits-run-vpxjbl"
echo "4) Stahuji nejnovější verzi hry (větev $BRANCH)..."
git fetch origin "$BRANCH" 2>&1 | tail -1
git checkout -q "$BRANCH" 2>/dev/null || git checkout -q -b "$BRANCH" "origin/$BRANCH"
git pull -q origin "$BRANCH" || { echo "   git pull selhal, pošli tenhle výpis Claudovi."; read -r -p "Enter zavře okno"; exit 1; }
echo "   Hotovo: $(git log -1 --format='%h %s' | cut -c1-80)"

# 5) Synchronizace do Studia
echo
echo "5) Spouštím synchronizaci do Roblox Studia. NECH TOTO OKNO OTEVŘENÉ."
echo "   Ve Studiu: otevři libovolné místo (Baseplate), záložka Plugins → Rojo → Connect (localhost:34872), pak Play."
echo "   Když Studio neukáže Rojo, restartuj ho (plugin se načítá při startu)."
echo "   Příště stačí dvojklik na aktualizuj-a-spust.command."
echo
node tools/rojo-sync.js
