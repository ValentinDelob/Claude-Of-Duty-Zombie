# Architecture cubique des cartes — inventaire, décisions, lots

Demande (option B) : **toute l'architecture est cubique**, comme le décor
(GAME_CONCEPT.md § 4.19, docs/VOXEL_DECOR_PLAN.md) : murs droits, en biais
et courbes, piliers, sols et plafonds à altitudes libres, escaliers (droits,
tournants, colimaçon), rampes, garde-corps, et **toutes les textures** des
sols, murs et plafonds en pixel art « 1 pixel = 1 cube de 5 cm » (univers
hôpital / laboratoire / zombies), même si les collisions changent.

État : **pilote fait** (§ 4) : textures pixel art de 3 clés (`concrete`,
`tiles`, `wall`) et murs en biais en escalier de cubes. Le reste est découpé
en 5 lots (§ 3). **Lot C fait** (§ 5) : toutes les surfaces en pixel art.
**Lot A fait** : grille de 5 cm,
format 20, copie de sauvegarde, erreurs nouvelles signalées, références
régénérées (détail : docs/MAP_AUTHORING.md § 4, « Passage aux cubes de 5 cm »).

## 1. Inventaire

### 1.1 Géométrie (cartes de l'éditeur et cartes en maillage)

Chaîne : `EditorMap` (5 JSON) → `MapRaster` (grille de 0,5 m,
`MapGeom.CELL`, décalage monde `WORLD_OFFSET` 4,25 = 85 cubes) →
`MapValidator` → `MapLayoutExport` (description `layout`) →
`MeshMapGeometry._build` (ArrayMesh à normales plates, un nœud par
`<matériau>__<salle>__<type>`, collisions par groupe). Cartes en maillage
Blender (`assets/maps/test_levels`) : mêmes clés, géométrie du .glb
(`tools/blender/mesh_map.py`).

