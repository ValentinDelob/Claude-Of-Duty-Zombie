#!/bin/sh
# Commit sécurisé : lance tools/check.sh et ne committe QUE s'il réussit.
# Usage : sh tools/commit.sh fichier_message.txt
cd "$(dirname "$0")/.."
MSG=$1
[ -f "$MSG" ] || { echo "message introuvable : $MSG"; exit 2; }
bash tools/check.sh > tests/_out/check.log 2>&1
RC=$?
grep -E "^== |TESTS|host=|ECHEC|ERROR|AVERTISSEMENT|échoué" tests/_out/check.log
if [ $RC -ne 0 ]; then
  echo "== COMMIT ANNULÉ : la vérification a échoué"
  exit 1
fi
# Notes de version pour les joueurs (changelogs/next/) : rangées sous le numéro
# de la version que ce commit va devenir (tools/release.sh : v<majeur.mineur>.<commits>).
GODOT=${GODOT:-godot}
BASE=$(sed -n 's/^config\/version="\([0-9]*\.[0-9]*\).*/\1/p' project.godot)
NEXT_TAG="v$BASE.$(( $(git rev-list --count HEAD) + 1 ))"
"$GODOT" --headless --path . -s res://tools/changelog_merge.gd -- "$NEXT_TAG" || { echo "== COMMIT ANNULÉ : notes de version invalides (changelogs/next/next.json)"; exit 1; }
git add -A && git commit -q -F "$MSG" && git log --oneline -1
