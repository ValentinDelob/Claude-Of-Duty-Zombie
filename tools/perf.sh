#!/bin/sh
# Mesures de performance fiables : un seul jeu à la fois, en 1920x1080.
# Référence : sur la GTX 1070 de développement (~3,5x une GTX 1050), ~210 fps
# en 1080p correspondent à ~60 fps sur une GTX 1050 (cible du projet).
# Coût de chaque poste de rendu (A/B) : sh tools/perf.sh perf_costs
# Usage : sh tools/perf.sh [scénarios...]
#         QUALITY=low sh tools/perf.sh      (préréglage graphique imposé :
#                                            low / medium / high, voir RenderQuality)
#         OUTLINE=off sh tools/perf.sh      (contour noir coupé : mesure avant / après)
cd "$(dirname "$0")/.."
. tools/nofocus.sh
nofocus_on
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT"
# Journaux Godot : tests/_out/logs, jamais ceux du joueur (voir check.sh).
LOGS="$PWD/$OUT/logs"; mkdir -p "$LOGS"
FAIL=0
SCENARIOS=${*:-"boot fps_controller zombie_entity map_tour startup_smoothness"}
QARG=""
[ -n "$QUALITY" ] && QARG="--quality=$QUALITY"
[ -n "$OUTLINE" ] && QARG="$QARG --outline=$OUTLINE"
# PERF_ARGS="--only=contour" : arguments de scénario en plus (ex. perf_costs ciblé).
[ -n "$PERF_ARGS" ] && QARG="$QARG $PERF_ARGS"
for S in $SCENARIOS; do
  "$GODOT" --log-file "$LOGS/perf_$S.log" --path . --resolution 1920x1080 -- --autotest=$S $QARG > "$OUT/perf_$S.log" 2>&1 || FAIL=1
  echo "== $S${QUALITY:+ ($QUALITY)}${OUTLINE:+ (contour $OUTLINE)}"
  grep -E "\[perf\]|\[cost\]|perf .*fps|ECHEC" "$OUT/perf_$S.log"
done
[ $FAIL -eq 0 ] && echo "== PERF OK" || echo "== PERF ECHEC"
exit $FAIL