| élément | source (description) | construit par | collision | non cubique aujourd'hui |
|---|---|---|---|---|
| murs droits de la grille | `blocks` (`_walls`, rectangles fusionnés sur 0,25 m) | `_box` lacet 0 | BoxShape3D | rien en x/z ; bas à sol − 0,1 / − 0,3 (sur la grille) ; haut = plafond libre (0,0001) ; linteaux à plafond − 0,01 (`UNDER_SLAB`) |
| murs en chemin | `walls` (cours derrière les fenêtres, `_pockets`) | `_box` tourné | BoxShape3D tournée | cours tournées sur un mur en biais (angle libre) |
| murs en biais, murs libres, pans de pièces polygonales | `obliques` (`MapRaster._obstacle_record`, `_merge_obliques`) | `_two_sided_box` tourné → **pilote : escalier de cubes** | CollisionBox tournée | angle libre ; raccords `_min_box` (taille et angle libres) |
| murs courbes | `mur_courbe` → 1 à 64 segments `obliques` (`MapShapes.arc_points`) | idem | idem | segments en biais |
| piliers | carrés ; tournés ou hors grille → `obliques` (`pillar_box`) | idem | idem | angle libre |
| pièces libres (polygone, cercle, ellipse, triangle, L) | bords sur la grille → `blocks`, autres → `obliques` ; sols au vrai contour | `_polygon` | ConcavePolygonShape3D | contour oblique du sol (caché sous le mur), morceaux `biais_*` |
| ouvertures | fenêtre 0,95–2,35, porte à zombies 0–2,1, porte 0–2,5 (`hauteur_portes`), passage : plafond − 0,01 | `wall_pieces` | — | 0,01 sous le plafond ; jambages en biais |
| sols, plafonds | `rooms` (`floor`, `ceiling`, `floor_slab` 0,3, `ceiling_slab`, `no_ceiling`, `slope`) | `_polygon`, `_slab` | concave / prisme | altitudes et plafonds libres (0,0001) ; `slope` (pente) seulement dans test_levels |
| plafond caché | `no_ceiling` (`sans_plafond`) | — | — | — (laisse voir le ciel) |
| dalles, mezzanines | `slabs` (Blender), `floor_slab` (éditeur) | `_slab` | prisme convexe | contours libres (Blender) |
| garde-corps de niveau | `rails` (h 1,0) | `_box` | un pavé h × 0,1 | main courante 0,08 (dessus à + 1,04), lisse 0,08, barreaux 0,05 tous les len/int(len/0,3) |
| escaliers | `stairs` : `kind` droit, palier, quart, demi_tour, large, service, colimacon, rampe ; `turn`, `steps`, `rail`, `closed`, `side`, `w` | `_stair`, `_spiral`, `_stair_edge` (`StairGen.plan`) | rampe convexe par volée (le joueur n'a pas de montée de marche), secteurs hélicoïdaux (colimaçon), tablier `apron` invisible | marche = H/n (≈ 18 cm) et giron = L/n libres ; volées tournées ; rampe en pente ; mains courantes en pente (`_obox`) ; noyau à 12 pans r 0,25 ; marches en secteurs de 0,2 ; séparation en pente du demi-tour ; paliers W × 0,6 |
| carte en grille BUNKER K-7 | `MapData` (cellules de 1 m, murs 3,2 m) | `MapBuilder` (SurfaceTool) | pavés fusionnés | **déjà cubique** (1 m, 3,2 m) ; seules ses textures changent |
| ciel | `carte.ciel` → `WorldLook.apply_sky` | — | — | hors géométrie (❓ § 4.19 « ciel » reste ouvert) |

Déplacements : joueur `floor_max_angle` 50°, capsule r 0,35, **aucune
montée de marche** (les escaliers marchent grâce aux rampes de collision) ;
zombies `MOTION_MODE_FLOATING`, hauteur par rayon vers le bas
(`_follow_floor`) ; navmesh `MeshNav` (cellule 0,2 × 0,1, rayon 0,4,
`agent_max_climb` 0,3, pente 42°) cuit sur les collisions ; escaliers suivis
par les couloirs d'ancres `StairLane` (indépendants des marches visibles).

### 1.2 Matériaux de surface

| famille | clés (`WorldLook.SURFACES`, motif de `surface.gdshader`) | source aujourd'hui |
|---|---|---|
| sols, murs, plafonds | `floor`(0), `wall`(4), `ceiling`(6), `concrete`(0), `concrete_dark`(0), `tiles`(1), `wood`(2), `metal`(3), `stone`(5, veines lumineuses), `wall_green`(4), `wall_cell`(4), `wall_lab`(1), `wall_rust`(3), `wall_concrete`(0), `wall_ritual`(5) | shader procédural (bruit fbm, coordonnées monde, filtrage linéaire) |
| décor | `crate`, `barrel`, `steel`, `fabric`, `door` | idem (station, menu) |
| théâtre (KINO, à retirer) | `carpet_red`, `marble`, `stage_wood`, `parquet`, `wall_theater`, `wall_lobby`, `wall_foyer`, `wall_loges`, `brick`, `cobble`, `velvet`, `brass`, `plaster_theater`, `vault_theater`, `carpet_theater`, `ceiling_theater`, `dark_wood` | idem ; `brick`, `cobble`, `dark_wood` servent aussi aux cours et garde-corps |
| spéciales | `glass`, `bulb`, `glow_blue`, `crystal`, `chalk`, `paper`, `paint_*`, `cable_blue`, `rubber`, `plank` (`MeshMapBuilder._special`), `glow_green`, `glow_red`, planche de barricade (`Barricade.plank_material`, bruit 128 × 32) | StandardMaterial3D unis / bruit |
| textures de la carte | `map:<tid>` → `tex-<tid>` (`MapTextureLib`, PNG/JPEG importés, `taille` en m) | `map_texture.gdshader`, filtrage linéaire anisotrope |
| aperçus de l'éditeur | `MapIcons` (vignettes 40 × 24), `MapCatalog.surface_look` | couleurs moyennes |

Rien n'est en pixel art : aucun filtrage au plus proche, motifs plus fins
qu'un cube (joints de 2,4 cm, rivets, damas, plis), dégradés lisses.
Cartes : BUNKER K-7 (`concrete`, `wall_green`, `concrete_dark`, `wall_cell`,
`tiles`, `wall_lab`, `wood`, `metal`, `wall_rust`, `wall_concrete`, `stone`,
`wall_ritual`), DRAFT ARENA (`concrete_dark`, `wall_concrete`, `tiles`,
`wall_green`, `concrete`, `brick`, `wood`, `wall_rust`), test_levels
(`floor`, `wall`, `ceiling`, `wood`, `dark_wood`, `cobble`, `brick`).

## 2. Décisions (prises en l'absence de l'auteur)

### 2.1 Grille de 5 cm partout

- **Toute coordonnée d'architecture** (x, z, altitude, plafond, épaisseur,
  bas et haut des ouvertures, girons, paliers) est un multiple de 5 cm dans
  le monde (la grille de l'éditeur est décalée de 4,25 m = 85 cubes : même
  grille).
