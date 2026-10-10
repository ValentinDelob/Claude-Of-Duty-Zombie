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

**BUNKER K-7** (carte de test) — salle de garde, couloir des cellules (piège
électrique), laboratoire, dortoir, générateur, quai du téléporteur et salle
d'arrivée. Manches, ferraille, portes payantes, courant, caisse au hasard,
téléporteur, pièges, état « à terre » et réanimation. Fenêtres barricadées
(15) : les zombies arrachent les 6 planches puis enjambent ; maintenir [F]
pour reconstruire (sans gain). Couteau à la BO1 (150 dégâts, fente vers le
zombie visé). Emplacement de grenade ([G], maintenir pour cuire la grenade) :
2 grenades au départ, +2 par manche, 4 au plus.

**Caisse au hasard** (GAME_CONCEPT.md §4.12 bis ; une seule par carte, fixe) :
950 ferraille le tirage. Elle ne donne que des objets à lancer ou à poser, qui
vont sur l'emplacement de grenade : grenade ou PELUCHE LEURRE (posée, sa
musique attire les zombies, puis elle explose). Seul l'acheteur peut prendre
l'objet ([F], 12 s) : il remplit l'emplacement (4 au plus) et remplace ce
qu'il contenait.

**Ferraille** (monnaie de partie, GAME_CONCEPT.md §4.8) : chaque joueur part
de 0 et gagne 50 ferraille par zombie qu'il tue lui-même, quel que soit le
coup (rien pour les touches, les réanimations ni les planches) ; elle paie
les portes et la caisse. PV des zombies linéaires : 150 + 100 par manche.

**CARTES PERSO** — faites avec l'**ÉDITEUR DE CARTES** du menu principal
(pièces vues de dessus, portes entre pièces collées, fenêtres, courant,
pièges, caisse... posés depuis un inventaire façon Minecraft, vérification façon BO1,
bouton TESTER) ; les cartes jouables apparaissent dans l'écran SOLO et dans
le salon multijoueur de l'hôte : les invités la téléchargent automatiquement
(vérifiée chez chacun), la partie démarre quand tout le monde l'a. Voir
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
- Chaque fonctionnalité livrée est publiée en **snapshot** (release GitHub en
  préversion, seulement les paquets qui ont changé, pour le lanceur) ; les
  versions **stables** joignent aussi un `ClaudeOfDutyZombie-vX.Y.Z.exe` autonome :
  le télécharger et le lancer, aucune installation. Tous les joueurs d'une partie
  doivent avoir la même version. Détails : `docs/RELEASE.md`.
- Construire localement : `sh tools/release.sh --local` (nécessite les modèles
  d'export Godot 4.7.2 : éditeur > Éditeur > Gérer les modèles d'export). Résultat :
  paquets dans `build/packs/`, `build/manifest.json` et le lanceur
  `build/ClaudeOfDutyZombie-Launcher.exe`.
- Publier : `sh tools/release.sh` (commit poussé sur `main`, `gh` connecté).

### Journaux et rapports de plantage

En cas de problème, ces fichiers aident à comprendre ce qui s'est passé
(à joindre à un signalement) :

