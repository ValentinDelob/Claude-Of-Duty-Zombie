#!/bin/sh
# Construit le .exe Windows du commit courant et le publie en release GitHub.
#   Version : <majeur.mineur de project.godot>.<nombre de commits>  (ex. v0.1.34)
#   Local   : build/CallOfClaudeZombie.exe (dernier build) + build/CallOfClaudeZombie-<version>.exe
#   GitHub  : release <version> (notes = message du commit) avec le .exe en pièce jointe.
# Prérequis : modèles d'export Godot 4.7.2 installés, `gh` connecté.
# Usage : sh tools/release.sh [--local]      (--local : build sans publication)
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
GH=${GH:-gh}
BASE=$(sed -n 's/^config\/version="\([0-9]*\.[0-9]*\).*/\1/p' project.godot)
N=$(git rev-list --count HEAD)
TAG="v$BASE.$N"
EXE=build/CallOfClaudeZombie.exe
mkdir -p build

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
VEXE="build/CallOfClaudeZombie-$TAG.exe"
cp "$EXE" "$VEXE"

echo "== vérification du build (scénario boot)"
# Fenêtre sans focus, réduite puis hors écran (l'exécutable lit override.cfg
# à côté de lui ; voir tools/nofocus.sh).
printf '[display]\n\nwindow/size/no_focus=true\nwindow/size/mode=1\n' > build/override.cfg
"./$EXE" --resolution 1280x720 -- --autotest=boot > build/smoke.log 2>&1
rm -f build/override.cfg
if ! grep -q "\[autotest\] fin : SUCCES" build/smoke.log || grep -qE "SCRIPT ERROR" build/smoke.log; then
  echo "== LE BUILD NE DÉMARRE PAS (voir build/smoke.log)"; exit 1
fi
echo "== build local : $VEXE"
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
  for C in $(git rev-list --reverse "$RANGE"); do
    echo "### $(git log -1 --format=%s "$C")"
    git log -1 --format=%b "$C" | grep -v "^Co-Authored-By"
    echo
  done
  echo "---"
  echo "Télécharger \`CallOfClaudeZombie-$TAG.exe\` ci-dessous et le lancer (Windows 64 bits,"
  echo "aucune installation). Multijoueur : même version pour tous les joueurs, port UDP 7777."
} > "$NOTES"
"$GH" release create "$TAG" "$VEXE" --target "$(git rev-parse HEAD)" \
  --title "$TAG — $SUBJECT" --notes-file "$NOTES" --latest || { echo "== PUBLICATION ECHEC"; exit 1; }
echo "== release publiée : $TAG"
