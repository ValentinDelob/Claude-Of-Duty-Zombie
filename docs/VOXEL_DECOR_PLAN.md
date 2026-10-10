# Décors cubiques de l'éditeur de cartes — inventaire, lots et marche à suivre

Demande : **tous les décors que l'éditeur de cartes peut poser sont cubiques**
(GAME_CONCEPT.md § 4.19, docs/ART_DIRECTION.md) : décor et objets de carte en
**cubes de 5 cm**, rien de non cubique, textures « un pixel = un cube »,
collisions en `CollisionBox` (jamais un modèle Blender). La conversion ne
change que le **visuel** : mêmes identifiants, emprises (`fp`), hauteurs (`h`),
blocage (`bloque`), `support`, montage et collisions ; les cartes existantes
se chargent et se jouent pareil.

État (pilote) : 3 décors convertis (`caisses`, `sacs_sable`,
`foyer_pierres`) ; le reste est listé « à faire » dans
`tests/test_voxel_decor.gd` (`TODO_LOT1` à `TODO_LOT4`).

## 1. Inventaire

Contrôle : `godot --headless --path . -s res://tools/voxel_check.gd -- <fichier.glb> --statique`
(VoxelCheck, grille de 5 cm) sur chaque `.glb` de `assets/models/props/` :
**tous échouent** (faces obliques, sommets hors grille, ombrage lissé). Les
décors construits par le code (`EditorPrefabs`, scripts des objets) utilisent
des cylindres, sphères, boîtes tournées ou des tailles hors grille : aucun
n'est cubique, sauf la station de construction.

Collision : « cat. » = pavés `boxes` du catalogue (description : `blockers`) ;
« json » = `<modèle>.collision.json` à côté du `.glb` ; « — » = aucune.

### 1.1 Décor (`MapCatalog.PREFABS`, onglet Décor)

| id | source avant | fp | h (m) | bloque | collision | support / montage | lot |
|---|---|---|---|---|---|---|---|
| **gravats** | glb `rubble_heap_b` (2 040 tri.) | 6×6 | 1,5 | solide | json | — | **1 ✔** |
| **gros_gravats** | glb `rubble_heap_a` (3 250) | 10×8 | 2,3 | solide | json | — | **1 ✔** |
| **eboulis** | glb `rubble_heap_c` (3 754) | 12×6 | 2,9 | solide | json | — | **1 ✔** |
| **debris_epars** | glb `debris_scatter` (2 566) | 6×6 | 0,25 | non | — | — | **1 ✔** |
| **planches** | glb `debris_planks` (520) | 4×3 | 0,4 | non | — (json ignoré) | — | **1 ✔** |
| **poutre** | glb `debris_beam` (1 718) | 14×4 | 1,8 | solide | json | — | **1 ✔** |
| **lustre_tombe** | glb `chandelier_fallen` (6 084) | 7×6 | 1,5 | barriere | json | — | **1 ✔** |
| **caisses** | glb `stage_crates` (3 176) | 5×4 | 1,5 | solide | json (5 pavés tournés) | — | **pilote ✔** |
| **tonneaux** | glb `blue_barrel_group` (2 296) | 4×4 | 1,8 | barriere | json | — | **2 ✔** |
| **sacs_sable** | code `EditorPrefabs` (boîtes tournées) | 4×2 | 0,9 | solide | cat. | support 0,9 | **pilote ✔** |
| **table_renversee** | code (plateau incliné) | 4×2 | 0,9 | solide | cat. (2) | — | **2 ✔** |
| **chaise_renversee** | code (assise inclinée) | 2×1 | 0,5 | barriere | cat. | — | **2 ✔** |
| **chaise** | glb `folding_chair` (156) | 1×1 | 0,9 | barriere | cat. | — | **2 ✔** |
| **bureau** | glb `desk` (924) | 3×2 | 0,8 | solide | json | support 0,78 | **2 ✔** |
| **etagere** | glb `reel_shelf` (3 052) | 3×1 | 1,8 | solide | json | — | **2 ✔** |
| **fauteuils** | glb `seat` ×4 (`copies`, 352) | 5×2 | 1,1 | barriere | cat. | — | **2 ✔** |
| **fauteuil_casse** | glb `seat_broken_b` (368) | 2×3 | 0,7 | barriere | cat. | — | **2 ✔** |
| **pupitre** | glb `lectern` (672) | 2×2 | 1,2 | solide | json | — | **2 ✔** |
| **projecteur_film** | glb `projector` (1 596) | 2×3 | 1,9 | solide | json | — | **2 ✔** |
| **chariot** | code (roues cylindres) | 3×2 | 1,0 | solide | cat. | support 0,85 | **2 ✔** |
| **epave_voiture** | code (boîtes tournées, roues) | 9×4 | 1,5 | solide | cat. (2) | — | **2 ✔** |
| **buches** | code (cylindres) | 1×1 | 0,15 | non | — | — | **3 ✔** |
| **foyer_pierres** | code (sphères, cylindres) | 3×3 | 0,3 | barriere | cat. | — | **pilote ✔** |
| planches_brulees | code (boîtes tournées) | 5×2 | 0,1 | non | — | — | **3 ✔** |
| electrodes | code (cylindres, sphères) | 3×1 | 1,1 | barriere | cat. (2) | — | **3 ✔** |
| bobine_tesla | code (cylindres, sphère) | 1×1 | 1,55 | solide | cat. | — | **3 ✔** |
| flaque_eau | code (disques plats, eau) | 3×3 | 0,01 | non | — | — | **3 ✔** |
| petite_flaque | code (disque plat) | 2×2 | 0,01 | non | — | — | **3 ✔** |
| torche_murale | code (manche incliné) | 1×1 | 0,5 | non | — | mur, y 1,8 | **3 ✔** |
| tuyau_vapeur | code (cylindres) | 1×1 | 0,2 | non | — | mur, y 1,2 | **3 ✔** |
| boitier_electrique | code (porte tournée, fils) | 1×1 | 0,45 | non | — | mur, y 1,6 | **3 ✔** |
| tuyau_fuite | code (cylindre) | 2×1 | 0,2 | non | — | mur, y 2,0 | **3 ✔** |
| cable_suspendu | code (cylindres fins) | 1×1 | 0,65 | non | — | plafond | **3 ✔** |

