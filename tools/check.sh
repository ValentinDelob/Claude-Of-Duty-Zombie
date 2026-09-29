#!/bin/bash
# Vérification avant commit (doit passer avant chaque commit / release).
#
#   1. import du projet (enregistre les class_name)
#   2. puis, dans un POOL de tâches parallèles (les plus longues d'abord,
#      d'après les durées mémorisées dans tests/_out/durations.txt) :
#        - compilation de tous les scripts, tests unitaires, test réseau ;
#        - chaque scénario d'autotest SANS RENDU (--headless : aucune fenêtre) ;
#        - les scénarios marqués « ## @rendu » AVEC rendu, dans une fenêtre
#          réduite puis déplacée hors des écrans (jamais visible) ;
#        - chaque test multijoueur (hôte + client, sans rendu, ports distincts).
#
# Usage : sh tools/check.sh [--fast]           --fast : sans réseau ni multijoueur
#   SCENARIOS="boot perks" sh tools/check.sh   uniquement ces scénarios (et pas de mp)
#   MP="lobby zombies" sh tools/check.sh       uniquement ces tests multijoueur
#   JOBS=6 sh tools/check.sh                   nombre de tâches simultanées
#   GUI_JOBS=1 sh tools/check.sh               fenêtres de rendu simultanées (déf. 2)
#   AUTOTEST_PORT_OFFSET=500                   décalage des ports (copies parallèles)
cd "$(dirname "$0")/.."
. tools/nofocus.sh
nofocus_on
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT/jobs"
DUR="$OUT/durations.txt"; touch "$DUR"
FAST=0
[ "$1" = "--fast" ] && FAST=1
NPROC=$(nproc 2>/dev/null || echo 4)
JOBS=${JOBS:-${PARALLEL:-$(( NPROC / 2 > 12 ? 12 : (NPROC / 2 < 2 ? 2 : NPROC / 2) ))}}
GUI_JOBS=${GUI_JOBS:-2}
BASE_PORT=${AUTOTEST_PORT_OFFSET:-0}
# Images/s plafonnées : la physique tourne à 60 Hz, inutile de brûler du CPU.
HEADLESS="--headless --max-fps 60"
T_START=$(date +%s)

echo "== import"
"$GODOT" --headless --path . --import > "$OUT/import.log" 2>&1
# Lanceur (projet Godot séparé, launcher/).
"$GODOT" --headless --path launcher --import >> "$OUT/import.log" 2>&1
if grep -qE "SCRIPT ERROR|Parse Error|ERROR:" "$OUT/import.log"; then
  grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$OUT/import.log" | head
  echo "== CHECK ECHEC (import)"; exit 1
fi

