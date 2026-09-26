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
"$GODOT" --headless --path . --export-release "Windows Desktop" "$EXE" > build/export.log 2>&1
if [ $? -ne 0 ] || [ ! -s "$EXE" ] || grep -qE "SCRIPT ERROR|Parse Error" build/export.log; then
  echo "== EXPORT ECHEC (voir build/export.log)"; exit 1
fi
VEXE="build/CallOfClaudeZombie-$TAG.exe"
cp "$EXE" "$VEXE"

echo "== vérification du build (scénario boot)"
"./$EXE" --windowed --resolution 1280x720 -- --autotest=boot > build/smoke.log 2>&1
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
{
  echo "**$SUBJECT**"
  echo
  git log -1 --format=%b | grep -v "^Co-Authored-By"
  echo
  echo "---"
  echo "Télécharger \`CallOfClaudeZombie-$TAG.exe\` ci-dessous et le lancer (Windows 64 bits,"
  echo "aucune installation). Multijoueur : même version pour tous les joueurs, port UDP 7777."
} > "$NOTES"
"$GH" release create "$TAG" "$VEXE" --target "$(git rev-parse HEAD)" \
  --title "$TAG — $SUBJECT" --notes-file "$NOTES" --latest || { echo "== PUBLICATION ECHEC"; exit 1; }
echo "== release publiée : $TAG"
