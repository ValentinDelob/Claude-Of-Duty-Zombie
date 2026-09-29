# Lanceur et notes de version

## Pour le joueur

`ClaudeOfDutyZombie-Launcher.exe` (pièce jointe de chaque release GitHub) :

- **Mise à jour automatique** : à l'ouverture, la dernière version du jeu est
  téléchargée si elle n'est pas déjà installée (barre de progression en bas).
- **Choix de la version** (comme le lanceur de Minecraft) : « Dernière version »
  (suit toujours la plus récente) ou n'importe quelle version publiée ; le choix
  est mémorisé. ✓ = version installée ; SUPPRIMER libère sa place.
- **Notes de version** de la version sélectionnée : titre, nouveautés en quelques
  puces écrites pour les joueurs, captures (clic pour agrandir).
- **JOUER** : lance la version choisie (après son téléchargement si besoin) et
  ferme le lanceur.
- Français ou anglais (menu en haut à droite) ; hors ligne, seules les versions
  installées sont proposées.
- Le lanceur se met à jour lui-même quand un lanceur plus récent est publié.

Versions installées : `%LOCALAPPDATA%\CallOfClaudeZombie\versions\<version>\CallOfClaudeZombie.exe`.
Réglages du lanceur : `%APPDATA%\CallOfClaudeZombieLauncher\launcher.cfg`. Les
réglages et le dossier de combat du jeu restent communs à toutes les versions.

## Fonctionnement

- Projet Godot séparé : `launcher/` (rendu Compatibilité, ignoré par le projet du
  jeu, exclu de son export). Scripts : `main.gd` (interface et déroulé),
  `releases.gd` (API GitHub, ordre des versions, notes), `store.gd` (versions
  installées, réglages), `texts.gd` (français / anglais), `version.gd`
  (`LAUNCHER_VERSION`).
- Versions : API publique `https://api.github.com/repos/ValentinDelob/Claude-Of-Duty-Zombie/releases`
  (le `.exe` du jeu de chaque release).
- Notes : `changelogs/changelogs.json` et `changelogs/img/` du dépôt, lus sur
  `raw.githubusercontent.com` (branche main) et gardés en cache pour le hors ligne.
- Mise à jour du lanceur : chaque release porte `ClaudeOfDutyZombie-Launcher.exe`
  et `launcher_version.txt` ; un lanceur plus ancien télécharge le nouveau, le
  remplace après sa fermeture (petit script `.bat`) et le relance.
- Sécurité (détails : `docs/SECURITY.md`, « Ce que le lanceur vérifie ») :
  HTTPS vers les seuls domaines GitHub (redirections revérifiées), réponses
  bornées, numéros de version et noms de fichiers filtrés, notes échappées ;
  chaque release publie `SHA256SUMS.txt` et le lanceur vérifie la somme du jeu
  (téléchargé en `.part`, renommé seulement s'il est conforme) et de sa propre
  mise à jour. Anciennes releases sans sommes : taille vérifiée seulement ;
  release récente sans sommes : refusée.
- Tests : `godot --headless --path launcher -s res://tests/test_launcher.gd`
  (tâche `launcher:tests` de `tools/check.sh`) ; la release démarre aussi le
  lanceur exporté hors écran (`--offline --capture=...`).
- Options de test : `--capture=<png>`, `--changelogs=<json local>`, `--offline`,
  `--quit-after-update`.

## Écrire les notes d'une nouvelle version

À chaque fonctionnalité livrée, avant `tools/ship.sh` :

1. Créer `changelogs/next/next.json` :
   ```json
   {"title": {"fr": "Titre court", "en": "Short title"},
    "items": [{"fr": "Ce que le joueur découvre.", "en": "What the player discovers."}]}
   ```
   Puces concises, pour les joueurs : nouveautés, cartes, armes, sons, confort de
   jeu, corrections gênantes en jeu ; **jamais** de détails techniques (fichiers,
   tests, outils, refactorisation). Français et anglais écrits nativement.
2. Ajouter à côté les captures (`.jpg` de préférence, 1280 × 720 au plus), triées
   par nom.
3. `tools/commit.sh` (appelé par `tools/ship.sh`) range ces notes sous le numéro
   de la version que le commit va devenir (`tools/changelog_merge.gd`) et
   `tools/release.sh` les place en tête de la page de la release.

Quand le lanceur change, augmenter `LAUNCHER_VERSION` dans `launcher/scripts/version.gd`.
