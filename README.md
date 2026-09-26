# Call of Claude Zombie

FPS coopératif de survie aux zombies, low-poly et horrifique, réalisé avec
**Godot 4.7.2** (GDScript, rendu Forward+). Solo ou coop réseau (hôte / client
par adresse IP, 2 à 8 joueurs). Tous les graphismes et tous les sons sont
**procéduraux** : aucun asset externe.

Carte : **BUNKER K-7** — salle de garde, couloir des cellules (piège électrique),
laboratoire, dortoir, générateur, quai du téléporteur et salle du rituel
(Pack-a-Punch). Manches, points, portes payantes, courant, achats muraux,
5 atouts, boîte mystère, Pack-a-Punch, téléporteur, pièges, état « à terre »
et réanimation. Fenêtres barricadées (15) : les zombies arrachent les
6 planches puis enjambent ; maintenir [F] pour reconstruire (+10 par planche,
500 points au plus par manche). Couteau à la BO1 (150 dégâts, fente vers le
zombie visé) et COUTEAU DE CHASSE au mur du quai (3000 : un coup jusqu'à la
manche 12).

## Lancer le jeu

1. Installer Godot 4.7.2 standard (ex. `winget install GodotEngine.GodotEngine`).
2. Première fois : `godot --headless --path . --import`
3. Jouer : `godot --path .` (ou ouvrir le projet dans l'éditeur et F5).

Les sons sont déjà générés dans `assets/audio/`. Pour les régénérer :
`godot --headless --path . -s res://tools/gen_audio.gd`.

## Builds Windows (.exe)

- Chaque fonctionnalité livrée est publiée en **release GitHub** (onglet Releases
  du dépôt) avec un `CallOfClaudeZombie-vX.Y.N.exe` autonome : le télécharger et le
  lancer, aucune installation. Tous les joueurs d'une partie doivent avoir la même
  version.
- Construire localement : `sh tools/release.sh --local` (nécessite les modèles
  d'export Godot 4.7.2 : éditeur > Éditeur > Gérer les modèles d'export). Résultat :
  `build/CallOfClaudeZombie.exe` (+ copie versionnée).
- Publier : `sh tools/release.sh` (commit poussé sur `main`, `gh` connecté).

## Commandes

| Action | Touche |
|---|---|
| Se déplacer | ZQSD / WASD (touches physiques) |
| Sauter / S'accroupir / Sprint | Espace / Ctrl ou C / Maj |
| S'allonger / Plonger | maintenir Ctrl ou C à l'arrêt / Ctrl ou C en sprintant |
| Tirer / Viser | Clic gauche / Clic droit |
| Recharger / Couteau (fente si un zombie visé est à ~3 m) | R / V |
| Changer d'arme | 1, 2, molette |
| Interagir (acheter, réanimer : maintenir) | F ou E |
| Tableau des scores | Tab (maintenu) |
| Pause | Échap |

## Multijoueur

- **Héberger** : MULTIJOUEUR > HÉBERGER UNE PARTIE (port 7777 par défaut). Le salon
  affiche l'IP locale et le port à communiquer.
- **Rejoindre** : MULTIJOUEUR > REJOINDRE UNE PARTIE, saisir l'IPv4 et le port.
- ENet utilise **UDP** : autoriser le port dans le pare-feu de l'hôte.
- Le serveur (hôte) fait autorité sur tout ce qui est critique (dégâts,
  zombies, points, achats, portes, manches...). Voir `docs/ARCHITECTURE.md`.

## Développement

- Architecture et conventions : `docs/ARCHITECTURE.md`.
- `sh tools/check.sh` : import, compilation de tous les scripts, tests unitaires,
  test réseau, tous les scénarios automatisés (fenêtres), tests multijoueur à
  deux fenêtres. **Doit passer avant chaque commit.**
- `sh tools/commit.sh message.txt` : lance check.sh et ne committe que s'il réussit.
- `sh tools/ship.sh message.txt` : commit vérifié, push sur `main`, puis build `.exe`
  et release GitHub (voir ci-dessous).
- `sh tools/perf.sh` : mesures de performance fiables (1080p, un jeu à la fois).
  Repère : ~150 fps sur la RTX A2000 de développement ≈ 60 fps sur GTX 1050.
- `sh tools/mp_test.sh <nom>` : un test multijoueur (hôte + client).
- Scénario isolé : `godot --path . -- --autotest=<nom>` (captures dans
  `tests/_out/shots/`).

## État d'avancement

Commits de fonctionnalités jusqu'au gameplay multijoueur complet. Travaux en
cours au moment de ce README (branches d'agents ou à reprendre) :
- menu principal complet (OPTIONS, CRÉDITS) et ambiance « horreur militaire »
  du menu ;
- presets de qualité graphique et optimisation du rendu ;
- optimisation du système de zombies et du réseau ;
- finitions visuelles ;
- `tests/autotest/long_endurance.gd` : investigation en cours (voir l'en-tête
  du fichier).
