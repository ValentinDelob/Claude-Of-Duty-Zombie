#!/bin/bash
# Construit et publie une SNAPSHOT du commit courant (docs/RELEASE.md) :
#   Version : v<M.m.p>-snapshot.<nombre de commits>  (M.m.p : config/version de
#             project.godot = la prochaine stable ; ex. v0.2.0-snapshot.180)
#   GitHub  : release « pre-release » (les anciens lanceurs ne la voient pas)
#   Fichiers publiés (le strict nécessaire, docs/RELEASE.md § 5) :
#     - manifest.json, SHA256SUMS.txt          toujours
#     - core-<sha8>.pck                        tout sauf les voix (toujours nouveau)
#     - vox-fr-<id>.pck, vox-en-<id>.pck       seulement si les répliques ont changé
#     - engine-<godot>.exe                     seulement si le moteur a changé
#     - ClaudeOfDutyZombie-Launcher.exe,       seulement si le lanceur a changé
#       launcher_version.txt                   (sources de launcher/ ou version de Godot)
#   Tout fichier identique à celui de la release précédente n'est pas republié :
#   le manifeste pointe vers la release qui le porte déjà (entrées engine,
#   packs et launcher). Plus d'exécutable complet ni d'ancien nom du lanceur
#   dans les snapshots : seuls les anciens lanceurs en ont besoin, et ils ne
#   voient que les stables (tools/promote.sh les y ajoute).
# Stable : tools/promote.sh <snapshot>.
# Prérequis : modèles d'export Godot installés, `gh` connecté.
# Usage : sh tools/release.sh [--local]      (--local : build sans publication)
#   PREV_MANIFEST=<manifest.json> (avec --local) : essai hors ligne de la
#   réutilisation des fichiers d'une release précédente.
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
GH=${GH:-gh}
W() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
TARGET=$(sed -n 's/^config\/version="\([0-9]*\.[0-9]*\.[0-9]*\)".*/\1/p' project.godot)
[ -n "$TARGET" ] || { echo "== config/version de project.godot doit être M.m.p (ex. 0.2.0)"; exit 1; }
# Stable v$TARGET déjà publiée (promote.sh) : les snapshots visent la suivante.
if git rev-parse -q --verify "refs/tags/v$TARGET" > /dev/null || git ls-remote --exit-code --tags origin "refs/tags/v$TARGET" > /dev/null 2>&1; then
  echo "== la stable v$TARGET existe déjà : passer config/version de project.godot à la prochaine stable (ex. ${TARGET%.*}.$(( ${TARGET##*.} + 1 )))"; exit 1
fi
N=$(git rev-list --count HEAD)
TAG="v$TARGET-snapshot.$N"
BUILD="${TAG#v}"
REPO=$(sed -n 's/^const REPO := "\(.*\)"$/\1/p' launcher/scripts/releases.gd)
mkdir -p tests/_out/logs
LOGS="$(W "$PWD")/tests/_out/logs"
GODOT_VER=$("$GODOT" --log-file "$LOGS/version.log" --version | sed -n 's/^\([0-9]*\.[0-9]*\.[0-9]*\)\..*/\1/p')
TEMPLATE="$APPDATA/Godot/export_templates/$GODOT_VER.stable/windows_release_x86_64.exe"
PK=build/packs
mkdir -p build
touch build/.gdignore   # builds : jamais importés par Godot

# Publication : seulement si le dernier check COMPLET (tools/check.sh --full,
# lancé par tools/ship.sh) a réussi sur exactement ce contenu (même empreinte
# de toutes les tâches, hors tests propres à une carte : docs/TESTING.md).
if [ "$1" != "--local" ]; then
  "$GODOT" --headless --log-file "$LOGS/deps_release.log" --path . -s res://tools/test_deps.gd -- --out=tests/_out/deps_release > /dev/null 2>&1
  NOW=$(awk '$4 == "-" { print $1, $2 }' tests/_out/deps_release/tasks.txt 2>/dev/null | md5sum | cut -c1-32)
  if [ ! -s tests/_out/deps_release/tasks.txt ] || [ "$NOW" != "$(cat tests/_out/last_full_ok 2>/dev/null)" ]; then
    echo "== RELEASE REFUSÉE : pas de check complet réussi sur ce contenu (sh tools/check.sh --full)"; exit 1
  fi