- **Deux verrous** : (1) l'éditeur arrondit à 5 cm à la saisie (mode
  « libre » de `MapSnap` : pas de 0,05 au lieu de 0,01 ; plafond, altitudes,
  points des contours, murs libres, arcs : `MapGeom.round_cube` au lieu de
  `round_mm` pour l'architecture) ; (2) **l'export arrondit** chaque valeur
  de la description à 5 cm (`MapLayoutExport._r` → `round_cube`), filet de
  sécurité pour les cartes reçues et les anciennes valeurs. Le décor garde
  ses règles (docs/VOXEL_DECOR_PLAN.md).
- Les décalages anti-scintillement de 1 cm (`UNDER_SLAB`, linteaux de
  passage) disparaissent : le plafond sous une dalle EST la face du dessous
  de la dalle (une seule face, pas de plafond en double).

### 2.2 Murs en biais, courbes, piliers tournés

- **Angle libre conservé** (les cartes de l'utilisateur en ont ; l'éditeur
  aimante déjà à 45° par défaut, Alt pour l'angle libre). Le **rendu** est un
  escalier de cubes aligné sur la grille du monde (pilote :
  `MeshMapGeometry._stepped_piece`).
- **Marche de 10 cm (2 × 2 cubes)**, pas de 5 cm : mesuré au pilote, la
  marche de 5 cm fait tracer au contour noir un trait tous les 5 cm et un
  moiré net sur un mur vu de biais à 4–6 m, pour deux fois plus de
  triangles ; à 10 cm l'escalier se lit comme une diagonale de pixels et le
  moiré disparaît presque. Les sommets restent sur la grille de 5 cm.
- **Éclairage** : les faces restent axiales (cubes), mais leur normale
  d'éclairage penche vers la normale du mur (`step_shade` 2) : les faces ±x
  et ±z d'un mur à 45° s'éclairent presque pareil (sinon rayures claires et
  sombres). Les pixels de texture suivent la vraie face (normale tirée des
  dérivées dans `pixel_surface.gdshader`).
- **Collision lisse** : le pavé tourné `CollisionBox` actuel reste. Raison :
  1 pavé au lieu de 40 à 90 par mur, glissement du joueur sans accroc sur
  les marches de 10 cm, navmesh et balles inchangés, écart avec le visuel ≤
  une demi-diagonale de marche (7 cm), invisible en jeu (une balle peut
  s'arrêter jusqu'à 7 cm devant une marche rentrante). Même principe que les
  escaliers, déjà en rampe de collision sous des marches visibles.
- Murs courbes : rendus comme UN contour rastérisé (pas segment par
  segment), pour un arc en pixels régulier ; collision : les segments
  actuels. Piliers tournés : idem en escalier.
- Ouvertures dans un mur en biais : gardées ; jambages en escalier ; la
  porte, la fenêtre et la barricade restent tournées à l'angle du mur
  (exception à « quarts de tour », comme les membres animés) ; le lot B
  ajoute un cadre cubique qui comble le jour entre l'objet et les marches.

### 2.3 Escaliers, rampes, garde-corps

- **Hauteur de marche en cubes** : cible 4 cubes (20 cm), répartition
  entière de la hauteur H (multiple de 5 cm) en n = round(H / 0,2) marches
  de 3 ou 4 cubes (15 ou 20 cm), réparties comme une droite de Bresenham
  (les marches de 15 cm en bas) ; giron : nombre entier de cubes, réparti
  de même sur la longueur de volée (multiple de 5 cm), au moins 5 cubes
  (25 cm). `steps` (nombre imposé) reste lu et borné à H / 0,05.
- **Rampe** (`rampe`) : devient des marches d'un cube (5 cm) de haut sur
  toute la longueur (« les pentes deviennent des marches ») ; clé gardée.
  Pente `slope` des sols (test_levels) : terrasses de 5 cm.
- **Colimaçon** : marches carrées = cellules de 10 cm dont le centre tombe
  dans le secteur de la marche ; noyau carré de 0,5 m (10 × 10 cubes) au
  lieu du prisme à 12 pans.
- **Garde-corps** : main courante 2 × 2 cubes (dessus à + 1,0 m), lisse
  2 × 2 cubes à + 0,1, barreaux 1 cube tous les 6 cubes (30 cm) alignés sur
  la grille ; sur une volée : une main courante en escalier (un tronçon par
  marche). Séparation du demi-tour : en marches.
- **Collisions inchangées** : rampe convexe par volée, secteurs du
  colimaçon, panneaux des garde-corps, tablier du haut. Raison : le joueur
  n'a pas de montée de marche (une marche verticale de 15–20 cm le
  bloquerait), les zombies flottent sur un rayon, le navmesh (montée 0,3,
  pente 42°) et les couloirs `StairLane` restent valides ; aucun risque sur
  la navigation des hordes (`stairs_hordes`). Écart visuel/collision : au
  plus une demi-marche (10 cm) au nez de marche, sous les pieds.

