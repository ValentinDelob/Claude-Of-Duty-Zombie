#!/bin/bash
# Promotion d'une snapshot validée en STABLE (docs/RELEASE.md § 5) :
#   sh tools/promote.sh v0.2.0-snapshot.180 [v0.2.0]
#   1. télécharge de la snapshot manifest.json et SHA256SUMS.txt (vérifiés) ;
#   2. lanceur : celui du manifeste (entrée « launcher », téléchargé depuis la
#      release qui le porte, somme vérifiée), ou celui joint à la snapshot pour
#      les snapshots sans entrée « launcher » (165 à 167) ;
#   3. jeu complet ClaudeOfDutyZombie-<stable>.exe pour les ANCIENS lanceurs
#      (ils ne savent installer qu'un exécutable complet ; les snapshots n'en
#      joignent plus) : exporté depuis le MÊME commit (worktree du tag), avec
#      le MÊME numéro de build que la snapshot, puis démarré (scénario boot,
#      fenêtre hors écran) avant d'être joint. Les paquets lus par les
#      nouveaux lanceurs ne sont PAS reconstruits : le manifeste pointe
#      toujours vers ceux de la snapshot ;
#   4. manifeste réécrit : numéro stable, canal stable ;
#   5. SHA256SUMS.txt ; release <stable> créée sur le même commit, marquée
#      « latest » (tous les lanceurs, anciens compris, la voient), avec le jeu
#      complet, le lanceur sous ses deux noms, launcher_version.txt, le
#      manifeste et les sommes ;
#   6. notes des joueurs : les snapshots depuis la stable précédente sont
#      rassemblées sous le numéro stable (changelogs/changelogs.json), commit
#      et push de ce seul fichier.
# DRY_RUN=1 : tout sauf la publication (fichiers dans build/promote) ; avec
# GH=<faux gh> et COMMIT=<sha>, essai entièrement hors ligne.
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
touch build/.gdignore
LOGS="$(W "$PWD")/tests/_out/logs"
REPO=$(sed -n 's/^const REPO := "\(.*\)"$/\1/p' launcher/scripts/releases.gd)
# COMMIT=<sha> (essai hors ligne avec un faux GH et DRY_RUN=1) : commit à la place du tag.
if [ -z "$COMMIT" ]; then
  git fetch -q --tags origin 2>/dev/null
  COMMIT=$(git rev-list -n 1 "$SNAP" 2>/dev/null)
fi
[ -n "$COMMIT" ] || { echo "== tag $SNAP introuvable (git fetch --tags)"; exit 1; }
# Champ du manifeste : mfield <fichier> <id> <champ> (id vide : le manifeste lui-même).
mfield() {
  "$GODOT" --headless --log-file "$LOGS/promote_get.log" --path . -s res://tools/manifest.gd -- \
      --get="$(W "$PWD")/$1" --id="$2" --field="$3" 2>/dev/null | grep "^=" | cut -c2-
}

echo "== manifeste de $SNAP"
"$GH" release download "$SNAP" -D "$OUT" -p "manifest.json" -p "SHA256SUMS.txt" || { echo "== TÉLÉCHARGEMENT ECHEC"; exit 1; }
mv "$OUT/SHA256SUMS.txt" "$OUT/snapshot.sums"
grep -q " [ *]manifest.json$" "$OUT/snapshot.sums" && ( cd "$OUT" && grep " [ *]manifest.json$" snapshot.sums | sha256sum -c --quiet ) \
  || { echo "== MANIFESTE DE LA SNAPSHOT NON CONFORME (somme)"; exit 1; }
mv "$OUT/manifest.json" "$OUT/manifest.snapshot.json"
BUILD=$(mfield "$OUT/manifest.snapshot.json" "" build)
GODOT_SNAP=$(mfield "$OUT/manifest.snapshot.json" engine godot)
GODOT_VER=$("$GODOT" --log-file "$LOGS/version.log" --version | sed -n 's/^\([0-9]*\.[0-9]*\.[0-9]*\)\..*/\1/p')
[ -n "$BUILD" ] || { echo "== numéro de build absent du manifeste"; exit 1; }
[ "$GODOT_SNAP" = "$GODOT_VER" ] || { echo "== Godot $GODOT_VER installé, la snapshot a été faite avec $GODOT_SNAP : même version requise"; exit 1; }

