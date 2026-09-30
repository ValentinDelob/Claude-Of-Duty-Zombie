#!/bin/bash
# Couverture de code (GDScript n'en a pas nativement ; docs/TESTING.md § 4).
#   1. copie du projet (et du lanceur) dans un dossier temporaire, sans les
#      sorties de tests ni les builds ; le cache d'import est copié (pas de
#      réimport des assets) ;
#   2. instrumentation des scripts de la copie (tools/coverage/instrument.gd) :
#      un compteur par instruction ;
#   3. dans la copie : check COMPLET (tools/check.sh --full --kino --no-retry,
#      mêmes réglages de charge) ; chaque jeu vide ses compteurs en quittant ;
#   4. rapport (tools/coverage/report.gd) : tests/_out/coverage/ (résumé par
#      dossier, détail par fichier et par fonction, lignes jamais exécutées).
# Les sources ne sont jamais modifiées. Un test qui échoue dans la copie est
# signalé mais n'empêche pas le rapport.
# Usage : sh tools/coverage.sh            COV_KEEP=1 : garde la copie
#         COV_SKIP_RUN=1 sh tools/coverage.sh   rapport seul (compteurs déjà là)
#         COV_RATCHET=1 : relève les seuils (tools/coverage/floors.txt) au niveau atteint
#         COV_STRICT=1  : échec si un dossier passe sous son seuil
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
SRC=$PWD
OUT=$SRC/tests/_out/coverage
COPY=$(cygpath -u "${COV_DIR:-${TEMP:-/tmp}/claude_of_duty_cov}" 2>/dev/null || echo "${COV_DIR:-/tmp/claude_of_duty_cov}")
# Chemins passés à Godot (Windows : « C:/… », pas « /c/… »).
W() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
SRC_W=$(W "$SRC"); COPY_W=$(W "$COPY"); OUT_W=$(W "$OUT")
mkdir -p "$OUT" "$SRC/tests/_out/logs"
T_START=$(date +%s)
# Import des sources d'abord : cache des classes à jour (l'instrumenteur
# tourne dans le projet source).
"$GODOT" --headless --log-file "$(cygpath -m "$SRC" 2>/dev/null || echo "$SRC")/tests/_out/logs/cov_src_import.log" --path . --import > /dev/null 2>&1

if [ "$COV_SKIP_RUN" != "1" ]; then
  echo "== copie du projet ($COPY)"
  rm -rf "$COPY"; mkdir -p "$COPY"
  # Tout sauf .git, sorties, builds et outils lourds (voix, synthèse).
  tar -C "$SRC" --exclude=./.git --exclude=./tests/_out --exclude=./build \
      --exclude=./tools/piper --exclude=./tools/tts --exclude=./override.cfg \
      -cf - . | tar -C "$COPY" -xf - || { echo "== COUVERTURE ECHEC (copie)"; exit 1; }
  rm -rf "$OUT/raw"; mkdir -p "$OUT/raw"
  # Durées mémorisées : séries équilibrées comme dans le vrai check.
  mkdir -p "$COPY/tests/_out" && cp -f "$SRC/tests/_out/durations.txt" "$COPY/tests/_out/" 2>/dev/null

  echo "== instrumentation"
  "$GODOT" --headless --log-file "$SRC_W/tests/_out/logs/cov_instrument.log" --path "$SRC_W" \
      -s res://tools/coverage/instrument.gd -- --dst="$COPY_W" --roots=scripts \
      --map="$OUT_W/map_game.txt" --class="$COPY_W/scripts/cov_hits.gd" | grep "\[cov\]"
  N_GAME=$(wc -l < "$OUT/map_game.txt")
  "$GODOT" --headless --log-file "$SRC_W/tests/_out/logs/cov_instrument_l.log" --path "$SRC_W" \
      -s res://tools/coverage/instrument.gd -- --dst="$COPY_W/launcher" --roots=scripts \
      --map="$OUT_W/map_launcher.txt" --class="$COPY_W/launcher/scripts/cov_hits.gd" | grep "\[cov\]"
  # Vidage des compteurs à la sortie : autoload CovDump (jeu) ; les tests du
  # lanceur (script -s, sans autoload) vident avant quit().
  cat > "$COPY/scripts/cov_dump.gd" <<'EOF'
extends Node
## Copie instrumentée seulement : vide les compteurs de couverture en quittant.
func _exit_tree() -> void:
	var tag := "game"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			tag = "autotest"
	CovHits.dump(tag)
EOF
  sed -i 's/^\[autoload\]$/[autoload]\n\nCovDump="*res:\/\/scripts\/cov_dump.gd"/' "$COPY/project.godot"
  sed -i 's/^\tquit(1 if failures > 0 else 0)$/\tCovHits.dump("launcher")\n\tquit(1 if failures > 0 else 0)/' "$COPY/launcher/tests/test_launcher.gd"

  echo "== import de la copie (enregistre CovHits)"
  "$GODOT" --headless --log-file "$SRC_W/tests/_out/logs/cov_import.log" --path "$COPY_W" --import > "$OUT/import.log" 2>&1
  "$GODOT" --headless --log-file "$SRC_W/tests/_out/logs/cov_import_l.log" --path "$COPY_W/launcher" --import >> "$OUT/import.log" 2>&1
  # Compilation : une erreur ici vient de l'instrumentation (à corriger).
  "$GODOT" --headless --log-file "$SRC_W/tests/_out/logs/cov_parse.log" --path "$COPY_W" -s res://tests/parse_all.gd > "$OUT/parse.log" 2>&1
  grep -h "PARSE:" "$OUT/parse.log"
  if ! grep -q "PARSE: .* 0 en erreur" "$OUT/parse.log"; then
    grep -E "SCRIPT ERROR|Parse Error|erreur" "$OUT/parse.log" | head -20
    echo "== COUVERTURE ECHEC (la copie instrumentée ne compile pas, voir $OUT/parse.log)"; exit 1
  fi

  echo "== tests dans la copie instrumentée"
  ( cd "$COPY" && COV_OUT="$OUT_W/raw" JOBS=${JOBS:-3} GUI_JOBS=${GUI_JOBS:-1} \
      bash tools/check.sh --full --kino --no-retry > "$OUT/check.log" 2>&1 )
  grep -E "^== (durée|CHECK)" "$OUT/check.log"
  grep -E "^---- " "$OUT/check.log" | sed 's/^/   échec dans la copie : /'
fi

echo "== rapport"
"$GODOT" --headless --log-file "$SRC_W/tests/_out/logs/cov_report.log" --path "$SRC_W" \
    -s res://tools/coverage/report.gd -- --dir="$OUT_W" $([ "$COV_RATCHET" = "1" ] && echo --ratchet) | grep -vE "^Godot Engine|^$"
RC_REPORT=${PIPESTATUS[0]}
[ "$COV_KEEP" = "1" ] || rm -rf "$COPY"
echo "== couverture : $OUT/summary.md ($(( $(date +%s) - T_START )) s)"
exit $RC_REPORT