### 2.4 Textures pixel art

- **Bibliothèque générée** `PixelSurfaces` (GDScript, aucun fichier) :
  une image par clé, **20 pixels par mètre**, couleurs unies par pixel
  (bruit entier déterministe à 2–3 paliers, comme `voxel_lib.noise`),
  teintes de `voxel_lib.DECOR_PALETTE` (copiées dans `PixelSurfaces.PAL` ;
  le lot C ajoute un test qui relit `voxel_lib.py` pour les garder égales),
  rendues plus sombres pour l'architecture (facteur par clé).
- **Mêmes clés** que `WorldLook.SURFACES` : `WorldLook.surface(clé)` rend la
  version pixel si la clé est convertie ; les cartes existantes se chargent
  sans changement de données.
- **Pose** (`pixel_surface.gdshader`) : coordonnées MONDE en mètres × 20
  (sol, plafond : x, z ; mur : le long du mur et hauteur depuis le sol de la
  salle `floor_y`, pour le soubassement peint) ; lignes du haut répétées
  au-delà de l'image (`wrap`) ; **plus proche** + mipmaps lues avec les
  dérivées du point continu (`textureGrad`) : pas de scintillement au loin.
  Pas de carte de normales.
- Images de 64 × 64 (3,2 m), carreaux de 40 cm (7 + joint d'un pixel),
  banches de 1,6 m, soubassement de 1,25 m (25 pixels).
- **Textures importées** d'une carte (`map:<tid>`) : réduites à la volée à
  `taille` × 20 pixels de large (moyenne de zone) puis filtrées au plus
  proche : 1 pixel = 5 cm sans toucher aux fichiers de la carte.
- Coût : 12 à 23 ms par image générée (une fois, au premier usage de la
  clé ; ≈ 0,7 s si les 36 clés servent : à cuire en PNG au lot C si le
  chargement en souffre), 16 Kio de mémoire vidéo par clé ; une lecture de
  texture par pixel au lieu de 3 à 6 bruits : moins cher que
  `surface.gdshader`.

### 2.5 Migration des cartes (format 19 → 20)

- `EditorMap.FORMAT` 20 ; `_migrate` : `if from < 20: snap_architecture()`
  APRÈS `migrate_levels` (dernier par construction). Arrondit à 5 cm :
  contours des pièces, `a`/`b`/`epaisseur` des murs libres, centre et rayon
  des arcs, rectangles des piliers et des escaliers, `altitude`, `plafond`,
  `altitude_haut`, positions des ouvertures et des objets muraux le long du
  mur. Deux pièces voisines arrondies par la même fonction gardent leur
  bord commun. Les escaliers sont recalculés au rendu (§ 2.3), rien à
  écrire.
- **Copie de sauvegarde** : à l'ouverture DANS L'ÉDITEUR d'une carte du
  dossier des cartes dont `format_read` < 20 et que l'arrondi modifie, copie
  du dossier dans `user://maps/_sauvegardes/<id>_f<format>_<date>/` avant
  tout enregistrement (jamais deux fois la même), message dans `load_notes`
  (FR/EN : nombre de valeurs arrondies, chemin de la copie). En jeu
  (`EditorMapDef.custom`), migration en mémoire seulement, rien n'est écrit.
- **Carte devenue invalide** : le validateur tourne avant et après
  l'arrondi ; toute erreur NOUVELLE est listée dans `load_notes` (« après le
  passage aux cubes de 5 cm : … ») ; la carte s'ouvre quand même, rien n'est
  supprimé, la copie reste ; `--check` (CLI) l'affiche et sort en 1.