### 1.2 Luminaires (`MapCatalog.LIGHTS`, `EditorPrefabs.fixture`)

| id | source avant | fp | montage | collision | lot |
|---|---|---|---|---|---|
| ampoule | code (fil, sphère émissive) | 1×1 | plafond, drop 0,75 | — | **3 ✔** |
| suspension | code (abat-jour conique) | 1×1 | plafond, drop 0,7 | — | **3 ✔** |
| neon | code (tubes cylindres) | 3×1 | plafond, drop 0,15 | — | **3 ✔** |
| lustre | glb `chandelier` (6 032) à l'échelle 0,25 | 3×3 | plafond, drop 1,1 | — | **3 ✔** |
| applique | glb `sconce` (580) | 1×1 | mur, y 2,0 | — | **3 ✔** |
| lampe_bureau | code (pied, abat-jour) | 1×1 | sol, y 0,45 | — | **3 ✔** |
| projecteur | code (trépied oblique) | 2×2 | sol, y 1,7 | cat. (barriere) | **3 ✔** |
| bougies | code (cylindres) | 1×1 | sol, y 0,25 | — | **3 ✔** |
| feu | code (baril cylindre, flammes) | 2×2 | sol, y 1,15 | cat. (solide) | **3 ✔** |

Les **effets** (`MapCatalog.EFFECTS` : flammes, fumées, étincelles, arcs,
eau, ambiance) sont des particules et des lumières, sans objet : hors du
périmètre (« particules cubiques » : chantier à part, GAME_CONCEPT.md § 4.19).

### 1.3 Objets de carte (scripts du jeu)

