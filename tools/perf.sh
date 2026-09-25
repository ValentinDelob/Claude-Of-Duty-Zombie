#!/bin/sh
# Mesures de performance fiables : un seul jeu à la fois, en 1920x1080.
# Référence : sur la RTX A2000 (portable) de développement, ~150 fps en 1080p
# correspondent à ~60 fps sur une GTX 1050 (cible du projet).
# Usage : sh tools/perf.sh [scénarios...]
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT"
FAIL=0
SCENARIOS=${*:-"boot fps_controller zombie_entity map_tour"}
for S in $SCENARIOS; do
  "$GODOT" --path . --windowed --resolution 1920x1080 -- --autotest=$S > "$OUT/perf_$S.log" 2>&1 || FAIL=1
  echo "== $S"
  grep -E "\[perf\]|perf .*fps|ECHEC" "$OUT/perf_$S.log"
done
[ $FAIL -eq 0 ] && echo "== PERF OK" || echo "== PERF ECHEC"
exit $FAIL
