#!/bin/bash
# Construit et publie une SNAPSHOT du commit courant (docs/RELEASE.md) :
#   Version : v<M.m.p>-snapshot.<nombre de commits>  (M.m.p : config/version de
#             project.godot = la prochaine stable ; ex. v0.2.0-snapshot.180)
#   GitHub  : release « pre-release » (les anciens lanceurs ne la voient pas)
#   Fichiers publiés :
#     - ClaudeOfDutyZombie-<version>.exe      jeu complet (PCK intégré) : pour les
#                                             anciens lanceurs une fois promue en stable
#     - ClaudeOfDutyZombie-Launcher.exe (+ ancien nom CallOfClaudeZombie-Launcher.exe),
#       launcher_version.txt
#     - core-<sha8>.pck                       tout sauf les voix (toujours nouveau)
#     - vox-fr-<id>.pck, vox-en-<id>.pck      seulement si les répliques ont changé
#     - engine-<godot>.exe                    seulement si le moteur a changé
#     - manifest.json, SHA256SUMS.txt
#   Les paquets identiques à ceux de la release précédente ne sont pas republiés :
#   le manifeste pointe vers la release qui les porte déjà.
# Stable : tools/promote.sh <snapshot> (même build, sans rien reconstruire).
# Prérequis : modèles d'export Godot installés, `gh` connecté.
# Usage : sh tools/release.sh [--local]      (--local : build sans publication)
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
GH=${GH:-gh}
W() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
TARGET=$(sed -n 's/^config\/version="\([0-9]*\.[0-9]*\.[0-9]*\)".*/\1/p' project.godot)
[ -n "$TARGET" ] || { echo "== config/version de project.godot doit être M.m.p (ex. 0.2.0)"; exit 1; }
N=$(git rev-list --count HEAD)
TAG="v$TARGET-snapshot.$N"
BUILD="${TAG#v}"
mkdir -p tests/_out/logs
LOGS="$(W "$PWD")/tests/_out/logs"
GODOT_VER=$("$GODOT" --log-file "$LOGS/version.log" --version | sed -n 's/^\([0-9]*\.[0-9]*\.[0-9]*\)\..*/\1/p')
TEMPLATE="$APPDATA/Godot/export_templates/$GODOT_VER.stable/windows_release_x86_64.exe"
EXE=build/ClaudeOfDutyZombie.exe
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
rm -f build/ClaudeOfDutyZombie-v*.exe build/CallOfClaudeZombie-v*.exe build/CallOfClaudeZombie.exe \
      build/core-*.pck build/vox-*.pck build/engine-*.exe
rm -rf "$PK"; mkdir -p "$PK"

echo "== export $TAG"
# Le numéro de build est inscrit dans les paquets (menu, poignée de main
# réseau), puis project.godot est remis en état.
cp project.godot build/project.godot.bak
sed -i "s/^config\/version=.*/config\/version=\"$BUILD\"/" project.godot
"$GODOT" --headless --log-file "$LOGS/export.log" --path . --export-release "Windows Desktop" "$EXE" > build/export.log 2>&1
RC=$?
"$GODOT" --headless --log-file "$LOGS/export_core.log" --path . --export-pack "Core" "$(W "$PWD")/$PK/core.pck" > build/export_core.log 2>&1 || RC=1
cp build/project.godot.bak project.godot
if [ $RC -ne 0 ] || [ ! -s "$EXE" ] || [ ! -s "$PK/core.pck" ] || grep -qE "SCRIPT ERROR|Parse Error" build/export.log build/export_core.log; then
  echo "== EXPORT ECHEC (voir build/export.log, build/export_core.log)"; exit 1