fi

# Anciens builds : seuls ceux de cette version restent (tous sont sur GitHub).
rm -f build/ClaudeOfDutyZombie-v*.exe build/CallOfClaudeZombie-v*.exe build/CallOfClaudeZombie.exe build/ClaudeOfDutyZombie.exe \
      build/CallOfClaudeZombie-Launcher.exe build/launcher_version.txt build/manifest.json build/SHA256SUMS.txt \
      build/core-*.pck build/vox-*.pck build/engine-*.exe
rm -rf "$PK"; mkdir -p "$PK"

echo "== export $TAG"
# Le numéro de build est inscrit dans le paquet (menu, poignée de main
# réseau), puis project.godot est remis en état.
cp project.godot build/project.godot.bak
sed -i "s/^config\/version=.*/config\/version=\"$BUILD\"/" project.godot
"$GODOT" --headless --log-file "$LOGS/export_core.log" --path . --export-pack "Core" "$(W "$PWD")/$PK/core.pck" > build/export_core.log 2>&1
RC=$?
cp build/project.godot.bak project.godot
if [ $RC -ne 0 ] || [ ! -s "$PK/core.pck" ] || grep -qE "SCRIPT ERROR|Parse Error" build/export_core.log; then
  echo "== EXPORT ECHEC (voir build/export_core.log)"; exit 1
fi
for L in fr en; do
  "$GODOT" --headless --log-file "$LOGS/pack_vox_$L.log" --path . -s res://tools/pack_vox.gd -- --lang=$L --out="$(W "$PWD")/$PK/vox-$L.pck" | grep "\[vox\]"
  [ -s "$PK/vox-$L.pck" ] && [ -s "$PK/vox-$L.pck.inputs" ] || { echo "== PAQUET DES VOIX ($L) ECHEC"; exit 1; }
done
[ -s "$TEMPLATE" ] || { echo "== modèle d'export introuvable : $TEMPLATE"; exit 1; }
cp "$TEMPLATE" "$PK/engine-$GODOT_VER.exe"

echo "== vérification des paquets (types de fichiers, taille)"
PACK_OK=1
"$GODOT" --headless --log-file "$LOGS/pack_check_core.log" --path . -s res://tools/pack_check.gd -- --pck="$(W "$PWD")/$PK/core.pck" \
    --max-mb=40 --list="$(W "$PWD")/$PK/core.files.txt" > build/pack_check.log 2>&1 || PACK_OK=0
for L in fr en; do
  "$GODOT" --headless --log-file "$LOGS/pack_check_$L.log" --path . -s res://tools/pack_check.gd -- --pck="$(W "$PWD")/$PK/vox-$L.pck" \
      --vox --max-mb=60 >> build/pack_check.log 2>&1 || PACK_OK=0
done
grep "\[pack\]" build/pack_check.log
[ $PACK_OK -eq 1 ] || { echo "== PAQUET REFUSÉ : fichier parasite ou taille dépassée (voir build/pack_check.log)"; exit 1; }

echo "== export du lanceur"
# Lanceur (launcher/, docs/LAUNCHER.md) : exporté à chaque fois (test de
# démarrage), publié seulement s'il a changé (entrée « launcher » du manifeste).
LEXE=build/ClaudeOfDutyZombie-Launcher.exe
rm -f "$LEXE"
"$GODOT" --headless --log-file "$LOGS/export_launcher.log" --path launcher --export-release "Windows Desktop" "$PWD/$LEXE" > build/export_launcher.log 2>&1
if [ ! -s "$LEXE" ] || grep -qE "SCRIPT ERROR|Parse Error" build/export_launcher.log; then
  echo "== EXPORT DU LANCEUR ECHEC (voir build/export_launcher.log)"; exit 1
