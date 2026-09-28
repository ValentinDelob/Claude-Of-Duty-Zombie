# KINO V2 — Kino der Toten à l'échelle 1, à l'identique

## Contexte
L'utilisateur veut refaire KINO comme la vraie Kino der Toten de BO1 : même forme, mêmes couloirs,
pièces, escaliers, emplacements d'armes, de boîte, etc., à l'échelle 1, avec des modèles construits
dans Blender. Décisions de l'utilisateur :
- les coordonnées issues de la liste d'entités publiée par un dépôt tiers sont utilisables, mais
  **nombres seulement** (aucun modèle, texture ni son) ;
- **tout** le contenu propre à Kino est reproduit (fosse à feu, tourelles, Claymores, MP40,
  Mule Kick sous nom original, rampants des plafonds, zombies des gravats, chutes des toits,
  salles bonus) ;
- l'actuelle KINO est **remplacée à la fin** (même id `kino`, même entrée de menu).

Références privées (git-ignorées) : `docs/reference/kino/layout_research.md` (positions exactes en
unités CoD, 1 u = 2,54 cm, niveaux de sol, 22 fenêtres, 9 boîtes, 5 pièges, 8 portes) et
`docs/reference/kino/images/` (65 images, dont le plan officiel du guide).
Emprise ≈ 95 × 89 m, 5 hauteurs de sol (-1 à 8,6 m), théâtre en pente, hall double hauteur
avec 2 escaliers et balcon, mezzanine du Foyer, arrière-salle surélevée, salle de projection.

Obstacle principal : tout le moteur suppose une carte plate (grille ASCII 2D, zombies forcés à
y = 0, navigation AStarGrid2D, zones et objets placés par cellules). ~20 systèmes en dépendent.

## Approche retenue
Carte « maillage » en 3D, à côté des cartes grille existantes (BUNKER K-7 et test_arena gardent
leur grille et leurs tests, qui servent de filet de sécurité).

