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
git add -A && git commit -q -F "$MSG" && git log --oneline -1
