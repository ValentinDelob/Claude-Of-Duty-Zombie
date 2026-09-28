#!/bin/sh
# Lance un scénario d'autotest sans jamais déranger l'utilisateur :
#   - par défaut AVEC rendu, dans une fenêtre réduite puis hors écran (captures) ;
#   - HEADLESS=1 : sans rendu ni fenêtre (plus rapide, pas de captures).
# Usage : sh tools/scenario.sh <nom> [arguments godot supplémentaires]
cd "$(dirname "$0")/.."
N=$1; shift
if [ "$HEADLESS" = "1" ]; then
  exec ${GODOT:-godot} --headless --max-fps 60 --path . "$@" -- --autotest=$N
fi
. tools/nofocus.sh
nofocus_on
${GODOT:-godot} --path . --resolution 1280x720 "$@" -- --autotest=$N
