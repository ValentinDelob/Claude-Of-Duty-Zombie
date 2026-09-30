#!/bin/sh
# Construit le .exe Windows du commit courant et le publie en release GitHub.
#   Version : <majeur.mineur de project.godot>.<nombre de commits>  (ex. v0.1.34)
#   Local   : build/ClaudeOfDutyZombie.exe (dernier build) + build/ClaudeOfDutyZombie-<version>.exe
#   GitHub  : release <version> (notes = message du commit) avec le .exe en pièce jointe.
# Prérequis : modèles d'export Godot 4.7.2 installés, `gh` connecté.
# Usage : sh tools/release.sh [--local]      (--local : build sans publication)
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
GH=${GH:-gh}
BASE=$(sed -n 's/^config\/version="\([0-9]*\.[0-9]*\).*/\1/p' project.godot)
N=$(git rev-list --count HEAD)
TAG="v$BASE.$N"
EXE=build/ClaudeOfDutyZombie.exe
mkdir -p build

# Publication : seulement si le dernier check COMPLET (tools/check.sh --full,
# lancé par tools/ship.sh) a réussi sur exactement ce contenu (même empreinte
# de toutes les tâches, hors tests propres à une carte : docs/TESTING.md).
if [ "$1" != "--local" ]; then
  "$GODOT" --headless --path . -s res://tools/test_deps.gd -- --out=tests/_out/deps_release > /dev/null 2>&1
  NOW=$(awk '$4 == "-" { print $1, $2 }' tests/_out/deps_release/tasks.txt 2>/dev/null | md5sum | cut -c1-32)
  if [ ! -s tests/_out/deps_release/tasks.txt ] || [ "$NOW" != "$(cat tests/_out/last_full_ok 2>/dev/null)" ]; then
    echo "== RELEASE REFUSÉE : pas de check complet réussi sur ce contenu (sh tools/check.sh --full)"; exit 1
  fi
fi

echo "== export $TAG"
# Le numéro de build est inscrit dans le paquet (menu, poignée de main réseau),
# puis project.godot est remis en état.
cp project.godot build/project.godot.bak
sed -i "s/^config\/version=.*/config\/version=\"${TAG#v}\"/" project.godot
"$GODOT" --headless --path . --export-release "Windows Desktop" "$EXE" > build/export.log 2>&1
RC=$?
cp build/project.godot.bak project.godot
if [ $RC -ne 0 ] || [ ! -s "$EXE" ] || grep -qE "SCRIPT ERROR|Parse Error" build/export.log; then
  echo "== EXPORT ECHEC (voir build/export.log)"; exit 1
fi
VEXE="build/ClaudeOfDutyZombie-$TAG.exe"
cp "$EXE" "$VEXE"

echo "== export du lanceur"
# Lanceur (launcher/, docs/LAUNCHER.md) : publié avec chaque version, avec son
# numéro (les lanceurs plus anciens se mettent à jour tout seuls).
LEXE=build/ClaudeOfDutyZombie-Launcher.exe
"$GODOT" --headless --path launcher --export-release "Windows Desktop" "$PWD/$LEXE" > build/export_launcher.log 2>&1
if [ ! -s "$LEXE" ] || grep -qE "SCRIPT ERROR|Parse Error" build/export_launcher.log; then
  echo "== EXPORT DU LANCEUR ECHEC (voir build/export_launcher.log)"; exit 1
fi
# Ancien nom : les lanceurs publiés avant le changement de nom cherchent ce fichier.
cp "$LEXE" build/CallOfClaudeZombie-Launcher.exe
sed -n 's/^const LAUNCHER_VERSION := \([0-9]*\).*/\1/p' launcher/scripts/version.gd > build/launcher_version.txt

echo "== vérification du build (scénario boot)"
# Fenêtre sans focus, réduite puis hors écran (l'exécutable lit override.cfg
# à côté de lui ; voir tools/nofocus.sh).
printf '[display]\n\nwindow/size/no_focus=true\nwindow/size/mode=1\n' > build/override.cfg
"./$EXE" --resolution 1280x720 -- --autotest=boot > build/smoke.log 2>&1
rm -f build/override.cfg
if ! grep -q "\[autotest\] fin : SUCCES" build/smoke.log || grep -qE "SCRIPT ERROR" build/smoke.log; then
  echo "== LE BUILD NE DÉMARRE PAS (voir build/smoke.log)"; exit 1
