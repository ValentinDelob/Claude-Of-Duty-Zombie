#!/bin/sh
# Régénère les aperçus des cartes du jeu de l'écran JOUER du hub v2
# (assets/ui/hub/maps/<carte>.png, 1280 × 720 : vue en jeu au départ du
# joueur, interface masquée) : scénario tests/autotest/map_shots.gd, fenêtre
# hors écran (jamais visible), puis import Godot sans perte avec mipmaps
# (réductions propres dans l'aperçu, comme les rendus du hub).
#   sh tools/map_shots.sh
# À relancer quand une carte du jeu change d'aspect à son point de départ.
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=assets/ui/hub/maps
mkdir -p "$OUT" tests/_out/logs
touch tests/_out/.gdignore
sh tools/scenario.sh map_shots || exit 1
"$GODOT" --headless --log-file "$PWD/tests/_out/logs/map_shots_import_godot.log" --path . --import > tests/_out/logs/map_shots_import.log 2>&1
for F in "$OUT"/*.png.import; do
  sed -i -e 's/^compress\/mode=.*/compress\/mode=0/' \
    -e 's/^mipmaps\/generate=.*/mipmaps\/generate=true/' \
    -e 's/^process\/size_limit=.*/process\/size_limit=0/' \
    -e 's/^detect_3d\/compress_to=.*/detect_3d\/compress_to=0/' "$F"
done
"$GODOT" --headless --log-file "$PWD/tests/_out/logs/map_shots_import_godot.log" --path . --import >> tests/_out/logs/map_shots_import.log 2>&1
ls -la "$OUT"/*.png
