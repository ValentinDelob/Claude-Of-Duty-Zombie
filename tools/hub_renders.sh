#!/bin/sh
# Régénère TOUS les rendus Blender du hub (docs/hub_v2) dans
# assets/ui/hub/renders/ : armes, ennemis, échantillons, personnages.
#
#   sh tools/hub_renders.sh                       tout
#   sh tools/hub_renders.sh weapons samples       seulement ces catégories
#   (weapons | enemies | samples | characters ; NOIMPORT=1 : sans passe Godot)
#
#   weapons/<modèle>.png      560 × 280   assets/models/weapons/voxel/*.glb
#                                         (sauf hands.glb et round_*.glb),
#                                         canon vers la droite, profil 3/4
#   enemies/<type>.png        600 × 720   types du codex (assets/data/hub/codex.json),
#                                         3/4 face
#   samples/<id>.png          512 × 512   LootRules.SAMPLES (tools/blender/samples)
#   characters/player*.png    600 × 720   joueur : ambre (joueur 1), neutre, masque
#                                         de la zone d'équipe (render_mobs.py)
#   characters/scientist_hero.png 1400 × 1800, scientist_bust.png 900 × 900
#                                         (Dr Brown, tools/blender/scientist)
#
# Un seul Blender à la fois (les étapes se suivent). Planches de contrôle
# (jamais livrées) : tests/_out/hub_renders/sheet_<catégorie>.png.
# Enfin, une passe d'import Godot crée les .import manquants puis impose les
# réglages des images d'interface : sans perte (compress/mode=0), mipmaps
# (réductions propres en 1280 × 720), jamais converties en VRAM pour la 3D.
# Accès depuis le jeu : scripts/ui/hub2/hub_renders.gd (HubRenders).
cd "$(dirname "$0")/.."
OUT=assets/ui/hub/renders
TMP=tests/_out/hub_renders
mkdir -p "$OUT/weapons" "$OUT/enemies" "$OUT/samples" "$OUT/characters" "$TMP"
touch tests/_out/.gdignore
CATS=${*:-"weapons enemies samples characters"}
BL="tools/blender.sh"
FAIL=0

sheet() {  # sheet <catégorie> <colonnes> <case>
  sh "$BL" tools/blender/hub_renders/contact_sheet.py --in "$OUT/$1" --out "$TMP/sheet_$1.png" \
    --cols "$2" --tile "$3" > "$TMP/sheet_$1.log" 2>&1 || FAIL=1
}

run() {  # run <journal> <script> [args...]
  LOG="$TMP/$1.log"; shift
  echo "== $*"
  if ! sh "$BL" "$@" > "$LOG" 2>&1 || grep -q "Traceback" "$LOG"; then
    echo "ÉCHEC (voir $LOG)"; grep -A8 "Traceback" "$LOG" | head -20; FAIL=1
  fi
}

for C in $CATS; do
  case $C in
    weapons)
      run weapons tools/blender/hub_renders/render_weapons.py --out "$OUT/weapons"
      sheet weapons 6 280x140 ;;
    enemies)
      run enemies tools/blender/hub_renders/render_mobs.py --out "$OUT" --group enemies
      sheet enemies 4 300x360 ;;
    samples)
      rm -rf "$TMP/samples"
      run samples tools/blender/samples/samples_render.py --out "$TMP/samples"
      for F in "$TMP"/samples/*.png; do
        case $(basename "$F") in samples_sheet.png) ;; *) cp "$F" "$OUT/samples/" ;; esac
      done
      sheet samples 5 256x256 ;;
    characters)
      run player tools/blender/hub_renders/render_mobs.py --out "$OUT" --group characters
      rm -rf "$TMP/scientist"
      run scientist tools/blender/scientist/scientist_render.py --out "$TMP/scientist"
      cp "$TMP/scientist/scientist_hero.png" "$TMP/scientist/scientist_bust.png" "$OUT/characters/" || FAIL=1
      sheet characters 5 300x360 ;;
    *) echo "catégorie inconnue : $C (weapons | enemies | samples | characters)"; exit 2 ;;
  esac
done

# --- Import Godot : .import manquants, puis réglages des images d'interface.
GODOT=${GODOT:-godot}
if [ -z "$NOIMPORT" ] && command -v "$GODOT" > /dev/null 2>&1; then
  echo "== import Godot"
  "$GODOT" --headless --path . --import > "$TMP/import.log" 2>&1
  for F in "$OUT"/*/*.png.import; do
    sed -i -e 's/^compress\/mode=.*/compress\/mode=0/' \
      -e 's/^mipmaps\/generate=.*/mipmaps\/generate=true/' \
      -e 's/^process\/fix_alpha_border=.*/process\/fix_alpha_border=true/' \
      -e 's/^process\/premult_alpha=.*/process\/premult_alpha=false/' \
      -e 's/^process\/size_limit=.*/process\/size_limit=0/' \
      -e 's/^detect_3d\/compress_to=.*/detect_3d\/compress_to=0/' "$F"
  done
  "$GODOT" --headless --path . --import >> "$TMP/import.log" 2>&1
fi

echo "== tailles"
du -ch "$OUT"/*/*.png | tail -1
for D in weapons enemies samples characters; do
  printf "  %-11s %3d fichiers  %s\n" "$D" "$(ls "$OUT/$D"/*.png 2> /dev/null | wc -l)" "$(du -sh "$OUT/$D" | cut -f1)"
done
echo "planches : $TMP/sheet_*.png"
exit $FAIL
