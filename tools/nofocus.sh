#!/bin/sh
# Fenêtres de test sans focus : les jeux lancés par les tests ne volent pas le
# focus clavier de l'utilisateur (display/window/size/no_focus, lu par Godot à
# la création de la fenêtre via override.cfg).
#   . tools/nofocus.sh   puis   nofocus_on / nofocus_off
# Imbrication sûre : seul l'appelant qui a créé le fichier le supprime.
NOFOCUS_OWNER=0
nofocus_on() {
  if [ ! -f override.cfg ]; then
    printf '; Généré par tools/nofocus.sh pendant les tests (ne pas committer).\n[display]\n\nwindow/size/no_focus=true\n' > override.cfg
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
