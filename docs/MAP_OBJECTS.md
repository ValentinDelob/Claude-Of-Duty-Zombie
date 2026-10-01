# Objets de l'éditeur de cartes : variantes, barrière invisible, escaliers

Complément de `docs/MAP_AUTHORING.md` (éditeur, format des cinq JSON,
partage réseau) pour les ajouts des **formats 5 et 6** des cartes :

1. les **variantes d'aspect** d'un type d'objet (plusieurs modèles de porte,
   de débris, d'arme murale) ;
2. la **barrière invisible** (« clip » de BO1) : un pavé qui arrête joueurs et
   zombies sans se voir en jeu ;
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

Pas de variante pour les fenêtres (barricade de BO1 : un seul aspect), les
portes du courant, les passages, les atouts (chaque machine a déjà son
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
  Invisible barrier. Tracée comme un pilier : glisser, ou clic puis clic,
  saisie au clavier (largeur, Tab, hauteur du rectangle, Entrée), poignées
  des coins, poignée ronde de rotation (15°, Alt : au degré près), R (90°).
- Règles de pose (`MapRules.check_rect`) : dans une seule pièce, **0,5 m** de
  côté au moins (1 m pour un pilier), sans chevaucher un autre objet posé au
  sol.
- Dessin : rectangle bleu clair translucide, **hachuré** à 45° (les hachures
  tournent avec lui), contour en tirets, icône au milieu.
- Propriétés : **Hauteur** (0 = du sol au plafond de l'étage ; sinon 0,5 à
  30 m), Angle, Pivoter, Supprimer, et le rappel de ce qu'elle bloque.
- Vérification : ses cases (0,5 m) sont **pleines** pour le validateur
  (passages, accessibilité, trajets à pied) comme un décor qui bloque ; une
  barrière qui coupe une zone en deux est donc signalée comme un mur.
- **Aperçu 3D** : un pavé bleu translucide à sa place ; menu **Affichage ▾ >
  Montrer les barrières invisibles** (coché par défaut, mémorisé avec les
  autres réglages de l'aperçu, clé `clips`).

### En jeu

Une `CollisionBox` (objet Godot du projet, `scripts/game/map/collision_box.gd`,
**jamais** une collision de modèle Blender) avec `barrier = true` : couche
`Barricade.BARRIER_LAYER`, **aucun maillage**. Elle passe par la clé
`blockers` de la description en maillage, comme les collisions du décor :

```json
{"center":[20.75,1.6,9.75],"size":[1,3.2,5],"yaw":0,"barrier":true,"surface":"concrete","clip":true,"eid":"i1"}
```

`clip` et `eid` servent seulement à l'aperçu 3D (`MapPreviewBuilder` y pose le
pavé translucide) ; `CollisionBox.from_dict` les ignore et `MeshMapBuilder`
ne construit rien de visible.

### Format

Type `bloc_invisible` de `objets.json` (identifiants `i1`, `i2`…) :

```json
{"id":"i1","type":"bloc_invisible","etage":0,"rect":[16,3,17,8]}
{"id":"i2","type":"bloc_invisible","etage":0,"rect":[5,5,5.5,8],"rot":30,"hauteur":1.2}
```

- `rect` = [x0, y0, x1, y1] (m) : le **vrai** pavé (pas un contour sur le
  trait comme un pilier) ; `rot` (facultatif) : rotation autour du centre,
  entier de 0 à 359, sens horaire vu de dessus ; `hauteur` (facultative,
  m, 0,5 à 30) : absente, du sol au plafond de l'étage.
- Cases pour le validateur (`MapRaster.clip_cells`) : celles dont le centre
  est dans le rectangle pris demi-ouvert dans son repère ([x0, x1[ × [y0,
  y1[) : une barrière de 0,5 m posée sur la grille prend une rangée de cases,
  pas deux.

## 3. Contrôle des cartes reçues (réseau, archives)

Une seule source, le catalogue (`MapCatalog.allowed_kinds()`), lue par
`CustomMapGuard` (docs/SECURITY.md) :

- `variante` : `{"t": "enum", "values": MapCatalog.variants(type)}`, déclarée
  **seulement** pour les types qui ont des variantes (`porte`, `debris`,
  `arme`). Refusés : une variante inconnue (`"titane"`), d'un autre type
  (`"planche"` sur une porte), qui n'est pas un texte, un chemin
  (`"res://…"`), une clé `variante` sur une fenêtre ou tout autre type.
- `bloc_invisible` : clés `id`, `type`, `etage`, `rect` (obligatoire,
  coordonnées bornées), `rot` (entier 0 à 359), `hauteur` (nombre fini de
  0,5 à 30) ; toute autre clé est refusée. Puis le validateur de jouabilité.
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
  masque le milieu du pied), le premier point des marches suivant alors
  l'ancre ; un escalier dont un bout n'a aucune place libre est signalé
  dans le journal (`[MeshNav] escalier ... couloir d'ancres désactivé`) et
  laissé au navmesh seul.
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
  la ligne de vue (pas de raccourci par l'angle d'un palier) ; il est passé
  quand le zombie franchit le plan perpendiculaire à sa direction
  d'arrivée ; sur les marches, séparation réduite (0,35), virage net
  (30 m/s²) et poussée vers l'axe au-delà de la demi-largeur
  (`MeshNav.lane_push`). La poursuite en ligne droite est interdite si la
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
côté (64,5 ; 51,4), celle de l'escalier est au milieu de l'allée qui lui fait
face. BUNKER K-7 (grille, un seul niveau) n'a pas d'escalier.

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

`EditorMap.FORMAT` = **6**. Toutes les nouvelles clés sont facultatives : une
carte au format 1 à 5 se lit telle quelle (`EditorMap._migrate`, rien à
convertir ; un escalier sans `variante` est droit) et s'enregistre au
format 6 ; DRAFT ARENA (format 1) reste identique octet pour octet dans sa
description en maillage. Un jeu plus ancien signale une carte au format 6
comme « plus récente » (et son contrôle refuserait les clés qu'il ne
connaît pas).

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
