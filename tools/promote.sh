#!/bin/bash
# Promotion d'une snapshot validée en STABLE, sans rien reconstruire
# (docs/RELEASE.md § 5) :
#   sh tools/promote.sh v0.2.0-snapshot.180 [v0.2.0]
#   1. télécharge de la snapshot : jeu complet, lanceurs, launcher_version.txt,
#      manifest.json ;
#   2. manifeste réécrit : numéro stable, canal stable (les paquets restent dans
#      la release de la snapshot : rien n'est republié) ;
#   3. jeu complet renommé ClaudeOfDutyZombie-<stable>.exe (anciens lanceurs) ;
#   4. SHA256SUMS.txt recalculé ; release <stable> créée sur le MÊME commit,
#      marquée « latest » (tous les lanceurs, anciens compris, la voient) ;
#   5. notes des joueurs : les snapshots depuis la stable précédente sont
#      rassemblées sous le numéro stable (changelogs/changelogs.json), commit
#      et push de ce seul fichier.
# Une release référencée par un manifeste ne doit jamais être supprimée.
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
GH=${GH:-gh}
W() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
SNAP=$1
case "$SNAP" in
  v*-snapshot.*) ;;
  *) echo "usage : sh tools/promote.sh v<M.m.p>-snapshot.<n> [v<M.m.p>]"; exit 2 ;;
esac
STABLE=${2:-${SNAP%%-snapshot.*}}
echo "$STABLE" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' || { echo "== numéro stable invalide : $STABLE"; exit 2; }
if "$GH" release view "$STABLE" > /dev/null 2>&1; then
  echo "== $STABLE existe déjà"; exit 1
fi
OUT=build/promote; rm -rf "$OUT"; mkdir -p "$OUT" tests/_out/logs
LOGS="$(W "$PWD")/tests/_out/logs"

echo "== fichiers de $SNAP"
"$GH" release download "$SNAP" -D "$OUT" -p "ClaudeOfDutyZombie-$SNAP.exe" -p "ClaudeOfDutyZombie-Launcher.exe" \
    -p "CallOfClaudeZombie-Launcher.exe" -p "launcher_version.txt" -p "manifest.json" -p "SHA256SUMS.txt" \
  || { echo "== TÉLÉCHARGEMENT ECHEC"; exit 1; }
# Fichiers vérifiés contre les sommes publiées de la snapshot.
( cd "$OUT" && sha256sum -c --ignore-missing SHA256SUMS.txt ) || { echo "== SOMMES DE LA SNAPSHOT NON CONFORMES"; exit 1; }
mv "$OUT/ClaudeOfDutyZombie-$SNAP.exe" "$OUT/ClaudeOfDutyZombie-$STABLE.exe"
mv "$OUT/manifest.json" "$OUT/manifest.snapshot.json"
"$GODOT" --headless --log-file "$LOGS/promote_manifest.log" --path . -s res://tools/manifest.gd -- \
    --promote="$(W "$PWD")/$OUT/manifest.snapshot.json" --version="$STABLE" --out="$(W "$PWD")/$OUT/manifest.json" | grep "\[manifest\]"
[ -s "$OUT/manifest.json" ] || { echo "== MANIFESTE ECHEC"; exit 1; }
rm -f "$OUT/manifest.snapshot.json" "$OUT/SHA256SUMS.txt"
FILES="ClaudeOfDutyZombie-$STABLE.exe ClaudeOfDutyZombie-Launcher.exe CallOfClaudeZombie-Launcher.exe launcher_version.txt manifest.json"
( cd "$OUT" && sha256sum $FILES ) > "$OUT/SHA256SUMS.txt"

echo "== notes des joueurs"
"$GODOT" --headless --log-file "$LOGS/promote_notes.log" --path . -s res://tools/changelog_merge.gd -- --promote="$SNAP" --stable="$STABLE" | grep "\[changelog\]"
COMMIT=$(git rev-list -n 1 "$SNAP")
NOTES="$OUT/notes.md"
{
  echo "**Canal : stable** — promue depuis \`$SNAP\` (même build, déjà testée en snapshot)."
  echo
  [ -f build/player_notes.md ] && head -1 build/player_notes.md | grep -q "<!-- $STABLE -->" && tail -n +2 build/player_notes.md
  echo "---"
  echo "Le plus simple : télécharger \`ClaudeOfDutyZombie-Launcher.exe\` et le lancer : il installe"
  echo "et met à jour le jeu tout seul. Sinon, télécharger \`ClaudeOfDutyZombie-$STABLE.exe\` ci-dessous"
  echo "et le lancer (Windows 64 bits, aucune installation). Multijoueur : même version pour tous, port UDP 7777."
  echo "Intégrité : \`SHA256SUMS.txt\` donne la somme SHA-256 de chaque fichier (vérifiée par le lanceur)."
} > "$NOTES"
"$GH" release create "$STABLE" "$OUT/ClaudeOfDutyZombie-$STABLE.exe" "$OUT/ClaudeOfDutyZombie-Launcher.exe" \
    "$OUT/CallOfClaudeZombie-Launcher.exe" "$OUT/launcher_version.txt" "$OUT/manifest.json" "$OUT/SHA256SUMS.txt" \
    --target "$COMMIT" --latest --title "$STABLE — version stable" --notes-file "$NOTES" || { echo "== PUBLICATION ECHEC"; exit 1; }
if ! git diff --quiet -- changelogs/changelogs.json; then
  git add changelogs/changelogs.json
  git commit -q -m "docs: player notes for $STABLE (stable, promoted from $SNAP)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- changelogs/changelogs.json
  git push -q origin HEAD:main || echo "== notes committées mais PUSH ECHEC (à pousser)"
fi
echo "== stable publiée : $STABLE (depuis $SNAP)"