fi
VEXE="build/ClaudeOfDutyZombie-$TAG.exe"
cp "$EXE" "$VEXE"
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
# Lanceur (launcher/, docs/LAUNCHER.md) : publié avec chaque version, avec son
# numéro (les lanceurs plus anciens se mettent à jour tout seuls).
LEXE=build/ClaudeOfDutyZombie-Launcher.exe
"$GODOT" --headless --log-file "$LOGS/export_launcher.log" --path launcher --export-release "Windows Desktop" "$PWD/$LEXE" > build/export_launcher.log 2>&1
if [ ! -s "$LEXE" ] || grep -qE "SCRIPT ERROR|Parse Error" build/export_launcher.log; then
  echo "== EXPORT DU LANCEUR ECHEC (voir build/export_launcher.log)"; exit 1
fi
# Ancien nom : les lanceurs publiés avant le changement de nom cherchent ce fichier.
cp "$LEXE" build/CallOfClaudeZombie-Launcher.exe
sed -n 's/^const LAUNCHER_VERSION := \([0-9]*\).*/\1/p' launcher/scripts/version.gd > build/launcher_version.txt

echo "== vérification du build (scénario boot, puis moteur + paquets)"
# Fenêtre sans focus, réduite puis hors écran (l'exécutable lit override.cfg
# à côté de lui ; voir tools/nofocus.sh). Journaux dans tests/_out/logs :
# jamais dans le dossier du joueur.
printf '[display]\n\nwindow/size/no_focus=true\nwindow/size/mode=1\n' > build/override.cfg
"./$EXE" --log-file "$LOGS/smoke_exe.log" --resolution 1280x720 -- --autotest=boot > build/smoke.log 2>&1
rm -f build/override.cfg
if ! grep -q "\[autotest\] fin : SUCCES" build/smoke.log || grep -qE "SCRIPT ERROR" build/smoke.log; then
  echo "== LE BUILD NE DÉMARRE PAS (voir build/smoke.log)"; exit 1
fi
# Installation en paquets telle que le lanceur la fait : moteur officiel +
# core au même nom (chargé tout seul) + répliques montées par Packs.
SM=build/smoke_packs; rm -rf "$SM"; mkdir -p "$SM"
cp "$PK/engine-$GODOT_VER.exe" "$SM/ClaudeOfDutyZombie.exe"; cp "$PK/core.pck" "$SM/ClaudeOfDutyZombie.pck"
timeout 180 "./$SM/ClaudeOfDutyZombie.exe" --headless --log-file "$LOGS/smoke_packs.log" -- --autotest=vox \
    --packs="$(W "$PWD")/$PK/vox-fr.pck,$(W "$PWD")/$PK/vox-en.pck" > build/smoke_packs.log 2>&1
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
# Release précédente qui a un manifeste : ses paquets identiques sont réutilisés.
PREV_M=""
if [ "$1" != "--local" ]; then
  for T in $("$GH" release list --limit 30 --json tagName --jq '.[].tagName' 2>/dev/null); do
    rm -rf build/prev_manifest; mkdir -p build/prev_manifest
    if "$GH" release download "$T" -p manifest.json -D build/prev_manifest > /dev/null 2>&1; then PREV_M=build/prev_manifest/manifest.json; break; fi
  done
