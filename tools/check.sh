#!/bin/sh
# Vérification avant commit :
#   1. import / parse de tout le projet
#   2. tests unitaires
#   3. test réseau multi-processus
#   4. lancement réel du jeu (fenêtré) + scénario auto éventuel, recherche d'erreurs
# Usage : sh tools/check.sh [--fast]   (--fast : saute le test réseau)
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT"
FAIL=0

echo "== import"
"$GODOT" --headless --path . --import > "$OUT/import.log" 2>&1
if grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$OUT/import.log"; then FAIL=1; fi

echo "== tests unitaires"
"$GODOT" --headless --path . res://tests/test_runner.tscn > "$OUT/unit.log" 2>&1 || FAIL=1
grep -E "\[FAIL\]|^\s+- |TESTS:|SCRIPT ERROR" "$OUT/unit.log"

if [ "$1" != "--fast" ]; then
  echo "== test réseau"
  sh tools/net_smoke.sh > "$OUT/net.log" 2>&1 || { FAIL=1; cat "$OUT/net.log"; }
  tail -1 "$OUT/net.log"
fi

echo "== lancement du jeu"
"$GODOT" --path . --windowed --resolution 1280x720 -- --autotest=boot > "$OUT/run.log" 2>&1
RC=$?
grep -E "\[autotest\]|\[perf\]" "$OUT/run.log"
if grep -E "SCRIPT ERROR|ERROR:" "$OUT/run.log"; then FAIL=1; fi
[ $RC -ne 0 ] && { echo "code de sortie du jeu : $RC"; FAIL=1; }

[ $FAIL -eq 0 ] && echo "== CHECK OK" || echo "== CHECK ECHEC"
exit $FAIL