- Cartes du jeu et fixtures : DRAFT ARENA réécrite au format 20 ; fixtures
  anciennes gardées (elles testent la chaîne de migration) ; goldens
  `tests/fixtures/levels/*_layout_f16.json` régénérés (l'export arrondit),
  avec un test qui vérifie que TOUTES les valeurs d'une description sont sur
  la grille de 5 cm.
- Cartes partagées en réseau : l'hôte envoie le texte migré
  (`file_texts()` au format 20), forme canonique respectée ; à vérifier par
  `mp_custommap_*`.

### 2.6 Éditeur et validateur

- Accrochage : grille 1 m, fin 0,5 / 0,25 / 0,1, **libre 0,05** (au lieu de
  0,01) ; plafond (SpinBox) par 0,05 ; altitudes déjà par 0,05.
- Rotation des murs libres, pièces et piliers : **conservée** (15°, Alt 1°),
  rendue en escalier (§ 2.2) ; l'aperçu 3D de l'éditeur montre l'escalier
  (même `MeshMapGeometry`).
- Validateur : hauteur de marche calculée en cubes (§ 2.3) pour la garde au
  plafond `_step_height` ; nouvel avertissement si une volée a des marches
  de 25 cm ou plus (H trop grande pour la longueur) ; contrôle
  `LayoutCheck` (test, et `--check`) : architecture d'une description en
  faces axiales et sommets sur 5 cm.

### 2.7 Coût (cible GTX 1050, 60 i/s en MEDIUM)

- Mur en biais : ≈ 16 triangles par rangée de marches ; marches de 10 cm :
  ≈ 1 300 triangles pour un mur à 45° de 5 m × 3 m (12 avant). Carte d'essai
  des murs en biais : **4 620 triangles** (216 avant), soit moins qu'un seul
  décor cubique (2 000 à 10 000). Une carte riche en murs courbes : quelques
  dizaines de milliers de triangles, mêmes appels de dessin (groupes par
  matériau et salle), collisions inchangées.
- Escaliers en cubes : marches pleines déjà en pavés ; colimaçon et
  garde-corps en escalier : quelques milliers de triangles par escalier.
- Mesure de référence au lot E : `tools/perf.sh` (`render_perf`) sur DRAFT
  ARENA et BUNKER K-7 en MEDIUM, avant / après, sur la GTX 1050.

## 3. Lots

Chaque lot ne touche que ses fichiers ou son bloc dans les fichiers partagés
(`mesh_map_geometry.gd` : une fonction par lot). Ordre : **A d'abord** (ou en
parallèle avec C), puis **B et D en parallèle**, **C** à tout moment,
**E en dernier**.

