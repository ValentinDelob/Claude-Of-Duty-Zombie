#!/bin/sh
# Commit sécurisé : lance tools/check.sh et ne committe QUE s'il réussit.
# CHECK_ARGS : options de check.sh (par défaut : tests impactés seulement ;
# tools/ship.sh passe --full avant une release).
# Usage : sh tools/commit.sh fichier_message.txt
# COMMIT_EXCLUDE="motif ..." : chemins laissés hors du commit (par exemple le
# travail en cours d'une autre session dans le même dossier), sans y toucher.
cd "$(dirname "$0")/.."
MSG=$1
[ -f "$MSG" ] || { echo "message introuvable : $MSG"; exit 2; }
mkdir -p tests/_out  # absent dans une copie neuve (ignoré par git)
set -f  # motifs de COMMIT_EXCLUDE laissés tels quels (pas de développement par le shell)
# Arbre de travail au départ : un fichier qui change PENDANT la vérification
# (autre session dans le même dossier...) ne doit pas partir dans ce commit
# sans avoir été vérifié. Les .uid/.import créés par l'import du check sont admis.
EXCL_RE=$(printf '%s\n' $COMMIT_EXCLUDE | sed 's/[.]/\./g; s/[*]/.*/g' | paste -sd'|' -)
tree_state() { git status --porcelain --untracked-files=all | grep -vE '\.(uid|import)$' | { [ -n "$EXCL_RE" ] && grep -vE "$EXCL_RE" || cat; } | while read -r _ f; do echo "$f $(git hash-object "$f" 2>/dev/null)"; done | sort; }
# Notes rangées AVANT la vérification : le check complet porte sur le contenu
# final (tools/release.sh refuse un contenu différent de celui vérifié).
# Notes de version pour les joueurs (changelogs/next/) : rangées sous le numéro
# de la version que ce commit va devenir (tools/release.sh :
# v<M.m.p>-snapshot.<commits>, M.m.p = config/version, la prochaine stable).
GODOT=${GODOT:-godot}
TARGET=$(sed -n 's/^config\/version="\([0-9]*\.[0-9]*\.[0-9]*\)".*/\1/p' project.godot)
# Commit qui conclut une fusion : les commits de la branche fusionnée comptent aussi.
if git rev-parse -q --verify MERGE_HEAD > /dev/null; then
  COUNT=$(git rev-list --count HEAD MERGE_HEAD)
else
  COUNT=$(git rev-list --count HEAD)
fi
NEXT_TAG="v$TARGET-snapshot.$(( COUNT + 1 ))"
# Copie des notes avant de les ranger : si la vérification échoue, elles sont
# remises telles quelles (le prochain essai les range sous le bon numéro).
UNDO=tests/_out/notes_undo
rm -rf "$UNDO"; mkdir -p "$UNDO"
cp changelogs/changelogs.json "$UNDO/" 2>/dev/null
[ -d changelogs/next ] && cp -r changelogs/next "$UNDO/next"
HAD_IMG=0; [ -d "changelogs/img/$NEXT_TAG" ] && HAD_IMG=1
undo_notes() {
  cp "$UNDO/changelogs.json" changelogs/changelogs.json 2>/dev/null
  [ -d "$UNDO/next" ] && { rm -rf changelogs/next; cp -r "$UNDO/next" changelogs/next; }
  [ $HAD_IMG -eq 0 ] && rm -rf "changelogs/img/$NEXT_TAG"
}
mkdir -p tests/_out/logs   # journal Godot hors du dossier du joueur
"$GODOT" --headless --log-file "$PWD/tests/_out/logs/changelog_merge.log" --path . -s res://tools/changelog_merge.gd -- "$NEXT_TAG" || { undo_notes; echo "== COMMIT ANNULÉ : notes de version invalides (changelogs/next/next.json)"; exit 1; }
BEFORE=$(tree_state)
bash tools/check.sh $CHECK_ARGS > tests/_out/check.log 2>&1
RC=$?
grep -E "^== |TESTS|host=|ECHEC|ERROR|AVERTISSEMENT|échoué" tests/_out/check.log
if [ $RC -ne 0 ]; then
  undo_notes
  echo "== COMMIT ANNULÉ : la vérification a échoué (notes de version remises dans changelogs/next)"
  exit 1
fi
AFTER=$(tree_state)
if [ "$BEFORE" != "$AFTER" ]; then
  undo_notes
  echo "== COMMIT ANNULÉ : des fichiers ont changé pendant la vérification :"
  echo "$BEFORE" > tests/_out/tree_before.txt
  echo "$AFTER" > tests/_out/tree_after.txt
  diff tests/_out/tree_before.txt tests/_out/tree_after.txt | grep '^[<>]' | head -20
  exit 1
fi
git add -A
[ -n "$COMMIT_EXCLUDE" ] && git reset -q -- $COMMIT_EXCLUDE
git commit -q -F "$MSG" && git log --oneline -1