| type | constructeur | cubique ? | dimensions | collision | lot |
|---|---|---|---|---|---|
| porte (blindée / bois / grille) | `interact/door.gd` `_build_steel`, `_build_wood`, `_build_gate`, `_decorate` | non : volants cylindres, entretoise en biais, barreaux cylindres | largeur × 2,5 × 0,22 | StaticBody (w, h, 0,9) | **4 ✔** |
| debris (planches / gravats) | `door.gd` `_build_debris`, `_build_rubble` | non : boîtes tournées au hasard, fers ronds | largeur × hauteur de l'ouverture | corps de la porte | **4 ✔** |
| porte_courant | `door.gd` `_build_steel` | presque : une boîte, épaisseur 0,22 hors grille | w × 2,5 × 0,22 | corps de la porte | **4 ✔** |
| passage | aucun objet (découpe du mur) | — | — | — | — |
| fenetre (fenêtre / porte / porte double) | `barricades/barricade.gd` `_build_planks`, `zombie_door_model.gd` | non : planches roulées ±0,44 rad, planches dentelées | 1 ou 2 m × 0,95–2,35 | barrière (BoxShape) | **4 ✔** |
| boite (caisse au hasard) | `interact/box_model.gd` + `assets/models/props/mystery_box.glb` (`tools/blender/props/mystery_box.py`), faisceau `CylinderMesh` | non (6 886 faces fautives) | 1,8 × 0,85 × 0,85 | StaticBody `BODY_SIZE` | **4 ✔** |
| courant | `interact/power_switch.gd` | non : câbles cylindres, levier tourné, sphère | 0,7 × 0,95 × 0,22 | — | **4 ✔** |
| teleporteur / arrivee | `interact/teleporter.gd` `_build_pad` | non : disques, tore, cônes, sphères | Ø 3,0 / 2,1 | — | **4 ✔** |
| poste_central (mur / sol) | `interact/mainframe.gd` | non : cadrans, capsules, sphère, socle cylindre | 2,2 × 2,3 × 0,7 / Ø 4,4 | StaticBody | **4 ✔** |
| piege (panneau) et levier | `interact/electric_trap.gd`, `interact/trap_lever.gd` | non : levier tourné, voyant sphère | 0,45 × 0,6 × 0,15 | — | **4 ✔** |
| evacuation | `interact/evac_door.gd` | presque : boîtes, voyant à y 2,125–2,275 hors grille | 1,4 × 2,1 × 0,15 | CollisionBox | **4 ✔** |
| station | `interact/build_station.gd` `build_model` | **oui** (contrôlée par `tests/test_build_rules.gd`) | 1,6 × 2,1 × 0,8 | 2 CollisionBox | — |
| caisse / baril (types historiques) | `MeshMapGeometry` (bloc de la description) | presque : une boîte à matériau procédural, posée au centimètre | 1 × 1 × 1 / 0,5 × 0,9 × 0,5 | bloc de géométrie | **4 ✔** |
| depart, apparition, lampe, bloc_invisible | aucun objet visible | — | — | — | — |