| lot | contenu | fichiers | tests et scénarios | fini quand |
|---|---|---|---|---|
| **A — grille de 5 cm et migration** (premier) | `round_cube`, accrochage libre 0,05, plafond par 0,05, export arrondi, `UNDER_SLAB` retiré, format 20, `snap_architecture`, copie de sauvegarde, erreurs nouvelles signalées, DRAFT ARENA au format 20, goldens régénérés | `scripts/editor/editor_map.gd` (FORMAT, `_migrate`), `scripts/editor/map_cube_snap.gd` (nouveau), `map_snap.gd`, `map_geom.gd`, `map_transform.gd`, `map_vertical.gd`, `map_panels.gd`, `map_layout_export.gd`, `map_validator.gd`, `scripts/game/map/custom_map_guard.gd` (borne de format), `assets/maps/draft_arena/*.json`, `tests/fixtures/levels/*` | `tests/test_voxel_archi_migration.gd` (nouveau : chaque fixture et `map_summary/map_verruckt.json` migrent, valeurs sur 5 cm, copie faite une fois, carte invalide signalée et conservée), `test_levels_migration`, `test_levels_reference`, `test_map_share`, `test_map_editor_freeform` ; scénarios `map_editor`, `map_editor_freeform`, `draft_arena`, `mp_custommap_host/client` | toute description exportée (fixtures, DRAFT ARENA, cartes de test) n'a que des multiples de 5 cm ; aucune carte de l'utilisateur (copie de `user://maps`) ne gagne d'erreur |
| **B — murs, piliers, courbes** | escalier de cubes généralisé (pilote) : raccords, piliers tournés, murs courbes rastérisés d'un bloc, cours tournées (`walls`), cadres des ouvertures en biais, sols `biais_*` jusqu'à l'axe du mur | `mesh_map_geometry.gd` (`_stepped_piece`, bloc murs), `scripts/editor/map_layout_export.gd` (`_obliques`, `_pocket_oblique` : marquer les arcs), `scripts/game/barricades/barricade_fit.gd` si besoin | `tests/test_voxel_archi.gd`, `test_map_editor_diagonal`, `test_map_editor_walls`, `test_barricade_wall_fit` ; scénarios `map_editor_diagonal`, `map_editor_freeform`, `voxel_archi_look` (captures) | aucune face non axiale dans les nœuds `*__wall`, `*__biais`, `*__block` d'une carte de l'éditeur ; collisions et navigation identiques |
| **C — textures** | les 36 clés de `SURFACES` + décor + spéciales unies converties (12 générateurs : béton, carrelage, planches, tôle rivetée, mur peint, pierre à veines `glow`, dalles de plafond, moquette, lambris + papier peint, briques, velours, pavés), textures importées réduites et au plus proche, planche de barricade, vignettes de l'éditeur, test de palette ; suppression de `surface.gdshader` et `NoiseLattice` s'ils ne servent plus | `scripts/game/map/pixel_surfaces.gd`, `assets/shaders/pixel_surface.gdshader`, `scripts/game/world_look.gd`, `map_texture_lib.gd`, `assets/shaders/map_texture.gdshader`, `scripts/editor/map_icons.gd`, `map_catalog.gd` (`surface_look`), `scripts/game/barricades/barricade.gd` (planche), `tools/blender/voxel/voxel_lib.py` (teintes ajoutées) | `tests/test_voxel_archi.gd` (toutes les clés, palette, déterminisme), `test_map_textures`, `test_map_editor` ; scénarios `map_textures_look`, `visual_look`, `bunker_*` (captures) | `WorldLook.surface(k)` est pixel art pour toute clé ; captures BUNKER K-7 et DRAFT ARENA relues (2 passes) |
| **D — escaliers, rampes, garde-corps** | marches en cubes (§ 2.3), rampe en marches, colimaçon carré, garde-corps en cubes et en escalier, paliers et séparation, `slope` en terrasses ; collisions inchangées | `scripts/game/map/stair_gen.gd` (répartition en cubes), `mesh_map_geometry.gd` (`_stair`, `_spiral`, `_stair_edge`, `rails`, bloc escaliers droits), `scripts/editor/map_validator.gd` (`_step_height`, avertissement 25 cm) | `test_stairs`, `test_stairs_floors`, `test_stairs_top_wall`, `test_voxel_archi` (marches entières, sommets sur 5 cm) ; scénarios `stairs_types`, `stairs_floors`, `stairs_hordes`, `levels_nav`, `levels_play` | toutes les marches et garde-corps en faces axiales sur 5 cm, hordes et joueur montent comme avant |
| **E — cartes Blender, contrôle final, perf** | `tools/blender/mesh_map.py` (test_levels : mêmes règles), `LayoutCheck` (toute l'architecture d'une carte jouable), BUNKER K-7 relu, mesure GTX 1050, docs (ART_DIRECTION, MAP_AUTHORING, ARCHITECTURE), suppression des réglages de comparaison du pilote | `tools/blender/mesh_map.py`, `assets/maps/test_levels/*`, `scripts/game/map/layout_check.gd` (nouveau), docs | `test_voxel_archi` (toutes les cartes du jeu), `tools/perf.sh render_perf` | aucune face non axiale ni sommet hors grille dans l'architecture des cartes du jeu ; 60 i/s en MEDIUM sur GTX 1050 |

## 4. Pilote

Fait sur la branche `voxel-archi` :

- `scripts/game/map/pixel_surfaces.gd` : bibliothèque pixel art (béton de
  bunker à banches et fissures en escalier, carrelage d'hôpital à carreaux
  fêlés ou manquants et sang séché, mur peint à soubassement vert d'eau
  écaillé, coulures et crasse au pied), 64 × 64, déterministe ;
  `assets/shaders/pixel_surface.gdshader` ; `WorldLook.surface` rend ces 3
  clés en pixel art.
