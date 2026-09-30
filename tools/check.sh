#!/bin/bash
# Vérification avant commit / release. Stratégie complète : docs/TESTING.md.
#
#   1. import du projet (enregistre les class_name) ;
#   2. carte des dépendances et empreinte de chaque tâche (tools/test_deps.gd) ;
#   3. SÉLECTION : par défaut, seules les tâches dont l'empreinte (le test et
#      les fichiers dont il dépend) a changé depuis leur dernier succès sont
#      relancées (tests/_out/test_cache.txt) ; --full relance tout ;
#   4. POOL de tâches parallèles (les plus longues d'abord, d'après
#      tests/_out/durations.txt) :
#        - compilation de tous les scripts, tests unitaires (une seule instance,
#          uniquement les fichiers impactés), test réseau, tests du lanceur ;
#        - scénarios SANS RENDU : --headless --fixed-fps 60 (temps de jeu
#          simulé aussi vite que possible, voir scripts/autoload/game_clock.gd) ;
#        - scénarios « ## @rendu » AVEC rendu, en temps réel, fenêtre réduite
#          puis déplacée hors des écrans (jamais visible) ;
#        - tests multijoueur (hôte + client, sans rendu, ports distincts) ;
#   5. un échec est REJOUÉ une fois : s'il passe, il est signalé INSTABLE
#      (tests/_out/flaky.txt) sans bloquer ;
#   6. bilan lisible + rapport JUnit (tests/_out/junit.xml).
#
# Tests d'une carte précise (« ## @carte kino ») : lancés seulement quand un
# fichier de cette carte change, même avec --full (--kino pour les forcer).
# Hors check : scénarios long_*, perf_* et « ## @niveau perf » (tools/perf.sh).
#
# Usage : sh tools/check.sh [--full] [--fast] [--kino] [--no-retry]
#   --full     tout relancer (obligatoire avant une release : tools/ship.sh)
#   --fast     sans réseau ni multijoueur
#   SCENARIOS="boot perks" sh tools/check.sh   uniquement ces scénarios (sans cache, pas de mp)
#   MP="lobby zombies" sh tools/check.sh       uniquement ces tests multijoueur
#   JOBS=6 sh tools/check.sh                   nombre de tâches simultanées (déf. 3)
#   GUI_JOBS=2 sh tools/check.sh               fenêtres de rendu simultanées (déf. 1)
# Par défaut peu de jeux ouverts à la fois (3 tâches, 1 fenêtre) : la machine
# reste silencieuse.
#   AUTOTEST_PORT_OFFSET=500                   décalage des ports (copies parallèles)
cd "$(dirname "$0")/.."
. tools/nofocus.sh
nofocus_on
GODOT=${GODOT:-godot}
OUT=tests/_out; mkdir -p "$OUT/jobs"
DUR="$OUT/durations.txt"; touch "$DUR"
CACHE="$OUT/test_cache.txt"; touch "$CACHE"
FAST=0; FULL=0; KINO=0; RETRY=1
for A in "$@"; do
  case $A in
    --fast) FAST=1 ;;
    --full) FULL=1 ;;
    --kino) KINO=1 ;;
    --no-retry) RETRY=0 ;;
    *) echo "option inconnue : $A"; exit 2 ;;
  esac
done
JOBS=${JOBS:-${PARALLEL:-3}}
GUI_JOBS=${GUI_JOBS:-1}
BASE_PORT=${AUTOTEST_PORT_OFFSET:-0}
# Sans rendu : temps simulé à 60 images/s de jeu, sans attendre l'horloge.
HEADLESS="--headless --fixed-fps 60"
T_START=$(date +%s)

echo "== import"
"$GODOT" --headless --path . --import > "$OUT/import.log" 2>&1
# Lanceur (projet Godot séparé, launcher/).
"$GODOT" --headless --path launcher --import >> "$OUT/import.log" 2>&1
if grep -qE "SCRIPT ERROR|Parse Error|ERROR:" "$OUT/import.log"; then
  grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$OUT/import.log" | head
  echo "== CHECK ECHEC (import)"; exit 1
fi

echo "== dépendances"
"$GODOT" --headless --path . -s res://tools/test_deps.gd -- --out=$OUT/deps > "$OUT/deps.log" 2>&1
if [ ! -s "$OUT/deps/tasks.txt" ] || grep -qE "SCRIPT ERROR|Parse Error" "$OUT/deps.log"; then
  cat "$OUT/deps.log" | head; echo "== CHECK ECHEC (carte des dépendances)"; exit 1
