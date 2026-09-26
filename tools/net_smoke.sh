#!/bin/sh
# Test réseau réel : 1 hôte (max 2 joueurs), 1 client accepté, 1 client refusé (plein).
# Chaque étape attend l'événement précédent dans les journaux (pas de délai fixe :
# le démarrage de Godot varie beaucoup d'une machine à l'autre).
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT"
PORT=$((17801 + ${AUTOTEST_PORT_OFFSET:-0}))
rm -f "$OUT/host.log" "$OUT/c1.log" "$OUT/c2.log"

# Attend (au plus 20 s) qu'un motif apparaisse dans un journal.
wait_for() {
  i=0
  while [ $i -lt 100 ]; do
    grep -q "$2" "$1" 2>/dev/null && return 0
    sleep 0.2
    i=$((i + 1))
  done
  echo "[smoke] délai dépassé en attendant « $2 » dans $1"
  return 1
}

"$GODOT" --headless --path . res://tests/net_smoke.tscn -- --role=host --port=$PORT --max=2 > "$OUT/host.log" 2>&1 &
H=$!
wait_for "$OUT/host.log" "\[smoke\] host en écoute"
"$GODOT" --headless --path . res://tests/net_smoke.tscn -- --role=client --port=$PORT --expect=ok > "$OUT/c1.log" 2>&1 &
C1=$!
wait_for "$OUT/c1.log" "\[smoke\] client accepté"
"$GODOT" --headless --path . res://tests/net_smoke.tscn -- --role=client --port=$PORT --expect=full > "$OUT/c2.log" 2>&1
R2=$?
# 3e client d'une autre release : refusé pour version différente.
AUTOTEST_FAKE_BUILD=9.9.99 "$GODOT" --headless --path . res://tests/net_smoke.tscn -- --role=client --port=$PORT --expect=version > "$OUT/c3.log" 2>&1
R3=$?
wait $C1; R1=$?
wait $H; RH=$?
grep -h "\[smoke\]\|ERROR" "$OUT/host.log" "$OUT/c1.log" "$OUT/c2.log" "$OUT/c3.log"
echo "host=$RH client1=$R1 client2=$R2 client3=$R3"
[ $RH -eq 0 ] && [ $R1 -eq 0 ] && [ $R2 -eq 0 ] && [ $R3 -eq 0 ]
