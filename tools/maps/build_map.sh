#!/bin/sh
# Carte dessinée -> jeu, en une commande (docs/MAP_AUTHORING.md) :
#   1. conversion + validation du dessin (Godot sans fenêtre) : rapport.txt et
#      rapport_etageN.png à côté du dessin ; arrêt si la carte est refusée ;
#   2. géométrie 3D par tools/blender/mesh_map.py (Blender sans fenêtre) :
#      assets/maps/<id>/<id>.glb et la vue de dessus dessin/apercu_dessus.png ;
#   3. import Godot du .glb.
# Usage : sh tools/maps/build_map.sh assets/maps/<id>/dessin/carte.txt
cd "$(dirname "$0")/../.."
TXT=$1
GODOT=${GODOT:-godot}
if [ -z "$TXT" ] || [ ! -f "$TXT" ]; then
  echo "usage : sh tools/maps/build_map.sh assets/maps/<id>/dessin/carte.txt"; exit 2
fi
"$GODOT" --headless --path . -s res://tools/maps/draw2layout.gd -- "$TXT" || { echo "== carte refusée : lisez le rapport ci-dessus"; exit 1; }
ID=$(sed -n 's/^[[:space:]]*id[[:space:]]*=[[:space:]]*\([a-z0-9_]*\).*/\1/p' "$TXT" | head -1)
DIR=assets/maps/$ID
# (chemin absolu pour l'aperçu : Blender résout un chemin relatif depuis la racine du disque)
sh tools/blender.sh tools/blender/mesh_map.py "$DIR/layout.json" "$DIR/$ID.glb" "$(pwd)/$(dirname "$TXT")/apercu_dessus.png" || { echo "== échec de Blender"; exit 1; }
"$GODOT" --headless --path . --import > /dev/null 2>&1
echo "== carte $ID prête : jouez-la avec --map=$ID (déclarée dans Game.MAP_SCRIPTS)"
