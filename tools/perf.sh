#!/bin/sh
# Mesures de performance fiables : un seul jeu à la fois, en 1920x1080.
# Référence : sur la GTX 1070 de développement (~3,5x une GTX 1050), ~210 fps
# en 1080p correspondent à ~60 fps sur une GTX 1050 (cible du projet).
# Coût de chaque poste de rendu (A/B) : sh tools/perf.sh perf_costs
# Usage : sh tools/perf.sh [scénarios...]
#         QUALITY=low sh tools/perf.sh      (préréglage graphique imposé :
#                                            low / medium / high, voir RenderQuality)
cd "$(dirname "$0")/.."
. tools/nofocus.sh
nofocus_on
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT"
FAIL=0
SCENARIOS=${*:-"boot fps_controller zombie_entity map_tour"}
QARG=""
[ -n "$QUALITY" ] && QARG="--quality=$QUALITY"
for S in $SCENARIOS; do
  "$GODOT" --path . --resolution 1920x1080 -- --autotest=$S $QARG > "$OUT/perf_$S.log" 2>&1 || FAIL=1
  echo "== $S${QUALITY:+ ($QUALITY)}"
  grep -E "\[perf\]|perf .*fps|ECHEC" "$OUT/perf_$S.log"
done
[ $FAIL -eq 0 ] && echo "== PERF OK" || echo "== PERF ECHEC"
exit $FAIL
