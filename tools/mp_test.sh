#!/bin/sh
# Test multijoueur réel : un hôte et un client dans deux fenêtres.
# Usage : sh tools/mp_test.sh <nom>   (lance mp_<nom>_host et mp_<nom>_client)
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT"
N=${1:-lobby}
AUTOTEST_PARALLEL=1 "$GODOT" --path . --windowed --resolution 960x540 --position 0,40 -- --autotest=mp_${N}_host > "$OUT/mp_${N}_host.log" 2>&1 &
H=$!
sleep 1
AUTOTEST_PARALLEL=1 "$GODOT" --path . --windowed --resolution 960x540 --position 970,40 -- --autotest=mp_${N}_client > "$OUT/mp_${N}_client.log" 2>&1 &
C=$!
wait $H; RH=$?
wait $C; RC=$?
for R in host client; do
  echo "== $N ($R)"
  grep -E "\[autotest\] (OK|ECHEC|fin)|SCRIPT ERROR|ERROR:" "$OUT/mp_${N}_$R.log"
done
[ $RH -eq 0 ] && [ $RC -eq 0 ] && ! grep -qE "SCRIPT ERROR|ERROR:" "$OUT/mp_${N}_host.log" "$OUT/mp_${N}_client.log"