echo "== lanceur"
LAUNCHER_TSV=""
LVER=$(mfield "$OUT/manifest.snapshot.json" launcher version)
if [ -n "$LVER" ]; then
  LREL=$(mfield "$OUT/manifest.snapshot.json" launcher release)
  LNAME=$(mfield "$OUT/manifest.snapshot.json" launcher file)
  LSHA=$(mfield "$OUT/manifest.snapshot.json" launcher sha256)
  mkdir -p "$OUT/l"
  "$GH" release download "$LREL" -D "$OUT/l" -p "$LNAME" || { echo "== LANCEUR INTROUVABLE ($LREL/$LNAME)"; exit 1; }
  [ "$(sha256sum "$OUT/l/$LNAME" | cut -c1-64)" = "$LSHA" ] || { echo "== LANCEUR NON CONFORME (somme du manifeste)"; exit 1; }
  echo "   lanceur $LVER, publié avec $LREL"
else
  # Snapshot antérieure à l'entrée « launcher » : lanceur et numéro joints à la snapshot.
  mkdir -p "$OUT/l"
  "$GH" release download "$SNAP" -D "$OUT/l" -p "ClaudeOfDutyZombie-Launcher.exe" -p "launcher_version.txt" \
    || { echo "== LANCEUR DE LA SNAPSHOT INTROUVABLE"; exit 1; }
  for F in ClaudeOfDutyZombie-Launcher.exe launcher_version.txt; do
    grep -q " [ *]$F$" "$OUT/snapshot.sums" && ( cd "$OUT/l" && grep " [ *]$F$" ../snapshot.sums | sha256sum -c --quiet ) \
      || { echo "== $F DE LA SNAPSHOT NON CONFORME (somme)"; exit 1; }
  done
  LNAME=ClaudeOfDutyZombie-Launcher.exe; LREL=$SNAP
  LVER=$(tr -dc '0-9' < "$OUT/l/launcher_version.txt")
  LSHA=$(sha256sum "$OUT/l/$LNAME" | cut -c1-64)
  printf 'launcher\t%s\t%s\t%s\t%s\t\t%s\n' "$LNAME" "$LSHA" "$(wc -c < "$OUT/l/$LNAME" | tr -d ' ')" "$LREL" "$LVER" > "$OUT/launcher.tsv"
  LAUNCHER_TSV="--launcher=$(W "$PWD")/$OUT/launcher.tsv"
  echo "   lanceur $LVER joint à $SNAP (entrée « launcher » ajoutée au manifeste stable)"
fi
[ -n "$LVER" ] || { echo "== numéro du lanceur illisible"; exit 1; }
mv "$OUT/l/$LNAME" "$OUT/ClaudeOfDutyZombie-Launcher.exe"
# Ancien nom : les lanceurs publiés avant le changement de nom cherchent ce fichier.
cp "$OUT/ClaudeOfDutyZombie-Launcher.exe" "$OUT/CallOfClaudeZombie-Launcher.exe"
echo "$LVER" > "$OUT/launcher_version.txt"
rm -rf "$OUT/l"

