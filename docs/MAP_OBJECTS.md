# Objets de l'éditeur de cartes : variantes, barrière invisible, escaliers, décor libre, portes à zombies

Complément de `docs/MAP_AUTHORING.md` (éditeur, format des cinq JSON,
partage réseau) pour les ajouts des **formats 5 à 9** des cartes
(format 7 : décor posé librement, § 8 ; format 8 : portes à zombies, § 9 ;
format 9 : barrière invisible en polygone, § 2, et chevauchements du décor,
§ 10) :

1. les **variantes d'aspect** d'un type d'objet (plusieurs modèles de porte,
   de débris, d'arme murale) ;
2. la **barrière invisible** (« clip » de BO1) : un volume tracé en polygone
   qui arrête joueurs et zombies sans se voir en jeu ;
3. (format 6) les **types d'escaliers** et leurs **ancres** pour les zombies
   (§ 4).

![Portes blindée, en bois, grille ; débris en planches et en béton ; M14 à la craie et sur une planche](map_objects/variantes_3d.jpg)
![Dans l'éditeur : porte en bois (nom sous le prix), éboulement de béton, barrière invisible hachurée](map_objects/editeur.png)

---

## 1. Variantes d'aspect

### Ce qui existe

| Type (`type`) | Variantes (`variante`) | Par défaut |
|---|---|---|
| `porte` (porte payante) | `blindee` Porte blindée / Armoured door · `bois` Porte en bois / Wooden door · `grille` Grille en fer / Iron gate | `blindee` |
| `debris` (débris à dégager) | `planches` Planches et gravats / Planks and rubble · `gravats` Éboulement de béton / Concrete cave-in | `planches` |
| `arme` (arme murale) | `craie` Craie sur le mur / Chalk on the wall · `planche` Craie sur une planche / Chalk on a board | `craie` |

La variante ne change **que le visuel** : même prix, même largeur, même
collision, même ouverture (la porte monte dans le linteau, les débris
s'enfoncent), même invite. Une grille en fer arrête donc les balles comme une
porte pleine (choix de jeu : pas de tir à travers une porte fermée).

Les modèles sont construits par le jeu, sans fichier importé
(`scripts/game/interact/door.gd` : `_build_steel`, `_build_wood`,
`_build_gate`, `_build_debris`, `_build_rubble` ;
`scripts/game/interact/wall_buy.gd` : `_build_board`), avec les surfaces du jeu
(`WorldLook.SURFACES` : bois, bois sombre, acier, tôle rouillée, béton) —
aucun élément graphique d'Activision.

Les fenêtres ont, depuis le format 8, trois **types** (fenêtre, porte à
zombies simple, porte double : § 9) choisis comme une variante (V, liste
**Type (V)**). Pas de variante pour les portes du courant, les passages, les atouts (chaque machine a déjà son
modèle), le décor et les luminaires (chaque modèle est déjà un objet du
catalogue : `MapCatalog.PREFABS`, `MapCatalog.LIGHTS`).

### Dans l'éditeur

- **Objet choisi** (outil Sélection) : onglet Propriétés, liste
  **Aspect (V)**, ou touche **V** (aspect suivant, en boucle ; Ctrl+Z
  annule) ; aussi menu Édition > Aspect suivant.
- **Objet tenu** (porte, débris ou arme dans la barre rapide) : **V** avant
  de poser choisit l'aspect des prochains objets posés (comme R pour la
  rotation) ; changer de case revient à l'aspect par défaut.
- **Plan** : sous le prix d'une porte ou de débris, le nom de l'aspect quand
  ce n'est pas celui par défaut (zoom suffisant) ; une arme sur une planche a
  un fond bois.
- Changer le **type** d'une ouverture (porte → débris) remet l'aspect par
  défaut (les variantes sont propres à un type).
- **Aperçu 3D** et **partie** : le bon modèle (mêmes fonctions de
  construction que le jeu).

### Format

Clé facultative `"variante"` dans `ouvertures.json` (portes, débris) et
`objets.json` (armes murales) :

```json
{"id":"o1","type":"porte","etage":0,"position":[14,5.25],"largeur":2,"prix":750,"variante":"bois"}
{"id":"w1","type":"arme","arme":"m14","etage":0,"position":[11.25,10],"mur":"s","variante":"planche"}
```

- **Absente** : l'aspect par défaut, c'est-à-dire exactement l'aspect d'avant
  les variantes. L'éditeur **n'écrit jamais** la variante par défaut (choisir
  « Porte blindée » retire la clé) : une carte sans variante garde ses octets,
  son empreinte SHA-256 de partage et sa description en maillage.
- Lecture d'un fichier écrit à la main : une variante inconnue ou d'un autre
  type est retirée (`EditorMap._normalize`), l'objet garde l'aspect par défaut.
- Chaîne : `MapRaster` (table `MapValidator.variants` : id -> variante, sans
  les aspects par défaut) → `MapLayoutExport` (clé `variant` des marqueurs
  `doors` et `wall_buys`, seulement si elle n'est pas celle par défaut) →
  `MeshMapLayout` (`data.variant`) → `Door.variant` / `WallBuy.variant`. Côté
  jeu, une valeur inconnue construit l'aspect par défaut (`Door.look()`).

## 2. Barrière invisible

### À quoi elle sert

Comme les « clips » invisibles des cartes de BO1 : empêcher de monter sur un
décor, fermer un recoin où l'on se coincerait, garder les joueurs hors d'un
endroit sans ajouter de mur visible, canaliser la horde.

| Ce qui la touche | Effet |
|---|---|
| Joueurs | arrêtés (couche BARRIER du masque du joueur) |
| Zombies | arrêtés, et leurs **trajets la contournent** (navmesh cuit avec la couche BARRIER) |
| Balles | passent (les tirs ne visent que la couche 1) |
| Fente au couteau (attaque de loin) | pas de fente à travers (même contrôle que pour une barricade) |
| Grenades, singe | passent (`Throwable.FLIGHT_MASK` = couche 1 et zombies) |
| Ligne de vue des zombies (`MeshNav.world_line_clear`) | coupée, comme par un décor « barrière » |
| Chiens de l'enfer | trajets autour d'elle (même navmesh) ; leur corps n'a pas la couche BARRIER dans son masque, comme pour les fauteuils et les autres décors « barrière » |

C'est le même comportement que les décors dont le blocage est « barrière »
(`MapCatalog.PREFABS[..].bloque`) : un choix fidèle aux clips de BO1 (on tire
à travers, on ne passe pas).

### Dans l'éditeur

- Inventaire (E), catégorie **Construction** : **Barrière invisible** /
  Invisible barrier (outil `poly`, format 9). Tracée comme une pièce
  polygone : un **clic par sommet** (côtés à 0, 45 ou 90° sur la grille ;
  Alt : angle libre ; G : grille fine ou libre ; saisie au clavier de la
  longueur et de l'angle du côté), fermée par un **double-clic**, un clic sur
  le **premier point** ou **Entrée** ; Retour arrière retire le dernier
  point, Échap ou clic droit annule. Un L, une croix, un contour qui épouse un
  meuble tourné : une seule barrière.
- Règles de pose (`MapRules.check_clip`) : **n'importe où** — dans une pièce,
  à cheval sur un mur, dehors, par-dessus n'importe quel objet (et un objet
  peut se poser par-dessus elle : elle n'entre jamais dans les
  chevauchements, `MapRules.NO_OVERLAP_CHECK`). Seuls refus : moins de 3 ou
  plus de 64 sommets, un côté de moins de 5 cm, des côtés qui se croisent,
  moins de 0,04 m², hors du terrain (x, y < 0 ou au-delà de
  `MapCatalog.MAX_COORD`).
- Édition (outil Sélection) : une **poignée carrée par sommet** (glisser :
  le sommet suit, refusé si le contour se croise), glisser la barrière la
  déplace, poignée ronde de rotation (15°, Alt : au degré près), R (90°),
  Ctrl+C / Ctrl+V, Suppr, Ctrl+Z. Elle bouge et tourne avec la pièce qui
  contient son centre, comme les autres objets.
- Dessin : polygone bleu clair translucide, **hachuré** à 45° (hachures
  coupées au contour, même concave), contour en tirets, sommets marqués,
  icône au milieu, hauteur écrite dessous quand elle n'est pas « jusqu'au
  plafond ».
- Propriétés : case **Jusqu'au plafond (hauteur de l'étage)** (cochée par
  défaut : pas de clé `hauteur`) ; décochée, champ **Hauteur** de 0,5 à 30 m
  au **dixième de mètre** (`MapCatalog.CLIP_HEIGHT_STEP`) ; la hauteur en jeu
  est rappelée dessous, avec le nombre de sommets et la surface ; Pivoter,
  Supprimer, et le rappel de ce qu'elle bloque.
- Vérification : ses cases (0,5 m) dont le centre est dans le polygone
  (`MapRaster.clip_cells`, un bord droit sur la grille compte comme [x0,
  x1[ : 0,5 m posé sur la grille = une rangée de cases) sont **pleines**
  pour le validateur (passages, accessibilité, trajets à pied) comme un
  décor qui bloque ; une barrière qui coupe une zone en deux est donc
  signalée comme un mur. Posées après tout le reste, elles ne changent
  jamais une case de mur, d'escalier ou d'objet de jeu qu'elles recouvrent.
- **Aperçu 3D** : le prisme bleu translucide du polygone, à sa hauteur ; menu
  **Affichage ▾ > Montrer les barrières invisibles** (coché par défaut,
  mémorisé avec les autres réglages de l'aperçu, clé `clips`).

### En jeu

Une `CollisionBox` (objet Godot du projet, `scripts/game/map/collision_box.gd`,
**jamais** une collision de modèle Blender) avec `barrier = true` : couche
`Barricade.BARRIER_LAYER`, **aucun maillage**. Elle passe par la clé
`blockers` de la description en maillage, comme les collisions du décor.
Format 9 : `poly` donne les sommets en x, z autour de `center` ; la
`CollisionBox` en fait un **prisme** de hauteur `size[1]`, découpé en
morceaux convexes (`Geometry2D.decompose_polygon_in_convex`), une
`ConvexPolygonShape3D` par morceau (un L = deux formes). `size` x et z : son
rectangle englobant ; `center` : le centre de ce rectangle, à mi-hauteur.

```json
{"center":[20.75,1.6,9.75],"size":[1,3.2,5],"yaw":0,"poly":[[-0.5,-2.5],[0.5,-2.5],[0.5,2.5],[-0.5,2.5]],"barrier":true,"surface":"concrete","clip":true,"eid":"i1"}
```

Hauteur : `hauteur` de l'objet (m depuis le sol de l'étage) ; absente, du
sol jusqu'au plafond de l'étage (au moins 2 m). Le navmesh est cuit sur ces
formes : les zombies contournent le polygone exact. `clip` et `eid` servent
seulement à l'aperçu 3D (`MapPreviewBuilder` y pose le prisme translucide,
`prism_mesh`) ; `CollisionBox.from_dict` les ignore et `MeshMapBuilder` ne
construit rien de visible. Sans `poly` (collisions du décor, tabliers
d'escalier), la `CollisionBox` reste le pavé `size` d'avant.

### Format

Type `bloc_invisible` de `objets.json` (identifiants `i1`, `i2`…) :

Format 9 (écrit par l'éditeur) :

```json
{"id":"i1","type":"bloc_invisible","etage":0,"sommets":[[16,3],[17,3],[17,8],[16,8]]}
{"id":"i2","type":"bloc_invisible","etage":0,"sommets":[[2,2],[6,2],[6,3],[3,3],[3,6],[2,6]],"hauteur":1.2}
```

- `sommets` = [[x, y], ...] (m, 3 à 64 points, `MapCatalog.CLIP_POINTS`) :
  le **vrai** contour (pas un contour sur le trait comme un pilier), dans
  l'ordre du tracé ; `hauteur` (facultative, m, 0,5 à 30, au centimètre) :
  absente, du sol au plafond de l'étage.
- **Cartes d'avant** (formats 5 à 8) : `rect` = [x0, y0, x1, y1] et `rot`
  (entier de 0 à 359, sens horaire vu de dessus). À la lecture
  (`EditorMap.normalize_clip`, appelé par `_normalize` pour toute carte,
  même écrite à la main), le rectangle devient le polygone de ses 4 coins
  (rotation comprise, au millimètre) et `rect` / `rot` disparaissent : même
  place, même collision, mêmes cases ; la carte s'enregistre ensuite au
  format 9. Le jeu, le validateur et l'éditeur savent aussi lire une barrière
  `rect` qui n'est pas passée par la lecture (`MapRaster.clip_poly`).
- `hauteur` illisible ou sous 0,5 m : retirée (jusqu'au plafond) ; au-dessus
  de 30 m : bornée.

## 3. Contrôle des cartes reçues (réseau, archives)

Une seule source, le catalogue (`MapCatalog.allowed_kinds()`), lue par
`CustomMapGuard` (docs/SECURITY.md) :

- `variante` : `{"t": "enum", "values": MapCatalog.variants(type)}`, déclarée
  **seulement** pour les types qui ont des variantes (`porte`, `debris`,
  `arme`, `escalier` et, format 8, `fenetre` : `fenetre`, `porte`,
  `porte_double`). Refusés : une variante inconnue (`"titane"`), d'un autre
  type (`"planche"` sur une porte, `"bois"` sur une fenêtre), qui n'est pas un
  texte, un chemin (`"res://…"`), une clé `variante` sur tout autre type ; une
  fenêtre garde `largeur` à 1 (la largeur d'une porte suit son type).
- `bloc_invisible` : clés `id`, `type`, `etage`, `sommets` (format 9 :
  `{"t": "points", "min": 3, "max": 64}`, chaque point [x, y] borné au
  terrain) **ou** `rect` (cartes d'avant, coordonnées bornées) — l'un des
  deux est obligatoire (`CustomMapGuard._check_object`) —, `rot` (entier 0
  à 359), `hauteur` (nombre fini de 0,5 à 30) ; toute autre clé est refusée.
  Puis le validateur de jouabilité.
- `carte.json` : `chevauchement_decor` (format 9, § 10), vrai / faux
  seulement.
- Une variante n'est jamais un nom de fichier ni un chemin : le jeu choisit
  son modèle dans une liste fixe écrite dans le code.

Les barrières et les variantes voyagent avec la carte (les cinq JSON du
paquet canonique) : l'hôte et les invités construisent les mêmes objets.

Escaliers (format 6) : `variante` parmi les huit types, `sens` (`droite`,
`gauche`), `marches` (entier de 3 à 60), `garde_corps` (booléen), `cotes`
(`ouverts`, `fermes`) ; toute autre valeur est refusée (contrôle et tests :
`tests/test_stairs.gd`).

## 4. Escaliers (format 6)

### Les types

L'escalier garde son outil (inventaire, Construction, glisser du bas vers
le haut) ; son **type** est sa variante (touche **V**, liste **Type (V)**
des propriétés). Contrairement aux autres variantes, le type change la
forme des marches, leur collision et le trajet des zombies.

| Type (`variante`) | Nom | Forme | Largeur tracée minimale |
|---|---|---|---|
| `droit` (défaut, clé absente) | Escalier droit / Straight stairs | une volée sur tout le rectangle | 1,5 m |
| `palier` | Droit avec palier / Straight with landing | deux volées et un palier au milieu (1 à 2 m) | 2 m |
| `quart` | En L (quart tournant) / L-shaped | volée, palier d'angle, volée tournée de 90° ; sortie sur le côté où il tourne, au bout ; le coin libre reste du sol | 3,5 m |
| `demi_tour` | En U (demi-tour) / U-shaped | volée, palier sur toute la largeur, volée qui revient ; noyau plein entre les deux ; sortie du côté du pied | 3,5 m |
| `large` | Escalier d'honneur / Grand stairs | une volée, garde-corps des deux côtés par défaut | 3,5 m |
| `service` | Escalier de service / Service stairs | une volée étroite, en file indienne | 1,5 m |
| `colimacon` | En colimaçon / Spiral stairs | un tour complet autour d'un noyau puis un palier de sortie au-dessus du début de la vis ; sortie en face du pied | 4,5 m de côté, 3,2 m entre les étages |
| `rampe` | Rampe / Ramp | plan incliné sans marches | 2 m |

Le rectangle tracé est « sur le trait » (comme un mur) : les marches
occupent ses cases intérieures (0,25 m de retrait de chaque côté). Pente
maximale : 40° (validateur), mesurée volée par volée (palier : volées plus
courtes ; colimaçon : sur l'axe des zombies).

Réglages (propriétés ; absents du fichier à leur valeur par défaut) :
**Tourne vers** (`sens` : `droite` / `gauche`, types L, U et colimaçon),
**Marches** (`marches` ; 0 = automatique, ≈ 18 cm ; jamais plus de 28 cm par
marche, même réglé bas), **Garde-corps** (`garde_corps`), **Côtés fermés**
(`cotes` : limons pleins jusqu'à la main courante). La hauteur est celle
entre les deux étages (un escalier monte d'un étage).

Dessin du plan : volées et leurs marches, paliers, colimaçon, flèches de
montée et, au zoom, les pointillés du couloir des zombies avec ses deux
ancres (point jaune : entrée ; orange : sortie). L'aperçu 3D et la partie
construisent le même escalier (`MeshMapGeometry`, code commun).

### Géométrie et collision (`StairGen`)

`scripts/game/map/stair_gen.gd` : plan commun au jeu, à l'aperçu 3D, au
validateur et au plan de l'éditeur. Entrée « stairs » de la description en
maillage : `a` (milieu du bord du pied, sol du bas), `b` (milieu du bord
opposé de l'emprise, sol du haut), `w`, et seulement s'ils ne sont pas par
défaut `kind`, `turn` (-1 : à gauche), `steps`, `rail`, `closed` (un
escalier d'avant garde exactement sa description et son aspect).

- **Collision** : sous chaque volée, un prisme plein en pente douce (jamais
  de marche de collision : le joueur n'a pas de montée de marche, les
  zombies flottent 0,3 m au-dessus du sol) ; paliers pleins à fleur des
  volées ; colimaçon en 32 secteurs minces qui se chevauchent d'un
  demi-degré (on passe dessous au pied) ; garde-corps et limons en panneaux
  minces jusqu'à la main courante.
- **Tablier** : au haut de CHAQUE escalier (KINO compris), une
  `CollisionBox` invisible (objet du projet, jamais un modèle Blender) de
  0,6 m sur le palier, à fleur du sol d'arrivée : aucune fente entre la
  dernière marche et le sol (la famille de bugs des hauts d'escalier de
  KINO) ; posée par `MeshMapBuilder._add_architecture`, donc aussi dans
  l'aperçu.
- **Navmesh** : cuit sur ces collisions (surface continue, sans trou au
  bord ; le rayon d'agent de 0,4 m garde le navmesh loin des garde-corps).

### Ancres des zombies (`StairLane`, `MeshNav`)

Chaque escalier porte un **couloir d'ancres** (`StairGen.plan(...).lane`) :
une **ancre d'entrée** 0,75 m devant le pied (sol du bas), des points sur
l'axe de chaque volée (au plus 1 m d'écart), à chaque palier et à chaque
virage, et une **ancre de sortie** 0,9 m au-delà du haut, sur le palier
d'arrivée. Chaque point a sa demi-largeur permise : largeur de la volée
moins le garde-corps ou le noyau, le rayon de la capsule (0,3 m) et une
marge (0,12 m) ; moitié moins aux ancres (la horde se resserre pour passer
une porte).

- Au chargement, `MeshNav.set_stairs` crée les couloirs ; dès que le serveur
  de navigation a synchronisé la carte (`ensure_anchors`), chaque ancre est
  posée sur le navmesh : à sa place, sinon décalée le long du bord (le décor
  masque le milieu du pied), toute la volée droite qui part de ce bord
  passant alors en face de l'ancre, sans écart ; un escalier dont un bout
  n'a aucune place libre est signalé dans le journal (`[MeshNav] escalier
  ... couloir d'ancres désactivé`) et laissé au navmesh seul. Quand le navmesh, rogné
  de 0,4 m, ne relie pas les deux ancres par les marches (escalier d'un mètre),
  l'escalier devient un passage du navmesh (`NavigationLink3D` d'une ancre à
  l'autre, coût = longueur du couloir, coupé tant qu'une porte payante sur
  le couloir est fermée). Un chemin qui ne fait que longer le pied (bande
  devant les marches de la scène de KINO) reste celui du navmesh.
- `MeshNav.find_path(from, to, lane_bias)` : un chemin du navmesh qui
  emprunte un escalier (il entre dans son emprise par un bout et en sort
  par l'autre) est réécrit : chemin jusqu'à l'ancre du bout d'arrivée,
  points du couloir, puis chemin depuis l'ancre de l'autre bout (partagé
  par la horde pendant un pas physique), dans les deux sens, plusieurs
  escaliers à la suite. Un zombie déjà engagé entre une ancre et les marches,
  ou déjà sur les marches, repart de sa place sur le couloir (jamais
  renvoyé en arrière). `last_lane_marks()` donne l'escalier de chaque point.
- Écart latéral : chaque zombie suit le couloir à son propre écart
  (`Zombie.lane_bias()`, de -1 à 1 d'après son identifiant), borné à la
  demi-largeur de chaque point ; aux virages, l'écart suit l'onglet des deux
  volées. Une horde de 10 monte de front sans s'empiler contre un bord.
- Suivi (`Zombie._follow_path`) : un point du couloir n'est jamais sauté par
  la ligne de vue (pas de raccourci par l'angle d'un palier) ; il est
  atteint à 0,25 m, ou passé quand le zombie franchit le plan
  perpendiculaire à sa direction d'arrivée sans en être à plus de 0,6 m ;
  sur les marches, séparation réduite (0,35), virage net (30 m/s²), 3 m/s au
  plus à l'approche d'un virage serré (L, U), file : on cède (moitié de la
  vitesse, plus aucun pas vers lui, léger recul) à un voisin à moins de
  0,67 m, devant ou à côté, plus avancé sur le couloir (`StairLane.left_to` :
  reste à parcourir, même mesure pour toute la horde, donc de deux voisins
  un seul cède et le plus avancé passe ; pas de bouchon à l'ouverture d'un
  escalier de service), un chemin recalculé sur les marches restant « sur le
  couloir » dès son premier tronçon, et poussée
  vers l'axe au-delà de la demi-largeur (`MeshNav.lane_push`). La poursuite en ligne droite est interdite si la
  ligne passe sur une emprise d'escalier (`MeshNav.crosses_stairs`) : plus de
  zombie qui fonce dans le flanc d'un escalier.
- Marcheurs, coureurs, sprinteurs, rampants et chiens de l'enfer (même
  code, `Hellhound` hérite de `Zombie`) ; même vitesse et mêmes animations
  qu'ailleurs (aucun déplacement forcé le long des marches). Multijoueur :
  tout est calculé par le serveur, les clients voient les marionnettes
  (rien de nouveau sur le réseau).

### Cartes existantes

Les escaliers de KINO (layout.json, `stairs`) et de DRAFT ARENA ont leurs
ancres sans rien changer à leur aspect ni à leurs données. Les marches de
la scène de KINO : la première rangée de fauteuils masque le milieu de leur
pied ; l'ancre d'entrée de l'escalier ouest se pose dans l'allée libre à
côté (64,5 ; 51,4) et les zombies montent en face d'elle ; celle de
l'escalier est dans l'allée qui lui fait face (85,4 ; 51,4). Aucun décor
n'a été déplacé. BUNKER K-7 (grille, un seul niveau) n'a pas d'escalier.

### Preuves automatiques

- `tests/test_stairs.gd` (unitaire) : marches ≤ 0,3 m et pente de chaque
  type ; couloir à une capsule au moins de chaque bord, garde-corps et
  noyau, pour tout écart ; ancres hors des marches ; collision construite
  sans fente ni rebord (saut du sol ≤ 0,3 m le long du couloir) et sous toute
  la largeur de marche, tablier à fleur ; escalier d'avant construit à
  l'identique ; écart d'une horde (10 couloirs distincts, bornés), deux
  sens, projection ; format 6 relu à l'identique, valeurs par défaut non
  écrites, valeurs illisibles retirées, formats 1 et 5 lus sans changement ;
  validateur (huit types acceptés et exportés, coin libre du L, sortie du U,
  colimaçon trop petit refusé, largeurs) ; contrôle des cartes reçues.
- Scénarios `stairs_types` (marcheur, sprinteur, rampant, chien) et
  `stairs_hordes` (horde de 10 coureurs) sur la carte d'essai (un hall et
  une mezzanine par type) : montée et descente de chaque type, tous
  arrivés, jamais plus de 3 s immobiles sur les marches, dans la largeur du
  couloir.
- `kino_stair_lanes` (`## @carte kino`) : les onze escaliers de KINO, marches
  de la scène comprises.

## 5. Versions du format

`EditorMap.FORMAT` = **9**. Toutes les nouvelles clés sont facultatives : une
carte au format 1 à 8 se lit telle quelle (`EditorMap._migrate` ; un
escalier sans `variante` est droit, une applique sans `hauteur` est à 2 m,
une fenêtre sans `variante` est la fenêtre d'avant ; seule conversion : la
barrière invisible rectangle devient un polygone de 4 sommets, § 2) et
s'enregistre au format 9 ; DRAFT ARENA (format 1) reste identique octet pour
octet dans sa description en maillage. Un jeu plus ancien signale une carte
au format 9 comme « plus récente » (et son contrôle refuserait les clés
qu'il ne connaît pas).

- Format 6 : types d'escaliers (§ 4).
- Format 7 : décor posé librement, hauteur d'une applique (§ 8).
- Format 8 : portes à zombies simple et double (§ 9).
- Format 9 : barrière invisible en polygone (§ 2), réglage
  `chevauchement_decor` (§ 10).

## 6. Ajouter une variante ou un type à variantes

1. `MapCatalog.VARIANTS` : `[identifiant, nom FR, nom EN]`, la première
   ligne étant l'aspect d'avant (par défaut). Le contrôle des cartes, la liste
   « Aspect (V) », la touche V et la lecture suivent tout seuls.
2. Construire le modèle dans la classe du jeu (`Door`, `WallBuy`…) en lisant
   `m.data.variant` ; une valeur inconnue doit donner l'aspect par défaut.
3. Pour un nouveau type : transmettre la variante dans `MapLayoutExport`
   (`md.variants[eid]`, seulement si elle existe) et dans `MeshMapLayout`.
4. Tests : `tests/test_map_objects.gd`.

## 7. Preuves automatiques

`tests/test_map_objects.gd` (unitaire, sans fenêtre) :
- catalogue : variantes de chaque type (noms FR / EN), entrée « Barrière
  invisible », types et valeurs admis ;
- JSON : variantes et barrière (rotation, hauteur) relues et réécrites à
  l'identique, aspect par défaut = clé absente, format 4 lu sans rien
  ajouter, variante inconnue écrite à la main retirée ;
- contrôle des cartes : carte acceptée et jouable, variantes et barrières
  piégées refusées (9 cas) ;
- validateur : cases de la barrière pleines, 0,5 m = une rangée, règles de
  pose ;
- jeu : chaque variante construit son propre modèle (et la porte blindée à
  l'identique sans la clé), arme sur une planche ; barrière = une
  `CollisionBox` sur la couche BARRIER sans maillage, rayon de balle et de
  grenade qui passe, rayon et corps de joueur arrêtés, pavé visible dans
  l'aperçu seulement ; navmesh cuit : le chemin d'un zombie contourne la
  barrière ;
- éditeur : touche V sur l'objet choisi (boucle, retour à la clé absente,
  Ctrl+Z) et sur l'objet tenu (aperçu de pose), barrière de 0,5 m tracée.

`tests/test_map_clip_polygon.gd` (unitaire, format 9) : barrière acceptée
partout (en L, dehors, à cheval sur un mur, sur la boîte et l'atout, 0,2 m
d'épaisseur) et contours refusés (2 sommets, côtés croisés, x négatif,
minuscule, côté de 1 cm, plat, 65 sommets) ; objets sous elle toujours
valides ; rectangle d'avant relu en polygone (coins, surface, mêmes cases,
même collision), relu à l'identique, accepté par le contrôle ; polygones
piégés refusés (6 cas) ; en jeu, L concave = plusieurs formes convexes sur
la couche BARRIER, rayons arrêtés sur les bras et libres dans le creux, au-
dessus de la hauteur réglée et pour les balles ; prisme de l'aperçu à la
bonne hauteur ; dans l'éditeur, tracé clic par clic (fermé sur le premier
point ou par Entrée), poignées de sommets, contour croisé refusé,
déplacement, R, Ctrl+Z, suppression, « Jusqu'au plafond » et Hauteur au pas
de 0,1 m appliquée en jeu ; réglage `chevauchement_decor` (§ 10). Scénario
`map_objects_play` : barrière tracée à la souris en polygone, enregistrée,
rouverte, joueur arrêté et zombie qui la contourne en partie.

## 8. Décor posé librement (format 7)

### Ce qui change

Le **décor** (`MapCatalog.DECOR_TYPES` : caisse, baril, prefabs de la
catégorie « Décor et obstacles », lampe, luminaires) se pose **où l'on
veut** :

| Avant | Maintenant |
|---|---|
| refusé s'il touchait la rangée de cases d'un mur (« touche un mur : posez-le plus au milieu de la pièce ») | contre un mur, dans un angle, à moitié dans le mur, centre sur le trait du mur ; il suffit qu'il touche le sol d'une pièce (`MapRules.room_touching`) |
| caisse et baril construits et heurtés sur leurs cases arrondies (0,5 m) | bloc et collision à leur vraie place, au centimètre |
| applique aimantée par cases le long du mur, refusée au-dessus d'une porte ou d'une fenêtre et près des angles, toujours à 2 m | partout le long du mur (jusqu'à la face du mur voisin dans un angle, au-dessus d'une porte ou d'une fenêtre), au centimètre sans grille, au quart de mètre avec ; **hauteur** au choix (propriétés, champ **Hauteur**) |

Toujours refusés : un décor hors de toute pièce, posé sur un objet de jeu
ou sur un autre décor (sauf la lampe posée sur un meuble porteur, et sauf
si la carte autorise les chevauchements, § 10), une applique loin de tout
mur. Rotation : comme avant (R : 90° ; poignée ronde,
15°, Alt : au degré près) pour les prefabs et luminaires ; la caisse et le
baril n'ont pas de rotation. Aimantation : touche **G** (grille 1 m, grille
fine, libre au centimètre) ; **Maj** maintenu inverse le mode le temps d'un
geste (pose fine sans changer de réglage).

Les **objets de jeu** (portes, débris, fenêtres, passages, armes murales,
atouts, boîte, Pack-a-Punch, interrupteur, leviers, pièges, départs,
apparitions, téléporteur) gardent leurs règles de pose (un objet de jeu
doit rester accessible, comme dans BO1).

### Murs : aspect et intégrité

- **Aspect** : la texture de chaque face de mur ne dépend que des pièces qui
  le bordent, jamais d'un objet posé devant (`MapLayoutExport._side_zone`,
  `_under_decor`). Avant le format 7, une case de sol sous un décor
  bloquant était, pour l'export, une case pleine **sans zone** : la face de
  mur qui la touchait prenait la texture de la pièce d'à côté (mur mitoyen)
  ou la texture par défaut « wall » (mur extérieur). C'était le « papier
  peint qui change » quand on poussait un décor contre un mur.
- **Pas de trou** : une caisse ou un baril ne rend pleines que ses cases de
  sol (comme les prefabs) ; une case de mur reste un mur.
- **Pas de scintillement** : un bloc de caisse ou de baril qui entre dans un
  mur est rentré de 5 mm de chaque côté (`MapLayoutExport.DECOR_WALL_INSET`) :
  aucune de ses faces n'est dans le plan d'une face de mur (une caisse d'1 m
  posée dans un mur mitoyen de 0,5 m a sa face sur celle de la pièce d'à
  côté).
- Les modèles et les pavés de collision des prefabs suivent déjà leur vraie
  position (`MapLayoutExport._props`, `_blockers_of`) ; ils peuvent entrer
  dans un mur, le mur reste entier.

### Vérification

Un décor contre ou dans un mur n'est jamais une erreur. Un décor posé
**devant une porte, des débris ou une fenêtre** est signalé par un
avertissement (onglet Vérification : « un décor posé devant gêne le
passage », « gêne l'entrée des zombies ») ; la carte reste jouable. Une
zone rendue inaccessible par du décor reste une erreur (accès, comme pour un
mur). Le départ des joueurs garde sa règle (1 m libre autour).

### Format

Clé facultative `"hauteur"` d'un luminaire **mural** (`objets.json`) :

```json
{"id":"x7","type":"luminaire","luminaire":"applique","etage":0,"position":[6.37,0],"mur":"n","hauteur":0.65}
```

- m au-dessus du sol, au centre de l'applique, 0,2 à 30 m
  (`MapCatalog.WALL_LIGHT_HEIGHT`) ; **absente** : 2 m (l'applique d'avant) ;
  jamais écrite à 2 m (`MapCatalog.set_wall_light_height`).
- En jeu, bornée à 15 cm sous le plafond de la pièce
  (`MapLayoutExport._fixture`).
- Lecture : valeur illisible, ou clé sur un luminaire qui n'est pas mural,
  retirée (`EditorMap._normalize`). Contrôle des cartes reçues :
  `{"t": "number", "min": 0.2, "max": 30}` (texte, négatif, 500 : refusés).
- Le décor posé au centimètre ou dans un mur n'a pas de clé nouvelle
  (`position` en mètres, `rot`, `mur`, `angle` comme avant) : seule la
  hauteur demande le format 7.

### Preuves automatiques

- `tests/test_map_decor_free.gd` (unitaire) : textures de tous les murs
  relevées (sondes 5 cm derrière chaque face) identiques avec 11 décors
  poussés contre les murs (le test échouait avant la correction), arme
  murale, atout, porte et débris aux bouts des murs ; règles de pose (décor
  dans les murs, au centimètre, tourné ; objets de jeu refusés) ; applique
  partout le long d'un mur, au centimètre ou au quart de mètre, calcul de
  `wall_decor_along` ; hauteur (construite, bornée sous le plafond,
  enregistrée, relue, contrôlée, format 6 inchangé) ; caisse et baril dans
  les murs (murs entiers, bloc à sa place et en retrait, bloc sur la grille
  identique à avant) ; avertissements du validateur.
- Scénario `map_decor_free` (vrai éditeur, sans fenêtre) : bureau, caisse,
  baril, arme murale et porte glissés à la souris contre les murs, textures
  inchangées dans les données de l'aperçu 3D (`MapPreviewWorld.compute`) et
  du jeu ; baril, caisse, étagère tournée de 37° et applique posés au
  centimètre, hauteur réglée dans les propriétés ; enregistrée, rouverte,
  TESTER : collisions à la vraie place (rien à la place arrondie), mur
  mitoyen entier, applique éclairée à sa hauteur.

## 9. Portes à zombies (format 8)

### Les types

L'entrée des zombies (« Fenêtre à zombies » de l'inventaire, type
`fenetre`) a trois types, choisis comme une variante : touche **V** (objet
tenu avant de le poser, ou objet choisi) ou liste **Type (V)** des
propriétés ; le plan écrit PORTE ou DOUBLE PORTE sur l'ouverture.

| Type (`variante`) | Nom | Largeur | Planches | Arrachent à la fois | Attendent derrière | Passages |
|---|---|---|---|---|---|---|
| `fenetre` (défaut, clé absente) | Fenêtre / Window | 1 m | 6 | 3 (milieu, gauche, droite) | 0 | 1 (enjambement) |
| `porte` | Porte à zombies (simple) / Zombie door (single) | 1 m | 6 | **1** | 3 | 1 (enjambement du battant cassé) |
| `porte_double` | Porte à zombies double / Zombie double door | 2 m | 10 (5 par battant) | **2** (un par battant) | 4 | 2 (un par battant) |

La fenêtre garde exactement son aspect, sa découpe et ses règles (KINO,
BUNKER K-7 et les cartes d'avant ne changent pas). Les règles des planches
sont celles des fenêtres de BO1 : réparation en maintenant [F] depuis
l'intérieur (+10 points par planche, plafond de 500 par manche, bonus
CHARPENTIER), coup à travers quand il reste 3 planches au plus, joueurs
arrêtés par l'ouverture même sans planches (la cour reste hors jeu, comme
derrière les fenêtres de BO1).

### Aspect : une vraie porte de 10 cm

Une **vraie porte** défoncée, pas un trou dans le mur
(`scripts/game/barricades/zombie_door_model.gd`, construite par le jeu, sans
fichier importé ni élément graphique d'Activision) :

- ouverture découpée **du sol** à 2,1 m (`MapValidator.ZOMBIE_DOOR_TOP`,
  `Barricade.DOOR_HEIGHT`), sans allège ; un seuil plein sous la porte
  (bloc à fleur du sol, ou bas du mur en biais) ; mur au-dessus ;
- bâti (montants et traverse de 7 cm), seuil, chambranle autour de
  l'ouverture sur la face du mur, socles ;
- battant(s) **cassé(s) à mi-hauteur** : seule la moitié basse reste sur
  ses gonds (planches debout cassées vers 0,95 m, `ZombieDoorModel.LEAF_TOP`,
  à des hauteurs différentes, bouts éclatés en dents de scie, une planche
  plus courte ; barre du bas entière, celle du haut cassée), le haut de
  l'ouverture vide (la penture du haut, tordue, reste seule sur le bâti) ;
  les zombies enjambent ce reste de battant comme une allège de fenêtre ;
  porte double : deux moitiés basses, gonds de chaque côté ;
- planches de la barricade clouées en travers devant le battant (porte
  double : 5 par battant, en miroir), arrachées une à une comme aux fenêtres ;
- bois brun veiné avec restes de peinture vert-de-gris (bâti plus sombre ;
  planches de la barricade grises), pentures en fer (`WorldLook.SURFACES`
  « metal »).

**Épaisseur** : tout l'assemblage (bâti, chambranle, battants, planches
au repos) tient dans une tranche de **10 cm** (`ZombieDoorModel.Z_BACK` à
`Z_FRONT` : de 16 à 26 cm du milieu du mur, côté salle). La porte est posée
**dans la face intérieure du mur** (chambranle 1 cm en saillie, planches à
fleur) : vue de la salle, c'est une porte dans son mur ; le reste de
l'épaisseur du mur (0,4 m) est l'embrasure, côté cour des zombies. Les
battants cassés restent dans leur plan, sans s'ouvrir vers la salle. Mesuré sur la géométrie
construite (`tests/test_zombie_doors.gd`).

### Les zombies

- Apparition : dans la cour derrière la porte (porte double : un point
  derrière chaque battant, `Barricade.DOUBLE_SPAWN_SIDE`).
- Places (`Barricade.TEAR_OFFSETS`, `WAIT_POINTS`) : porte simple, une place
  devant les planches (dans l'embrasure, 0,62 m dehors) et trois places
  d'attente derrière (deux à 1,15 m, une à 2,3 m, à l'écart du point
  d'apparition) ; porte double, une place devant chaque battant (à ±0,5 m)
  et quatre d'attente. Un zombie à une place d'attente s'agite (pose « de
  folie ») et prend la première place libre devant les planches.
- File (`BarricadeRules.queue_max`, `Barricade.queue_full`) : au plus 4
  zombies rattachés à une porte simple (1 + 3), 6 à une double (2 + 4) ; le
  point d'apparition est sauté tant que la file est pleine (fenêtres :
  `WINDOW_QUEUE_MAX` = 3, inchangé).
- Arrachage : même cycle que les fenêtres (`BarricadeRules.tear_tick` :
  2,5 s par planche en moyenne, pause « de folie ») ; porte double, chacun
  arrache d'abord les planches de son battant
  (`BarricadeRules.plank_to_tear_lane`), puis aide l'autre : 10 planches en
  ~12 s à deux, contre ~14 s pour les 6 d'une porte simple à un seul.
- Passage : sans planche, le zombie **enjambe** le battant cassé à
  mi-hauteur, comme l'allège d'une fenêtre (`BarricadeRules.VAULT_TIME` =
  1,1 s, même animation ; `Zombie._vault`, `ZombieAnim`) jusqu'à 1 m dedans, puis poursuit
  le joueur. Une arrivée par passage (`exit_clear(z, lane)`) : deux zombies
  passent de front une porte double.
- Navigation : comme aux fenêtres, l'approche dans la cour et le passage sont
  menés par la barricade (pas de chemin du navmesh à travers l'ouverture : la
  barrière reste là pour les joueurs) ; dedans, le zombie reprend le navmesh
  depuis l'arrivée.
- Réseau : masque des planches (10 bits) diffusé comme celui des fenêtres
  (`Interactable.broadcast_state` ; état complet au lancement en
  `PackedInt32Array`) ; le passage suit l'état VAULT du zombie, les clients
  animent la marche.

### Règles de pose et vérification

Comme une fenêtre : sur un mur **extérieur** (sol d'une pièce d'un côté, du
vide de l'autre), **0,5 m de mur plein** à chaque bout, dans un mur de
0,5 m, **cour libre** derrière : 2,5 m de profondeur sur 3 m (porte simple)
ou **4 m** (porte double, `MapRules.pocket_width`). Changer le type d'une
fenêtre posée est refusé si la porte double ne tient pas à sa place
(`MapRules.apply_variant` ; V passe alors au type suivant qui tient ; message
dans les deux langues). Le validateur revérifie la largeur (« elle fait 2 m
le long d'un mur de 0,5 m »), la cour et les deux côtés.

### Format

```json
{"type":"fenetre","position":[25.1,17.25],"etage":0,"id":"o1","variante":"porte_double"}
```

- `variante` absente : la fenêtre d'avant (jamais écrite) ; pas de clé
  `largeur` (la largeur suit le type ; une `largeur` autre que 1 est
  refusée par le contrôle).
- Description en maillage (`markers.windows`) : `kind` (`porte`,
  `porte_double`), `w` (largeur), `h` = 2,1 et une ou deux `spawns` ; une
  fenêtre garde exactement ses clés d'avant (`p`, `in`, `h`, `zone`,
  `spawns`). Chaîne : `MapRaster` (`variants`) → `MapValidator.windows`
  (`kind`) → `MapLayoutExport` (découpe, marqueur) → `MeshMapLayout.windows()`
  (`Opening.kind`, `width`) → `Barricade`.

### Preuves automatiques

- `tests/test_zombie_doors.gd` (unitaire) : règles par type (planches,
  zombies qui arrachent, file, battants, réparation alternée), cadence
  simulée (porte double ~2 fois plus rapide par planche), format 8 relu à
  l'identique, fenêtre d'avant décrite à l'identique, type inconnu retiré,
  contrôle (5 cas refusés), validateur (pose, 0,5 m de mur, cour de 4 m, mur
  trop court, changement de type refusé), découpe sans allège sur la grille
  et sur un mur hors grille (seuil plein, mur au-dessus), épaisseur de la
  porte construite ≤ 10 cm, places écartées et hors des apparitions, fenêtre
  construite comme avant.
- Scénario `zombie_doors` (cartes `tests/fixtures/maps/smallest_door/` et
  `smallest_double_door/`) : manche 1, file de 4 / 6 respectée ; porte
  simple, un seul zombie arrache (jamais deux à la fois) ; porte double, deux
  à la fois, 10 planches en ~12 s ; personne n'entre avant la dernière
  planche ; toute la horde passe le seuil et entre (deux de front à la
  double) ; le joueur ne sort pas ; réparation [F] (+10 par planche).
- Captures (hors check, `## @niveau perf`) : `zombie_door_look` (fenêtre,
  porte simple, double : de face, de biais, de près, à moitié arrachée,
  ouverte, depuis la cour).

## 10. Chevauchements du décor et des obstacles (format 9)

### Le réglage

Onglet Propriétés, rien de choisi (réglages de la carte) : case
**Autoriser les chevauchements décor / obstacles** / Allow decor / obstacle
overlaps. Clé `"chevauchement_decor": true` de `carte.json`
(`MapCatalog.OVERLAP_KEY`) ; décochée, la clé disparaît (une carte d'avant
garde ses octets et ses règles de pose). Valeur illisible ou `false` écrite à
la main : retirée à la lecture (`EditorMap._normalize`) ; contrôle des cartes
reçues : vrai / faux seulement.

### Ce qui peut se chevaucher

Coché, les objets de `MapCatalog.OVERLAP_TYPES` peuvent se recouvrir
**entre eux** :

| Peut chevaucher un autre objet de cette liste | Types |
|---|---|
| Décor (format 7) | `caisse`, `baril`, `prefab` (catégorie « Décor et obstacles »), `lampe`, `luminaire` (au plafond, au mur ou au sol, chacun dans sa couche : plafond, applique, sol) |
| Obstacles | `pilier` (« Pilier / obstacle ») |

Les **objets de jeu** gardent toutes leurs règles, dans les deux sens : un
décor ne se pose jamais sur eux et ils ne se posent jamais sur un décor
(`MapRules._blocking_overlaps`) : portes, débris, portes du courant,
passages, fenêtres et portes à zombies, armes murales, grenades, atouts,
boîte mystère, Pack-a-Punch, interrupteur du courant, poste central,
leviers, pièges électriques, départs des joueurs, apparitions, téléporteurs
et arrivées, escaliers. Ainsi la carte reste jouable (un atout ou une arme
toujours accessibles, des escaliers et des pièges dégagés). Les murs libres
gardent leurs règles. La **barrière invisible** (§ 2) se pose toujours
n'importe où, avec ou sans ce réglage.

### Où c'est appliqué

- Pose et déplacement : `MapRules.place_floor_item` (caisses, barils,
  décor, luminaires au sol et au plafond), `place_wall_decor` (appliques),
  `check_rect` (piliers) ; la lampe posée sur un meuble porteur garde sa clé
  `sur` (hauteur du dessus du meuble).
- Éléments déjà posés (`MapRules.check_existing`, dessin en rouge,
  rotation) : mêmes fonctions, donc rien de rouge pour un chevauchement
  permis ; décocher le réglage remet en rouge les objets qui se recouvrent.
- Vérification (`MapRaster`, `MapValidator`) : le décor et les piliers ne
  rendent pleines que des cases ; deux décors qui se recouvrent ne sont
  jamais une erreur. Un objet de jeu posé sur une case pleine reste une
  erreur (« doit être posé sur le sol d'une pièce »).
- En jeu : chaque objet garde ses collisions (`CollisionBox` du catalogue) ;
  des collisions qui se recouvrent ne gênent pas la physique.

### Preuves automatiques

`tests/test_map_clip_polygon.gd` : caisse sur caisse, bureau sur caisse,
pilier sur caisse refusés par défaut et acceptés avec le réglage ; caisse
sur le départ, départ sur une caisse, escalier sur une caisse toujours
refusés ; objets posés valides, carte valide et jouable ; réglage retiré :
chevauchement de nouveau signalé ; clé écrite, relue, contrôlée (valeur
texte refusée), `false` retiré, carte neuve décochée.
