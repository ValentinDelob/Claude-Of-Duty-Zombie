#!/bin/sh
# Vérification avant commit :
#   1. import / parse de tout le projet
#   2. tests unitaires
#   3. test réseau multi-processus
#   4. lancement réel du jeu (fenêtré) avec chaque scénario d'autotest
# Usage : sh tools/check.sh [--fast]      (--fast : saute le test réseau)
#         SCENARIOS="boot fps_controller" sh tools/check.sh
cd "$(dirname "$0")/.."
. tools/nofocus.sh
nofocus_on
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT"
FAIL=0
FAST=0
[ "$1" = "--fast" ] && FAST=1
# Tous les scénarios de tests/autotest/ (hors fichiers utilitaires).
ALL=$(ls tests/autotest/*.gd | xargs -n1 basename | sed 's/\.gd$//' | grep -vE '^(scenario|helpers|mp_.*|long_.*|perf_.*)$' | tr '\n' ' ')
SCENARIOS=${SCENARIOS:-$ALL}

echo "== import"
"$GODOT" --headless --path . --import > "$OUT/import.log" 2>&1
if grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$OUT/import.log"; then FAIL=1; fi

echo "== compilation des scripts"
"$GODOT" --headless --path . -s res://tests/parse_all.gd > "$OUT/parse.log" 2>&1 || { FAIL=1; grep -E "ERREUR|ERROR" "$OUT/parse.log"; }
grep "PARSE:" "$OUT/parse.log"

echo "== tests unitaires"
"$GODOT" --headless --path . res://tests/test_runner.tscn > "$OUT/unit.log" 2>&1 || FAIL=1
grep -E "\[FAIL\]|^\s+- |TESTS:|SCRIPT ERROR" "$OUT/unit.log"
if grep -qE "SCRIPT ERROR|ERROR:" "$OUT/unit.log"; then FAIL=1; grep -E "ERROR" "$OUT/unit.log" | head; fi

if [ $FAST -eq 0 ]; then
  echo "== test réseau"
  sh tools/net_smoke.sh > "$OUT/net.log" 2>&1 || { FAIL=1; cat "$OUT/net.log"; }
  tail -1 "$OUT/net.log"
fi

# Scénarios lancés par lots de PARALLEL fenêtres simultanées (les mesures de
# perf sont donc pessimistes : plusieurs jeux partagent le GPU).
PARALLEL=${PARALLEL:-3}
set -- $SCENARIOS
while [ $# -gt 0 ]; do
  PIDS=""
  BATCH=""
  i=0
  while [ $# -gt 0 ] && [ $i -lt $PARALLEL ]; do
    S=$1; shift
    AUTOTEST_PARALLEL=1 "$GODOT" --path . --windowed --resolution 1280x720 -- --autotest=$S > "$OUT/run_$S.log" 2>&1 &
    PIDS="$PIDS $!"
    BATCH="$BATCH $S"
    i=$((i + 1))
  done
  for P in $PIDS; do wait $P || { FAIL=1; echo "un scénario a échoué (pid $P)"; }; done
  for S in $BATCH; do
    echo "== scénario $S"
    grep -E "\[autotest\] (ECHEC|fin)|\[perf\]" "$OUT/run_$S.log"
    if grep -E "SCRIPT ERROR|ERROR:" "$OUT/run_$S.log"; then FAIL=1; fi
  done
done

# Tests multijoueur (paires hôte/client dans deux fenêtres).
if [ $FAST -eq 0 ]; then
  for H in tests/autotest/mp_*_host.gd; do
    [ -f "$H" ] || continue
    N=$(basename "$H" | sed 's/^mp_//; s/_host.gd$//')
    echo "== multijoueur $N"
    sh tools/mp_test.sh "$N" > "$OUT/mp_$N.log" 2>&1 || { FAIL=1; cat "$OUT/mp_$N.log"; }
    grep -E "fin :" "$OUT/mp_$N.log"
  done
fi

[ $FAIL -eq 0 ] && echo "== CHECK OK" || echo "== CHECK ECHEC"
exit $FAIL