fi
LVER=$(sed -n 's/^const LAUNCHER_VERSION := \([0-9]*\).*/\1/p' launcher/scripts/version.gd)
[ -n "$LVER" ] || { echo "== LAUNCHER_VERSION illisible (launcher/scripts/version.gd)"; exit 1; }
# Empreinte d'entrée du lanceur : ses sources (hors tests), telles que git les
# enregistre (fins de ligne normalisées : même empreinte sur tous les postes),
# et la version de Godot (le modèle d'export fait l'exécutable).
LIN=$( { echo "godot $GODOT_VER"
  { git ls-files -- launcher; git ls-files -o --exclude-standard -- launcher; } | grep -v '^launcher/tests/' | LC_ALL=C sort -u | \
    while read -r F; do [ -f "$F" ] && echo "$F $(git hash-object "$F")"; done; } | sha256sum | cut -c1-64)

echo "== vérification du build (moteur + paquets, comme le lanceur l'installe)"
# Installation en paquets telle que le lanceur la fait : moteur officiel +
# core au même nom (chargé tout seul) + répliques montées par Packs.
SM=build/smoke_packs; rm -rf "$SM"; mkdir -p "$SM"
cp "$PK/engine-$GODOT_VER.exe" "$SM/ClaudeOfDutyZombie.exe"; cp "$PK/core.pck" "$SM/ClaudeOfDutyZombie.pck"
VOXARG="--packs=$(W "$PWD")/$PK/vox-fr.pck,$(W "$PWD")/$PK/vox-en.pck"
# 1. Scénario boot avec rendu : fenêtre sans focus, réduite puis hors écran
# (l'exécutable lit override.cfg à côté de lui ; voir tools/nofocus.sh).
# Journaux dans tests/_out/logs : jamais dans le dossier du joueur.
printf '[display]\n\nwindow/size/no_focus=true\nwindow/size/mode=1\n' > "$SM/override.cfg"
timeout 180 "./$SM/ClaudeOfDutyZombie.exe" --log-file "$LOGS/smoke_boot.log" --resolution 1280x720 -- --autotest=boot "$VOXARG" > build/smoke.log 2>&1
rm -f "$SM/override.cfg"
if ! grep -q "\[autotest\] fin : SUCCES" build/smoke.log || grep -qE "SCRIPT ERROR" build/smoke.log; then
  echo "== LE BUILD NE DÉMARRE PAS (voir build/smoke.log)"; exit 1
fi
grep -q "Claude of Duty Zombie v$BUILD " build/smoke.log || { echo "== NUMÉRO DE BUILD ABSENT DU PAQUET ($BUILD, voir build/smoke.log)"; exit 1; }
# 2. Répliques lues depuis les paquets des voix (sans rendu).
timeout 180 "./$SM/ClaudeOfDutyZombie.exe" --headless --log-file "$LOGS/smoke_packs.log" -- --autotest=vox "$VOXARG" > build/smoke_packs.log 2>&1
if ! grep -q "\[autotest\] fin : SUCCES" build/smoke_packs.log || ! grep -q "\[Packs\] paquet monté : vox-fr.pck" build/smoke_packs.log; then
  echo "== LE JEU EN PAQUETS NE DÉMARRE PAS (voir build/smoke_packs.log)"; exit 1
fi
rm -rf "$SM"
# Lanceur : démarre hors écran, sans focus, sans réseau, capture puis se ferme.
printf '[display]\n\nwindow/size/no_focus=true\n' > build/override.cfg
rm -f build/launcher_smoke.png
timeout 60 "./$LEXE" --log-file "$LOGS/smoke_launcher.log" --position -20000,-20000 -- --offline --capture="$PWD/build/launcher_smoke.png" > build/launcher_smoke.log 2>&1
rm -f build/override.cfg
if [ ! -s build/launcher_smoke.png ] || grep -qE "SCRIPT ERROR" build/launcher_smoke.log; then
  echo "== LE LANCEUR NE DÉMARRE PAS (voir build/launcher_smoke.log)"; exit 1
