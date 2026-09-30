#!/bin/sh
# Test multijoueur réel : un hôte et un client (ENet sur 127.0.0.1).
# Usage : sh tools/mp_test.sh <nom>   (lance mp_<nom>_host et mp_<nom>_client)
# Par défaut SANS RENDU (--headless : aucune fenêtre, rapide) ; GUI=1 pour
# les voir (fenêtres réduites puis hors écran, captures possibles).
# AUTOTEST_PORT_OFFSET décale les ports (plusieurs tests en parallèle).
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT"
N=${1:-lobby}
if [ "$GUI" = "1" ]; then
  . tools/nofocus.sh
  nofocus_on
  MODE="--resolution 960x540"
else
  # Temps de jeu simulé (--fixed-fps) : voir docs/TESTING.md. MP_MODE pour
  # forcer un autre mode (ex. temps réel : "--headless --max-fps 60").
  MODE=${MP_MODE:-"--headless --fixed-fps 60"}
  # « ## @temps-reel » dans le script hôte : ce test mesure ou limite quelque
  # chose par seconde RÉELLE (débit, transfert cadencé…), il reste en temps réel.
  if [ -z "$MP_MODE" ] && grep -q "^## @temps-reel" "tests/autotest/mp_${N}_host.gd"; then
    MODE="--headless --max-fps 60"
  fi
fi
AUTOTEST_PARALLEL=1 "$GODOT" $MODE --path . -- --autotest=mp_${N}_host > "$OUT/mp_${N}_host.log" 2>&1 &
H=$!
sleep 1
AUTOTEST_PARALLEL=1 "$GODOT" $MODE --path . -- --autotest=mp_${N}_client > "$OUT/mp_${N}_client.log" 2>&1 &
C=$!
wait $H; RH=$?
wait $C; RC=$?
for R in host client; do
  echo "== $N ($R)"
  grep -E "\[autotest\] (OK|ECHEC|fin)|SCRIPT ERROR|ERROR:" "$OUT/mp_${N}_$R.log"
done
[ $RH -eq 0 ] && [ $RC -eq 0 ] && ! grep -qE "SCRIPT ERROR|ERROR:" "$OUT/mp_${N}_host.log" "$OUT/mp_${N}_client.log"
