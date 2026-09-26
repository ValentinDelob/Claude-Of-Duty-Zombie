#!/bin/sh
# Livraison complète d'une fonctionnalité :
#   1. tools/commit.sh (check complet puis commit),
#   2. push sur origin/main,
#   3. tools/release.sh (build .exe local + release GitHub).
# Usage : sh tools/ship.sh fichier_message.txt
cd "$(dirname "$0")/.."
sh tools/commit.sh "$1" || exit 1
git push -q origin HEAD:main || { echo "== PUSH ECHEC"; exit 1; }
sh tools/release.sh
