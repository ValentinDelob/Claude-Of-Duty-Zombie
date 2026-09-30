#!/bin/bash
# Profil CPU par fonction (docs/TESTING.md, niveau perf), sans toucher aux
# sources : copie du projet dans un dossier temporaire, instrumentation de la
# copie (tools/profile/instrument.gd : chaque _process / _physics_process et
# quelques fonctions chaudes), puis scénario perf_cpu sans rendu dans la copie.
# Sortie : lignes [cpu] (image complète), [prof] (ms par image et µs par appel
# de chaque fonction, temps inclusifs) et [micro] (micro-mesures).
# Un seul jeu à la fois, sans fenêtre.
# Usage : bash tools/profile.sh [scénario]      (défaut : perf_cpu)
#         PROF_DIR=<dossier> : emplacement de la copie
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
SRC=$PWD
SCEN=${1:-perf_cpu}
COPY=$(cygpath -u "${PROF_DIR:-${TEMP:-/tmp}/claude_of_duty_prof}" 2>/dev/null || echo "${PROF_DIR:-/tmp/claude_of_duty_prof}")
W() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
SRC_W=$(W "$SRC"); COPY_W=$(W "$COPY")
LOGS="$SRC_W/tests/_out/logs"; mkdir -p "$SRC/tests/_out/logs"
OUT="$SRC/tests/_out/profile_$SCEN.txt"

echo "== copie du projet ($COPY)"
rm -rf "$COPY"; mkdir -p "$COPY"
tar -C "$SRC" --exclude=./.git --exclude=./tests/_out --exclude=./build \
    --exclude=./tools/piper --exclude=./tools/tts --exclude=./override.cfg \
    -cf - . | tar -C "$COPY" -xf - || { echo "== PROFIL ECHEC (copie)"; exit 1; }
echo "== instrumentation"
"$GODOT" --headless --log-file "$LOGS/prof_instrument.log" --path "$SRC_W" \
    -s res://tools/profile/instrument.gd -- --dst="$COPY_W" | grep "\[prof\]"
echo "== import de la copie"
"$GODOT" --headless --log-file "$LOGS/prof_import.log" --path "$COPY_W" --import > /dev/null 2>&1
"$GODOT" --headless --log-file "$LOGS/prof_parse.log" --path "$COPY_W" -s res://tests/parse_all.gd > "$SRC/tests/_out/prof_parse.txt" 2>&1
grep -h "PARSE:" "$SRC/tests/_out/prof_parse.txt"
echo "== $SCEN (copie instrumentée, sans rendu)"
"$GODOT" --headless --fixed-fps 60 --log-file "$LOGS/prof_$SCEN.log" --path "$COPY_W" -- --autotest=$SCEN > "$OUT" 2>&1
RC=$?
grep -E "\[cpu\]|\[prof\]|\[micro\]|ECHEC|SCRIPT ERROR" "$OUT"
[ "$PROF_KEEP" = "1" ] || rm -rf "$COPY"
[ $RC -eq 0 ] && echo "== PROFIL OK ($OUT)" || echo "== PROFIL ECHEC ($OUT)"
exit $RC