fi
# Lanceur : démarre hors écran, sans focus, sans réseau, capture puis se ferme.
printf '[display]

window/size/no_focus=true
' > build/override.cfg
rm -f build/launcher_smoke.png
timeout 60 "./$LEXE" --position -20000,-20000 -- --offline --capture="$PWD/build/launcher_smoke.png" > build/launcher_smoke.log 2>&1
rm -f build/override.cfg
if [ ! -s build/launcher_smoke.png ] || grep -qE "SCRIPT ERROR" build/launcher_smoke.log; then
  echo "== LE LANCEUR NE DÉMARRE PAS (voir build/launcher_smoke.log)"; exit 1
fi
# Sommes SHA-256 de tous les fichiers publiés (docs/SECURITY.md) : le lanceur
# refuse d'installer le jeu ou de se remplacer si la somme ne correspond pas.
# Calculées APRÈS les tests de démarrage (fichiers définitifs), noms seuls.
SUMS=build/SHA256SUMS.txt
( cd build && sha256sum "ClaudeOfDutyZombie-$TAG.exe" ClaudeOfDutyZombie-Launcher.exe \
    CallOfClaudeZombie-Launcher.exe launcher_version.txt ) > "$SUMS" || { echo "== SHA256SUMS ECHEC"; exit 1; }
if [ "$(grep -cE '^[0-9a-f]{64} [ *][A-Za-z0-9._-]+$' "$SUMS")" != 4 ]; then
  echo "== SHA256SUMS INVALIDE (voir $SUMS)"; exit 1
fi
echo "== build local : $VEXE (sommes : $SUMS)"
[ "$1" = "--local" ] && exit 0

if git status --porcelain | grep -q .; then
  echo "== arbre de travail modifié : committer avant de publier"; exit 1
fi
git fetch -q origin
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main 2>/dev/null)" ]; then
  echo "== HEAD n'est pas poussé sur origin/main : git push d'abord"; exit 1
fi
SUBJECT=$(git log -1 --format=%s)
NOTES=build/release_notes.md
# Notes : tous les commits depuis la release précédente.
PREV=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null)
RANGE=${PREV:+$PREV..}HEAD
{
  # Notes pour les joueurs (tools/changelog_merge.gd), si elles sont celles de cette version.
  if [ -f build/player_notes.md ] && head -1 build/player_notes.md | grep -q "<!-- $TAG -->"; then
    tail -n +2 build/player_notes.md
    echo "---"
    echo "## Détails techniques"
  fi
  for C in $(git rev-list --reverse "$RANGE"); do
    echo "### $(git log -1 --format=%s "$C")"
    git log -1 --format=%b "$C" | grep -v "^Co-Authored-By"
    echo
  done
  echo "---"
  echo "Le plus simple : télécharger \`ClaudeOfDutyZombie-Launcher.exe\` et le lancer : il installe"
  echo "et met à jour le jeu tout seul, et permet de choisir la version. Sinon, télécharger"
  echo "\`ClaudeOfDutyZombie-$TAG.exe\` ci-dessous et le lancer (Windows 64 bits, aucune installation)."
  echo "Multijoueur : même version pour tous les joueurs, port UDP 7777."
  echo "Intégrité : \`SHA256SUMS.txt\` donne la somme SHA-256 de chaque fichier (vérifiée par le lanceur)."
} > "$NOTES"
"$GH" release create "$TAG" "$VEXE" "$LEXE" build/CallOfClaudeZombie-Launcher.exe build/launcher_version.txt "$SUMS" --target "$(git rev-parse HEAD)" \
  --title "$TAG — $SUBJECT" --notes-file "$NOTES" --latest || { echo "== PUBLICATION ECHEC"; exit 1; }
echo "== release publiée : $TAG"
