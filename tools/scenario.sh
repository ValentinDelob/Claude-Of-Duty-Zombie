#!/bin/sh
# Lance un scénario d'autotest dans une fenêtre qui ne vole pas le focus.
# Usage : sh tools/scenario.sh <nom> [arguments godot supplémentaires]
cd "$(dirname "$0")/.."
. tools/nofocus.sh
nofocus_on
N=$1; shift
${GODOT:-godot} --path . --windowed --resolution 1280x720 "$@" -- --autotest=$N