fi
# Champ d'un fichier de l'ancien manifeste : prev_field <id> <champ>.
prev_field() {
  [ -n "$PREV_M" ] && "$GODOT" --headless --log-file "$LOGS/manifest_get.log" --path . -s res://tools/manifest.gd -- \
      --get="$(W "$PWD")/$PREV_M" --id="$1" --field="$2" 2>/dev/null | grep "^=" | cut -c2-
}
UPLOAD=""
# entry <id> <fichier local> <nom publié> <empreinte d'entrée> : ligne du manifeste (TSV).
entry() {
  local ID=$1 F=$2 NAME=$3 IN=$4 SHA SIZE REL
  SHA=$(sha256sum "$F" | cut -c1-64); SIZE=$(wc -c < "$F" | tr -d ' ')
  REL=$TAG
  if [ -n "$PREV_M" ] && [ -n "$IN" ] && [ "$(prev_field "$ID" inputs)" = "$IN" ]; then
    # Même contenu d'entrée que la release précédente : on garde SON fichier.
    NAME=$(prev_field "$ID" file); SHA=$(prev_field "$ID" sha256); SIZE=$(prev_field "$ID" size); REL=$(prev_field "$ID" release)
    echo "   $ID : inchangé, repris de $REL ($NAME)" >&2
  else
    cp "$F" "build/$NAME"; UPLOAD="$UPLOAD build/$NAME"
    echo "   $ID : nouveau ($NAME, $((SIZE / 1048576)) Mo)" >&2
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ID" "$NAME" "$SHA" "$SIZE" "$REL" "$IN" >> build/manifest.tsv
}
rm -f build/manifest.tsv
ENG_SHA=$(sha256sum "$PK/engine-$GODOT_VER.exe" | cut -c1-64)
entry engine "$PK/engine-$GODOT_VER.exe" "engine-$GODOT_VER.exe" "$ENG_SHA"
entry core "$PK/core.pck" "core-$(sha256sum "$PK/core.pck" | cut -c1-8).pck" ""
for L in fr en; do
  IN=$(tr -d '\r\n' < "$PK/vox-$L.pck.inputs")
  entry "vox-$L" "$PK/vox-$L.pck" "vox-$L-$(echo "$IN" | cut -c1-8).pck" "$IN"
done
"$GODOT" --headless --log-file "$LOGS/manifest.log" --path . -s res://tools/manifest.gd -- --make="$(W "$PWD")/build/manifest.tsv" \
    --version="$TAG" --channel=snapshot --build="$BUILD" --godot="$GODOT_VER" --out="$(W "$PWD")/build/manifest.json" | grep "\[manifest\]"
[ -s build/manifest.json ] || { echo "== MANIFESTE ECHEC"; exit 1; }

# Sommes SHA-256 de tous les fichiers publiés (docs/SECURITY.md) : le lanceur
# refuse d'installer le jeu, un paquet ou de se remplacer si la somme ne
# correspond pas. Calculées APRÈS les tests de démarrage (fichiers définitifs).
SUMS=build/SHA256SUMS.txt
FILES="ClaudeOfDutyZombie-$TAG.exe ClaudeOfDutyZombie-Launcher.exe CallOfClaudeZombie-Launcher.exe launcher_version.txt manifest.json"
for U in $UPLOAD; do FILES="$FILES $(basename "$U")"; done
( cd build && sha256sum $FILES ) > "$SUMS" || { echo "== SHA256SUMS ECHEC"; exit 1; }
N_FILES=$(echo $FILES | wc -w)
if [ "$(grep -cE '^[0-9a-f]{64} [ *][A-Za-z0-9._-]+$' "$SUMS")" != "$N_FILES" ]; then
  echo "== SHA256SUMS INVALIDE (voir $SUMS)"; exit 1
fi
echo "== build local : $VEXE, paquets dans $PK (sommes : $SUMS)"
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
  echo "Le plus simple : télécharger \`ClaudeOfDutyZombie-Launcher.exe\` et le lancer : il installe"
  echo "et met à jour le jeu tout seul (canal stable ou snapshot, choix de la version)."
  echo "Multijoueur : même version pour tous les joueurs, port UDP 7777."
  echo "Intégrité : \`SHA256SUMS.txt\` donne la somme SHA-256 de chaque fichier (vérifiée par le lanceur)."
} > "$NOTES"
"$GH" release create "$TAG" "$VEXE" "$LEXE" build/CallOfClaudeZombie-Launcher.exe build/launcher_version.txt build/manifest.json "$SUMS" $UPLOAD \
  --target "$(git rev-parse HEAD)" --prerelease --title "$TAG — $SUBJECT" --notes-file "$NOTES" || { echo "== PUBLICATION ECHEC"; exit 1; }
echo "== snapshot publiée : $TAG ($(echo $UPLOAD | wc -w) paquet(s) nouveau(x))"