fi

echo "== manifeste"
# Release précédente qui a un manifeste : ses fichiers identiques sont réutilisés.
PREV_M=""
if [ "$1" != "--local" ]; then
  for T in $("$GH" release list --limit 30 --json tagName --jq '.[].tagName' 2>/dev/null); do
    rm -rf build/prev_manifest; mkdir -p build/prev_manifest
    if "$GH" release download "$T" -p manifest.json -D build/prev_manifest > /dev/null 2>&1; then PREV_M=build/prev_manifest/manifest.json; break; fi
  done
elif [ -n "$PREV_MANIFEST" ]; then
  PREV_M=$PREV_MANIFEST
  echo "   (essai : release précédente simulée par $PREV_M)"
fi
# Champ d'un fichier de l'ancien manifeste : prev_field <id> <champ>.
prev_field() {
  [ -n "$PREV_M" ] && "$GODOT" --headless --log-file "$LOGS/manifest_get.log" --path . -s res://tools/manifest.gd -- \
      --get="$(W "$PWD")/$PREV_M" --id="$1" --field="$2" 2>/dev/null | grep "^=" | cut -c2-
}
UPLOAD=""
# entry <id> <fichier local> <nom publié> <empreinte d'entrée> [numéro] : ligne du manifeste (TSV).
# REUSED=1 quand le fichier de la release précédente est repris.
entry() {
  local ID=$1 F=$2 NAME=$3 IN=$4 VER=$5 SHA SIZE REL
  SHA=$(sha256sum "$F" | cut -c1-64); SIZE=$(wc -c < "$F" | tr -d ' ')
  REL=$TAG; REUSED=0
  if [ -n "$PREV_M" ] && [ -n "$IN" ] && [ "$(prev_field "$ID" inputs)" = "$IN" ]; then
    # Même contenu d'entrée que la release précédente : on garde SON fichier.
    NAME=$(prev_field "$ID" file); SHA=$(prev_field "$ID" sha256); SIZE=$(prev_field "$ID" size); REL=$(prev_field "$ID" release)
    [ -n "$VER" ] && VER=$(prev_field "$ID" version)
    REUSED=1
    echo "   $ID : inchangé, repris de $REL ($NAME)" >&2
  else
    [ "$F" -ef "build/$NAME" ] || cp "$F" "build/$NAME"
    UPLOAD="$UPLOAD build/$NAME"
    echo "   $ID : nouveau ($NAME, $((SIZE / 1048576)) Mo)" >&2
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ID" "$NAME" "$SHA" "$SIZE" "$REL" "$IN" "$VER" >> build/manifest.tsv
}
rm -f build/manifest.tsv
ENG_SHA=$(sha256sum "$PK/engine-$GODOT_VER.exe" | cut -c1-64)
entry engine "$PK/engine-$GODOT_VER.exe" "engine-$GODOT_VER.exe" "$ENG_SHA"
entry core "$PK/core.pck" "core-$(sha256sum "$PK/core.pck" | cut -c1-8).pck" ""
for L in fr en; do
  IN=$(tr -d '\r\n' < "$PK/vox-$L.pck.inputs")
  entry "vox-$L" "$PK/vox-$L.pck" "vox-$L-$(echo "$IN" | cut -c1-8).pck" "$IN"
done
# Lanceur : un lanceur modifié doit porter un numéro plus grand (sinon les
# lanceurs installés ne le verraient pas) ; jamais un numéro plus petit.
PREV_LVER=$(prev_field launcher version)
if [ -n "$PREV_LVER" ] && [ "$(prev_field launcher inputs)" != "$LIN" ] && [ "$LVER" -le "$PREV_LVER" ]; then
  echo "== LANCEUR MODIFIÉ sans LAUNCHER_VERSION augmenté ($LVER, déjà publié : $PREV_LVER) : launcher/scripts/version.gd"; exit 1
