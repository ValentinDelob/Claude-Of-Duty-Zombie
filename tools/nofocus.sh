#!/bin/sh
# Fenêtres de test invisibles pour l'utilisateur : les jeux lancés par les
# tests démarrent RÉDUITS et SANS FOCUS (override.cfg lu par Godot à la
# création de la fenêtre), puis l'autotest les déplace hors de tous les écrans
# avant de les restaurer (Autotest._move_offscreen). Elles rendent normalement
# (captures, mesures) mais n'apparaissent jamais par-dessus le bureau.
#   . tools/nofocus.sh   puis   nofocus_on / nofocus_off
# Imbrication sûre : seul l'appelant qui a créé le fichier le supprime.
# AUTOTEST_ONSCREEN=1 : fenêtres visibles (débogage).
NOFOCUS_OWNER=0
nofocus_on() {
  if [ ! -f override.cfg ]; then
    if [ "$AUTOTEST_ONSCREEN" = "1" ]; then
      printf '; Généré par tools/nofocus.sh pendant les tests (ne pas committer).\n[display]\n\nwindow/size/no_focus=true\n' > override.cfg
    else
      printf '; Généré par tools/nofocus.sh pendant les tests (ne pas committer).\n[display]\n\nwindow/size/no_focus=true\nwindow/size/mode=1\n' > override.cfg
    fi
    NOFOCUS_OWNER=1
    trap 'nofocus_off' EXIT INT TERM
  fi
}
nofocus_off() {
  if [ "$NOFOCUS_OWNER" = "1" ]; then
    rm -f override.cfg
    NOFOCUS_OWNER=0
  fi
}