echo "== jeu complet pour les anciens lanceurs (même commit, build $BUILD)"
FULL="$OUT/ClaudeOfDutyZombie-$STABLE.exe"
SRC=build/promote_src
# Seule reconstruction de la promotion (docs/RELEASE.md § 5) : export
# « Windows Desktop » du commit de la snapshot, dans un worktree à part, avec
# son numéro de build ; le dépôt courant n'est pas touché.
build_full() {
  local RC=0
  git worktree remove --force "$SRC" > /dev/null 2>&1; rm -rf "$SRC"
  git worktree add -q --detach "$SRC" "$COMMIT" || { echo "== WORKTREE ECHEC"; return 1; }
  # Cache d'import du dépôt principal (réimport des seuls fichiers qui diffèrent).
  [ -d .godot ] && cp -r .godot "$SRC/.godot"
  mkdir -p "$SRC/tests/_out" "$SRC/build"; touch "$SRC/tests/_out/.gdignore" "$SRC/build/.gdignore"
  sed -i "s/^config\/version=.*/config\/version=\"$BUILD\"/" "$SRC/project.godot"
  "$GODOT" --headless --log-file "$LOGS/promote_import.log" --path "$SRC" --import > "$OUT/import.log" 2>&1
  "$GODOT" --headless --log-file "$LOGS/promote_export.log" --path "$SRC" --export-release "Windows Desktop" "$(W "$PWD")/$FULL" > "$OUT/export.log" 2>&1
  if [ ! -s "$FULL" ] || grep -qE "SCRIPT ERROR|Parse Error" "$OUT/export.log"; then
    echo "== EXPORT DU JEU COMPLET ECHEC (voir $OUT/export.log)"; RC=1
  fi
  git worktree remove --force "$SRC" > /dev/null 2>&1 || rm -rf "$SRC"
  git worktree prune
  rm -f "$OUT/import.log"
  [ $RC -eq 0 ] && echo "   reconstruit depuis $COMMIT ($(( $(wc -c < "$FULL") / 1048576 )) Mo)"
  return $RC
}
if grep -q " [ *]ClaudeOfDutyZombie-$SNAP.exe$" "$OUT/snapshot.sums"; then
  # Snapshots d'avant ce changement (165 à 167) : leur jeu complet est repris tel quel.
  "$GH" release download "$SNAP" -D "$OUT" -p "ClaudeOfDutyZombie-$SNAP.exe" \
    && ( cd "$OUT" && grep " [ *]ClaudeOfDutyZombie-$SNAP.exe$" snapshot.sums | sha256sum -c --quiet ) \
    || { echo "== JEU COMPLET DE LA SNAPSHOT NON CONFORME"; exit 1; }
  mv "$OUT/ClaudeOfDutyZombie-$SNAP.exe" "$FULL"
  echo "   repris de $SNAP (aucune reconstruction)"
else
  build_full || exit 1
fi
# Démarrage vérifié : fenêtre sans focus, réduite puis hors écran (override.cfg
# lu à côté de l'exécutable), journaux dans tests/_out/logs.
printf '[display]\n\nwindow/size/no_focus=true\nwindow/size/mode=1\n' > "$OUT/override.cfg"
timeout 180 "./$FULL" --log-file "$LOGS/promote_smoke.log" --resolution 1280x720 -- --autotest=boot > "$OUT/smoke.log" 2>&1
rm -f "$OUT/override.cfg"
if ! grep -q "\[autotest\] fin : SUCCES" "$OUT/smoke.log" || grep -qE "SCRIPT ERROR" "$OUT/smoke.log"; then
  echo "== LE JEU COMPLET NE DÉMARRE PAS (voir $OUT/smoke.log)"; exit 1
fi
grep -q "Claude of Duty Zombie v$BUILD " "$OUT/smoke.log" || { echo "== LE JEU COMPLET N'A PAS LE NUMÉRO DE BUILD $BUILD"; exit 1; }

echo "== manifeste stable"
"$GODOT" --headless --log-file "$LOGS/promote_manifest.log" --path . -s res://tools/manifest.gd -- \
    --promote="$(W "$PWD")/$OUT/manifest.snapshot.json" --version="$STABLE" $LAUNCHER_TSV --out="$(W "$PWD")/$OUT/manifest.json" | grep "\[manifest\]"
[ -s "$OUT/manifest.json" ] || { echo "== MANIFESTE ECHEC"; exit 1; }
rm -f "$OUT/manifest.snapshot.json" "$OUT/snapshot.sums" "$OUT/launcher.tsv"
FILES="ClaudeOfDutyZombie-$STABLE.exe ClaudeOfDutyZombie-Launcher.exe CallOfClaudeZombie-Launcher.exe launcher_version.txt manifest.json"
( cd "$OUT" && sha256sum $FILES ) > "$OUT/SHA256SUMS.txt"
echo "== fichiers de $STABLE : $FILES SHA256SUMS.txt"
if [ "$DRY_RUN" = "1" ]; then echo "== DRY_RUN : rien n'est publié ($OUT)"; exit 0; fi

echo "== notes des joueurs"
"$GODOT" --headless --log-file "$LOGS/promote_notes.log" --path . -s res://tools/changelog_merge.gd -- --promote="$SNAP" --stable="$STABLE" | grep "\[changelog\]"
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
echo "== stable publiée : $STABLE (depuis $SNAP ; https://github.com/$REPO/releases/tag/$STABLE)"