fi
entry launcher "$LEXE" "ClaudeOfDutyZombie-Launcher.exe" "$LIN" "$LVER"
LAUNCHER_NEW=$((1 - REUSED))
LREL=$(awk -F'\t' '$1 == "launcher" { print $5 }' build/manifest.tsv)
LNAME=$(awk -F'\t' '$1 == "launcher" { print $2 }' build/manifest.tsv)
LVER_M=$(awk -F'\t' '$1 == "launcher" { print $7 }' build/manifest.tsv)
if [ $LAUNCHER_NEW -eq 1 ]; then
  # Lanceur publié : aussi son numéro, pour les lanceurs 7 et plus anciens du
  # canal snapshot (ils ne lisent que launcher_version.txt de la dernière release).
  echo "$LVER" > build/launcher_version.txt
  UPLOAD="$UPLOAD build/launcher_version.txt"
fi
"$GODOT" --headless --log-file "$LOGS/manifest.log" --path . -s res://tools/manifest.gd -- --make="$(W "$PWD")/build/manifest.tsv" \
    --version="$TAG" --channel=snapshot --build="$BUILD" --godot="$GODOT_VER" --out="$(W "$PWD")/build/manifest.json" | grep "\[manifest\]"
[ -s build/manifest.json ] || { echo "== MANIFESTE ECHEC"; exit 1; }

# Sommes SHA-256 de tous les fichiers publiés (docs/SECURITY.md) : le lanceur
# refuse d'installer le jeu, un paquet ou de se remplacer si la somme ne
# correspond pas. Calculées APRÈS les tests de démarrage (fichiers définitifs).
SUMS=build/SHA256SUMS.txt
FILES="manifest.json"
for U in $UPLOAD; do FILES="$FILES $(basename "$U")"; done
( cd build && sha256sum $FILES ) > "$SUMS" || { echo "== SHA256SUMS ECHEC"; exit 1; }
N_FILES=$(echo $FILES | wc -w)
if [ "$(grep -cE '^[0-9a-f]{64} [ *][A-Za-z0-9._-]+$' "$SUMS")" != "$N_FILES" ]; then
  echo "== SHA256SUMS INVALIDE (voir $SUMS)"; exit 1
fi
TOTAL=$(for F in $FILES SHA256SUMS.txt; do wc -c < "build/$F"; done | awk '{ s += $1 } END { printf "%.1f", s / 1048576 }')
echo "== build local : $((N_FILES + 1)) fichier(s) à publier, $TOTAL Mo ($FILES SHA256SUMS.txt)"
echo "   lanceur $LVER_M : $([ $LAUNCHER_NEW -eq 1 ] && echo "publié avec $TAG" || echo "repris de $LREL")"
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
  echo "**Canal : snapshot** (préversion : chaque nouveauté dès sa sortie). Les versions stables sont promues depuis une snapshot validée."
  echo
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
  echo "Le plus simple : télécharger le lanceur [\`$LNAME\`](https://github.com/$REPO/releases/download/$LREL/$LNAME)"
  echo "(joint à la release \`$LREL\`) et le lancer : il installe et met à jour le jeu tout seul"
  echo "(canal stable ou snapshot, choix de la version). Cette snapshot ne joint que ce qui a changé."
  echo "Multijoueur : même version pour tous les joueurs, port UDP 7777."
  echo "Intégrité : \`SHA256SUMS.txt\` donne la somme SHA-256 de chaque fichier (vérifiée par le lanceur)."
} > "$NOTES"
"$GH" release create "$TAG" build/manifest.json "$SUMS" $UPLOAD \
  --target "$(git rev-parse HEAD)" --prerelease --title "$TAG — $SUBJECT" --notes-file "$NOTES" || { echo "== PUBLICATION ECHEC"; exit 1; }
echo "== snapshot publiée : $TAG ($N_FILES fichier(s) + sommes, $TOTAL Mo)"
