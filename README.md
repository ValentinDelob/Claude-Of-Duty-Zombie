# Call of Claude Zombie

FPS coopératif de survie aux zombies, low-poly et horrifique, réalisé avec
**Godot 4.7.2** (GDScript, rendu Forward+). Solo ou coop réseau (hôte / client
par adresse IP, 2 à 8 joueurs). Tous les graphismes sont **procéduraux**
(aucune image externe). Les bruitages (armes, impacts, grenades, chiens, joueur, barricades, voix
des zombies) sont des enregistrements **libres de droits (CC0)** retravaillés
(liste, auteurs et licences : [docs/ASSETS.md](docs/ASSETS.md)) ; musiques,
ambiances, annonces et interface restent synthétisées par du code.

Cartes (SOLO ouvre l'écran de sélection ; en multijoueur, l'hôte choisit dans
le salon ; le dernier choix est mémorisé) :

**KINO** — théâtre abandonné inspiré de Kino der Toten : hall d'entrée à
galerie (poste central du téléporteur, M-14 et fusil à pompe au mur), foyer,
loges et allée (deux pièges électriques dans les passages étroits), salle des
machines (courant), salle de théâtre (fauteuils, scène, rideaux, écran qui
projette un film une fois le courant rétabli), cabine de projection. Comme à
Kino : activer la plateforme de la scène puis la relier au poste central avant
chaque voyage ; le premier voyage fait surgir le Pack-a-Punch sur la scène.
Boîte mystère : 5 emplacements, départ tiré au sort parmi 3.

**BUNKER K-7** — salle de garde, couloir des cellules (piège électrique),
laboratoire, dortoir, générateur, quai du téléporteur et salle du rituel
(Pack-a-Punch). Manches, points, portes payantes, courant, achats muraux,
7 atouts, boîte mystère, Pack-a-Punch, téléporteur, pièges, état « à terre »
et réanimation. Atouts de Five / Ascension (aussi sur KINO) : NOVA FLOP
(2000 : aucun dégât de ses propres explosions, le plongeon en sprint explose
à l'atterrissage) et DEADEYE DRAM (1500 : la visée s'aimante vers la tête,
dispersion en hanche et recul réduits). Fenêtres barricadées (15) : les zombies arrachent les
6 planches puis enjambent ; maintenir [F] pour reconstruire (+10 par planche,
500 points au plus par manche). Couteau à la BO1 (150 dégâts, fente vers le
zombie visé) et COUTEAU DE CHASSE au mur du quai (3000 : un coup jusqu'à la
manche 12). Grenades à fragmentation ([G] : 2 au départ, +2 par manche, 4 au
plus, achat mural à 250) et SINGE-TAMBOUR ([Q], boîte mystère) qui attire
tous les zombies avant d'exploser. Arme merveille TONNERRE-7 (boîte mystère, rare, une seule dans la partie) : onde de choc qui projette et tue tous les zombies devant soi.

## Lancer le jeu

1. Installer Godot 4.7.2 standard (ex. `winget install GodotEngine.GodotEngine`).
2. Première fois : `godot --headless --path . --import`
3. Jouer : `godot --path .` (ou ouvrir le projet dans l'éditeur et F5).

Les sons sont déjà dans `assets/audio/`. Pour régénérer les sons procéduraux :
`godot --headless --path . -s res://tools/gen_audio.gd` (les sons importés
sont ignorés). Pour réimporter les sons CC0 (téléchargement des sources avec
curl, puis traitement et mise à l'intensité perçue de leur catégorie) : `godot --headless --path . -s res://tools/audio/sfx_import.gd` ; `-- --loudness` affiche le rapport LUFS par catégorie.

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
| Retenir sa respiration (lunette du L96A1, de la Dragunov) | Maj (maintenu, 4 s au plus) |
| Recharger / Couteau (fente si un zombie visé est à ~3 m) | R / V |
| Grenade (maintenir = cuire, relâcher = lancer) / SINGE-TAMBOUR | G / Q (touches physiques) |
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
- Scénario isolé sans voler le focus : `sh tools/scenario.sh <nom>` (check.sh,
  mp_test.sh et release.sh ouvrent aussi leurs fenêtres sans focus, via un
  override.cfg temporaire : voir tools/nofocus.sh).
- Scénario isolé : `godot --path . -- --autotest=<nom>` (captures dans
  `tests/_out/shots/`).

## État d'avancement

Clone de Black Ops 1 Zombies en cours ; chaque fonctionnalité est publiée en
release GitHub (.exe). Livré : règles BO1 (manches, points, atouts), deux
cartes (BUNKER K-7, KINO), fenêtres barricadées, arsenal BO1 et Pack-a-Punch,
armes merveilles, grenades et singe, bonus (dont FAUCHEUSE et Liquidation),
chiens de l'enfer, rampants et démembrement, 7 atouts, sons CC0, refonte
visuelle BO1 (étalonnage, HUD, zombies, armes et mains), réseau optimisé.
Liste de tâches vivante et reste à faire : [docs/PLAN.md](docs/PLAN.md) ;
reprise sur une autre machine : [docs/HANDOFF.md](docs/HANDOFF.md).
