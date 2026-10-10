# Direction artistique — style cubique

Le jeu a quitté le rendu réaliste de Black Ops 1 pour une identité propre :
un style **entièrement cubique (voxel)**, dans l'esprit de Trove
(GAME_CONCEPT.md § 4.19). Ce fichier décrit la direction en vigueur, la chaîne
de production des modèles cubiques et l'état de chaque famille d'objets. Les
anciennes notes d'observation de BO1 (zombies, armes, machines, salle de
KINO) sont gardées plus bas, sous **Historique**, pour mémoire : elles ne
sont plus une cible. Les images de référence vont dans `docs/reference/`
(ignoré par git) ; aucune image ni aucun asset d'Activision n'est intégré au
dépôt.

## Règles du style cubique

- Deux échelles seulement, l'une sous-multiple de l'autre :
  - **personnages et mobs : 1 cube = 2,5 cm** (40 par mètre) : un personnage
    de 1,80 m mesure 72 cubes. Mesuré sur la planche du zombie (un pixel de la
    planche ≈ 2 cm, une dent = 1 pixel) ;
  - **décor et objets de la carte : 1 cube = 5 cm** (20 par mètre) : une porte
    fait 40 cubes, un mur de 3 m en fait 60. 2 cubes de personnage = 1 cube de
    décor.
- **Règle absolue** : rien qui ne soit pas cubique ou pas à l'échelle. Pas de
  courbe, de biseau, de lissage, ni de détail plus fin qu'un cube.
- Arêtes sur la grille de l'échelle, normales alignées sur les axes, ombrage plat ;
  les objets posés sur une carte tournent par quarts de tour ; les pentes
  deviennent des marches.
- Personnages et zombies : cubes **articulés**, chaque cube rigidement lié à
  un os ; les membres tournent à n'importe quel angle quand ils sont animés,
  mais chaque membre reste fait de cubes. Le dos voûté, une épaule tombante...
  s'obtiennent par la **pose des os** ou par un **escalier de cubes**, jamais
  par un cisaillement.
- Textures : **un pixel = un cube**, une couleur unie par face de cube ; un
  léger **ombrage peint** (dessus clair, côtés un peu plus sombres, dessous
  dans l'ombre) aide la lecture, comme sur les planches de référence.
- Effets (sang, étincelles, flammes, fumée, éclats) : particules cubiques.
- Interface : pas forcément cubique, mais en harmonie avec le style.
- Vérification automatique : `VoxelCheck` (`scripts/game/map/voxel_check.gd`),
  outil `tools/voxel_check.gd` (`--anime` pour un personnage : chaque partie
  dans le repère de son os, grille de 2,5 cm ; `--statique` pour un objet,
  grille de 5 cm ; `--pas=<cm>` force le pas). L'éditeur de cartes et
  l'import de modèles refusent un modèle non conforme.
- **Contour noir** autour des pièces et ombrage simple, comme la planche de
  référence : rendu des planches de validation par coque inversée ; en jeu,
  passe en espace écran `ScreenOutline` (voir « Contour noir en jeu » plus
  bas ; option OPTIONS > VIDÉO > CONTOUR, activée par défaut).
- ❓ Lumières, post-traitement et ciel restent à décider (§ 4.19) ; l'étalonnage
  ci-dessous est celui du code actuel.

## Chaîne de production cubique (tools/blender/voxel/voxel_lib.py)

Bibliothèque Python pour Blender (5.2, toujours sans fenêtre :
`sh tools/blender.sh <script>.py`). Un script de modèle décrit des **cellules**
en unités de cube (repère Blender : Z en haut, avant vers -Y, gauche d'un
personnage vers +X), au pas `CUBE_CHAR` (2,5 cm, personnages et mobs) ou
`CUBE_DECOR` (5 cm, décor et objets), puis la bibliothèque construit, vérifie
et exporte.

| Fonction | Rôle |
|---|---|
| `Model(cube)` | grille de voxels au pas `cube` (m) : cellule (x, y, z) -> matière, os, partie, couleur |
| `m.box(x0, x1, y0, y1, z0, z1, mat, bone, part, color)` | pavé de cellules (bornes hautes exclues), écrase |
| `m.set(...)`, `m.clear(...)` | une cellule ; vider un pavé (bouche, narines...) |
| `m.layers(rows, origin, legend, bone, part)` | grilles colorées par couche (une chaîne par rangée, un caractère par cube) |
| `m.fill_gaps(parts)` | bouche les fentes d'un cube laissées par une sculpture |
| `m.face_color[(x, y, z, dir)]`, `m.face_mat[...]` | couleur / matière d'UNE face de cube (`dir` : `+x -x +y -y +z -z`) |
| `View(...)`, `view.frac(masque, cellule)`, `register`, `iou` | vue orthographique d'une planche : part d'un masque de pixels dans la case d'une cellule (sculpture par silhouettes), recalage et recouvrement |
| `paint_from_views(model, views, accept)` | chaque face tournée vers une vue et non cachée prend la couleur dominante de sa case projetée |
| `fill_unpainted(model, painted, interior_parts=...)` | faces cachées / dessus / dessous : face peinte la plus proche de la même partie ; intérieur (jupe creuse) assombri |
| `shade(model)` | ombrage peint par direction de face (`SHADE`) |
| `quantize(model, {mat: k})` | palette réduite par matière (k-moyennes) : plus de faces fusionnées |
| `save_cache(model, json)`, `load_cache(json)` | cellules et couleurs de faces en JSON (suivi par git) : reconstruire sans la planche |
| `build_mesh(model, name)` | maillage : faces visibles + faces entre deux os, fusion des faces coplanaires de même couleur/matière/os, couleurs « Col » par coin (sRGB), aucun sommet partagé entre rectangles, matériaux nommés comme `ZombieGlb.MATS` |
| `build_armature(name, bones, cube)`, `bind(ob, rig)` | squelette (os droits, `RigBuilder.BONES` pour un personnage), pondération rigide |
| `self_check(ob, cube)` | avant écriture : sommets sur la grille, normales sur les axes, poids rigides |
| `export_glb(path, objs, cube)` | .glb (Y en haut, peau, COLOR_0) après `self_check` |
| `godot_check(path, animated, cube=None)` | lance `tools/voxel_check.gd` sur le fichier écrit |
| `add_outline(model, name, rig)` | contour noir des rendus : coque inversée sur la grille, suit la pose (jamais exportée) |
| `setup_render`, `render_view(path, azimut, cible, hauteur_m)`, `sheet`, `load_png`, `save_png` | rendus orthographiques (hauteur visible en mètres : même échelle que la planche) et planches de validation |

- Matières (`MATERIALS`) : `skin`, `eye` (émissif : alpha 0 dans le jeu),
  `cloth`, `leather`, `metal`, `wound`, `bone` — la matière du shader des
  zombies (`zombie.gdshader`) ; la couleur vient de la face (COLOR_0, lue par
  `ZombieGlb`, déjà linéaire dans Godot).
- Personnages : ossature `RigBuilder.BONES` (noms, parents), repos membres
  pendants sans rotation (le jeu ne lit que les positions), pas d'os de main
  ni de pied (mains sur `forearm`, pieds sur `shin`).
- Objets statiques : aucun os ; `godot_check(path, False)`.
- Budget : < 15 000 triangles pour un personnage en cubes de 2,5 cm ; la
  fusion des faces garde le zombie complet vers 8 200.
- Après l'export, toujours : `godot --headless --path . --import` (fichier
  `.import`), `tools/voxel_check.gd -- <fichier> --anime|--statique`, et une
  planche de validation regardée à l'œil avant de brancher le modèle.

