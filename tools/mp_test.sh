#!/bin/sh
# Test multijoueur réel : un hôte et un client (ENet sur 127.0.0.1).
# Usage : sh tools/mp_test.sh <nom>   (lance mp_<nom>_host et mp_<nom>_client)
# Par défaut SANS RENDU (--headless : aucune fenêtre, rapide) ; GUI=1 pour
# les voir (fenêtres réduites puis hors écran, captures possibles).
# AUTOTEST_PORT_OFFSET décale les ports (plusieurs tests en parallèle).
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT"
# Journaux Godot : tests/_out/logs, jamais ceux du joueur (voir check.sh).
LOGS="$PWD/$OUT/logs"; mkdir -p "$LOGS"
N=${1:-lobby}
if [ "$GUI" = "1" ]; then
  . tools/nofocus.sh
  nofocus_on
  MODE="--resolution 960x540"
else
  MODE="--headless --max-fps 60"
fi
AUTOTEST_PARALLEL=1 "$GODOT" $MODE --log-file "$LOGS/mp_${N}_host.log" --path . -- --autotest=mp_${N}_host > "$OUT/mp_${N}_host.log" 2>&1 &
H=$!
sleep 1
AUTOTEST_PARALLEL=1 "$GODOT" $MODE --log-file "$LOGS/mp_${N}_client.log" --path . -- --autotest=mp_${N}_client > "$OUT/mp_${N}_client.log" 2>&1 &
C=$!
wait $H; RH=$?
wait $C; RC=$?
for R in host client; do
  echo "== $N ($R)"
  grep -E "\[autotest\] (OK|ECHEC|fin)|SCRIPT ERROR|ERROR:" "$OUT/mp_${N}_$R.log"
done
[ $RH -eq 0 ] && [ $RC -eq 0 ] && ! grep -qE "SCRIPT ERROR|ERROR:" "$OUT/mp_${N}_host.log" "$OUT/mp_${N}_client.log"
