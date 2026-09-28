# Reprise du travail — prompt à redonner à Claude

Copier TOUT le bloc ci-dessous dans une nouvelle session Claude Code ouverte à
la racine du dépôt cloné (`git clone git@github.com:ValentinDelob/Claude-Of-Duty-Zombie.git`).

```text
Tu reprends le développement de « Call of Claude Zombie », un CLONE de
Call of Duty: Black Ops 1 — mode Zombies, en Godot 4.7.2 (GDScript, Forward+).
Dépôt GitHub : ValentinDelob/Claude-Of-Duty-Zombie, branche main. Tout le texte
du jeu, les commentaires et les messages de commit sont en FRANÇAIS.

## 0. Objectif et demandes de l'utilisateur (à respecter en permanence)
- Reproduire au plus près BO1 Zombies (Kino der Toten, Five, Ascension) :
  menu, gameplay, rythme des manches, économie de points, prix, armes, atouts,
  boîte mystère, Pack-a-Punch, téléporteur, pièges, zombies, HUD, sons,
  ambiance. En cas de doute : fais comme BO1. Le « ressenti » compte autant
  que les tests : l'utilisateur joue chaque release et juge la fidélité.
- Réserve (cahier des charges) : ne pas copier le logo Call of Duty ni les
  assets graphiques d'Activision (textures, modèles, sons extraits du jeu).
  Noms d'atouts et d'armes merveilles ORIGINAUX (déjà en place) ; noms d'armes
  réelles autorisés (M1911, MP40, M14...).
- Sons : l'utilisateur AUTORISE les sons libres de droits (CC0, licence vérifiée
  pour chaque fichier, crédités dans docs/ASSETS.md et dans les CRÉDITS du
  jeu) quand le procédural est moins bon. Graphismes : procéduraux ou libres
  de droits ; images de référence de BO1 autorisées UNIQUEMENT comme modèle,
  stockées dans docs/reference/ (ignoré par git, jamais publiées).
- CHAQUE commit est poussé sur GitHub ET publié en release GitHub avec un
  .exe Windows (et copie locale dans build/) pour que l'utilisateur et ses
  amis testent chaque fonctionnalité.
- Les fenêtres de jeu des tests ne doivent JAMAIS apparaître au-dessus des
  fenêtres de l'utilisateur ni voler son focus (il travaille sur la même
  machine) : passe toujours par les outils ci-dessous (tests sans rendu en
  --headless ; sinon fenêtre réduite et sans focus via override.cfg, puis
  déplacée hors de tous les écrans par Autotest._move_offscreen).
- Les tests doivent rester RAPIDES (l'utilisateur s'est plaint de leur
  dérive) : check.sh complet ~3-5 min. Tout nouveau scénario : sans rendu par
  défaut (`## @rendu` seulement s'il lit des pixels ou mesure le rendu),
  attendre des événements (`until`) plutôt que des délais fixes, et découper
  en parties (`## @parts N`, `mine(i)`, `owns(k)`) s'il dépasse ~60 s.
- Utilise autant d'agents que nécessaire pour aller vite (voir §3), mais la
  machine varie (portable RTX A2000, 20 threads ; ou i7-7700 4c/8t, GTX 1070,
  16 Go, disque presque plein) : `JOBS=4` sur la petite machine.

