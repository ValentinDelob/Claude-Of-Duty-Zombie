#!/bin/sh
# Lance un script Blender SANS FENÊTRE (aucune fenêtre ne s'ouvre sur le bureau).
# Usage : sh tools/blender.sh tools/blender/<script>.py [arguments du script...]
# BLENDER : chemin de blender.exe (défaut : installation winget de Blender 5.2).
cd "$(dirname "$0")/.."
BLENDER=${BLENDER:-"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"}
S=$1; shift
exec "$BLENDER" --background --factory-startup --python "$S" -- "$@"
