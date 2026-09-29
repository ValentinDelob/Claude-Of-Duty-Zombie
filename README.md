# Claude of Duty Zombie

FPS coopératif de survie aux zombies, low-poly et horrifique, réalisé avec
**Godot 4.7.2** (GDScript, rendu Forward+). Solo ou coop réseau (hôte / client
par adresse IP, 2 à 8 joueurs). Tous les graphismes sont **procéduraux**
(aucune image externe). Les bruitages (armes, impacts, grenades, chiens, joueur, barricades, voix
des zombies) sont des enregistrements **libres de droits (CC0)** retravaillés
(liste, auteurs et licences : [docs/ASSETS.md](docs/ASSETS.md)) ; musiques,
ambiances, annonces et interface restent synthétisées par du code.

Cartes (SOLO ouvre l'écran de sélection ; en multijoueur, l'hôte choisit dans
le salon ; le dernier choix est mémorisé) :

**KINO** — Kino der Toten à l'échelle 1, sur plusieurs niveaux (carte en
maillage construite dans Blender, voir [docs/KINO_V2.md](docs/KINO_V2.md)) :
hall d'entrée à double escalier et balcon (départ sur le disque du poste
central, Olympia et M14), salle basse et ruelle, arrière-salle surélevée,
salle haute, Foyer à mezzanine, loges, coulisses (courant), salle de théâtre
en ruines (fauteuils, gravats, scène, écran qui projette un film une fois le
courant rétabli) et salle de projection (Pack-a-Punch). Les deux boucles de
portes de BO1 (750 / 1000 / 1250), portes du couloir et rideau de scène
ouverts par le courant, 22 fenêtres barricadées, arsenal mural de Kino
(dont MP40 et couteau de chasse), 4 atouts, boîte mystère à 9 emplacements
(départ tiré au sort parmi 8) et tableaux à la craie qui l'indiquent,
5 pièges à deux leviers (40 s, dont la fosse à feu encore électrique).
Téléporteur de Kino : gratuit, activer le pad de la scène puis le relier au
poste central ; 30 s en salle de projection, retour sur le disque, 90 s de
recharge.

**BUNKER K-7** — salle de garde, couloir des cellules (piège électrique),
laboratoire, dortoir, générateur, quai du téléporteur et salle du rituel
(Pack-a-Punch). Manches, points, portes payantes, courant, achats muraux,
7 atouts, boîte mystère, Pack-a-Punch, téléporteur, pièges, état « à terre »
et réanimation. Atouts de Five / Ascension (BUNKER K-7 seulement) : NOVA FLOP
(2000 : aucun dégât de ses propres explosions, le plongeon en sprint explose
à l'atterrissage) et DEADEYE DRAM (1500 : la visée s'aimante vers la tête,
dispersion en hanche et recul réduits). Fenêtres barricadées (15) : les zombies arrachent les
6 planches puis enjambent ; maintenir [F] pour reconstruire (+10 par planche,
500 points au plus par manche). Couteau à la BO1 (150 dégâts, fente vers le
zombie visé) et COUTEAU DE CHASSE au mur du quai (3000 : un coup jusqu'à la
manche 12). Grenades à fragmentation ([G] : 2 au départ, +2 par manche, 4 au
plus, achat mural à 250) et SINGE-TAMBOUR ([Q], boîte mystère) qui attire
tous les zombies avant d'exploser. Arme merveille TONNERRE-7 (boîte mystère, rare, une seule dans la partie) : onde de choc qui projette et tue tous les zombies devant soi.

**CARTES PERSO** — faites avec l'**ÉDITEUR DE CARTES** du menu principal
(pièces vues de dessus, portes entre pièces collées, fenêtres, atouts, armes,
boîte... posés depuis un inventaire façon Minecraft, vérification façon BO1,
bouton TESTER) ; les cartes jouables apparaissent dans l'écran SOLO. Voir
[docs/MAP_AUTHORING.md](docs/MAP_AUTHORING.md).

## Lancer le jeu