## 1. Mise en place sur une nouvelle machine (Windows)
- Godot 4.7.2 : `winget install --id GodotEngine.GodotEngine -e` (vérifie avec
  `winget show GodotEngine.GodotEngine` qu'aucune version plus récente n'est
  sortie ; si oui, demande à l'utilisateur avant de changer de version).
  Wrapper Git Bash `~/bin/godot` :
    #!/bin/sh
    exec "$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe" "$@"
- Modèles d'export (nécessaires au .exe), SEULEMENT Windows (le paquet complet
  fait 1,3 Go) :
    mkdir -p "$APPDATA/Godot/export_templates/4.7.2.stable" && cd "$TEMP" &&
    curl -L -o tpl.tpz https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz &&
    unzip -o -q tpl.tpz 'templates/windows_*x86_64*' 'templates/version.txt' 'templates/icudt_godot.dat' -d tplx &&
    cp tplx/templates/* "$APPDATA/Godot/export_templates/4.7.2.stable/" && rm -rf tplx tpl.tpz
- GitHub CLI : `winget install --id GitHub.cli -e`, wrapper `~/bin/gh` vers
  "/c/Program Files/GitHub CLI/gh.exe", puis `gh auth status` (si non connecté,
  demande à l'utilisateur de lancer `gh auth login` lui-même ; clé SSH ou
  `gh auth setup-git` pour pousser).
- Blender (modèles de KINO V2, construits par scripts sans fenêtre) :
  `winget install --id BlenderFoundation.Blender -e` (5.2.1). Serveur MCP officiel
  « Blender Lab » (facultatif, pour inspecter une scène) : `winget install --id
  astral-sh.uv -e`, cloner https://projects.blender.org/lab/blender_mcp.git (tag
  v1.0.3), `uv tool install --python 3.12 <clone>/mcp`, construire l'extension
  (`blender --command extension build --source-dir <clone>/addon/blender_mcp_addon`)
  puis `blender --command extension install-file -r user_default -e mcp-1.0.3.zip`,
  et `claude mcp add blender --scope user -e BLENDER_PATH=<blender.exe> --
  <~/.local/bin/blender-mcp.exe>` ; lancer Blender avec `--online-mode`.
- `godot --headless --path . --import` (enregistre les class_name ; à refaire
  après tout nouveau fichier avec class_name ou tout reset de worktree).
- Lis README.md, docs/ARCHITECTURE.md, docs/PLAN.md (liste de tâches vivante),
  docs/ART_DIRECTION.md, docs/ASSETS.md et ce fichier.
- Vérifie que tout passe : `sh tools/check.sh` (~3-5 min sur la machine de
  développement à 20 threads ; `JOBS=` réduit le parallélisme sur une petite
  machine).

## 2. Méthode de travail (imposée)
- Chaque fonctionnalité : analyse -> plan -> implémentation -> lancement du
  jeu -> test réel + captures (tests/_out/shots/, REGARDE-LES) -> logs ->
  corrections -> commit. Jamais « ça devrait marcher ».
- Commits atomiques : `feat:` / `fix:` / `perf:` / `test:` / `docs:` / `build:`
  + titre court en anglais comme l'historique, puces en français, ligne finale
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Livraison : `sh tools/ship.sh message.txt` = check complet -> commit ->
  push main -> `tools/release.sh` (export du .exe avec le numéro de build
  v<majeur.mineur>.<nombre de commits>, vérification du .exe exporté par le
  scénario boot, release GitHub avec notes = tous les commits depuis la
  précédente). Si des commits sont déjà faits (intégration d'agents) :
  `sh tools/check.sh` puis `git push origin main` puis `sh tools/release.sh`.
  Ne jamais chaîner un commit après un `grep` (code de retour faux).
- Outils (jamais de fenêtre visible) : `sh tools/scenario.sh <nom>` (un
  scénario avec rendu hors écran et captures ; `HEADLESS=1` sans rendu),
  `sh tools/mp_test.sh <nom>` (hôte + client sans rendu ; `GUI=1` avec rendu),
  `sh tools/check.sh` (pool parallèle ; `SCENARIOS="a b"`, `MP="lobby"`,
  `JOBS=`, `GUI_JOBS=`, `--fast`), `sh tools/perf.sh [scénarios]` (1080p, un
  jeu à la fois, `QUALITY=low|medium|high`).
  NE LANCE JAMAIS `godot --path . -- --autotest=...` directement.
- Plusieurs copies en parallèle : `AUTOTEST_PORT_OFFSET=<n>` décale les ports
  des tests réseau (check.sh ajoute 100 x numéro de place pour ses propres
  tâches) ; `JOBS=4 sh tools/check.sh` réduit la charge.
- Agents (outil Agent, `isolation: worktree`, en arrière-plan) :
  * Brief commun à leur donner (règles ci-dessus + « analyse, test réel,
    captures, un commit atomique dans ta worktree, pas de push, pas de
    release, pas de `taskkill /IM Godot` (tue seulement tes PID), au plus
    2 fenêtres de jeu à la fois, décalage de ports unique, `sh tools/scenario.sh`,
    ne lance pas check.sh complet »), plus une mission précise avec les
    valeurs BO1 et un périmètre de fichiers disjoint des autres agents.
  * Intégration : essai de cherry-pick dans une worktree d'intégration
    (ex. `.claude/worktrees/lead`) sur la tête de main ; conflits le plus
    souvent additifs (garder les deux côtés) ; si le conflit est de fond,
    demander à l'agent (SendMessage) de rebaser lui-même sur la nouvelle
    tête. Puis cherry-pick sur main, check complet, push, release.
  * ATTENTION au répertoire courant : une commande `cd` dans une worktree
    puis une autre sans `cd` s'exécute dans le dépôt principal ; toujours
    préfixer par `cd <chemin absolu> &&`.
  * Supprimer les worktrees terminées (`git worktree remove --force`) : le
    disque C: est presque plein.
- Tests instables sous charge : chaque fois qu'un test échoue, distinguer
  un vrai défaut (à corriger dans le jeu) d'un test dépendant du temps
  (fenêtre fixe, marge trop faible, action trop tôt). Corriger le test en
  attendant l'événement (`until(...)`) plutôt qu'avec des délais fixes.

## 3. État actuel (voir docs/PLAN.md pour le détail et les releases)
Livré et publié (dernière release : voir `gh release list`) :
- Réseau host/client ENet (solo = même code), serveur autoritaire, instantanés
  delta (NetCodec, ~2 Ko/s par client), poignée de main avec version de build.
- Règles BO1 : manches (_zombiemode.gsc : nombre, santé, vitesse, délai),
  points, atouts (sans limite, Quick Revive solo 3 fois), à terre/réanimation.
- Deux cartes : BUNKER K-7 (grille ASCII) et KINO = Kino der Toten à
  l'échelle 1 (carte en maillage à plusieurs niveaux construite dans
  Blender, docs/KINO_V2.md : téléporteur de BO1 relié au poste central,
  salle de projection et Pack-a-Punch, 22 fenêtres, 9 boîtes, 5 pièges),
  sélection de carte (solo et salon), fenêtres barricadées (6 planches,
  rythme BO1 ~1,9 s par planche), portes, courant, pièges électriques.
- Arsenal BO1 complet (M1911 de départ, 9 armes murales, 17 armes de boîte,
  Pack-a-Punch avec noms originaux), CLAUDE-RAY, TONNERRE-7 (Thundergun),
  grenades (G) et SINGE-TAMBOUR (Q), couteau avec fente, couteau de chasse
  (Bowie), plongeon ; tir droit (réticule = impact), visée alignée par arme
  (test weapon_aim à 0 px), lunettes des fusils de précision, recul BO1,
  effets à la bouche du canon, douilles, impacts par matière.
- Bonus : Munitions max, Mort instantanée, Double points, Nuke, Charpentier,
  Liquidation (boîtes à tous les emplacements), FAUCHEUSE (Death Machine).
- Manches de chiens de l'enfer, rampants et démembrement (hitboxes
  d'avant-bras), 7 atouts dont NOVA FLOP (PhD) et DEADEYE DRAM (Deadshot).
- Sons CC0 (armes, zombies, chiens, grenades, impacts, joueur) nivelés en
  intensité perçue (LUFS) ; musiques/ritournelles originales synthétisées.
- Refonte visuelle R4 (partie 1) : étalonnage et post-traitement BO1 (grain,
  vignettage, brume volumétrique), HUD BO1 (manche peinte), zombies refaits
  (6 archétypes, animations), armes FPS détaillées + mains, FOV d'arme séparé.
- Dossier de combat (statistiques), menu principal, options (dont grain).
PERF (1080p). GTX 1070 après « perf: optimize rendering after the visual
rework » : MEDIUM 4,5 ms de GPU sur la pire vue, 24 zombies au contact 5,0 ms,
HIGH 511 -> 296 draw calls. Re-mesure GPU libre du 28/09/2026 sur le portable
RTX A2000 (~1,25x une GTX 1070 ; cible 60 fps GTX 1050 ≈ 3,4 ms ici) : MEDIUM
231-251 fps sur les pires vues (3,3-3,45 ms), 24 zombies au contact 207 fps
(3,96 ms, physique ~2,5 ms par pas), LOW ~390 fps, HIGH ~147 fps. Préréglage
automatique au premier lancement (scripts/game/quality_probe.gd). Coûts par
poste : `sh tools/perf.sh perf_costs` ; détail dans docs/ARCHITECTURE.md.

## 4. Reste à faire (dans cet ordre ; détail dans docs/PLAN.md)
1. PERF (reste) : fps re-mesurés le 28/09/2026 (voir §3) ; KINO (l'ancienne,
   en grille) et BUNKER sans zombie tenaient la cible MEDIUM (BUNKER à
   ~0,05 ms près), la horde de 24 zombies la dépasse de ~0,5 ms (lampes
   1,5 ms, animation 0,3 ms). La nouvelle KINO (~6 fois plus grande) est à
   re-mesurer (`sh tools/perf.sh kino_tour perf_costs`, étape 6 de
   docs/KINO_V2.md : occlusion, distances de visibilité).
   Pistes restantes à chiffrer avec perf_costs :
   animation des zombies lointains à cadence réduite, bruit
   des zombies moins cher, ombres des lampes ; vérifier le préréglage
   automatique sur d'autres cartes graphiques.
2. R4 suite : décors et matériaux plus riches par zone, machines d'atouts,
   boîte mystère, Pack-a-Punch, téléporteur au style BO1 ; menu principal et
   écran de chargement au style BO1 ; occlusion des sons derrière les murs
   (HUD à l'échelle de la résolution et lampes « courant coupé » neutres :
   faits en v0.1.94).
3. R5 — KINO V2 (EN COURS, demandé par l'utilisateur) : Kino der Toten à
   l'échelle 1 et à l'identique, plan validé dans **docs/KINO_V2.md** (7 étapes,
   chacune livrée). Références privées dans docs/reference/kino/ :
   layout_research.md (positions exactes en unités CoD) et images/ (65 images,
   INDEX.md). L'utilisateur a accepté d'utiliser les coordonnées d'une liste
   d'entités publiée par un dépôt tiers, NOMBRES SEULEMENT (aucun modèle,
   texture ni son) ; tout le contenu de Kino est reproduit ; l'ancienne KINO
   est remplacée à la fin. Modèles construits par scripts Blender sans fenêtre
   (Blender 5.2.1 installé ; serveur MCP officiel « Blender Lab » enregistré
   dans Claude Code, lancer Blender avec `--online-mode`). Étapes 1 à 4 et 7
   faites (MapLayout ; cartes à étages ; maquette et jeu BO1 ; remplacement :
   la V2 EST la carte `kino`, l'ancienne KINO en grille est supprimée),
   étape 6 faite pour la salle de théâtre. Restent l'étape 5 (contenu propre
   à Kino : Claymores, tourelles, fosse à feu, Mule Kick, rampants des
   plafonds, zombies des gravats, chutes des toits, salles bonus) et l'étape 6
   pour les autres salles (liste dans docs/KINO_V2.md, « Reste »).
4. Écarts BO1 connus à reprendre : annonceur (voix procédurale), zone de
   renversement du TONNERRE-7, arme merveille unique, M16 amélioré sans
   lance-grenades, vol des zombies non physique, pas d'animations de tir des
   coéquipiers pour les lancers, pas de ragdoll.
5. Garder README (état d'avancement), docs/ARCHITECTURE.md et docs/PLAN.md à
   jour à chaque livraison.

## 5. Pièges déjà rencontrés (ne pas les refaire)
- Shader spatial : si POSITION est écrit dans une branche, l'écrire dans TOUS
  les cas. Control enfant d'un CanvasLayer : ancrages AVANT add_child.
  Couleurs de sommets : sRGB -> linéaire. save_to_wav n'écrit pas de boucle :
  edit/loop_mode=2 dans le .import.
- RPC : requêtes client->serveur `@rpc("any_peer","call_local")` + rpc_id(1) ;
  diffusions `@rpc("authority","call_local")` ; le serveur ne fait jamais
  confiance au client (dégâts, points, achats, portes, manches).
- Autotests : réglages dans user://settings_autotest.cfg ; le délai d'un
  scénario (timeout_sec) est vérifié chaque seconde (il était figé à 60 s) ;
  les manches de chiens et les bonus aléatoires sont coupés en autotest.
- Zombies en mode flottant (y = 0 sur les cartes grille, sol suivi par un
  rayon sur les cartes en maillage) ; cellules de navigation uniquement via
  NavGrid.set_blocked ; corps non solide pendant l'émergence.
- Marqueurs de grille déjà pris (BUNKER K-7) : W fenêtres, % Bowie,
  * grenades, ( ) NOVA FLOP et DEADEYE DRAM, + ! $ & A B achats muraux.
  Vérifie avant d'en ajouter un. KINO n'a plus de grille : ses emplacements
  sont des marqueurs nommés de assets/maps/kino/layout.json (GÉNÉRÉ par
  tools/blender/kino/make_layout.py, ne pas l'éditer à la main).
- Cartes en maillage : `MeshMapLayout.zone_at` teste des boîtes ; les poches
  « dehors » des fenêtres peuvent tomber dans la boîte d'une autre zone (la
  fenêtre du balcon du hall surplombe la salle basse) : pour un zombie
  derrière une fenêtre, prendre la zone de sa fenêtre.
- Godot 4.7 réécrit default_bus_layout.tres à l'import (uid) : committer le
  changement, sinon release.sh refuse l'arbre modifié.
- Tests unitaires : libérer (free()) tout nœud construit, sinon « leaked at
  exit » fait échouer check.sh.
- Heredocs bash avec apostrophes et perl -0pi : préférer l'outil d'édition de
  fichiers pour les remplacements délicats.
- La FAUCHEUSE et les explosions peuvent rendre un zombie rampant : dans les
  tests, viser `z.hit_body.global_position`, pas une hauteur fixe.

## 6. Travail en cours au moment de l'arrêt
(voir la section « État actuel » ci-dessous, mise à jour juste avant
l'extinction de la machine précédente)

Commence par la mise en place (§1), vérifie `sh tools/check.sh` sur main,
puis reprends §6 puis §4 dans l'ordre en respectant §0 et §2.
```

## État actuel

28/09/2026, portable RTX A2000 (20 threads).
- main poussé sur GitHub avec la refonte des tests (« test: make the test
  suite parallel and headless ») : check.sh complet en ~4 min au lieu de
  35-45 min, aucune fenêtre visible (headless ou hors écran).
- Tests fragiles corrigés : powerups « bonus dû » (corps du zombie précédent
  qui arrêtait les balles), mp_dogs (munitions max ramassées par l'hôte dans
  la même image que leur apparition), scope (visée du torse, attentes sur
  événements).
- Aucun agent en cours, aucun travail non poussé : tout est sur main.
- KINO V2, étape 7 faite : la V2 remplace l'ancienne KINO (id `kino`, même
  entrée de menu) ; scénarios `kino_tour`, `kino_gameplay`, `kino_theater`.
- Prochaine étape : KINO (§4.3, docs/KINO_V2.md), étape 5 (nouveau contenu :
  Claymores, tourelles, fosse à feu, Mule Kick sous nom original, rampants des
  plafonds, zombies des gravats, chutes des toits, 4 salles bonus ; la MP40 est
  déjà au mur) puis étape 6 pour les salles hors théâtre ; voir « Reste ».
- Les tests dépendant du temps sont nombreux : lancer check.sh avec un `JOBS=`
  réduit quand des agents font tourner des jeux en même temps.