- **Jeu** : journaux dans `%APPDATA%\Godot\app_userdata\Call of Claude Zombie\logs\`
  (`godot.log` = partie en cours, les précédents sont datés), gardés au moins
  14 jours (200 Mo au plus).
- **Plantages** : si le jeu s'est arrêté brutalement (plantage, fermeture
  forcée, coupure), le lancement suivant enregistre un rapport dans
  `%APPDATA%\Godot\app_userdata\Call of Claude Zombie\crashes\`
  (`plantage_<date>.txt` : version, heure, dernier écran, dernières lignes ;
  `plantage_<date>.log` : journal complet de la session), gardé 30 jours. Un
  message discret au menu principal indique où il se trouve (bouton « Ouvrir
  le dossier »).
- **Lanceur** : même chose dans `%APPDATA%\CallOfClaudeZombieLauncher\logs\` et
  `...\crashes\` (message sous l'état du lanceur).

Collez le chemin dans la barre d'adresse de l'Explorateur Windows pour ouvrir
le dossier.

## Commandes

Par défaut, une seule touche et un seul bouton de manette par action (le
tableau ci-dessous) ; chaque action en accepte deux de chaque (voir plus
bas). Manettes Xbox et PlayStation (et toute manette reconnue en disposition
standard), branchées à chaud.

| Action | Clavier / souris | Manette Xbox | Manette PlayStation |
|---|---|---|---|
| Se déplacer | ZQSD / WASD (touches physiques) | stick gauche (progressif) | stick gauche |
| Regarder | souris | stick droit | stick droit |
| Sauter | Espace | A | Croix |
| S'accroupir (maintenir à l'arrêt : s'allonger ; en sprintant : plonger) | C | B | Rond |
| Sprint | Maj (maintenu) | LS (un clic : sprint tant qu'on avance, comme BO1) | L3 |
| Tirer / Viser | Clic gauche / Clic droit | RT / LT | R2 / L2 |
| Retenir sa respiration (lunette du L96A1, de la Dragunov) | Maj (maintenu, 4 s au plus) | LS (maintenu) | L3 (maintenu) |
| Recharger | R | RB | R1 |
| Couteau (fente si un zombie visé est à ~3 m) | V | RS | R3 |
| Grenade ou peluche leurre (grenade : maintenir = cuire, relâcher = lancer) | G (touche physique) | LB | L1 |
| Arme suivante | Q (A en AZERTY), molette (haut / bas) | Y | Triangle |
| Arme en main 1 / 2 / 3 | 1 / 2 / 3 | croix gauche / bas / droite | flèches gauche / bas / droite |
| Inventaire de partie (échanger une arme en main avec une arme rangée ; la partie continue) | I (Échap ferme) | croix haut (B ferme) | flèche haut (Rond ferme) |
| Interagir (acheter, réanimer : maintenir) | F | X | Carré |
| Tableau des scores | Tab (maintenu) | Back (maintenu) | Share / Create (maintenu) |
| Pause (REPRENDRE, OPTIONS, QUITTER LA PARTIE) | Échap | Start | Options |

Les invites (« Appuyer sur F pour acheter… ») montrent le bouton de la
manette (« Appuyer sur X », « Press SQUARE ») dès qu'elle sert, et reviennent
à la touche dès qu'on touche au clavier ou à la souris. Une action à deux
touches (ou deux boutons) montre la première. Les noms Xbox ou
PlayStation suivent le nom de la manette branchée.

Dans les menus, à la manette : croix directionnelle ou stick gauche pour se
déplacer, A / Croix pour valider, B / Rond pour revenir, LB / RB (L1 / R1)
pour changer d'onglet dans les options.

Toutes ces commandes (sauf Échap et Start / Options) se réaffectent dans
**OPTIONS > COMMANDES**, depuis le menu principal ou en pleine partie
(Échap > OPTIONS) : deux colonnes, CLAVIER / SOURIS et MANETTE, de deux cases
chacune (◄ / ► choisissent la case) : deux touches et deux boutons au plus
par action, la deuxième case est vide par défaut. Clic, Entrée ou A sur une
case, puis la nouvelle touche, bouton de souris ou cran de molette (haut,
bas, gauche, droite), ou le nouveau bouton, gâchette ou direction du stick
gauche. Échap annule ; dans la colonne clavier, B annule aussi ; dans la
colonne manette, Start / Options annule (B se réaffecte). Retour arrière ou
X / Carré efface la case (la deuxième remonte si la première est effacée).
Exemple : le couteau sur V et sur la molette vers le bas. Un cran de molette
affecté à une action ne change plus d'arme (l'autre sens, si). Un cran de
molette est un appui bref : un coup de couteau, un saut, une recharge, une
grenade lancée par cran.
Une même commande peut servir à plusieurs actions (par exemple F pour
INTERAGIR et RECHARGER) : l'affecter ne la retire d'aucune autre action, et un
appui les déclenche toutes. La case l'indique en petit, en or (« AUSSI :
COUTEAU »), et la barre d'aide nomme les autres actions quand la case est
choisie ; pour ne la garder que sur une action, effacez-la sur l'autre ligne.
Avec la même touche pour RECHARGER et INTERAGIR, devant un objet utilisable
(porte, caisse, courant…) l'appui sert à l'objet et ne recharge pas, comme
X / Carré dans BO1 sur console ; ailleurs il recharge. Mise dans l'autre case
de la même action, une commande change de case. « Rétablir les commandes par
défaut » remet les deux colonnes (aucune commande partagée).
Enregistré dans `settings.cfg` (les fichiers de la version à une commande
par action se relisent tels quels ; les anciens fichiers à deux touches
d'origine, d'avant la manette, gardent la première).

## Options

OPTIONS (menu principal, ou Échap > OPTIONS en jeu : partie suspendue en solo
comme dans BO1, en multijoueur la partie continue mais votre survivant ne
bouge plus tant que le menu est ouvert). Onglets (◄ / ►, ou Page préc. /
Page suiv.) :

- **JEU** : nom du joueur, LANGUE / LANGUAGE (interface des options et du menu
  pause, voix des personnages).
- **COMMANDES** : sensibilité de la souris, de la manette (stick droit), en visée, inversion de
  l'axe vertical (souris et manette), réaffectation des touches et des boutons de manette.
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
- Sécurité (modèle de menace, règles pour les RPC, les fichiers et le chargement
  de ressources, vérifications du lanceur) : `docs/SECURITY.md`.
- Concevoir une carte avec l'**éditeur de cartes** (menu principal > ÉDITEUR
  DE CARTES, ou `godot --path . res://scenes/editor/map_editor.tscn`, ou
  `tools/map_editor.bat`) : pièces vues de dessus, inventaire façon Minecraft,
  vérification façon BO1, bouton TESTER ; cinq JSON lisibles dans
  `user://maps/<id>/` ou une archive .zip. Voir `docs/MAP_AUTHORING.md`.
  Une IA (Claude Code ou tout client MCP HTTP) peut piloter l'éditeur : le
  jeu est lui-même le serveur MCP (127.0.0.1:7791, jeton), sans les sources
  ni Python ; éditeur > Collaboration > Connecter une IA (MCP)… donne la
  commande à copier. Voir `docs/MCP.md`.
  Vérifier une carte sans fenêtre :
  `godot --headless --path . res://scenes/editor/map_editor.tscn -- --check=<dossier>`.
