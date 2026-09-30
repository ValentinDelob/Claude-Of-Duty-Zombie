#!/bin/sh
# Lance un scénario d'autotest sans jamais déranger l'utilisateur :
#   - par défaut AVEC rendu, dans une fenêtre réduite puis hors écran (captures) ;
#   - HEADLESS=1 : sans rendu ni fenêtre (plus rapide, pas de captures).
# Journal Godot : tests/_out/logs/scenario_<nom>.log (jamais celui du joueur).
# Usage : sh tools/scenario.sh <nom> [arguments godot supplémentaires]
cd "$(dirname "$0")/.."
N=$1; shift
LOGS="$PWD/tests/_out/logs"; mkdir -p "$LOGS"
if [ "$HEADLESS" = "1" ]; then
  exec ${GODOT:-godot} --headless --max-fps 60 --log-file "$LOGS/scenario_$N.log" --path . "$@" -- --autotest=$N
fi
. tools/nofocus.sh
nofocus_on
${GODOT:-godot} --log-file "$LOGS/scenario_$N.log" --path . --resolution 1280x720 "$@" -- --autotest=$N
