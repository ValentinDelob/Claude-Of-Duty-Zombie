#!/bin/sh
# Test réseau réel : 1 hôte (max 2 joueurs), 1 client accepté, 1 client refusé (plein).
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT"
"$GODOT" --headless --path . res://tests/net_smoke.tscn -- --role=host --port=17801 --max=2 > "$OUT/host.log" 2>&1 &
H=$!
sleep 1.5
"$GODOT" --headless --path . res://tests/net_smoke.tscn -- --role=client --port=17801 --expect=ok > "$OUT/c1.log" 2>&1 &
C1=$!
sleep 1.5
"$GODOT" --headless --path . res://tests/net_smoke.tscn -- --role=client --port=17801 --expect=full > "$OUT/c2.log" 2>&1
R2=$?
wait $C1; R1=$?
wait $H; RH=$?
grep -h "\[smoke\]\|ERROR" "$OUT/host.log" "$OUT/c1.log" "$OUT/c2.log"
echo "host=$RH client1=$R1 client2=$R2"
[ $RH -eq 0 ] && [ $R1 -eq 0 ] && [ $R2 -eq 0 ]