fi
declare -A HASH MAPOF OKH
while read -r T H N M; do HASH[$T]=$H; MAPOF[$T]=$M; done < "$OUT/deps/tasks.txt"
while read -r T H; do [ -n "$T" ] && OKH[$T]=$H; done < "$CACHE"

# ------------------------------------------------------------ liste des tâches
# Une tâche = « type:nom ». Types : parse, unit, launcher, net, head, gui, mp.
# Clé d'empreinte : la tâche sans son suffixe de partie (« gui:x+0+3 » -> « gui:x »).
CANDIDATES=("parse:scripts" "launcher:tests")
[ $FAST -eq 0 ] && [ -z "$SCENARIOS" ] && CANDIDATES+=("net:smoke")
ALL=$(ls tests/autotest/*.gd | xargs -n1 basename | sed 's/\.gd$//' | grep -vE '^(scenario|helpers|mp_.*|long_.*|perf_.*)$')
for S in ${SCENARIOS:-$ALL}; do
  F="tests/autotest/$S.gd"
  grep -q "^## @niveau perf" "$F" 2>/dev/null && [ -z "$SCENARIOS" ] && continue
  KIND=head
  grep -q "^## @rendu" "$F" 2>/dev/null && KIND=gui
  # « ## @parts N » : scénario découpé en N parties lancées en parallèle.
  NP=$(grep -m1 -oE '^## @parts [0-9]+' "$F" 2>/dev/null | grep -oE '[0-9]+$')
  if [ -n "$NP" ] && [ "$NP" -gt 1 ]; then
    for K in $(seq 0 $((NP - 1))); do CANDIDATES+=("$KIND:$S+$K+$NP"); done
  else
    CANDIDATES+=("$KIND:$S")
  fi
done
if [ $FAST -eq 0 ] && { [ -z "$SCENARIOS" ] || [ -n "$MP" ]; }; then
  MPALL=$(ls tests/autotest/mp_*_host.gd 2>/dev/null | xargs -n1 basename | sed 's/^mp_//; s/_host\.gd$//')
  for N in ${MP:-$MPALL}; do CANDIDATES+=("mp:$N"); done
fi

# Faut-il relancer cette tâche ? (0 = oui)
needed() {
  local T=$1 K=${1%%+*}
  local M=${MAPOF[$K]:--}
  if [ -n "$SCENARIOS$MP" ] && [[ $T == head:* || $T == gui:* || $T == mp:* ]]; then return 0; fi
  if [ "$M" != "-" ]; then
    [ $KINO -eq 1 ] && return 0
    [ "${OKH[$T]}" != "${HASH[$K]}" ]; return
  fi
  [ $FULL -eq 1 ] && return 0
  [ -z "${HASH[$K]}" ] && return 0
  [ "${OKH[$T]}" != "${HASH[$K]}" ]
}

TASKS=()
SKIPPED=0
for T in "${CANDIDATES[@]}"; do
  if needed "$T"; then TASKS+=("$T"); else SKIPPED=$((SKIPPED + 1)); fi
done
# Tests unitaires : une seule instance pour tous les fichiers impactés.
UNIT_FILES=()
UNIT_ALL=0
if [ -z "$SCENARIOS$MP" ] || [ $FULL -eq 1 ]; then
  for F in $(ls tests/test_*.gd | xargs -n1 basename | grep -vE '^test_(case|runner)\.gd$'); do
    T="unit:${F%.gd}"
    if needed "$T"; then UNIT_FILES+=("$F"); else SKIPPED=$((SKIPPED + 1)); fi
  done
fi
UNIT_TOTAL=$(ls tests/test_*.gd | grep -vcE 'test_(case|runner)\.gd$')
[ ${#UNIT_FILES[@]} -eq "$UNIT_TOTAL" ] && UNIT_ALL=1
[ ${#UNIT_FILES[@]} -gt 0 ] && TASKS+=("unit:tests")
UNIT_ARG=""
[ $UNIT_ALL -eq 0 ] && UNIT_ARG="--files=$(IFS=,; echo "${UNIT_FILES[*]}")"
echo "== ${#TASKS[@]} tâche(s) à lancer (${#UNIT_FILES[@]} fichier(s) unitaire(s)), $SKIPPED inchangée(s) depuis leur dernier succès$([ $FULL -eq 1 ] && echo ' — complet')"

# Les plus longues d'abord (durée mémorisée, 20 s par défaut).
duration_of() { awk -v k="$1" '$1 == k { d = $2 } END { print (d == "" ? 20 : d) }' "$DUR"; }
ORDERED=$(for T in "${TASKS[@]}"; do echo "$(duration_of "$T") $T"; done | sort -rn | awk '{print $2}')

# ------------------------------------------------------------ exécution d'une tâche
log_of() { echo "$OUT/jobs/${1/:/_}.log"; }
run_task() {
  local T=$1 KIND=${1%%:*} NAME=${1#*:} SLOT=$2 LOG RC=0
  LOG=$(log_of "$1")
  local PORTS=$(( BASE_PORT + 100 * SLOT ))
  local SCN=${NAME%%+*} PARTARG=""
  if [[ $NAME == *+* ]]; then local R=${NAME#*+}; PARTARG="--part=${R%+*}/${R#*+}"; fi
  case $KIND in
    parse) "$GODOT" --headless --path . -s res://tests/parse_all.gd > "$LOG" 2>&1 || RC=1 ;;
    unit)  "$GODOT" --headless --path . res://tests/test_runner.tscn -- $UNIT_ARG > "$LOG" 2>&1 || RC=1 ;;
    launcher) "$GODOT" --headless --path launcher -s res://tests/test_launcher.gd > "$LOG" 2>&1 || RC=1 ;;
    net)   AUTOTEST_PORT_OFFSET=$PORTS sh tools/net_smoke.sh > "$LOG" 2>&1 || RC=1 ;;
    head)  local MODE=$HEADLESS
           # « ## @temps-reel » : mesure par seconde réelle, pas d'accélération.
           grep -q "^## @temps-reel" "tests/autotest/$SCN.gd" && MODE="--headless --max-fps 60"
           AUTOTEST_PARALLEL=1 timeout 420 "$GODOT" $MODE --path . -- --autotest=$SCN $PARTARG > "$LOG" 2>&1 || RC=1 ;;
    gui)   AUTOTEST_PARALLEL=1 timeout 420 "$GODOT" --path . --resolution 1280x720 -- --autotest=$SCN $PARTARG > "$LOG" 2>&1 || RC=1 ;;
    mp)    AUTOTEST_PORT_OFFSET=$PORTS HEADLESS_MP=1 sh tools/mp_test.sh "$NAME" > "$LOG" 2>&1 || RC=1 ;;
  esac
  if grep -qE "SCRIPT ERROR|ERROR:|\[FAIL\]|ECHEC" "$LOG"; then RC=1; fi
  exit $RC
}

# ------------------------------------------------------------ pool
declare -A PID_TASK PID_T0 PID_SLOT TASK_DUR
FREE=($(seq 1 $JOBS))       # numéros de place libres (servent aux ports)
PENDING=($ORDERED)
GUI_RUNNING=0
FAILED=()
PASSED=()
DONE=0
TOTAL=${#PENDING[@]}

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
  [ ${#PID_TASK[@]} -eq 0 ] && break
  wait -n -p DONE_PID; RC=$?
  T=${PID_TASK[$DONE_PID]}
  D=$(( $(date +%s) - ${PID_T0[$DONE_PID]} ))
  FREE+=(${PID_SLOT[$DONE_PID]})
  [[ $T == gui:* ]] && GUI_RUNNING=$((GUI_RUNNING - 1))
  unset "PID_TASK[$DONE_PID]" "PID_T0[$DONE_PID]" "PID_SLOT[$DONE_PID]"
  DONE=$((DONE + 1))
  TASK_DUR[$T]=$D
  if [ $RC -eq 0 ]; then
    printf "[%2d/%d] ok     %-30s %4ds\n" $DONE $TOTAL "$T" $D
    PASSED+=("$T")
  else
    printf "[%2d/%d] ECHEC  %-30s %4ds\n" $DONE $TOTAL "$T" $D
    FAILED+=("$T")
  fi
done

# ------------------------------------------------------------ rejeu des échecs
# Une fois, une tâche à la fois (machine peu chargée). Le premier journal est
# gardé à côté (.1.log) pour comprendre l'instabilité.
FLAKY=()
if [ $RETRY -eq 1 ] && [ ${#FAILED[@]} -gt 0 ]; then
  STILL=()
  for T in "${FAILED[@]}"; do
    L=$(log_of "$T"); cp "$L" "${L%.log}.1.log"
    echo "== rejeu : $T"
    T0=$(date +%s)
    if ( run_task "$T" 1 ); then
      FLAKY+=("$T"); PASSED+=("$T")
      echo "$(date '+%Y-%m-%d %H:%M') $T (1er journal : ${L%.log}.1.log)" >> "$OUT/flaky.txt"
    else
      STILL+=("$T")
    fi
    TASK_DUR[$T]=$(( $(date +%s) - T0 ))
  done
  FAILED=("${STILL[@]}")
fi

# ------------------------------------------------------------ cache, durées, JUnit
# Succès -> empreinte mémorisée ; échec -> oubliée (relancée la prochaine fois).
for T in "${PASSED[@]}"; do
  if [ "$T" = "unit:tests" ]; then
    LOG=$(log_of "$T")
    for F in "${UNIT_FILES[@]}"; do K="unit:${F%.gd}"; OKH[$K]=${HASH[$K]}; done
  else
    OKH[$T]=${HASH[${T%%+*}]}
  fi
done
for T in "${FAILED[@]}"; do
  if [ "$T" = "unit:tests" ]; then
    # Seuls les fichiers qui ont échoué sont oubliés ; les autres ont réussi.
    LOG=$(log_of "$T")
    for F in "${UNIT_FILES[@]}"; do
      K="unit:${F%.gd}"
      if grep -q "\[FAIL\] $F::" "$LOG" || ! grep -q "\] $F::" "$LOG"; then unset "OKH[$K]"; else OKH[$K]=${HASH[$K]}; fi
    done
  else
    unset "OKH[$T]"
  fi
done
{ for K in "${!OKH[@]}"; do [ -n "${HASH[${K%%+*}]}" ] && echo "$K ${OKH[$K]}"; done; } | sort > "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
# Durées : mises à jour pour les tâches lancées, entrées disparues retirées.
{
  for T in "${CANDIDATES[@]}" "unit:tests"; do
    if [ -n "${TASK_DUR[$T]}" ]; then echo "$T ${TASK_DUR[$T]}"
    else awk -v k="$T" '$1 == k { d = $2 } END { if (d != "") print k, d }' "$DUR"; fi
  done
} > "$DUR.tmp" && mv "$DUR.tmp" "$DUR"
xml_escape() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo "<testsuite name=\"check\" tests=\"${#TASKS[@]}\" failures=\"${#FAILED[@]}\" skipped=\"$SKIPPED\">"
  for T in "${TASKS[@]}"; do
    echo "  <testcase classname=\"${T%%:*}\" name=\"${T#*:}\" time=\"${TASK_DUR[$T]:-0}\">"
    if printf '%s\n' "${FAILED[@]}" | grep -qxF "$T"; then
      echo "    <failure message=\"voir $(log_of "$T")\">"
      grep -hE "\[autotest\] ECHEC|\[FAIL\]|^\s+- |SCRIPT ERROR|ERROR:" "$(log_of "$T")" | head -20 | xml_escape
      echo "    </failure>"
    elif printf '%s\n' "${FLAKY[@]}" | grep -qxF "$T"; then
      echo "    <system-out>INSTABLE : réussi au rejeu</system-out>"
    fi
    echo "  </testcase>"
  done
  echo "</testsuite>"
} > "$OUT/junit.xml"

# ------------------------------------------------------------ bilan
grep -h "PARSE:" "$OUT/jobs/parse_scripts.log" 2>/dev/null | tail -1
[ ${#UNIT_FILES[@]} -gt 0 ] && grep -h "TESTS:" "$(log_of unit:tests)" 2>/dev/null
for T in "${FLAKY[@]}"; do echo "== INSTABLE (réussi au rejeu) : $T — premier journal ${OUT}/jobs/${T/:/_}.1.log"; done
for T in "${FAILED[@]}"; do
  echo "---- $T ($(log_of "$T"))"
  grep -hE "\[autotest\] ECHEC|\[FAIL\]|^\s+- |SCRIPT ERROR|ERROR:|ECHEC|délai" "$(log_of "$T")" | head -12
done
echo "== durée totale : $(( $(date +%s) - T_START )) s ($JOBS tâches simultanées)"
if [ ${#FAILED[@]} -eq 0 ]; then
  # Check complet réussi : empreinte de tout ce qui a été vérifié (hors tests
  # d'une carte précise), exigée par tools/release.sh.
  [ $FULL -eq 1 ] && [ -z "$SCENARIOS$MP" ] && [ $FAST -eq 0 ] && \
    awk '$4 == "-" { print $1, $2 }' "$OUT/deps/tasks.txt" | md5sum | cut -c1-32 > "$OUT/last_full_ok"
  echo "== CHECK OK"; exit 0
fi
echo "== CHECK ECHEC (${#FAILED[@]} tâche(s))"
exit 1