1. Installer Godot 4.7.2 standard (ex. `winget install GodotEngine.GodotEngine`).
2. Première fois : `godot --headless --path . --import`
3. Jouer : `godot --path .` (ou ouvrir le projet dans l'éditeur et F5).

Les sons sont déjà dans `assets/audio/`. Pour régénérer les sons procéduraux :
`godot --headless --path . -s res://tools/gen_audio.gd` (les sons importés
sont ignorés). Pour réimporter les sons CC0 (téléchargement des sources avec
curl, puis traitement et mise à l'intensité perçue de leur catégorie) : `godot --headless --path . -s res://tools/audio/sfx_import.gd` ; `-- --loudness` affiche le rapport LUFS par catégorie.

## Builds Windows (.exe)

- **Lanceur** (le plus simple) : `ClaudeOfDutyZombie-Launcher.exe`, joint à chaque
  release. Il télécharge et met à jour le jeu tout seul, permet de choisir la
  version et montre les notes de chaque version avec des captures ; JOUER lance
  le jeu. Voir `docs/LAUNCHER.md`.
- Chaque fonctionnalité livrée est publiée en **release GitHub** (onglet Releases
  du dépôt) avec un `ClaudeOfDutyZombie-vX.Y.N.exe` autonome : le télécharger et le
  lancer, aucune installation. Tous les joueurs d'une partie doivent avoir la même
  version.
- Construire localement : `sh tools/release.sh --local` (nécessite les modèles
  d'export Godot 4.7.2 : éditeur > Éditeur > Gérer les modèles d'export). Résultat :
  `build/ClaudeOfDutyZombie.exe` (+ copie versionnée).
- Publier : `sh tools/release.sh` (commit poussé sur `main`, `gh` connecté).

## Commandes

| Action | Touche |
|---|---|
| Se déplacer | ZQSD / WASD (touches physiques) |
| Sauter / S'accroupir / Sprint | Espace / Ctrl ou C / Maj |
| S'allonger / Plonger | maintenir Ctrl ou C à l'arrêt / Ctrl ou C en sprintant |
| Tirer / Viser | Clic gauche / Clic droit |
| Retenir sa respiration (lunette du L96A1, de la Dragunov) | Maj (maintenu, 4 s au plus) |
| Recharger / Couteau (fente si un zombie visé est à ~3 m) | R / V |
| Grenade (maintenir = cuire, relâcher = lancer) / SINGE-TAMBOUR | G / Q (touches physiques) |
| Changer d'arme | 1, 2, molette |
| Interagir (acheter, réanimer : maintenir) | F ou E |
| Tableau des scores | Tab (maintenu) |
| Pause (REPRENDRE, OPTIONS, QUITTER LA PARTIE) | Échap |

Toutes ces touches (sauf Échap) se réaffectent dans **OPTIONS > COMMANDES**,
depuis le menu principal ou en pleine partie (Échap > OPTIONS) : clic ou
Entrée sur une action, puis la nouvelle touche ou le bouton de souris (Échap
annule, Retour arrière efface) ; deux touches par action ; une touche déjà
prise est retirée de l'autre action (message affiché) ; « Rétablir les touches
par défaut ». Enregistré dans `settings.cfg`.

## Options

OPTIONS (menu principal, ou Échap > OPTIONS en jeu : partie suspendue en solo
comme dans BO1, en multijoueur la partie continue mais votre survivant ne
bouge plus tant que le menu est ouvert). Onglets (◄ / ►, ou Page préc. /
Page suiv.) :

- **JEU** : nom du joueur, LANGUE / LANGUAGE (interface des options et du menu
  pause, voix des personnages).
- **COMMANDES** : sensibilité de la souris, sensibilité en visée, inversion de
  l'axe vertical, réaffectation des touches.
- **GRAPHISMES** : plein écran, synchro verticale, limite d'images par seconde
  (illimitée, 30, 60, 120, 144, 240), échelle de rendu 3D (50 à 100 %), qualité
  (basse, moyenne, haute), champ de vision, luminosité (gamma, comme BO1),
  grain de film.
- **SON** : volumes général, musique, effets.

Chaque réglage s'applique tout de suite et est enregistré.

## Multijoueur

- **Héberger** : MULTIJOUEUR > HÉBERGER UNE PARTIE (port 7777 par défaut). Le salon
  affiche l'IP locale et le port à communiquer.
- **Rejoindre** : MULTIJOUEUR > REJOINDRE UNE PARTIE, saisir l'IPv4 et le port.
- ENet utilise **UDP** : autoriser le port dans le pare-feu de l'hôte.
- Le serveur (hôte) fait autorité sur tout ce qui est critique (dégâts,
  zombies, points, achats, portes, manches...). Voir `docs/ARCHITECTURE.md`.

## Développement

- Architecture et conventions : `docs/ARCHITECTURE.md`.
- Concevoir une carte avec l'**éditeur de cartes** (menu principal > ÉDITEUR
  DE CARTES, ou `godot --path . res://scenes/editor/map_editor.tscn`, ou
  `tools/map_editor.bat`) : pièces vues de dessus, inventaire façon Minecraft,
  vérification façon BO1, bouton TESTER ; cinq JSON lisibles dans
  `user://maps/<id>/` ou une archive .zip. Voir `docs/MAP_AUTHORING.md`.
  Vérifier une carte sans fenêtre :
  `godot --headless --path . res://scenes/editor/map_editor.tscn -- --check=<dossier>`.
- `sh tools/check.sh` : import, compilation de tous les scripts, tests unitaires,
  test réseau, tous les scénarios automatisés et tous les tests multijoueur.
  **Doit passer avant chaque commit.** Tout tourne dans un pool de tâches
  parallèles (les plus longues d'abord, durées mémorisées dans
  `tests/_out/durations.txt`) ; les scénarios et tests multijoueur tournent
  **sans rendu** (`--headless`, aucune fenêtre) ; seuls ceux marqués
  `## @rendu` ouvrent une fenêtre, réduite puis déplacée hors des écrans (jamais
  visible). Un scénario long déclare `## @parts N` pour être découpé en N
  parties parallèles (`mine(i)` / `owns(k)` dans `tests/autotest/scenario.gd`).
  Réglages : `JOBS=3` (tâches simultanées, défaut : peu de jeux ouverts, machine
  silencieuse), `GUI_JOBS=1` (fenêtres de rendu, défaut),
  `SCENARIOS="perks scope"` / `MP="lobby"` (sous-ensemble), `--fast` (sans réseau).
- `sh tools/commit.sh message.txt` : lance check.sh et ne committe que s'il réussit.
- `sh tools/ship.sh message.txt` : commit vérifié, push sur `main`, puis build `.exe`
  et release GitHub (voir ci-dessous).
- `sh tools/blender.sh <script.py> [args]` : Blender sans fenêtre (modèles et
  architecture des cartes en maillage, voir docs/ARCHITECTURE.md).
- `sh tools/perf.sh` : mesures de performance fiables (1080p, un jeu à la fois).
  Repère : ~210 fps sur une GTX 1070 (~250 fps sur la RTX A2000 portable) ≈
  60 fps sur GTX 1050 ;
  `sh tools/perf.sh perf_costs` : coût GPU de chaque poste de rendu. Au premier
  lancement, le préréglage graphique est choisi automatiquement (carte + banc d'essai).
- `sh tools/mp_test.sh <nom>` : un test multijoueur (hôte + client, sans rendu ;
  `GUI=1` pour le rendu et les captures).
- Scénario isolé : `sh tools/scenario.sh <nom>` (rendu dans une fenêtre hors
  écran, captures dans `tests/_out/shots/`) ; `HEADLESS=1` : sans rendu, plus
  rapide ; `AUTOTEST_ONSCREEN=1` : fenêtre visible pour déboguer. Les fenêtres
  des outils (check, perf, release) démarrent réduites et sans focus
  (override.cfg temporaire, voir tools/nofocus.sh), puis l'autotest les place
  hors des écrans : elles n'apparaissent jamais par-dessus le bureau.

## État d'avancement

Clone de Black Ops 1 Zombies en cours ; chaque fonctionnalité est publiée en
release GitHub (.exe). Livré : règles BO1 (manches, points, atouts), deux
cartes (BUNKER K-7, KINO), fenêtres barricadées, arsenal BO1 et Pack-a-Punch,
armes merveilles, grenades et singe, bonus (dont FAUCHEUSE et Liquidation),
chiens de l'enfer, rampants et démembrement, 7 atouts, sons CC0, refonte
visuelle BO1 (étalonnage, HUD, zombies, armes et mains), réseau optimisé.
Liste de tâches vivante et reste à faire : [docs/PLAN.md](docs/PLAN.md) ;
reprise sur une autre machine : [docs/HANDOFF.md](docs/HANDOFF.md).