**Lot 4 fait** (contrôle : `tests/test_voxel_objects.gd`, VoxelCheck de
chaque objet, pièces mobiles dans leur repère ; collisions, points
d'interaction, durées et animations inchangés) :

- taille fixe, sous Blender (`tools/blender/voxel_props/objets.py` ->
  `assets/models/props/voxel/objets/<objet>.glb`, une pièce par nœud
  `voxel__<objet>_<pièce>__<type>`, lue par `VoxelBuild.parts`) : `boite`
  (coffre, couvercle sous le pivot de la charnière, intérieur et fond qui
  s'allument : `voxel_glow.gdshader` ; ≈ 10 100 tri.), `courant` (boîtier et
  câbles, levier sous son pivot, gyrophare ; 1 700), `levier_piege` (piège et
  second levier : panneau, voyant ; 510), `teleporteur` / `arrivee` (socle,
  anneau et boules au matériau lumineux ; 4 300 / 3 100),
  `poste_central_mur` (armoire, tubes, voyant ; 9 300), `poste_central_sol`
  (socle en marches, anneau à fleur, voyant, câble ; 9 200 ; la collision
  garde le tronc de cône), `evacuation` (bâti, battant qui recule, voyant
  posé sur la grille ; 3 200). Colonne de lumière et halo de la caisse :
  pavés sur la grille. `mystery_box.glb`, `mystery_box.py` et
  `mystery_box.gdshader` supprimés ;
- taille de la carte, construits par le jeu (`scripts/game/map/voxel_build.gd`,
  `VoxelBuild`, repère Godot, matériau « voxel ») : portes blindée, bois,
  grille et porte du courant (20 cm d'épaisseur visuelle, cadre, prix peint
  en chiffres de 3 × 5 cubes des deux côtés ; 3 300 à 6 000 tri. pour 2 m),
  débris planches et gravats (tas en blocs, planches et fers qui dépassent,
  poutre ou dalle en escalier), planches des barricades (`plank_mesh`,
  26 × 3 × 1 et 18 × 3 × 1 cubes, à plat sur la grille au repos ; elles ne
  tournent qu'en vol), portes à zombies (`ZombieDoorModel` : deux couches de
  cubes dans la tranche de 10 cm), caisse et baril de l'éditeur
  (`MeshMapGeometry.decor_model`, à la taille du bloc, dont la collision
  reste celle du bloc).

Architecture (hors des 4 lots, **décision à prendre** : la changer modifie
les collisions et le jeu) : escaliers (`StairGen`, marches ≈ 18 cm, rampe en
pente, colimaçon à secteurs), garde-corps (lacet libre, 8 cm), murs et
piliers tournés ou courbes, ouvertures (seuils 0,95 / 2,35 m). Les murs et
sols sur la grille de 0,25 m sont déjà sur celle de 5 cm.

## 2. Les 4 lots (indépendants)

Chaque lot ne touche que **ses** fichiers ou **son bloc** dans les fichiers
partagés (blocs séparés par une ligne vide ou un commentaire : git fusionne
sans conflit). Fichiers partagés et règle :

- `scripts/editor/map_catalog.gd` : chaque lot ne modifie que les lignes de
  ses entrées (PREFABS lignes des gravats = lot 1, `caisses` … `epave_voiture`
  = lot 2, décors des effets et `LIGHTS` = lot 3) ;
- `tests/test_voxel_decor.gd` : le lot vide **son** `TODO_LOTn` et ajoute ses
  entrées à `FROZEN` (une entrée par ligne, à la fin du dictionnaire, chaque
  lot dans un bloc précédé d'un commentaire « # Lot n ») ;
- `tools/blender/props/catalog_props.py` : `BUILDERS` est rangé par lot ;
  chaque lot retire ses lignes et ses fonctions `m_*` (le dernier lot qui le
  vide supprime le script et `NO_FLOOR`) ;
- `scripts/game/map/editor_prefabs.gd` : chaque lot retire ses branches de
  `build`, `_effect_decor`, `fixture` (le lot qui vide la dernière supprime
  la classe et ses appels : `MeshMapBuilder._build_props`,
  `MapLayoutExport` clé `build`) ;
- `scripts/game/map/mesh_map_builder.gd` `_special` : ne retirer une clé
  (braises, eau, cuivre...) que si plus rien ne l'utilise (grep).

| lot | entrées | fichiers propres | fichiers partagés (son bloc) |
|---|---|---|---|
| **1 — gravats et ruines** | gravats, gros_gravats, eboulis, debris_epars, planches, poutre, lustre_tombe (7) | `tools/blender/voxel_props/ruines.py` (nouveau), `assets/models/props/voxel/{gravats,gros_gravats,eboulis,debris_epars,planches,poutre,lustre_tombe}.*` ; supprime `rubble_heap_a/b/c`, `debris_scatter`, `debris_planks`, `debris_beam`, `chandelier_fallen` (.glb, .import, .collision.json) | catalogue (lignes `gravats` … `lustre_tombe` : retirer `remap`), `TODO_LOT1`, `catalog_props.py` (bloc lot 1, `heap`, `chunk`...) |
| **2 — mobilier et stockage** | tonneaux, table_renversee, chaise_renversee, chaise, bureau, etagere, fauteuils, fauteuil_casse, pupitre, projecteur_film, chariot, epave_voiture (12) | `tools/blender/voxel_props/mobilier.py` (existe : caisses, sacs_sable), modèles `voxel/…` ; supprime `blue_barrel_group`, `folding_chair`, `desk`, `reel_shelf`, `seat`, `seat_broken_b`, `lectern`, `projector` | catalogue (lignes `tonneaux` … `epave_voiture`), `TODO_LOT2`, `catalog_props.py` (bloc lot 2), `editor_prefabs.gd` (`build` : table, chaise, chariot, épave) |
| **3 — décors des effets et luminaires** | buches, planches_brulees, electrodes, bobine_tesla, flaque_eau, petite_flaque, torche_murale, tuyau_vapeur, boitier_electrique, tuyau_fuite, cable_suspendu ; ampoule, suspension, neon, lustre, applique, lampe_bureau, projecteur, bougies, feu (20) | `tools/blender/voxel_props/effets.py` (existe : foyer_pierres), `tools/blender/voxel_props/luminaires.py` (nouveau), modèles `voxel/…` ; supprime `chandelier`, `sconce` | catalogue (décors des effets et `LIGHTS`), `TODO_LOT3`, `catalog_props.py` (bloc lot 3), `editor_prefabs.gd` (`_effect_decor`, `fixture`) |
| **4 — objets de carte** | porte (3 variantes), debris (2), porte_courant, fenetre (planches, portes à zombies), boite, courant, teleporteur, arrivee, poste_central, piege, levier, evacuation, caisse, baril | `tools/blender/voxel_props/objets.py` (nouveau) et/ou les scripts `scripts/game/interact/*.gd`, `scripts/game/barricades/*.gd` ; `tools/blender/props/mystery_box.py` remplacé ; un test cubique par objet (comme `tests/test_build_rules.gd` pour la station) | `TODO_LOT4` |

Remarques par lot :

- Lot 1 : les tas sont gros (jusqu'à 6 × 3 × 2,9 m) : garder des faces
  fusionnées (peu de paliers de couleur par matière, `C.grain(levels=2..3)`),
  budget conseillé < 15 000 triangles par modèle. Les pentes deviennent des
  marches de cubes ; les pavés de collision (json) ne bougent pas.
- Lot 2 : `fauteuils` est un modèle répété (`copies`, MultiMesh
  `instances`) : un modèle `voxel/fauteuils_siege` d'UN fauteuil, `copies`
  inchangé (vérifier `MeshMapBuilder._build_instances`). Bureau et chariot
  gardent leur `support` (hauteur du dessus : 0,78 m n'est pas sur la grille,
  le plateau se termine à 0,80 m ; c'est `support` qui fait foi pour poser une
  lampe, à garder tel quel).
- Lot 3 : décors muraux (origine sur la face du mur, +Z Godot = -Y Blender
  vers la pièce) et au plafond (origine au plafond, modèle vers le bas). Les
  flaques ont 1 cm de haut : une couche d'un cube (5 cm) à moitié enfoncée
  n'est pas possible (pas de sous-cube) ; poser une couche de 5 cm, type
  `ns`, couleur d'eau sombre, ou garder la hauteur et laisser `h` (aperçu).
  Luminaires : `fixture()` charge déjà un modèle (`model` + loader) ; passer
  chaque luminaire à `"model": "voxel/<id>"` sans `scale` (le lustre est
  modélisé à sa taille finale) ; les parties lumineuses en matière `glow`.
- Lot 4 : les objets de carte ne sont pas des entrées `model` du catalogue :
  soit un .glb `voxel/<objet>` chargé par leur script (même matériau
  `MeshMapBuilder.material_for("voxel")`), soit des boîtes posées par le
  script sur la grille de 5 cm (comme `BuildStation.build_model`). Leurs
  parties mobiles (battants, levier, couvercle) restent des nœuds séparés qui
  tournent ; chaque partie est cubique dans son repère. Garder les
  collisions (StaticBody / CollisionBox) et les tailles de jeu.

## 3. Patron de conversion (mis en place par le pilote)

- **Modèle** : `assets/models/props/voxel/<id>.glb`, `<id>` = identifiant du
  catalogue. Un seul objet `voxel__<id>__<type>` (`block` : ombre portée ;
  `ns` : sans ombre). Origine identique à l'ancien modèle (centre de
  l'emprise au sol ; mur : face du mur ; plafond : sous le plafond). Repère
  Blender (Z en haut, avant -Y = +Z Godot).
- **Catalogue** : `"model": "voxel/<id>"` remplace `"model": "<ancien>"` ou
  `"build": "<id>"` ; tout le reste est **inchangé** (`fp`, `h`, `bloque`,
  `boxes`, `surface`, `support`, `mount`, `y`, `copies`...) ; `scale` et
  `remap` disparaissent (modèle à sa taille, couleurs de face).
- **Décor construit par le code (`build`) → modèle** : ses collisions étaient
  déjà les `boxes` du catalogue ; elles restent dans le catalogue. Avec
  `boxes`, l'export pose `"nocollide": true` sur l'objet (le modèle n'ajoute
  aucune collision) et les pavés deviennent des `blockers` : même résultat
  qu'avant. La branche de `EditorPrefabs` est supprimée.
- **Ancien .glb → modèle** : `git mv <ancien>.collision.json
  voxel/<id>.collision.json` (contenu identique, octet pour octet) ; `git rm`
  de l'ancien `.glb` et de son `.import` ; fonction `m_*` retirée de
  `catalog_props.py`.
- **Jeu** : `MeshMapBuilder.model_name_ok` admet le seul préfixe `voxel/`
  (`CustomMapGuard.asset_name_ok` pour le reste) ; `MapPrefabLib.catalog_boxes`
  et `_collision_boxes` lisent `voxel/<id>.collision.json` ; matériau unique
  `voxel` (`MeshMapBuilder._special` : `assets/shaders/voxel_prop.gdshader`,
  couleur de face COLOR_0, faces d'alpha 0 émissives) ; le contour noir
  (`ScreenOutline`) s'applique comme au reste du décor.
- **Blender** : `tools/blender/voxel/voxel_lib.py` (matières du décor
  `DECOR_MATERIALS`, `glow` émissive par alpha 0, palette `DECOR_PALETTE`,
  `noise` et `tone` pour la texture par cube) et
  `tools/blender/voxel_props/common.py` (export, contrôle Godot, planches).

## 4. Marche à suivre pour convertir un décor

1. **Relever l'ancien** : entrée du catalogue (`fp`, `h`, `bloque`, `boxes`,
   `surface`, `support`, `mount`, `y`) et, pour un .glb, son
   `.collision.json` et ses dimensions (`catalog_props.py`, ou VoxelCheck qui
   les imprime). Copier l'ancien .glb dans le dossier de travail
   (`<scratchpad>/old_glb/`) pour la planche « avant ».
2. **Décrire le modèle** dans le script de sa famille
   (`tools/blender/voxel_props/<famille>.py`) : une fonction `<id>()` qui
   renvoie un `vx.Model(C.CUBE)` (cubes de 5 cm, entiers), ajoutée à
   `BUILDERS` (et à `BEFORE` : id -> nom de l'ancien .glb) ; attribut
   `<fonction>.kind = "ns"` pour un décor sans ombre (flaque, câble).
   - Repère Godot (x, y, z) -> cellules Blender (x, -z, y) / 0,05. Partir des
     pavés de collision pour placer les volumes (ils restent justes).
   - Matières : `wood`, `stone`, `concrete`, `fabric`, `rubber`, `metal`,
     `glass`, `glow` (émissive : braises, ampoules, écrans) ; teintes de
     `vx.DECOR_PALETTE` (`C.col(nom, facteur)`) ; ajouter une teinte à la
     palette plutôt qu'une couleur en dur, dans l'univers hôpital /
     laboratoire / zombies.
   - Texture « un pixel = un cube » : `C.fill(..., amp, levels)` (2 ou 3
     paliers, `amp` 0,03 à 0,1) ; détails peints par face (`C.paint` :
     étiquettes, bandes) plutôt que des cubes de plus ; arrondis et pentes en
     escalier ; rien de plus fin qu'un cube ; quarts de tour seulement (un
     objet en biais dans l'ancien modèle est remis d'aplomb).
   - L'ombrage peint (`vx.shade`) est appliqué à l'export.
3. **Exporter et contrôler** (Blender sans fenêtre, un seul à la fois) :
   `GODOT=<chemin de godot.exe> sh tools/blender.sh tools/blender/voxel_props/<famille>.py <id> --sheet <scratchpad>/decor --before <scratchpad>/old_glb`
   — la ligne `[voxel_props]` donne cellules, triangles, taille ; la ligne
   `[voxel_check]` sans « ÉCHEC » confirme la grille de 5 cm (sinon le script
   finit en erreur). `GODOT` : le `godot` du shell est un script, Python ne
   peut pas le lancer.
4. **Planche** `<scratchpad>/decor/<id>.png` (rangée « avant » si l'ancien
   .glb est donné, rangée « après » ; trois-quarts et face, contour noir) :
   la regarder (lecture d'image) et corriger, **au moins deux passes**
   (trous visibles entre cubes, détails illisibles, texture trop bruitée).
5. **Brancher** : catalogue `"model": "voxel/<id>"` (retirer `build`,
   `scale`, `remap`) ; pour un ancien .glb : `git mv` du `.collision.json`,
   `git rm` du .glb et de son `.import`, fonction `m_*` retirée ; pour un
   `build` : branche de `EditorPrefabs` retirée. Importer :
   `godot --headless --path . --import`.
6. **Tests** : retirer l'entrée de `TODO_LOTn`, ajouter ses valeurs d'avant
   à `FROZEN` (`tests/test_voxel_decor.gd`) ; mettre à jour les tests qui
   citent l'ancien nom (`grep -rn '<ancien>' tests`, dont
   `tests/fixtures/scale_layout_golden.json` : `"build":"<id>"` devient
   `"model":"voxel/<id>","nocollide":true` dans un prefab groupe ou avec
   `boxes`). Lancer
   `godot --headless --path . res://tests/test_runner.tscn -- --files=test_voxel_decor.gd,test_map_effects.gd,test_map_editor_decor.gd,test_map_scale.gd,test_map_prefabs.gd`,
   `tests/parse_all.gd`, la suite unitaire, puis les scénarios qui posent du
   décor (`map_editor_play`, `map_objects_play`, `map_decor_free`,
   `map_decor_scale`, `map_decor_stack`, `draft_arena`), un Godot à la fois.
7. **Docs** : ligne de l'inventaire ci-dessus (lot → ✔), docs/ART_DIRECTION.md
   si une famille entière change.

## 5. Pilote : décors convertis

| id | script | modèle | cellules | triangles | taille (m, x × y × z Blender) |
|---|---|---|---|---|---|
| caisses | `voxel_props/mobilier.py` | `voxel/caisses.glb` + `.collision.json` (ex-`stage_crates`) | 23 076 | 7 484 | 2,45 × 1,8 × 1,5 |
| sacs_sable | `voxel_props/mobilier.py` | `voxel/sacs_sable.glb` (ex-`build`) | 6 696 | 3 916 | 2,0 × 0,8 × 0,9 |
| tonneaux (lot 2) | `voxel_props/mobilier.py` | `voxel/tonneaux.glb` + `.collision.json` (ex-`blue_barrel_group`) | 14 602 | 8 806 | 1,9 × 1,55 × 1,8 |
| table_renversee (lot 2) | `voxel_props/mobilier.py` | `voxel/table_renversee.glb` (ex-`build`) | 901 | 2 134 | 1,6 × 0,75 × 0,85 |
| chaise_renversee (lot 2) | `voxel_props/mobilier.py` | `voxel/chaise_renversee.glb` (ex-`build`) | 140 | 420 | 0,85 × 0,4 × 0,45 |
| chaise (lot 2) | `voxel_props/mobilier.py` | `voxel/chaise.glb` (ex-`folding_chair`) | 140 | 458 | 0,4 × 0,45 × 0,85 |
| bureau (lot 2) | `voxel_props/mobilier.py` | `voxel/bureau.glb` + `.collision.json` (ex-`desk`) | 3 547 | 2 308 | 1,4 × 0,7 × 1,0 |
| etagere (lot 2) | `voxel_props/mobilier.py` | `voxel/etagere.glb` + `.collision.json` (ex-`reel_shelf`) | 2 938 | 4 182 | 1,2 × 0,4 × 1,8 |
| fauteuils (lot 2) | `voxel_props/mobilier.py` | `voxel/fauteuils_siege.glb` (UN fauteuil, ×4 par `copies` ; ex-`seat`) | 560 | 884 | 0,5 × 0,55 × 1,1 |
| fauteuil_casse (lot 2) | `voxel_props/mobilier.py` | `voxel/fauteuil_casse.glb` (ex-`seat_broken_b`) | 551 | 966 | 0,55 × 1,1 × 0,55 |
| pupitre (lot 2) | `voxel_props/mobilier.py` | `voxel/pupitre.glb` + `.collision.json` (ex-`lectern`) | 2 166 | 1 398 | 0,7 × 0,6 × 1,3 |
| projecteur_film (lot 2) | `voxel_props/mobilier.py` | `voxel/projecteur_film.glb` + `.collision.json` (ex-`projector`) | 6 165 | 3 980 | 1,0 × 1,4 × 1,9 |
| chariot (lot 2) | `voxel_props/mobilier.py` | `voxel/chariot.glb` (ex-`build`) | 1 644 | 1 950 | 1,25 × 0,7 × 1,0 |
| epave_voiture (lot 2) | `voxel_props/mobilier.py` | `voxel/epave_voiture.glb` (ex-`build`) | 45 526 | 10 652 | 4,3 × 1,7 × 1,4 |
| foyer_pierres | `voxel_props/effets.py` | `voxel/foyer_pierres.glb` (ex-`build`, braises `glow`) | 681 | 2 092 | 1,2 × 1,2 × 0,25 |

- `caisses` : cinq caisses de transport de laboratoire (cornières d'acier,
  cerclages, poignées, fermetures, croix rouge, bande de danger, flèches au
  pochoir) aux pavés de l'ancienne collision arrondis à 5 cm et remis
  d'aplomb ; la collision (pavés tournés de 4 à 15°) est gardée telle quelle.
- `sacs_sable` : trois rangs décalés (4, 3, 2 sacs de 0,5 × 0,7 × 0,3 m),
  bords en escalier, liens aux bouts, couture.
- `foyer_pierres` : dix pierres en cercle (faces vers le feu noircies), lit
  de cendres et de braises, quatre bûches calcinées croisées à braises
  émissives.

## 6. Lot 3 : décors des effets et luminaires convertis

Scripts : `voxel_props/effets.py` (décors des effets) et
`voxel_props/luminaires.py` (objets des 9 luminaires, type `ns`, parties
lumineuses en `glow`). Anciens `chandelier` et `sconce` supprimés ; branches
`_effect_decor` et `fixture` de `EditorPrefabs` retirées (un luminaire n'est
plus que son modèle) ; matériaux `embers_wood`, `charred`, `tar_glow`,
`water`, `copper`, `porcelain`, `paint_olive` retirés de
`MeshMapBuilder._special` (plus utilisés). Contrôle propre au lot :
`tests/test_voxel_decor_lot3.gd` (décor mural devant le mur, au plafond
dessous, flaques d'une couche, emprise ; faces émissives là où le jeu pose
la lumière ; matériau `voxel` sans ombre).

| id | cellules | triangles | remarque |
|---|---|---|---|
| buches | 104 | 366 | deux rangs de bûches croisées, lit de cendres et braises |
| planches_brulees | 259 | 1 104 | 5 planches en quarts de tour, bouts rongés, braises |
| electrodes | 264 | 876 | tiges à ±0,6 m, isolateurs, boules de cuivre |
| bobine_tesla | 436 | 862 | socle à bande de danger, bobinage, tore |
| flaque_eau | 446 | 1 016 | une couche de 5 cm (h 0,01 garde l'aperçu) |
| petite_flaque | 261 | 592 | idem |
| torche_murale | 96 | 286 | manche remis d'aplomb, tête à 0,15-0,25 m, 0,25 m du mur |
| tuyau_vapeur | 45 | 172 | bride, tuyau, raccord, vanne |
| boitier_electrique | 137 | 350 | porte ouverte à 90°, disjoncteurs, fils |
| tuyau_fuite | 182 | 428 | section en croix, manchons, colliers, fissure |
| cable_suspendu | 19 | 110 | boîte de dérivation, câble, brins de cuivre |
| ampoule | 28 | 144 | ampoule de 0,1 m à 0,75 m |
| suspension | 121 | 360 | abat-jour d'émail vert en escalier |
| neon | 160 | 200 | réglette, deux tubes de 1,2 m |
| lustre | 389 | 1 406 | à sa taille finale (sans `scale`), 12 bougies |
| applique | 108 | 316 | deux tulipes de verre dépoli à ±0,2 m |
| lampe_bureau | 76 | 238 | abat-jour d'émail, ampoule à 0,45 m |
| projecteur | 456 | 1 124 | mât, pieds en escalier, phare jaune vers +Z |
| bougies | 58 | 220 | sur un haricot d'infirmerie en acier |
| feu | 958 | 2 742 | fût rouillé en escalier, braises, flammes en cubes |

Reste hors du lot : les **particules** des effets (`MapEffects`) et des
impacts (`Fx`, `ParticlePool`) sont encore des panneaux texturés
(`QuadMesh`, textures de `assets/textures/fx/`, billboard), pas des cubes.