### Zombie « patient » (tools/blender/zombies/zombie_voxel.py)

- `assets/models/zombies/zombie_voxel.glb`, cubes de **2,5 cm**, **pas encore
  branché** dans le jeu (en attente de validation ; `zombie_base.glb` reste le
  modèle de `--zombie-model`). Test : `tests/test_zombie_voxel.gd`.
- Formes SCULPTÉES par la planche `docs/reference/zombie_patient/turnaround.png`
  (9,5 pixels par cube) : chaque partie est un pavé de cellules dont une
  cellule reste si sa case est pleine (ou de la bonne matière : peau, tissu)
  dans la vue de face (ou de dos) ET de profil. Le dos voûté, la tête en
  avant, les genoux, le bas déchiré, les manches évasées et le col en
  escalier en sortent en marches de cubes. Puis : jupe creuse (parois d'un
  cube) autour des jambes, bas déchiré mesuré paroi par paroi sur la vue qui
  la montre ; yeux 3 × 2 émissifs au fond d'orbites, arcades en saillie, nez
  creusé, bouche ouverte de deux cubes de profondeur et six dents d'un cube,
  oreilles, encolure en V (couche de tissu ôtée, peau du cou derrière), trois
  doigts séparés et recourbés, orteils marqués.
- 72 × 38 × 20 cubes, ~16 600 cellules, ~8 200 triangles : tête 18 × 18 × 16
  (oreilles comprises), mâchoire 14 × 5 × 6, torse 20 × 16 × 26, jupe 22 × 12
  × 18, manches 8 × 13 × 16, bras et mains 8 × 8 × 35, jambes 7 × 12 × 30.
- Couleurs prélevées une par face de cube (plis de la blouse, taches de sang,
  bleus) ; cases prises sur un trait d'encrage recomblées par leurs voisines ;
  palette réduite à ~90 teintes.
- Cache : `tools/blender/zombies/zombie_voxel_cells.json` (suivi par git) ;
  sans la planche (ou avec `--cache`), le modèle est reconstruit à l'identique.