- `sh tools/check.sh` : vérification avant commit. Par défaut, seules les
  tâches **impactées** par les fichiers modifiés depuis leur dernier succès sont
  relancées (carte des dépendances `tools/test_deps.gd`) ; `--full` relance
  tout. Scénarios et multijoueur **sans rendu** et en **temps de jeu accéléré**
  (`--headless --fixed-fps 60`) ; seuls les tests `## @rendu` ouvrent une
  fenêtre, réduite puis hors des écrans (jamais visible). Un échec est rejoué
  une fois (signalé INSTABLE s'il passe). Rapport JUnit `tests/_out/junit.xml`.
  Réglages : `JOBS=3`, `GUI_JOBS=1` (peu de jeux ouverts, machine silencieuse),
  `SCENARIOS="grenades melee"` / `MP="lobby"`, `--fast`, `--cartes`, `--no-retry`.
  Stratégie, niveaux et écriture des tests : **docs/TESTING.md**.
- `sh tools/commit.sh message.txt` : lance check.sh (tâches impactées) et ne
  committe que s'il réussit (`CHECK_ARGS=--full` pour tout vérifier).
- `sh tools/ship.sh message.txt` : commit avec check **complet**, push sur
  `main`, puis build `.exe` et release GitHub (voir ci-dessous) ;
  `tools/release.sh` refuse de publier sans check complet réussi sur ce contenu.
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
release GitHub (.exe). Livré : règles BO1 (manches, ferraille), une carte de
test (BUNKER K-7), fenêtres barricadées, arsenal BO1, caisse au hasard
(grenades, peluches leurres), chiens de l'enfer, rampants et démembrement,
sons CC0, refonte visuelle BO1 (étalonnage, HUD, zombies, armes et mains),
réseau optimisé. Atouts, armes murales, bonus au sol, Pack-a-Punch et armes
merveilles ont été retirés (nouvelle direction, GAME_CONCEPT.md).
Liste de tâches vivante et reste à faire : [docs/PLAN.md](docs/PLAN.md) ;
reprise sur une autre machine : [docs/HANDOFF.md](docs/HANDOFF.md).