# ------------------------------------------------------------ liste des tâches
# Une tâche = « type:nom ». Types : parse, unit, launcher, net, head, gui, mp.
TASKS=()
TASKS+=("parse:scripts" "unit:tests" "launcher:tests")
[ $FAST -eq 0 ] && [ -z "$SCENARIOS" ] && TASKS+=("net:smoke")
ALL=$(ls tests/autotest/*.gd | xargs -n1 basename | sed 's/\.gd$//' | grep -vE '^(scenario|helpers|mp_.*|long_.*|perf_.*)$')
for S in ${SCENARIOS:-$ALL}; do
  KIND=head
  grep -q "^## @rendu" "tests/autotest/$S.gd" 2>/dev/null && KIND=gui
  # « ## @parts N » : scénario découpé en N parties lancées en parallèle.
  NP=$(grep -m1 -oE '^## @parts [0-9]+' "tests/autotest/$S.gd" 2>/dev/null | grep -oE '[0-9]+$')
  if [ -n "$NP" ] && [ "$NP" -gt 1 ]; then
    for K in $(seq 0 $((NP - 1))); do TASKS+=("$KIND:$S+$K+$NP"); done
  else
    TASKS+=("$KIND:$S")
  fi
done
if [ $FAST -eq 0 ] && { [ -z "$SCENARIOS" ] || [ -n "$MP" ]; }; then
  MPALL=$(ls tests/autotest/mp_*_host.gd 2>/dev/null | xargs -n1 basename | sed 's/^mp_//; s/_host\.gd$//')
  for N in ${MP:-$MPALL}; do TASKS+=("mp:$N"); done
fi

# Les plus longues d'abord (durée mémorisée, 30 s par défaut).
duration_of() { awk -v k="$1" '$1 == k { d = $2 } END { print (d == "" ? 30 : d) }' "$DUR"; }
ORDERED=$(for T in "${TASKS[@]}"; do echo "$(duration_of "$T") $T"; done | sort -rn | awk '{print $2}')

# ------------------------------------------------------------ exécution d'une tâche
run_task() {
  local T=$1 KIND=${1%%:*} NAME=${1#*:} SLOT=$2 LOG="$OUT/jobs/${1/:/_}.log" RC=0
  local PORTS=$(( BASE_PORT + 100 * SLOT ))
  local SCN=${NAME%%+*} PARTARG=""
  if [[ $NAME == *+* ]]; then local R=${NAME#*+}; PARTARG="--part=${R%+*}/${R#*+}"; fi
  case $KIND in
    parse) "$GODOT" --headless --path . -s res://tests/parse_all.gd > "$LOG" 2>&1 || RC=1 ;;
    unit)  "$GODOT" --headless --path . res://tests/test_runner.tscn > "$LOG" 2>&1 || RC=1 ;;
    launcher) "$GODOT" --headless --path launcher -s res://tests/test_launcher.gd > "$LOG" 2>&1 || RC=1 ;;
    net)   AUTOTEST_PORT_OFFSET=$PORTS sh tools/net_smoke.sh > "$LOG" 2>&1 || RC=1 ;;
    head)  AUTOTEST_PARALLEL=1 timeout 420 "$GODOT" $HEADLESS --path . -- --autotest=$SCN $PARTARG > "$LOG" 2>&1 || RC=1 ;;
    gui)   AUTOTEST_PARALLEL=1 timeout 420 "$GODOT" --path . --resolution 1280x720 -- --autotest=$SCN $PARTARG > "$LOG" 2>&1 || RC=1 ;;
    mp)    AUTOTEST_PORT_OFFSET=$PORTS HEADLESS_MP=1 sh tools/mp_test.sh "$NAME" > "$LOG" 2>&1 || RC=1 ;;
  esac
  if grep -qE "SCRIPT ERROR|ERROR:|\[FAIL\]|ECHEC" "$LOG"; then RC=1; fi
  exit $RC
}

# ------------------------------------------------------------ pool
declare -A PID_TASK PID_T0 PID_SLOT
FREE=($(seq 1 $JOBS))       # numéros de place libres (servent aux ports)
PENDING=($ORDERED)
GUI_RUNNING=0
FAILED=()
DONE=0
TOTAL=${#PENDING[@]}
NEWDUR="$OUT/durations.new"; cp "$DUR" "$NEWDUR"

record() {  # $1 = tâche, $2 = durée (s)
  awk -v k="$1" '$1 != k' "$NEWDUR" > "$NEWDUR.tmp"; echo "$1 $2" >> "$NEWDUR.tmp"; mv "$NEWDUR.tmp" "$NEWDUR"
}

# Lance la première tâche en attente autorisée (fenêtres limitées à GUI_JOBS).
start_next() {
  local i T SLOT
  for i in "${!PENDING[@]}"; do
    T=${PENDING[$i]}
    if [[ $T == gui:* ]] && [ $GUI_RUNNING -ge $GUI_JOBS ]; then continue; fi
    SLOT=${FREE[0]}; FREE=("${FREE[@]:1}")
    ( run_task "$T" "$SLOT" ) &
    PID_TASK[$!]=$T; PID_T0[$!]=$(date +%s); PID_SLOT[$!]=$SLOT
    [[ $T == gui:* ]] && GUI_RUNNING=$((GUI_RUNNING + 1))
    unset "PENDING[$i]"; PENDING=("${PENDING[@]}")
    return 0
  done
  return 1
}

while [ ${#PENDING[@]} -gt 0 ] || [ ${#PID_TASK[@]} -gt 0 ]; do
  while [ ${#FREE[@]} -gt 0 ] && [ ${#PENDING[@]} -gt 0 ] && start_next; do :; done
  wait -n -p DONE_PID; RC=$?
  T=${PID_TASK[$DONE_PID]}
  D=$(( $(date +%s) - ${PID_T0[$DONE_PID]} ))
  FREE+=(${PID_SLOT[$DONE_PID]})
  [[ $T == gui:* ]] && GUI_RUNNING=$((GUI_RUNNING - 1))
  unset "PID_TASK[$DONE_PID]" "PID_T0[$DONE_PID]" "PID_SLOT[$DONE_PID]"
  DONE=$((DONE + 1))
  record "$T" "$D"
  if [ $RC -eq 0 ]; then
    printf "[%2d/%d] ok     %-28s %4ds\n" $DONE $TOTAL "$T" $D
  else
    printf "[%2d/%d] ECHEC  %-28s %4ds\n" $DONE $TOTAL "$T" $D
    FAILED+=("$T")
  fi
done
mv "$NEWDUR" "$DUR"

# ------------------------------------------------------------ bilan
grep -h "PARSE:" "$OUT/jobs/parse_scripts.log" 2>/dev/null
grep -h "TESTS:" "$OUT/jobs/unit_tests.log" 2>/dev/null
for T in "${FAILED[@]}"; do
  echo "---- $T (tests/_out/jobs/${T/:/_}.log)"
  grep -hE "\[autotest\] ECHEC|\[FAIL\]|^\s+- |SCRIPT ERROR|ERROR:|ECHEC|délai" "$OUT/jobs/${T/:/_}.log" | head -12
done
echo "== durée totale : $(( $(date +%s) - T_START )) s ($JOBS tâches simultanées)"
if [ ${#FAILED[@]} -eq 0 ]; then echo "== CHECK OK"; exit 0; fi
echo "== CHECK ECHEC (${#FAILED[@]} tâche(s))"
exit 1