- Planche de validation : `--sheet tests/_out/voxel/zombie_voxel_sheet_25.png`
  (rangée 1 : planche ; rangée 2 : rendu au même cadrage et à la même échelle,
  contour noir compris ; rangée 3 : les deux à 50 % pour comparer pixel à
  pixel ; vues : face, dos, profils, trois-quarts, pose d'attaque).

### Contour noir en jeu (scripts/game/screen_outline.gd)

La planche dessine un trait noir d'environ 1 cm autour des pièces. Choix
retenu : **contour en espace écran** (`ScreenOutline`, shader
`assets/shaders/screen_outline.gdshader`), créé par
`WorldLook.setup_environment` pour la partie (pas pour l'aperçu de
l'éditeur de cartes : ses poignées prendraient un trait).

- Quad plein écran dessiné en tête de la passe transparente
  (`render_priority` minimale) : lit la profondeur de la pré-passe opaque
  (`hint_depth_texture`, 5 lectures par pixel) et écrit un noir teinté
  (linéaire 0,03 / 0,035 / 0,04, opacité 0,95) AVANT le tonemap et
  l'étalonnage, qui lui donnent le relèvement bleu-vert des noirs.
- Détection par la **profondeur seule** : la profondeur brute inversée est
  affine en 1/z, donc affine à l'écran sur tout plan ; sa dérivée seconde
  est nulle sur un plan même rasant (aucun trait parasite sur les grands
  sols et murs) et marque : le côté PROCHE d'un saut (silhouettes, marches
  vues de dessus : trait d'un pixel), les arêtes saillantes et les coins
  rentrants des cubes (pli de 90° >= 2 angles de pixel à toute distance).
  Seuils (`ScreenOutline`) : pli 1,0 angle de pixel, coin rentrant si les
  deux voisins sont plus proches dans un rapport >= 0,2, seuil relevé de
  20 % de la pente sur les surfaces rasantes.
- Le tampon des normales (`hint_normal_roughness_texture`, première version)
  a été écarté : +0,28 ms GPU (pré-passe avec un second tampon) pour un trait
  équivalent sur des formes faites de plans.
- Trait d'1 px jusqu'à 1080p (2 px en 2160p, écart des voisins arrondi à
  la hauteur / 1080) ; fondu de 10 à 24 m (au-delà, une marche de 2,5 cm
  fait moins de 2 px et le trait deviendrait du bruit).
- Sans trait : HUD et écran de lunette (CanvasLayer), **arme et mains en vue
  FPS** (profondeur écrasée vers le plan proche par `weapon.gdshader`,
  > 0,9 : exclues, car le trait dessinerait les facettes de leurs formes
  arrondies et la frontière arme / décor n'a pas de sens), ciel (profondeur
  0), brume et particules transparentes (hors profondeur, dessinées
  par-dessus le trait).
- Option **OPTIONS > VIDÉO > CONTOUR** (`Settings.outline`, `video/outline`,
  activée par défaut, dans les trois préréglages) ; désactivée d'office hors
  Forward+ (`ScreenOutline.supported` : la profondeur inversée 0..1 de
  Vulkan est supposée ; Mobile et Compatibility non vérifiés). `--outline=off`
  la coupe en ligne de commande (mesures).
- Captures : scénario `outline_look` (BUNKER K-7, zombies du jeu et
  zombies « patient » 2,5 cm, avec et sans contour, gros plans x2,
  sol plan sans trait parasite). Coût : docs/ARCHITECTURE.md.

Options écartées :

1. **Coque inversée par sommet** (comme les planches de validation) : second
   matériau sur le maillage du zombie, `render_mode cull_front, unshaded`,
   sommets poussés vers l'extérieur dans le vertex shader. Les faces du modèle
   ne partageant pas leurs sommets, il faut une normale « de coin » par sommet
   (somme des normales des faces voisines, calculée par `ZombieGlb` ou
   stockée en attribut). Coût : le maillage dessiné deux fois (≈ 8 000
   triangles de plus par zombie : sensible avec 24 zombies à l'écran), trait
   épaissi au loin, pas de trait sur le décor.
2. **Coque dans le .glb** : refusée — ce serait un second maillage hors de
   la grille, non conforme à VoxelCheck.

## Étalonnage et post-traitement (code actuel, à revoir pour le style cubique)


### Ce qui caractérise l'image de BO1 Zombies
- **Image désaturée, jamais grise** : les couleurs vives (velours de Kino,
  néons des machines, sang) restent lisibles mais « délavées » ; les murs, le
  béton et les uniformes tirent vers un gris vert-de-gris.
- **Deux températures** : les zones éteintes et les recoins sont froids
  (bleu-vert, surtout dans les noirs), la lumière des ampoules et des lustres
  est chaude (jaune-orangé) — le contraste froid/chaud fait la profondeur.
- **Noirs denses mais lisibles** : les ombres sont profondes, mais on distingue
  toujours la silhouette d'un zombie dans un couloir ; jamais d'aplat noir
  absolu (les noirs sont légèrement relevés et teintés).
- **Bloom marqué sur les sources** : ampoules, lustres, écrans des machines
  d'atouts, écran de cinéma et faisceau du projecteur « bavent » largement ;
  les surfaces ordinaires ne brillent pas.
- **Brume visible dans les faisceaux** : poussière en suspension, halos autour
  des lampes (surtout le projecteur de Kino) ; manches de chiens : brouillard
  épais qui noie les lumières.
- **Grain de film** présent en permanence, fin et animé, plus visible dans les
  tons moyens ; léger vignettage ; de rares franges colorées sur les bords.
- **Interface nette** : le grain et le vignettage ne touchent pas le HUD.

### Mise en œuvre (procédurale)
- `WorldLook.grade_color` / `grade_lut` : table de correspondance 3D (24³)
  calculée au chargement et appliquée par `Environment.adjustment_color_correction`
  (coût nul : incluse dans la passe de tonemap). Étapes : désaturation des
  couleurs vives, virage ombres vert-de-gris / hautes lumières chaudes (sans
  changer la luminance), pied de courbe (noirs plus denses, tons moyens
  intacts), relèvement bleu-vert du noir, léger gain. Surcharge par carte :
  `MapDef.look["grade"]`.
- Bloom : glow en mode « écran », seuil HDR 1,0, niveaux larges (3 à 5).
- Brume volumétrique fine (anisotropie 0,7 : halos vers les lampes) en MEDIUM
  et HIGH ; triplée pendant les manches de chiens (`apply_dog_round_look`).
- `FilmPost` (CanvasLayer 5, sous le HUD) : grain animé à 24 images/s,
  vignettage ovale, aberration chromatique radiale (MEDIUM/HIGH) ; variante LOW
  multiplicative sans lecture de l'écran. Option **OPTIONS > VIDÉO > GRAIN DE
  FILM** (0 à 100 %, 50 % par défaut).
- Contrainte utilisateur : l'éclairage venait d'être relevé (« trop sombre ») —
  l'étalonnage ne ré-assombrit pas : `tests/autotest/visual_look.gd` mesure la
  luminance moyenne de chaque zone (courant rétabli) et échoue sous 0,05.
- Courant coupé (`PowerGrid`) : lampes à 40 %, blanc pâle neutre (à peine
  chaud, l'étalonnage refroidissant les zones sombres), comme BO1 avant le
  courant ; seul le gyrophare de l'interrupteur reste rouge.

### Écarts restants
- Pas de flou de profondeur ni de flou de mouvement (coût, et peu visibles dans
  BO1 hors visée).
- Bloom : un écran de machine d'atout vu à bout portant sature en blanc.

## HUD (code actuel ; l'interface reste libre mais en harmonie avec le style cubique)

### Ce qui caractérise le HUD de BO1 Zombies
- **Compteur de manche** en bas à gauche, gros, rouge sang « peint à la
  main » : bâtons pour les manches 1 à 5 (le 5e barre les quatre autres), puis
  chiffres tracés au pinceau, irréguliers, avec de petites coulures.
- **Transitions de manche** : à la fin d'une manche le compteur passe au blanc
  et pulse lentement (blanc <-> rouge) pendant l'entracte ; au début de la
  suivante l'ancien chiffre s'efface et le nouveau apparaît en blanc puis
  vire au rouge. Manche de chiens : clignotement rouge braise.
- **Atouts** : petites pastilles carrées arrondies, à la couleur de la
  boisson, alignées juste au-dessus du compteur de manche.
- **Points** en bas à droite, au-dessus des munitions : un bandeau par joueur
  à sa couleur (blanc, bleu, jaune, vert), le sien plus grand ; chaque gain
  fait jaillir un « +10 » / « +50 » doré qui s'envole vers la gauche en
  s'éparpillant ; les dépenses apparaissent en rouge.
- **Munitions** : nom de l'arme au-dessus (s'efface quelques secondes après
  le changement d'arme), chargeur en gros chiffres, réserve plus petite ;
  icônes de grenades (et singes) à gauche. Chargeur presque vide en rouge.
- **Invites** au centre bas, texte blanc sans cadre : « Appuyer sur F pour
  acheter M14 [Coût : 500] », « Maintenir F pour ... ».
- **Réticule** : quatre traits fins blancs qui s'écartent avec la dispersion ;
  marqueur de touche en croix.
- **Dégâts** : sang qui envahit les bords (éclaboussures, coulures), voile
  rouge bref à chaque coup, battements de cœur à faible santé.
- **À terre** : vision floue qui respire, délavée, bords rouges pulsés.
- **Fin de partie** : « GAME OVER » en grand, « Vous avez survécu N manches »
  dessous, puis le tableau des scores (points, tués, têtes, réanimations,
  à terre) avec une ligne colorée par joueur.
- **Typographie** : sans empattement, condensée, blanc cassé avec ombre ;
  aucune fioriture, lisible sur le grain.

### Mise en œuvre
- `HudStyle` (`scripts/game/hud/hud_style.gd`) : polices système condensées
  (Bahnschrift étroite, repli Arial Narrow / Impact), couleurs, et pinceau
  procédural `brush_stroke` (largeur variable, bords irréguliers, stries,
  coulures) ; `digit_strokes` décrit les chiffres 0-9 en traits.
- `RoundCounter` : bâtons et chiffres peints, machine d'états INTRO / OUTRO /
  IDLE (`whiteness` = part de blanc), clignotement des manches de chiens.
- `ScorePanel` : bandeaux dégradés à la couleur du joueur, « +N » envolés.
- `Hud.bo1_prompt` : convertit le texte des objets (« [F] Acheter M14 [500] »)
  au format BO1 ; `_prompt` garde le texte brut (tests).
- `hurt_vignette.gdshader` (sang, voile), `downed_blur.gdshader` (flou par
  mipmaps de l'écran, uniquement à terre), `Scoreboard` restylé, fin de
  partie mise en page par `Hud.show_game_over_table`.
- Mise à l'échelle : tout le 2D (HUD et menus) suit la résolution depuis une
  base 1280x720 (`display/window/stretch` = `canvas_items`, `expand`), comme
  le HUD de BO1 ; la 3D reste rendue à la définition de l'écran.
- Captures de contrôle : `tests/autotest/visual_look.gd` (`--hud` pour ne
  jouer que la partie HUD).

### Écarts restants
- Pas d'icônes de réanimation au-dessus des coéquipiers à terre dans le
  monde (hors périmètre du HUD 2D).
## Historique : rendu réaliste BO1

Notes d'observation et mise en œuvre de la première direction (refonte R4,
clone de Black Ops 1 Zombies). **Historique** : ces modèles procéduraux et
Blender réalistes sont à refaire en cubes (GAME_CONCEPT.md § 5) ; le code
décrit existe encore tant que les versions cubiques ne l'ont pas remplacé.

### Zombies

#### Référence (Kino der Toten, Five, Ascension)
- **Silhouette** : humains maigres, décharnés, épaules tombantes, buste voûté
  vers l'avant, tête projetée en avant ; bras longs et osseux, mains crochues.
  La lecture à 10 m se fait par la silhouette sombre et les deux yeux.
- **Vêtements (Kino)** : uniformes de la Wehrmacht feldgrau (vert-gris terne,
  sali, taché de sang séché brun-rouge), col plus sombre, ceinturon et
  cartouchières de cuir noir, brelages, pantalon gris ardoise rentré dans des
  bottes hautes ; couvre-chefs variés (casque d'acier M35 à bord évasé,
  casquette M43 à visière, casquette d'officier à plateau haut) ou tête nue.
  Tuniques déchirées : manches arrachées, trous laissant voir les côtes.
  D'autres cartes montrent des civils, du personnel, des scientifiques en
  blouse ; on garde quelques variantes de ce type pour la variété.
- **Peau** : gris pâle légèrement verdâtre, marbrée, veines et ecchymoses
  violacées ; orbites creuses et sombres ; lèvres rongées, dents visibles,
  **mâchoire pendante / disloquée** ; plaies ouvertes, entrailles parfois.
- **Yeux** : **jaunes lumineux** à Kino (halo net qui « bave » dans le bloom),
  la marque la plus reconnaissable du mode, visible de loin dans le noir.
- **Sang** : abondant mais sombre (rouge profond presque noir une fois sec),
  surtout bouche/menton/poitrine, mains, autour des plaies.
- **Animations** :
  - marcheur : pas traînant, titubant, souvent une jambe qui traîne ; bras
    tendus en avant ou un bras levé et l'autre ballant, ou bras pendants ;
  - coureur : penché en avant, bras ballants qui battent mollement ;
  - sprinteur : très penché, bras tendus vers la proie ;
  - attaque : coup de griffes à deux bras (bras levés puis frappe plongeante) ;
  - émergence : les mains crèvent le sol d'abord, puis la tête ; le zombie se
    hisse en prenant appui ;
  - fenêtres : agrippe une planche, l'arrache en se jetant en arrière, la jette,
    puis enjambe l'allège ;
  - rampants (jambes arrachées) : se traînent à la force des bras ;
  - morts : chute molle (ragdoll), effondrements variés, tête qui éclate au
    tir à la tête mortel.

#### Mise en œuvre (scripts/game/zombies/zombie_model.gd, zombie_anim.gd)
- Maillage procédural à **normales lissées** (RigBuilder : ellipsoïdes et tubes
  de sections elliptiques « loft »), toujours **skinné sur le squelette
  commun** (13 os + mâchoire) et **un seul draw call** ; articulations
  partagées entre deux os (coudes, genoux, épaules, cou) : aucune fissure.
- **6 archétypes** (soldat casqué, soldat en calot, officier, soldat débraillé
  torse nu à bretelles, scientifique en blouse, civil en gilet), 36 looks
  déterministes (variante réseau -> look), couleurs converties sRGB -> linéaire.
- Détails : col, boutons, poches à rabat, pattes d'épaule, ceinturon à boucle,
  cartouchières, brelages, boîtier de masque à gaz ou gourde, jugulaire ;
  côtes à vif dans les déchirures, trous de balles, joue arrachée, crâne
  ouvert, entrailles (rare), moignons prévus pour le démembrement.
- **Shader dédié** (assets/shaders/zombie.gdshader, corps dans
  zombie_body.gdshaderinc) : matière par pièce
  (tissu, peau marbrée veinée, cuir, métal peint écaillé, plaie humide, os),
  bruit calculé sur la position de repos (ne glisse pas pendant l'animation),
  **sang peint par sommet** à bord irrégulier (pas de pastilles géométriques).
- Zombies sur la **couche de rendu 2** : les décalques de sang du sol ne les
  « peignent » plus (bottes rouges auparavant).
- Coût : ~1 800 à 2 700 sommets par look, mesh et Skin partagés (cache),
  looks préparés en arrière-plan (WorkerThreadPool) dès le premier zombie :
  construction d'un zombie < 0,1 ms. A/B dans zombie_look : rendu de 24
  zombies de près à ~96 % des images/s de l'ancien modèle en boîtes.

#### Écarts restants avec BO1
- Pas de vrai ragdoll physique (morts procédurales variées).
- Pas de traînée lumineuse des yeux en mouvement ni d'yeux rouges vus « à
  terre » (effet d'écran).
- Détail limité par le low-poly procédural (pas de textures peintes, visages
  simplifiés).

### Armes à la première personne et mains

#### Ce qui caractérise BO1
- **Champ de vision de l'arme** : BO1 dessine l'arme avec le `cg_fov` par
  défaut de 65° (horizontal en 4:3, soit ~51° verticalement). L'arme reste
  « loin » de l'œil et peu déformée : pas d'effet grand-angle sur la crosse,
  le bas de l'écran reste dégagé. Le décalage `cg_gun_x/y/z` place l'arme en
  bas à droite, légèrement tournée vers le réticule.
- **Hanche** : on voit le dessus et le flanc gauche de l'arme, la bouche du
  canon vers le centre de l'écran, la crosse sort par le coin inférieur
  droit. Les pistolets sont tenus à deux mains, plus près et plus haut.
- **Visée** : cran et guidon parfaitement centrés ; la carcasse occupe le bas
  de l'écran sans le boucher (armes à lunette : écran de lunette plein).
- **Formes** : pas un seul bloc brut. Canons ronds étagés, cache-flammes à
  lamelles, chambre conique de l'AK74u, garde-mains ronds nervurés (M16),
  bois arrondi (AK74u, M14, Olympia), chargeurs courbes (AK74u, Galil,
  MP5K, Dragunov), tambour nervuré (RPK), glissière aux stries arrière
  (M1911), barillet cannelé (Python), lunettes à objectif évasé.
- **Matériaux** : acier bronzé presque noir aux arêtes usées qui laissent
  voir le métal nu, phosphatation grise sur les armes américaines, noyer
  vernis rougeâtre veiné (M14, Olympia), bakélite, polymère mat, laiton des
  douilles. Contraste fort : reflets nets sur le métal, bois chaud.
- **Mains** : chaque personnage de Kino a ses mains (d'après les fichiers
  de modding : bras de prisonnier américain pour Dempsey, de bagnard de
  Vorkouta pour Nikolaï, de soldat nord-vietnamien pour Takeo, de
  combinaison de protection pour Richtofen). Doigts refermés sur la
  poignée, index sur la détente, pouce par-dessus ; la main gauche
  soutient le garde-main (doigts remontant sur le flanc, pouce le long de
  l'autre) ou tient la poignée avant ; manches visibles jusqu'au bord de
  l'écran.
- **Animations** : sortie (l'arme remonte du bas à droite en pivotant) et
  rangement ; rechargement réaliste (l'arme bascule, la main gauche
  retire le chargeur, en rapporte un neuf, l'enfonce d'un coup sec, arme la
  culasse si le chargeur était vide) ; cartouche par cartouche pour les
  fusils à pompe et le China Lake (coup de pompe final) ; canons basculés de
  l'Olympia ; barillet sorti du Python ; pompe à chaque tir (Stakeout,
  SPAS-12) ; verrou du L96 ; glissière qui recule à chaque tir et reste
  ouverte chargeur vide (pistolets) ; sprint : arme basse, tournée et
  inclinée, grand balancement en huit.

#### Mise en œuvre (Claude of Duty Zombie)
- `WeaponMesh` : primitives arrondies (profil extrudé chanfreiné, révolution,
  capsule), fusionnées en un maillage par matériau et par pièce mobile,
  construites une fois et mises en cache. Couleur de sommet = donnée
  (arêtes usées, variation par pièce).
- `WeaponModels` : archétypes détaillés, groupes mobiles `mag`, `slide`,
  `pump`, `barrels`, `cyl` et leurs pivots ; ancres de visée inchangées
  (alignement testé à ±2 px par `weapon_aim`).
- `ViewHands` : mains, doigts en phalanges, avant-bras et manches ; quatre
  tenues selon l'emplacement du joueur (manches kaki retroussées et mains
  nues, veste matelassée et mitaines, veste olive, combinaison jaunâtre et
  gants de caoutchouc noir).
- `ViewModel` : champ de vision de l'arme 51,3° à la hanche (72° en visée,
  pour que la carcasse ne bouche pas l'écran), appliqué par
  `weapon.gdshader` (`vm_fov_scale`) ; les effets (flamme, douilles,
  traçantes) partent du point où l'on VOIT la bouche du canon.
- `weapon.gdshader` : usure des arêtes, veinage et vernis du bois, trame des
  manches, liseré de contre-jour et lumière d'appoint de la vue FPS.

#### Écarts restants avec BO1
- Pas de textures peintes (gravures, marquages, quadrillage des plaquettes) :
  le détail vient de la géométrie et du bruit procédural.
- Mains stylisées (doigts en capsules), sans rides ni ongles.
- Les animations sont procédurales (courbes) et non capturées : pas de
  léger dépassement ou d'hésitation humaine, et une seule chorégraphie
  « chargeur » partagée par les armes à chargeur.

### Machines d'atouts

#### Référence (Kino der Toten, Five, Ascension)
- Distributeurs de soda américains des années 50, environ 2,1 à 2,3 m
  ornement compris, un peu moins d'un mètre de large, collés au mur ; chaque
  atout a **sa propre silhouette** reconnaissable de loin : grand
  distributeur bordeaux à épaules arrondies et tête crème (Juggernog),
  caisse verte à tête blanche et colonne de hublots (Speed Cola), coffre
  ambré à bande de tôle ondulée et capsule (Double Tap), glacière basse
  bleu-gris à fronton incliné et panneau rond sur un mât (Quick Revive).
- Panneau et enseigne ronde du dessus éclairés de l'intérieur **seulement
  avec le courant** (sauf Quick Revive en solo) ; la lumière colorée de la
  machine baigne le sol et les murs voisins ; lettrage peint, fente à
  pièces, levier, trappe de distribution, garnitures chromées ; peinture
  écaillée, rouille et crasse au pied ; ritournelle de temps en temps.

#### Mise en œuvre (tools/blender/props/perk_machines.py, PerkMachine)
- Modèles Blender scriptés, un par atout, noms et emblèmes ORIGINAUX en
  relief (police intégrée de Blender) : TITAN BREW (enclume), RAPID FIZZ
  (éclair), TWIN SHOT (deux balles dans une capsule), LAZARUS TONIC (cœur),
  STRIDE SODA (vitrine en arche, chevrons), NOVA FLOP (machine « âge
  atomique » à dôme de verre, étoile), DEADEYE DRAM (caisse à fronton,
  réticule). Aucune image ni aucun logo d'Activision.
- Usure procédurale (`perk_machine.gdshader`) ; éteint : panneau terne ;
  allumé : panneau lumineux (bloom modéré, lettrage lisible) et lampe
  colorée devant la machine, à hauteur de hanche.

#### Écarts restants
- Pas de textures peintes (réclames « glacé », prix, éraflures fines) : le
  détail vient de la géométrie et du bruit procédural.
- Lettrage en capitales italiques et non en écriture cursive peinte.

### Salle de théâtre de KINO : objets

#### Référence (Kino der Toten, BO1)
- Salle en fer à cheval sous une coupole ovale à nervures, trouée par
  endroits ; un grand lustre à pampilles suspendu et un second écrasé sur
  les sièges ; fauteuils à haut dossier de bois sombre au sommet chantourné,
  garniture rouge râpée ; balcon unique à garde-corps plein et gradins ;
  arcades aveugles et pilastres cannelés sur les murs, appliques à tulipes ;
  grands drapeaux rouges à disque blanc (chez nous : bannières à emblème
  original) ; cadre de scène doré, lambrequin festonné à frange, rideaux
  retroussés, écran « vieille télé » à cadre noir arrondi, pupitre à petit
  drapeau et chaises pliantes ; champs de gravats (plâtre, caissons, lattes,
  poutres, sièges arrachés) sur une bonne partie du parterre.
- Téléporteur (MDT) sur la scène : socle rond à gradins et grille
  d'aération, tambour noir à grand emblème et voyant vert, épaulement
  conique hérissé de 6 isolateurs à ailettes, cage de barreaux autour d'une
  « cervelle » électrique bleue, chapeau en dôme, câbles vers les cintres.
  Estrade de la tourelle en bois avec son escalier.
- Salle de projection : machine d'amélioration en forme de poêle sarcelle
  à trois rouleaux blancs et enseigne à losanges colorés, projecteur sur
  socle en fonte, étagère à bobines, bureau, horloge, bobines au sol.
- Scène et coulisses (captures) : salle gris-vert sale ; nez de scène en
  bois sombre à bandeau sculpté ; bidons bleus empilés au pied de la scène
  à gauche et en coulisses ; caisses de transport noires ou gris foncé
  empilées ; échafaudage métallique et son escalier en coulisses à droite ;
  gros câbles bleu foncé qui partent de la tour du téléporteur, descendent
  du bord de scène et serpentent dans l'allée ; frise à losanges gris-bleu
  en haut des murs sous une corniche épaisse ; grand bloc de coulisses en
  planches qui porte l'écran, perche de projecteurs en haut.

#### Mise en œuvre (tools/blender/props/catalog_props.py, assets/models/props/)
- Carte KINO retirée (GAME_CONCEPT.md §6) : seuls les décors repris par le
  catalogue de l'éditeur et la machine d'amélioration restent.
- Modèles low poly scriptés (un .glb par objet, un maillage par matériau
  `<mat>__<modèle>__solid|ns`, matériaux remplacés par les shaders
  procéduraux du jeu) ; collisions en boîtes dans `<modèle>.collision.json`
  (repère Godot, `barrier` : laisse passer les balles), aucun objet de
  collision dans les .glb.
- Salle : `seat`, `seat_broken_a/b`, `balcony_front` (2 rangs),
  `balcony_back` (4 rangs), `column_balcony`, `wall_arch_panel`, `sconce`,
  `banner`, `proscenium`, `curtain_drape`, `valance`, `screen_frame`,
  `lectern`, `folding_chair`, `turret_podium`, `mdt_tower`, `chandelier`,
  `chandelier_fallen`, `dome`.
- Gravats : `rubble_heap_a/b/c` (tas), `rubble_field_a/b` (tapis bas),
  `rubble_mound_big` (grand champ du parterre), `debris_beam`,
  `debris_planks`, `debris_scatter`.
- Salle de projection : `pap_machine` (enseigne ORIGINALE « PUNCH-O-MATIC,
  Augmentez votre puissance de feu ! », police intégrée de Blender),
  `projector`, `reel_shelf`, `desk`, `wall_clock`, `film_reel`.
- Scène et coulisses : `stage_lip` (nez de scène 4 x 1,15 m, rinceaux en
  relief, se répète bout à bout), `wall_frieze` (frise 6 x 1,6 m, losanges
  en pointe de diamant entre moulures crème, corniche à denticules de
  0,5 m de saillie), `blue_barrel_group` (7 bidons, 2 barrières),
  `stage_crates` (5 caisses de transport à cornières), `scaffold_stairs`
  (tour de 5 m, plancher à 4 m, escalier raide accolé ; seuls les montants
  et le bas de l'escalier arrêtent), `cable_run_a/b` (câbles en S au sol,
  ~8 m, raccord d'acier au bout +X), `cable_drop` (descente du bord de
  scène, origine sur l'arête), `screen_block_face` (habillage 16 x 14 m du
  bloc de l'écran, zone de l'écran laissée plate), `mdt_arcs` (arcs bleus
  figés, même origine que `mdt_tower`). Les modèles d'architecture à coller
  au mur (`stage_lip`, `wall_frieze`, `screen_block_face`) ont leur origine
  au bas du milieu de la face arrière.
- Clés de matériau propres à la salle (aperçus Blender et shaders du jeu) :
  `plaster_theater` (plâtre gris-vert), `vault_theater` (gris des voûtes),
  `carpet_theater` (moquette gris-bleu).
- Aucun symbole politique : emblèmes originaux (bobine de film stylisée
  sur les bannières, le pupitre et l'estrade ; éclair dans un anneau sur le
  téléporteur ; pistolet et étincelle sur la machine d'amélioration).

#### Écarts restants
- Seules la salle de théâtre, la scène, les coulisses et la salle de
  projection sont habillées : hall, salles basse et haute, ruelle,
  arrière-salle, Foyer et loges restent en maquette grise (murs et sols
  aux matériaux de la description, lampes en grille), sans affiches, lustres
  du hall, coiffeuses ni portants (l'ancienne KINO en grille, remplacée,
  en avait des versions procédurales : `PropBuilder` et
  `TheaterLook.poster_image`, récupérables dans l'historique git).
- Formes simplifiées : pas de caissons sculptés dans la coupole, rinceaux
  du nez de scène en tiges et volutes simples, feuillages des niches
  absents, trous du plafond à bords
  en escalier (grille de la coupole) ; fauteuils des balcons simplifiés.
- La « cervelle » du téléporteur est une masse bosselée émissive ; ses arcs
  (`mdt_arcs`) sont figés (pas d'animation dans le modèle).
- Pas de peinture bleue parmi les clés du jeu : les bidons prennent la
  peinture sarcelle (`paint_teal`), les gros câbles le caoutchouc noir
  (`rubber`) ; constantes `BARREL_MAT` et `CABLE_MAT` du script.
