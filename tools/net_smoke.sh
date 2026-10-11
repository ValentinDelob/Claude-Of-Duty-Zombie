#!/bin/sh
# Test réseau réel : 1 hôte (max 2 joueurs), 1 client accepté, 1 client refusé
# (plein), 1 client d'une autre release (refusé).
# Chaque étape attend l'événement précédent dans les journaux (pas de délai fixe :
# le démarrage de Godot varie beaucoup d'une machine à l'autre, et plus encore
# pendant le check, où d'autres jeux tournent en même temps).
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT"
# Journaux Godot : tests/_out/logs, jamais ceux du joueur (voir check.sh).
LOGS="$PWD/$OUT/logs"; mkdir -p "$LOGS"
PORT=$((17801 + ${AUTOTEST_PORT_OFFSET:-0}))
# Signal de fin pour le client accepté : il reste connecté jusqu'à ce que ce
# fichier existe (créé quand les deux clients refusés ont fini).
RELEASE="$OUT/smoke_release_$PORT"
rm -f "$OUT/host.log" "$OUT/c1.log" "$OUT/c2.log" "$OUT/c3.log" "$RELEASE"

# Attend (au plus 60 s : garde-fou, l'attente s'arrête dès le motif vu) qu'un
# motif apparaisse dans un journal.
wait_for() {
  i=0
  while [ $i -lt 300 ]; do
    grep -q "$2" "$1" 2>/dev/null && return 0
    sleep 0.2
    i=$((i + 1))
  done
  echo "[smoke] délai dépassé en attendant « $2 » dans $1"
  return 1
}

"$GODOT" --headless --log-file "$LOGS/smoke_host_$PORT.log" --path . res://tests/net_smoke.tscn -- --role=host --port=$PORT --max=2 > "$OUT/host.log" 2>&1 &
H=$!
wait_for "$OUT/host.log" "\[smoke\] host en écoute"
"$GODOT" --headless --log-file "$LOGS/smoke_c1_$PORT.log" --path . res://tests/net_smoke.tscn -- --role=client --port=$PORT --expect=ok --release=res://$RELEASE > "$OUT/c1.log" 2>&1 &
C1=$!
wait_for "$OUT/c1.log" "\[smoke\] client accepté"
"$GODOT" --headless --log-file "$LOGS/smoke_c2_$PORT.log" --path . res://tests/net_smoke.tscn -- --role=client --port=$PORT --expect=full > "$OUT/c2.log" 2>&1
R2=$?
# 3e client d'une autre release : refusé pour version différente.
AUTOTEST_FAKE_BUILD=9.9.99 "$GODOT" --headless --log-file "$LOGS/smoke_c3_$PORT.log" --path . res://tests/net_smoke.tscn -- --role=client --port=$PORT --expect=version > "$OUT/c3.log" 2>&1
R3=$?
# Les clients refusés ont fini : le client accepté peut partir (l'hôte quitte
# alors à son tour, après avoir vérifié les deux refus).
touch "$RELEASE"
wait $C1; R1=$?
wait $H; RH=$?
rm -f "$RELEASE"
grep -h "\[smoke\]\|ERROR" "$OUT/host.log" "$OUT/c1.log" "$OUT/c2.log" "$OUT/c3.log"
echo "host=$RH client1=$R1 client2=$R2 client3=$R3"
[ $RH -eq 0 ] && [ $R1 -eq 0 ] && [ $R2 -eq 0 ] && [ $R3 -eq 0 ]
