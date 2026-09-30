#!/bin/bash
# Audit des avertissements GDScript (docs/REFACTORING_PLAN.md, étape 1).
# Godot n'affiche les avertissements que dans l'éditeur ; réglés sur « erreur »
# dans project.godot, ils deviennent des erreurs d'analyse visibles sans
# fenêtre. On le fait dans une COPIE du projet (sources jamais modifiées) :
#   1. copie (comme tools/coverage.sh) ;
#   2. chaque avertissement de la liste passe en erreur (valeur 2) ;
#   3. compilation de tous les scripts (tests/parse_all.gd) ;
#   4. bilan : nombre par avertissement et par fichier
#      (tests/_out/warnings/summary.txt, détail dans details.txt).
# Les avertissements déjà à zéro sont ensuite réglés sur « erreur » dans le
# vrai project.godot : toute nouvelle occurrence fait échouer le check.
# Usage : sh tools/warnings.sh [avertissement ...]   (défaut : liste ci-dessous)
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
SRC=$PWD
OUT=$SRC/tests/_out/warnings
COPY=$(cygpath -u "${TEMP:-/tmp}/claude_of_duty_warn" 2>/dev/null || echo /tmp/claude_of_duty_warn)
W() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
mkdir -p "$OUT" "$SRC/tests/_out/logs"
LIST=${*:-"unused_variable unused_local_constant unused_private_class_variable unused_parameter unused_signal
  shadowed_variable shadowed_variable_base_class shadowed_global_identifier unreachable_code unreachable_pattern
  standalone_expression standalone_ternary incompatible_ternary integer_division narrowing_conversion
  static_called_on_instance redundant_await assert_always_true assert_always_false confusable_identifier
  inference_on_variant native_method_override get_node_default_without_onready onready_with_export
  return_value_discarded untyped_declaration unsafe_property_access unsafe_method_access unsafe_cast
  unsafe_call_argument unsafe_void_return int_as_enum_without_cast int_as_enum_without_match enum_variable_without_default"}

echo "== copie du projet"
rm -rf "$COPY"; mkdir -p "$COPY"
tar -C "$SRC" --exclude=./.git --exclude=./tests/_out --exclude=./build \
    --exclude=./tools/piper --exclude=./tools/tts --exclude=./override.cfg \
    -cf - . | tar -C "$COPY" -xf - || { echo "== ECHEC (copie)"; exit 1; }
# Section [debug] : les avertissements demandés passent en erreur.
KEYS=$(for K in $LIST; do printf 'gdscript/warnings/%s=2\\n' "$K"; done)
if grep -q '^\[debug\]$' "$COPY/project.godot"; then
  sed -i "s|^\[debug\]$|[debug]\n\n$KEYS|" "$COPY/project.godot"
else
  printf '\n[debug]\n\n%b' "$KEYS" >> "$COPY/project.godot"
fi
# Une clé déjà présente plus bas l'emporterait : on retire les anciennes valeurs.
for K in $LIST; do
  awk -v k="gdscript/warnings/$K=" 'index($0, k) == 1 { if (seen[k]++) next } { print }' "$COPY/project.godot" > "$COPY/p.tmp" && mv "$COPY/p.tmp" "$COPY/project.godot"
done

echo "== compilation (avertissements = erreurs)"
"$GODOT" --headless --log-file "$(W "$SRC")/tests/_out/logs/warn_import.log" --path "$(W "$COPY")" --import > "$OUT/import.log" 2>&1
"$GODOT" --headless --log-file "$(W "$SRC")/tests/_out/logs/warn_parse.log" --path "$(W "$COPY")" -s res://tests/parse_all.gd > "$OUT/parse.log" 2>&1
# « SCRIPT ERROR: Parse Error: <message> (Warning treated as error.) » puis
# « at: GDScript::reload (res://<fichier>:<ligne>) ».
awk '
  /Warning treated as error/ { msg = $0; sub(/^.*Parse Error: /, "", msg); sub(/ \(Warning treated as error\.\).*$/, "", msg); want = 1; next }
  want && /at: GDScript::reload/ { loc = $0; sub(/^.*\(res:\/\//, "", loc); sub(/\).*$/, "", loc); print loc "\t" msg; want = 0 }
' "$OUT/parse.log" | sort -u > "$OUT/details.txt"
# Type d'avertissement déduit du message (formulations de Godot 4.7).
classify() {
  awk -F'\t' '{
    m = $2; t = "autre"
    if (m ~ /declared but never used in the block/) t = "unused_variable"
    else if (m ~ /local constant .* never used/) t = "unused_local_constant"
    else if (m ~ /private class variable/) t = "unused_private_class_variable"
    else if (m ~ /parameter .* never used/) t = "unused_parameter"
    else if (m ~ /signal .* declared but never/) t = "unused_signal"
    else if (m ~ /shadowing|shadows/) t = "shadowed_*"
    else if (m ~ /Unreachable code/) t = "unreachable_code"
    else if (m ~ /Unreachable pattern/) t = "unreachable_pattern"
    else if (m ~ /Standalone expression/) t = "standalone_expression"
    else if (m ~ /Standalone ternary/) t = "standalone_ternary"
    else if (m ~ /Integer division/) t = "integer_division"
    else if (m ~ /Narrowing conversion/) t = "narrowing_conversion"
    else if (m ~ /static function .* called on an instance|called on an instance/) t = "static_called_on_instance"
    else if (m ~ /await/) t = "redundant_await"
    else if (m ~ /return value .* discarded|discarded/) t = "return_value_discarded"
    else if (m ~ /has no static type|no return type|not have a (static )?type|untyped/) t = "untyped_declaration"
    else if (m ~ /property .* not present on the inferred type|is not present on the inferred type .*property/) t = "unsafe_property_access"
    else if (m ~ /method .* not present on the inferred type/) t = "unsafe_method_access"
    else if (m ~ /Casting a .Variant/) t = "unsafe_cast"
    else if (m ~ /argument .* requires the subtype|Variant.* passed/) t = "unsafe_call_argument"
    else if (m ~ /inferred from a Variant|Variant/) t = "inference_on_variant"
    else if (m ~ /enum/) t = "int_as_enum_*"
    print t "\t" $1
  }' "$OUT/details.txt"
}
{
  echo "Avertissements GDScript (réglés sur erreur dans une copie) — $(date '+%Y-%m-%d %H:%M')"
  echo "Total : $(wc -l < "$OUT/details.txt")"
  echo
  echo "Par avertissement :"
  classify | cut -f1 | sort | uniq -c | sort -rn
  echo
  echo "Par dossier :"
  cut -f1 "$OUT/details.txt" | sed 's/:[0-9]*$//' | awk -F/ '{ d = ($2 == "game" && NF > 3) ? $1 "/" $2 "/" $3 : $1 "/" $2; print d }' | sort | uniq -c | sort -rn
} > "$OUT/summary.txt"
cat "$OUT/summary.txt"
N_OTHER=$(grep -c "SCRIPT ERROR" "$OUT/parse.log")
echo "(lignes SCRIPT ERROR dans la compilation : $N_OTHER, détail : $OUT/details.txt)"
rm -rf "$COPY"