- `MeshMapGeometry._stepped_piece` : murs `obliques` en escalier de marches
  de 10 cm, faces visibles seulement, deux matériaux selon le côté, normale
  d'éclairage penchée (`step_shade`), collision `CollisionBox` lisse
  inchangée.
- Contrôles : `tests/test_voxel_archi.gd` (clés, déterminisme, soubassement,
  faces axiales et sommets sur 5 cm, côtés, marche de 10 cm) ; scénario
  `tests/autotest/voxel_archi_look.gd` (@rendu, hors check : captures, le
  joueur bute sur le mur, mesure ; `ARCHI_GRAIN`, `ARCHI_SHADE` pour
  comparer).
- Passes de captures : (1) marches de 5 cm, éclairage par face : rayures
  claires et sombres, moiré au loin, coulures trop nombreuses, taches du
  béton trop fortes ; (2) normale d'éclairage penchée : rayures atténuées,
  le moiré du contour reste ; marches de 10 cm comparées : moiré presque
  disparu, deux fois moins de triangles → retenu ; (3) final.
- Mesures : 4 620 triangles pour les murs en biais de la carte d'essai
  (9 442 en marches de 5 cm, 216 avant) ; 12 à 23 ms par texture générée ;
  ≈ 420 i/s sur la vue de l'octogone (RTX A2000, sans valeur pour la
  GTX 1050 : mesure au lot E).

## 5. Lot C (fait) : textures pixel art de toutes les surfaces

- `PixelSurfaces` : 12 générateurs (béton, carrelage, planches, tôle,
  mur peint, pierre à veines lumineuses, dalles de plafond, moquette,
  lambris et papier peint, briques, velours, pavés) réglés par clé (teinte,
  taille, usure) : les **37 clés** de `WorldLook.SURFACES` (sols, murs,
  plafonds, décor, théâtre) et `plank` (encadrement des fenêtres,
  `Barricade.plank_material`, clé spéciale des cartes en maillage). Images
  64 × 64 RGBA (alpha = 1 - lueur), variante mate (`specular_disabled`) pour
  plâtre, pierre, brique, tissu. Teinte `brick` ajoutée à `DECOR_PALETTE`.
- `surface.gdshader` supprimé ; `NoiseLattice` gardé (caisse au hasard,
  zombies). Les cartes grille ne créent plus tous les matériaux : seules les
  clés citées sont générées.
- Spéciales unies (`chalk`, `paper`, `paint_*`, `cable_blue`, `rubber`) :
  teintes de la palette.
- Textures importées : `MapTextureLib.pixelate` (taille × 20 pixels de large,
  moyenne de zone, au plus proche si l'image est plus petite), lues au plus
  proche sur la grille du monde ; aperçus de l'éditeur au même grain.
- Vignettes de l'éditeur (`MapIcons.surface_texture`) : 2 m × 1,2 m de la
  vraie texture, éclaircie ; mur vu de face.
- **Génération gardée (pas de PNG)** : 38 images en 355 ms en tout (9 ms en
  moyenne, treillis de `blotch` mis en cache) ; au lancement le menu en crée
  14 (154 ms), BUNKER K-7 5 de plus (36 ms sur 1,33 s de chargement), DRAFT
  ARENA 4 (27 ms sur 0,95 s).
- Coût GPU (`perf_costs --only=surface`, BUNKER K-7 labo + 24 zombies,
  RTX A2000, 1080p MEDIUM) : `pixel_surface.gdshader` +0,07 ms contre une
  couleur unie (`surface.gdshader` : +0,08 ms) ; `map_tour` : pire vue
  277 i/s (266 avant), GPU 2,82 à 2,98 ms (2,86 à 3,06 avant).
- Passes de captures (`voxel_textures_look`) : (1) griffures et bâtons
  répétés tous les 3,2 m, fissures trop longues, rouille rouge sang, veines
  de la salle rituelle trop nombreuses, dalles de plafond tombées trop
  fréquentes, joints du carrelage trop contrastés ; (2) corrigés, sang des
  carreaux en trait rouge vif répété ; (3) sang en tache brun-rouge sombre.