1. **Interface `MapLayout`** (`scripts/game/map/map_layout.gd`) : zones `zone_at(Vector3)`,
   `snap_to_floor`, `find_path` (points avec y), `line_of_sight` 3D, bloqueurs nommés
   (portes, fenêtres, boîte, PaP), marqueurs typés en `Transform3D` (apparitions, portes,
   fenêtres, achats muraux, atouts, boîtes, pièges avec volume 3D, téléporteur, interrupteur,
   lampes), `power`/`flicker`/`warmup_materials`, image d'aperçu.
   - `GridMapLayout` enveloppe le code actuel sans changer le comportement (MapData, MapDef,
     NavGrid, BarricadeLayout ; ids réseau inchangés : `wallbuy_X`, `grenades_x_y`).
   - `MeshMapLayout` lit la description de carte (ci-dessous), instancie les .glb et navigue
     sur un navmesh.
   - Consommateurs migrés vers l'interface (remplacement d'API) : `game.gd`, door, wall_buy,
     perk_machine, power_switch, mainframe, mystery_box, pack_a_punch, teleporter (tolérance
     verticale du pad), grenade_buy, spawner, powerup_system (plus de `max(y, 0)`), hud (zone de
     sortie du téléporteur au lieu du « p » codé en dur), map_preview.
   - Refonte réelle : `zombie.gd`/`hellhound.gd` (plus de y = 0 forcé : mode flottant gardé
     pour le coût, y suivi du navmesh ; portée d'attaque, morsure et bond avec tolérance
     verticale ; ligne de vue par rayon, en cache 0,1 s comme aujourd'hui), séparation de
     `ZombieManager` filtrée en hauteur, `DogRound` (points tirés sur le navmesh),
     barricades (fenêtres décrites, hauteur réelle), `ElectricTrap` (volume 3D), `Door`
     (taille et hauteur décrites), effets au sol (`GibPool.FLOOR_Y`, particules).

2. **Navigation** : `NavigationServer3D`, navmesh précalculé par un outil (`tools/bake_navmesh.gd`
   en headless) et versionné. Une région par zone + une petite région par porte, activée à
   l'ouverture (connexion par bords communs). Serveur uniquement, comme aujourd'hui.
   Risque principal : vérifié en premier sur une petite carte de test à étages.

3. **Description unique de la carte** `assets/maps/kino/layout.json` (écrite par nous, en mètres,
   repère Godot : x = x_CoD·0,0254, y = z·0,0254, z = -y·0,0254, puis décalage pour garder
   x, z ≥ 0 exigé par `NetCodec`). Contient : salles (contour, sol ou pente, plafond), ouvertures,
   escaliers (rampe de collision invisible + marches visuelles : le joueur n'a pas de montée de
   marche), balcons, volumes de zones, et tous les marqueurs avec leur orientation.
   Lue à la fois par le script Blender (géométrie) et par Godot (gameplay).

4. **Chaîne Blender** (sans fenêtre, reproductible ; Blender 5.2.1 déjà installé) :
   - `tools/blender.sh <script>` lance `blender --background --factory-startup --python`.
   - `tools/blender/kino/build_architecture.py` : sols, murs avec ouvertures, escaliers,
     balcons, coupole, arcades et moulures, découpés par salle ; collisions simplifiées
     (`-colonly`) ; lampes en empties `LAMP_n`.
   - `tools/blender/kino/props/*.py` : fauteuils et gravats, scène, rideau, écran, lustres,
     guichet, bar, coiffeuses, portants, disque du mainframe, tour du téléporteur, projecteur,
     tableaux à la craie avec ampoules, podiums de tourelles, décors des salles bonus.
   - Sorties `.glb` versionnées dans `assets/maps/kino/` (le jeu n'a pas besoin de Blender).
   - `tools/blender/kino/render_views.py` : rendus depuis les points de vue des captures de
     référence, pour comparer côte à côte avant chaque livraison.
   - À l'import : matériaux nommés d'après `WorldLook.SURFACES` → `WorldLook.surface(nom)`
     (garde l'allure BO1 et les optimisations) ; `surface.gdshader` reçoit une hauteur de sol
     par instance (les bandes peintes sont aujourd'hui en y absolu) ; lampes créées par le code
     commun de `PropBuilder._map_light` (extrait dans un utilitaire) pour rester reliées au
     courant, au scintillement et à `RenderQuality` ; `meta "surface"` sur les collisions pour
     les impacts ; couche BARRIER pour les gravats et fauteuils franchissables par les balles.
   - Le serveur MCP Blender (après redémarrage de session) sert à inspecter les scènes ; la
     construction elle-même reste scriptée.

5. **Fidélité BO1** (d'après la recherche) :
   - Boucle de portes : hall rdc → salle basse 750 → ruelle 1000 → arrière-salle 1250 →
     scène 1250 ; hall étage → salle haute 750 → Foyer 1000 → loges 1250 → scène 1250.
     Doubles portes hall ↔ théâtre et rideau de scène ouverts par le courant (non achetables).
   - Armes : Olympia 500, M14 500, MPL 1000, AK74u 1200, PM63 1000, MP40 1000,
     Stakeout 1500, MP5K 1000, M16 1200, Claymores 1000, couteau de chasse 3000, grenades 250.
   - Atouts : Quick Revive (hall), Juggernog (théâtre), Speed Cola (Foyer), Double Tap
     (ruelle), Mule Kick (salle haute) sous noms originaux. NOVA FLOP et DEADEYE DRAM
     retirés de Kino (ils viennent de Five/Ascension).
   - Boîte : 9 emplacements, départ au hasard parmi 8 (pas le balcon du hall), ours selon les
     probabilités du script, tableaux à la craie qui indiquent la boîte.
   - Téléporteur gratuit : relier pad puis mainframe, 30 s en salle de projection (PaP),
     75 % de chances de passer ~4 s dans une salle bonus, retour sur le mainframe, 90 s de recharge.
   - Pièges 1000 (40 s, recharge 60 s, un levier à chaque bout) : 4 électriques, 1 fosse à feu.
     Tourelles 1500 (30 s) sur le bord de scène et dans le Foyer.
   - 22 fenêtres, rampants des plafonds après le courant, zombies des gravats du théâtre,
     chutes des toits de la ruelle et des plafonds de la salle haute et des loges.
   - Départ des joueurs sur le mainframe, regard vers la scène.
   - Vérifier les vitesses du joueur et des zombies par rapport à BO1 (course ≈ 190 u/s ≈ 4,8 m/s)
     pour que l'échelle 1 « se sente » comme dans le jeu.

## Étapes (chacune livrée : check complet → commit → push → release .exe)
1. **Interface `MapLayout` + `GridMapLayout`**, consommateurs migrés, aucun changement de
   comportement (tous les tests actuels passent).
2. **3D** : `MeshMapLayout`, navmesh par zones et portes, zombies et chiens qui suivent le sol,
   barricades, pièges et portes décrits en 3D. Petite carte de test à étages (2 niveaux,
   escalier, pente, porte, fenêtre) générée par Blender + nouveaux tests.
3. **KINO V2 en maquette grise** (`--map=kino_v2`, hors menu) : `layout.json` complet, architecture
   Blender simple, toutes les zones, portes, escaliers, fenêtres, apparitions et navigation.
4. **Gameplay complet** : atouts, achats muraux, 9 boîtes et tableaux, 5 pièges, téléporteur BO1,
   salle de projection et PaP, portes et rideau liés au courant.
5. **Nouveau contenu** : MP40, Claymores, tourelles, fosse à feu, Mule Kick (nom original),
   rampants des plafonds, zombies des gravats, chutes des toits, 4 salles bonus.
6. **Passe artistique** salle par salle dans Blender, comparée aux captures (rendus côte à côte),
   éclairage et courant, occlusion (`OccluderInstance3D`, occlusion culling) et distances de
   visibilité pour tenir la cible MEDIUM sur une carte ~6 fois plus grande.
7. **Remplacement** : KINO V2 prend l'id `kino`, l'ancienne `kino.gd` et ses tests sont retirés,
   docs (README, ARCHITECTURE, ART_DIRECTION, PLAN, HANDOFF) à jour.

Les étapes 5 et 6 se parallélisent avec des agents (worktrees, fichiers disjoints, 5 au plus).

## Fichiers clés
- Nouveaux : `scripts/game/map/map_layout.gd`, `grid_map_layout.gd`, `mesh_map_layout.gd`,
  `mesh_map_builder.gd`, `map_lights.gd` (extrait de PropBuilder), `assets/maps/kino/layout.json`
  et `*.glb`, `tools/blender.sh`, `tools/blender/kino/*.py`, `tools/bake_navmesh.gd`,
  `scripts/game/map/maps/kino_v2.gd`.
- Modifiés : `scripts/game/game.gd`, `zombies/zombie.gd`, `zombie_manager.gd`, `dogs/*.gd`,
  `barricades/*.gd`, `interact/*.gd`, `rounds/spawner.gd`, `powerups/powerup_system.gd`,
  `hud/hud.gd`, `ui/map_preview.gd`, `assets/shaders/surface.gdshader`, `fx/gib_pool.gd`,
  `fx/particle_pool.gd`, `weapons/weapon_db.gd` (MP40), `perks` (Mule Kick),
  `interact/teleporter.gd` (gratuit, recharge, salles bonus).
- Réutilisés tels quels : `WorldLook.surface`, `TheaterLook`, `PowerGrid`, `LightFlicker`,
  `RenderQuality.apply_lamp`, `NetCodec` (plage x/z ≥ 0 respectée par le décalage).

## Vérification
- À chaque étape : `sh tools/check.sh` complet (≈ 4 min, sans fenêtre visible).
- Unitaires : `tests/test_map_layout.gd` (grille et maillage donnent les mêmes réponses sur
  test_arena), `tests/test_kino_layout.gd` (22 fenêtres, 9 boîtes, 8 portes avec leurs prix,
  5 pièges, atouts et achats par zone, toutes les zones reliées par le navmesh).
- Scénarios : carte à étages (zombie qui monte l'escalier, suit la pente, franchit une porte
  ouverte seulement), `kino_tour` réécrit par ids de marqueurs (plus de cellules), trajets
  spawn → scène par les deux boucles, téléporteur complet, fosse à feu et tourelles,
  `mp_*` sur Kino (hôte et client voient les zombies aux bons étages).
- Visuel : `visual_look` et `render_views.py` comparés aux captures de référence ; `perf.sh`
  (`kino_tour`, `perf_costs`) pour garder la cible MEDIUM.

## Avancement
- Étape 1 (v0.1.95) : interface `MapLayout`, `GridMapLayout`.
- Étape 2 (v0.1.96) : cartes en maillage à étages (`MeshMapLayout`, `MeshNav`,
  `tools/blender/mesh_map.py`), carte `test_levels`, distributeurs pleins.
- Étape 3 : maquette grise `--map=kino_v2` (hors menus). La description
  `assets/maps/kino/layout.json` est GÉNÉRÉE par
  `sh tools/blender.sh tools/blender/kino/make_layout.py assets/maps/kino/layout.json`
  puis `sh tools/blender.sh tools/blender/mesh_map.py assets/maps/kino/layout.json assets/maps/kino/kino.glb [aperçu.png]`
  (vue de dessus orthographique, nord en haut). Salles, portes, fenêtres et
  objets y sont écrits en unités CoD d'après les relevés ; murs, garde-corps,
  contremarches et poches des fenêtres sont calculés (rastérisation par
  cases de 10 u). Portes liées (`link`), portes du courant (`power`) et
  rideau de scène (`curtain`) gérés par `Door`. Scénario `kino_v2_tour` :
  22 fenêtres, 9 boîtes, prix des portes, zones de chaque objet, tout
  accessible, zombies qui changent d'étage. Écarts connus de la maquette :
  contours des murs [PROBABLE] (volumes englobants), escalier en U de
  l'arrière-salle simplifié en une volée, pas encore de gravats ni de
  fauteuils dans la salle, poste central encore mural, fosse à feu en piège
  électrique provisoire, lampes en grille.
- Étape 4 : jeu de Kino der Toten sur la maquette. Téléporteur de BO1
  (réglages par carte `MapDef.teleporter_*` : gratuit, charge 1,8 s, zombies
  foudroyés à 7,6 m du pad au départ, 30 s en salle de projection, retour sur
  le poste central, 90 s de recharge puis nouvelle liaison) ; poste central
  en disque au sol du hall (`TeleporterMainframe.floor_pad`, bord incliné
  praticable, départ des joueurs dessus, face à la scène :
  `MapLayout.player_spawn_yaw`) ; Pack-a-Punch en salle de projection ;
  pièges à deux leviers (`TrapLever`) et durées par piège (Kino : 40 s / 60 s) ;
  tableaux à la craie de la boîte (`BoxBoard` : plan tracé d'après les salles,
  une ampoule par emplacement, verte à l'emplacement actuel après le courant,
  clignotement pendant un déplacement ou une Liquidation) ; ours de la boîte
  aux probabilités de BO1 (`MysteryBox.skull_chance`, toutes les cartes).
  Scénario `kino_v2_gameplay`.
- Étape 6, salle de théâtre (décor d'après les captures de BO1) : objets
  modélisés dans Blender (`tools/blender/props/kino_theater.py` →
  `assets/models/kino/*.glb`), posés par la description (`props`, `instances`
  en MultiMesh pour les fauteuils, `screens`, `beams`). Balcon en fer à cheval
  à ~4,8 m sur colonnes, coin de l'atout rouge exigu sous le balcon du fond,
  dix rangées de chaque côté de l'allée (moitié ensevelies), grand tas au
  centre-droit avec le lustre tombé, nappes de gravats sur les côtés, écran
  6,5 × 4,2 m dans son cadre, tour du téléporteur, pupitre et chaises
  pliantes. Cabine de projection : deux baies ouvertes sur la salle (on y tire
  d'en haut). Toutes les collisions invisibles (ruines, rangées, baies,
  objets) sont des `CollisionBox` décrites en données (`blockers` de la
  description, `<modèle>.collision.json`), jamais des modèles Blender.
  Scénario `kino_v2_theater` (captures + tir depuis les baies).
- Théâtre d'après les photos de référence (v0.1.103 et suivante) : cabine de
  projection avec une seule fente vers la salle (85 % de la largeur du mur, 1 m de
  haut centrée sur les yeux du joueur : on voit la scène et on tire au milieu de la
  salle) ; coulisses avec un grand bloc qui porte l'écran (à 8 m derrière le rideau,
  relevé de BO1), passage de 3 m tout autour et emplacement de la boîte contre le mur
  du fond ; cadre de scène ramené à 17 × 8,3 m ; palette gris-vert de BO1 ; rangées
  courbes ; larges escaliers de scène ; habillage : nez de scène sculpté, gros câbles
  bleus de la tour à l'allée, bidons bleus, caisses et échafaudage en coulisses,
  frises à losanges et corniches, arcs électriques de la tour. Emblèmes originaux :
  bobine dorée sur rouge, jamais de disque blanc sur fond rouge.
  Restent : voûte à nervures et demi-coupoles (plafond encore plat avec coupole),
  gravats plus hauts, animation des arcs.
