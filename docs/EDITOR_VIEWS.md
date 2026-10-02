# Vues multiples de l'éditeur : élévations, ViewCube, dispositions

Spécification de conception (à valider avant tout code). Maquette :
`docs/editor_views_mockup/index.html` (taille réelle 1280 × 720, carte
DRAFT ARENA). Elle contient 4 écrans et une planche de composants :
1. 4 vues avec ViewCube ;
2. déplacement vertical d'une torche murale avec ses cotes ;
3. plafond d'une pièce agrandi en vue Avant, avec coupe ;
4. menu Disposition.

Demande : déplacer les éléments verticalement grâce à une vue verticale
affichée en même temps que la vue du dessus. Une vue unique bascule d'un plan
à l'autre par un cube cliquable (ViewCube, comme dans Fusion 360). On choisit
le nombre de fenêtres, on agrandit les zones selon les axes de la vue, et le
rendu est celui d'un éditeur professionnel.

## 0. Résumé des décisions

| # | Décision |
|---|---|
| D1 | Une **fenêtre de vue** (« vue ») = un plan orthographique (Dessus, Dessous, Avant, Arrière, Gauche, Droite) ou la **3D** (l'aperçu actuel, intégré). Chaque vue a son plan, son zoom et son déplacement. |
| D2 | Les vues de côté (**élévations**) montrent **tous les étages empilés** en projection, avec les éléments lointains estompés. Une **coupe** (tranche de profondeur) est facultative, réglable dans la vue, et sert à isoler une partie de la carte. |
| D3 | Chaque vue édite **les deux axes qu'elle montre** : X/Y en Dessus, X/Z en Avant, Y/Z en Droite. Le déplacement vertical change soit la **hauteur de pose** d'un élément, soit son **étage** (aimanté sur les niveaux), selon son type (§ 3). |
| D4 | **ViewCube** en haut à droite de chaque vue. Face = bascule du plan. Arête ou coin = passage en 3D vue de ce coin. Flèches ◄ ► = tour des façades. Maison = vue d'origine de la fenêtre. |
| D5 | Dispositions : **1 vue**, **2 côte à côte**, **2 empilées**, **3 (1 + 2)**, **3 (2 + 1)**, **4 en quadrillage**. Séparateurs déplaçables, vue active encadrée, **Ctrl+Espace** agrandit la vue active (bascule), **Ctrl+Alt+Q** passe en 4 vues. Tout est mémorisé (`_editeur.cfg`). |
| D6 | **Sélection commune** à toutes les vues (un seul `MapEditor.selected`, comme aujourd'hui). |
| D7 | **Vues liées** (option, activée par défaut) : axes communs synchronisés (X entre Dessus et Avant, Y entre Dessus et Droite, Z entre Avant et Droite : centre et zoom). |
| D8 | Axes colorés : **X rouge** (est), **Y vert** (sud), **Z bleu** (haut). Ils servent aux règles, au trièdre et aux flèches de déplacement. |
| D9 | Verrouillage d'axe : **flèches colorées** sur l'élément choisi (glisser une flèche = un seul axe), ou **X / Y / Z** pendant un glissement (comme dans Blender). **Maj garde son rôle actuel** (inverser l'aimantation). |
| D10 | Cotes affichées pendant tout glissement (hauteur au-dessus du sol, écart, largeur), dans toutes les vues, y compris la vue du dessus (nouveau). |
| D11 | Panneau Propriétés : champs **X, Y, Z** modifiables (Z = hauteur de pose quand elle existe, sinon l'étage). Un champ validé = une annulation. |
| D12 | **Format 12**, peu de nouvelles clés, toutes facultatives (§ 7) : `z` (hauteur de pose du décor), `hauteur` des luminaires au sol, `descente` (luminaires et effets au plafond). Aucune conversion n'est nécessaire : une carte au format ≤ 11 (zones d'effets) se lit telle quelle. |
| D13 | **La pose (création) reste en vue Dessus** dans cette version. Les élévations servent à choisir, déplacer, redimensionner et mesurer. Si un outil de pose est en main dans une élévation, la barre d'état le dit. |
| D14 | Une seule 3D à la fois : la fenêtre 3D **est** l'aperçu existant (même `MapPreviewWorld`), qui quitte alors son panneau flottant. Sans fenêtre 3D, le panneau flottant et la touche P marchent comme aujourd'hui. |

## 1. Existant (relevé)

### 1.1 Vue du dessus (`map_canvas.gd`)

- **Transformation** : `to_px(m) = origin + m * zoom`. Le zoom va de 4 à 120 px/m (`MIN_ZOOM`, `MAX_ZOOM`). Ctrl + molette zoome sous le curseur ; la molette seule fait défiler la barre rapide. On déplace la vue au clic milieu ou avec Espace + glisser. Origine : recadrer.
- **Dessin** : `_draw()` en mode immédiat. Couches dans l'ordre :
  1. fond ;
  2. grille (1 m, traits forts tous les 5 m, grille fine) ;
  3. étage du dessous en transparence ;
  4. pièces (couleur de zone) ;
  5. cases du validateur (`ed.raster()` : murs, vides, ouvertures) ;
  6. escaliers venus d'en dessous ;
  7. objets, ouvertures, noms ;
  8. éléments invalides ;
  9. sélection et poignées ;
  10. survol ;
  11. outil ;
  12. repère de la caméra 3D ;
  13. collaboration (`CollabView.draw_on`) ;
  14. règles de 20 px.

  Seul l'étage courant est dessiné.
- **Sélection** : un seul identifiant (`MapEditor.selected`). Le choix se fait par `element_at` (ouvertures, puis le plus petit objet via l'index par cases de 4 m, puis les pièces).
- **Glissements** (`drag.kind`) : `move`, `handle`, `rotate`, `create`, `capture`. L'instantané complet est pris à l'appui (`drag.snap`). À chaque mouvement, on restaure cet instantané puis on applique le candidat s'il est valide (`try_move`, `try_handle` → `MapRules.check_*`) ; sinon le refus s'affiche 1,5 s. Au relâché : `push_undo_snapshot(drag.snap)` puis `changed()`, soit **une entrée d'historique**.
- **Poignées** (`handles()`) :

  | Élément | Poignées |
  |---|---|
  | Pièce rectangle | 8 (coins, milieux) |
  | Pièce polygone ou forme | sommets |
  | Barrière invisible | sommets |
  | Pilier, escalier, piège | 4 coins (tournés si `rot`) |
  | Mur | 2 bouts |
  | Rotation | poignée ronde |

  Ouvertures, objets muraux, objets au sol et murs courbes n'ont pas de poignée.
- **Aimantation** (`map_snap.gd`) :
  - grille 1 m, grille fine (0,5 / 0,25 / 0,1 m) ou libre (centimètre, aimants sur les sommets et les côtés) ;
  - G change de mode, Maj+G change le pas fin, Maj maintenu inverse le mode ;
  - Alt libère l'angle.
- **Cotes** : pendant un tracé seulement (« L m · angle° », « l × h m »). Rien pendant un déplacement ou une poignée.
- **Curseur** : toujours la flèche par défaut.
- **Collaboration** :
  - les ops `put`, `del`, `carte`, `depart`, `add` (`map_ops.gd`) ;
  - la présence `{cursor:[x,y], floor, selection:[…], tool, live}`, 10 fois par seconde au plus ;
  - les dessins des autres participants (`collab_view.gd`) sont tous en coordonnées du plan.
- **MCP** (`map_agent_link.gd`) :
  - `editor_screenshot` fabrique un `MapCanvas` hors écran (`offscreen`, `floor_override`) de 1280 × 960 ;
  - il capture **le plan seul** ;
  - un `editor_apply` = une étape d'annulation.
- **Interface** (`MapEditor._build_ui`) :
  - un `HBoxContainer` : liste des objets, canvas, panneaux (340 px, 30 % au plus) ;
  - la barre rapide et l'inventaire sont **enfants du canvas** ;
  - l'aperçu 3D est un panneau flottant, agrandissable ou détachable.

  Fenêtre de référence : **1280 × 720** (`project.godot`). Taille d'interface : 80 % par défaut.
- **Thème** (`make_theme`, `UiStyle`) :

  | Élément | Couleurs |
  |---|---|
  | Panneaux | #212225, bord #38383D |
  | Boutons | #333338, survol #4D4233, enfoncé #73241A |
  | Onglet choisi | #4D1F14 |
  | Champs | #121214, focus #D99940 |
  | Textes | #DBD6C7 / BONE #DBD1B8 / DIM #8C8575 / GOLD #F2C759 |
  | Canvas | fond #1A1B1D, terrain #222426, murs #9E9EA8 |
  | Sélection, survol | #FFD94D, #59E6FF |
  | Porte, fenêtre | #FFAB00, #1A73FF |
  | 3D, Claude | caméra 3D #FF8C26, Claude #A066FF |

  Polices : Bahnschrift (corps, 14 × facteur), Impact (titres de section), Consolas (mono).

### 1.2 Grandeurs verticales par type d'élément

Altitude dans le monde = `etages[k].sol` + hauteur locale. Un étage :
- `sol` vaut `k × 3,5` par défaut ;
- `hauteur` (plafond) vaut 3,2 par défaut.

`check_floors` impose au moins 3,1 m entre deux sols (2,8 m + dalle `DALLE` de 0,3 m). Le plafond réel d'une case vaut :
- le dessous de la dalle de l'étage du dessus si celui-ci a un sol ;
- sinon, le plafond de la pièce ;
- si la case du dessus est une trémie, on remonte à l'étage du dessus (`MapLayoutExport.ceil_at`).

| Élément | Existe déjà (modifiable) | Implicite (constante) | Manque |
|---|---|---|---|
| **Étage** | `sol` (−20 à 200), `hauteur` (2,8 à 10 dans l'interface) | dalle 0,3 | — |
| **Pièce** | `etage` ; `plafond` (hauteur sous plafond ; interface 2,8 à 9, catalogue 2 à 20) ; `double_hauteur` (ouverte sur l'étage du dessus) | sol = sol de l'étage | décalage de sol dans un étage (mezzanine, demi-niveau) |
| **Mur libre, mur courbe, pilier** | `etage` | du sol au plafond (`wall_top`) | hauteur propre (muret) |
| **Porte, débris, porte du courant** | `carte.hauteur_portes` (une valeur pour toute la carte, 2,2 à 3,5) | linteau au-dessus | hauteur par porte |
| **Passage** | — | ouvert jusqu'au plafond | — |
| **Fenêtre** | `variante` | allège 0,95, linteau 2,35 (`SILL`, `LINTEL`) ; porte à zombies 2,1 | — |
| **Escalier** | `etage` | monte de `sol(k)` à `sol(k+1)` | escalier sur plusieurs étages |
| **Objets muraux** (atout, arme, boîte, Pack-a-Punch, courant, poste central, levier, grenades) | `etage` | au sol ; tableau d'arme 1,45, tableau de la boîte 1,65, levier 1,3 | — (gameplay fixe) |
| **Départ, apparition, téléporteur, arrivée** | `etage` | au sol | — |
| **Piège** | `etage` | zone de 0 à 2,5 m | — |
| **Décor (prefab)** | `etage` | posé au sol ; `h` (hauteur du modèle), `support` (dessus d'un meuble) | **hauteur de pose** (empiler, poser sur une étagère) |
| **Luminaire mural** | `hauteur` (0,2 à 30, 2 m par défaut) | sous le plafond − 0,15 | — |
| **Luminaire au plafond** | — | `drop` du catalogue (0,15 à 1,1) | **descente** réglable |
| **Luminaire au sol** | — | sur le `support` du meuble dessous | hauteur choisie |
| **Effet au sol, au mur** | `hauteur` (0 à 30 ; défauts du catalogue : torche 1,8, baril 0,9…) | mur : sous le plafond − 0,2 | — |
| **Effet au plafond** | — (la `hauteur` y est retirée) | collé au plafond | **descente** |
| **Barrière invisible** | `hauteur` (0,5 à 30, absente = jusqu'au haut de l'étage) | — | — |
| **Zone** | — (`plafond` y est une texture) | — | — |

Incohérences relevées (à corriger au passage, étape 3) :
- les bornes du `plafond` d'une pièce ne sont pas les mêmes dans l'interface, le catalogue et le contrôle des cartes, et le validateur ne les vérifie pas ;
- la surbrillance 3D d'une applique ignore sa `hauteur` ;
- une barrière sans `hauteur` monte au haut de l'étage, pas au plafond de la pièce ;
- `MAP_AUTHORING.md` annonce 6 étages et 1024 objets, alors que le code en permet 8 et 2048.

## 2. Références retenues

- **Fusion 360** : on reprend son ViewCube (faces, arêtes et coins cliquables ; maison ; flèches de rotation ; transition animée courte), ses cotes pendant le glissement et la saisie d'une valeur exacte.
- **Blender** : on reprend la vue en quadrillage (Ctrl+Alt+Q), l'agrandissement de la vue active (Ctrl+Espace) et le verrouillage X/Y/Z pendant un glissement.
- **Hammer, TrenchBroom** : on reprend les 3 vues orthographiques plus la 3D ; chaque vue édite ses deux axes ; poignées de redimensionnement dans chaque vue ; grille commune ; tout est projeté dans les vues de côté.
- **Unreal, Unity** : on reprend les axes X rouge, Y vert, Z bleu et les flèches de déplacement par axe.
- **On écarte** :
  - le gizmo de rotation 3D (la rotation reste en vue Dessus, autour de Z) ;
  - les vues perspectives multiples (une seule 3D) ;
  - les effets décoratifs (ombres portées, cubes brillants).

## 3. Modèle de vues

### 3.1 Plans et axes

Repère de la carte : X vers l'est, Y vers le sud, Z vers le haut. Une
**élévation** porte le nom de la face du cube que la caméra regarde. AVANT =
face sud : la caméra est au sud et regarde vers le nord.

| Vue | Caméra | Axe → (écran) | Axe ↑ (écran) | Profondeur (proche → loin) |
|---|---|---|---|---|
| **Dessus** | au-dessus | +X | −Y (nord en haut, comme aujourd'hui) | Z haut → bas |
| **Dessous** | en dessous | −X | −Y | Z bas → haut |
| **Avant** | au sud, regard vers le nord | +X | +Z | Y grand → petit |
| **Arrière** | au nord | −X | +Z | Y petit → grand |
| **Droite** | à l'est, regard vers l'ouest | −Y (nord à droite) | +Z | X grand → petit |
| **Gauche** | à l'ouest | +Y | +Z | X petit → grand |
| **3D** | orbite / vol / joueur (aperçu actuel) | — | — | — |

Les règles affichent les **vraies coordonnées** de l'axe montré, même quand il
va de droite à gauche (Droite affiche Y décroissant). Le nom de l'axe est écrit
dans le coin de la règle (« X », « Y », « Z ») avec sa couleur.

**Dessous** reste disponible par cohérence du cube, mais peu utile. En
Dessous, la vue montre l'étage courant vu par en dessous, plafonds compris.

### 3.2 Ce que montre une élévation

- **Tous les étages empilés** (choix par défaut). La plage d'étages se règle
  dans l'en-tête de la vue : « Étages : tous | jusqu'à l'étage courant |
  l'étage courant » (mêmes options que l'aperçu 3D).
- **Projection** de tous les éléments, dessinés du plus lointain au plus proche.
  Un élément plus lointain que le plus proche qui le recouvre est **estompé**
  (opacité de 100 % à 35 % selon la profondeur). Les étages autres que
  l'étage courant sont légèrement estompés aussi.
- **Coupe** (facultative) : tranche de profondeur [p0, p1] réglée de trois façons :
  - dans l'en-tête (« Coupe : aucune | autour de la sélection | personnalisée ») ;
  - en glissant ses deux traits pointillés dans la vue Dessus ;
  - par la touche **K** (coupe autour de la sélection, bascule).

  Hors tranche, les éléments sont dessinés à 15 % et ne réagissent pas au clic.
  C'est l'outil pour travailler une salle cachée derrière une autre.
- **Représentation** :

  | Élément | En élévation |
  |---|---|
  | Pièce | boîte du sol au plafond réel (`ceil_at`), remplie de la couleur de sa zone (faible opacité), contour gris ; nom en haut si elle n'est pas entièrement cachée |
  | Pièce double hauteur | jusqu'au plafond de l'étage du dessus |
  | Murs vus de face | surface de la pièce |
  | Murs vus de profil (perpendiculaires à la vue) | barres de 0,5 m (#9E9EA8) du bas de la dalle au plafond |
  | Dalles d'étage | bandes hachurées de 0,3 m sous chaque pièce d'un étage > 0 |
  | Sol de la carte | trait Z = 0 orange (comme les axes du plan), terrain hachuré dessous |
  | Ouvertures | rectangles colorés à leur vraie hauteur : porte de 0 à `hauteur_portes`, fenêtre de 0,95 à 2,35, passage jusqu'au plafond ; prix au-dessus de la porte |
  | Escalier | profil en marches quand on le voit de côté, bandes de contremarches quand on le voit de face |
  | Objets muraux et au sol | boîte à leur hauteur réelle (tableaux, machines, décor d'après `h` et `boxes`), icône du plan si la place le permet |
  | Luminaires, effets | icône à leur hauteur de lumière, trait fin pointillé jusqu'à leur point d'accroche (plafond, mur, sol) |
  | Barrière invisible | boîte hachurée violette jusqu'à sa `hauteur` |

- **Grille verticale** :
  - traits de 1 m, traits forts tous les 5 m, grille fine selon le mode ;
  - plus des **lignes de niveau** : chaque sol d'étage en trait plein, chaque plafond d'étage en tirets ;
  - à gauche, sur la règle Z, des **étiquettes de niveau** (« É1 +3,50 ») ; celle de l'étage courant est en or.
- **Aimantation verticale** :
  - même mode que la vue Dessus (grille 1 m, fine, libre au centimètre) ;
  - en libre, **aimants** sur les sols, plafonds (étage et pièce), dessous de dalle, `hauteur_portes`, allège et linteau des fenêtres, et dessus du décor (`support`, `h`) sous l'élément ;
  - l'aimant actif est signalé par un trait bleu (#59E6FF) et son nom (« Plafond · 3,20 »).

### 3.3 Vue Dessus

Elle reste la vue d'aujourd'hui. On ajoute :
- les traits de **coupe** des élévations ;
- la **puce Z** de l'élément choisi (« Z 2,40 m ») ;
- les flèches X/Y colorées sur l'élément choisi ;
- les cotes pendant le déplacement ;
- l'en-tête de vue et le ViewCube (avec rose N, E, S, O autour de la face DESSUS).

## 4. ViewCube

- **Place** : coin haut droit de chaque vue, 72 px à 100 % d'interface (suit la taille d'interface). Opacité de 60 % au repos, 100 % au survol.
- **Vue orthographique** : la face courante est dessinée de face, en carré étiqueté. Ses 4 faces voisines sont des bandes trapézoïdales autour, cliquables. Les 4 petits coins mènent à la 3D.
- **Vue 3D** : cube isométrique qui suit la caméra. Les 3 faces visibles, les arêtes et les coins sont cliquables.
- **Étiquettes** selon la langue du jeu : DESSUS/TOP, DESSOUS/BOTTOM, AVANT/FRONT, ARRIÈRE/BACK, GAUCHE/LEFT, DROITE/RIGHT.
- **Actions** :

  | Cible | Effet |
  |---|---|
  | Clic sur une face | bascule la vue vers ce plan |
  | Clic sur une arête ou un coin | la vue passe en 3D, caméra en orbite placée sur cette direction (isométrique pour un coin), visant le centre de la vue quittée |
  | Flèches ◄ ► (sous le cube, vue de côté) | façade suivante : Avant → Droite → Arrière → Gauche |
  | Flèches en vue Dessus | inutiles, masquées (le nord reste en haut) |
  | Maison ⌂ | vue d'origine de cette fenêtre (son plan dans la disposition par défaut), recadrée sur la carte |
  | Petit ▾ | menu : plan au choix, « Définir comme vue d'origine », « Recadrer (Origine) » |

  Si la 3D est déjà affichée dans une autre fenêtre, une arête ou un coin bascule cette fenêtre-là sur la direction choisie, puisqu'il n'y a qu'une 3D (D14).
- **Survol** : la face, l'arête ou le coin sous la souris s'éclaire (bouton survolé #4D4233, bord #D99940). Une bulle d'aide en donne le nom.
- **Transition** : 180 ms. En ortho, les deux plans ont un axe commun. Cet axe reste fixe, et l'autre glisse en fondu (fondu croisé de 2 images + glissement). On n'anime pas de vraie rotation 3D. L'animation est coupée si l'option « Réduire les animations » est active.
- **Raccourcis** (souris sur la vue) :

  | Touche | Vue |
  |---|---|
  | 7 du pavé | Dessus |
  | 1 du pavé | Avant |
  | 3 du pavé | Droite |
  | Ctrl + 1 / 3 / 7 du pavé | vue opposée |
  | 5 du pavé | bascule 3D / dernier plan |

  Les chiffres du pavé choisissent aujourd'hui une case de la barre rapide. Ils la gardent quand la souris n'est sur aucune vue, et les chiffres du haut du clavier la gardent toujours.

## 5. Dispositions multi-fenêtres

- **Menu Disposition** (nouveau bouton de la barre du haut, à droite d'APERÇU 3D, icône de quadrillage + ▾) :
  - 6 vignettes : 1 vue, 2 côte à côte, 2 empilées, 3 (1 grande + 2), 3 (2 + 1 large), 4 vues ;
  - options : « Lier les vues » (coché), « Coupe partagée entre élévations », « Agrandir la vue active (Ctrl+Espace) », « Réinitialiser la disposition ».
- **Plans par défaut** :

  | Disposition | Plans |
  |---|---|
  | 2 | Dessus · Avant |
  | 3 | Dessus (grande) · Avant · Droite |
  | 4 | Dessus (haut gauche) · 3D (haut droite) · Avant (bas gauche, sous Dessus : mêmes colonnes X) · Droite (bas droite, à côté d'Avant : mêmes lignes Z) |

  Une fenêtre garde le plan qu'on lui a donné tant qu'on ne réinitialise pas.
- **Séparateurs** :
  - 4 px, poignée centrale de 3 points, curseur ↔ / ↕ ;
  - double-clic : partage égal ;
  - taille minimale d'une vue : 220 × 160 px.
- **Vue active** : celle qui a reçu le dernier clic ou que survole la souris (clavier et molette vont à la vue survolée). Elle est encadrée de 1 px #D99940 et son en-tête est plus clair.
- **En-tête de vue** (22 px) :
  - à gauche : nom du plan en capitales (Bahnschrift semi-gras), étage ou plage d'étages, axes de l'écran (« X → · Z ↑ » en couleurs) ;
  - à droite : « Étages ▾ », « Coupe ▾ » (élévations), zoom en %, bouton ⛶ (agrandir).
- **Agrandir** : Ctrl+Espace ou ⛶ agrandit la vue active à toute la zone des vues ; une seconde fois, retour à la disposition. Double-clic sur l'en-tête : même effet.
- **Liaison** (D7) :
  - zoom commun pour toutes les vues orthographiques ;
  - centre commun sur l'axe partagé ;
  - glisser la vue Dessus vers l'est fait glisser Avant ;
  - désactivée, chaque vue est libre.
- **Barre rapide** :
  - en 1 vue, elle reste posée sur le bas de la vue, comme aujourd'hui ;
  - en 2 vues ou plus, elle est **ancrée dans une bande de 48 px** sous les vues, avec à gauche l'outil et à droite l'aimantation ;
  - l'inventaire s'ouvre au-dessus de la zone des vues.
- **Mémorisation** dans `_editeur.cfg`, clé `vues` : disposition, plan de chaque fenêtre, proportions, liaison, coupe, plage d'étages. Le zoom et le centre ne sont pas mémorisés : chaque vue se recadre à l'ouverture d'une carte.
- **Premier lancement** : 2 vues empilées, Dessus au-dessus d'Avant (écran 2 de la maquette, validé le 03/10/2026) ; ensuite, le choix est mémorisé.

## 6. Édition dans chaque vue

### 6.1 Déplacer

- Glisser un élément le déplace dans les **deux axes de la vue**.
- Sur l'élément choisi, des **flèches d'axe** permettent de glisser un seul axe :
  - X rouge, Y vert, Z bleu, pointées vers le sens positif à l'écran ;
  - un carré central (deux couleurs) déplace sur les deux axes ;
  - elles apparaissent seulement si l'élément peut bouger sur cet axe.
- Pendant un glissement, **X / Y / Z** verrouille l'axe ; la même touche le libère. Un trait de guide infini de la couleur de l'axe s'affiche.
- **Composante verticale** selon le type :

  | Type | Effet d'un glissement vertical |
  |---|---|
  | **Hauteur de pose** : effet au sol / au mur, luminaire mural / au sol (`hauteur`), effet ou luminaire au plafond (`descente`), décor (`z`, format 12) | Z continu, aimanté (§ 3.2). Monter ou descendre au-delà du sol ou du plafond de son étage fait passer l'élément à l'étage voisin, qui doit exister : `etage` est recalculé et la hauteur devient relative au nouveau sol. Bornes : 0 à plafond réel − marge (règles de `MapLayoutExport`) |
  | **Niveau** : pièce (avec son contenu, comme un déplacement dans le plan), escalier, pilier, mur, piège, objets muraux, départ, apparitions, téléporteur | Z aimanté **sur les sols d'étage uniquement** : l'élément change d'`etage`. Il est validé sur l'étage cible par les mêmes `MapRules.check_*` (place libre, murs, porte sur bord commun…). Un escalier ne peut pas aller sur le dernier étage |
  | **Fixe** : ouvertures (portes, fenêtres, passages) | pas de déplacement vertical. Elles suivent leur mur. Pour changer d'étage, il faut déplacer la pièce |

- **Composante horizontale** en élévation : elle déplace sur l'axe de la vue, la profondeur restant inchangée. Une ouverture ou un objet mural glisse **le long de son mur** si ce mur est face à la vue ; sinon l'axe horizontal est verrouillé.
- Le refus éventuel s'affiche comme aujourd'hui (contour rouge, raison dans la barre d'état), et l'élément reste à la dernière place valide.

### 6.2 Redimensionner (agrandir les zones)

Les poignées n'apparaissent que là où la grandeur existe pour le type et la vue :

| Élément | Dessus | Élévation (Avant, Droite…) |
|---|---|---|
| Pièce rectangle | 8 poignées (inchangé) | gauche/droite = côtés sur l'axe horizontal de la vue ; **haut = `plafond`** (aimanté sur le plafond de l'étage et sur le dessous de la dalle du dessus ; impossible si `double_hauteur` : la poignée devient un cadenas avec une bulle d'aide) |
| Pièce polygone, forme | sommets | **haut = `plafond`** seulement (pas de côtés : la forme ne se déforme qu'en Dessus) |
| Pilier, escalier, piège (rect non tourné) | 4 coins | gauche/droite sur l'axe de la vue (pilier, piège) ; aucune poignée de hauteur (implicite) |
| Barrière invisible | sommets | **haut = `hauteur`** (poignée en pointillés quand elle va « jusqu'au plafond » ; la tirer fixe une valeur) |
| Mur libre | 2 bouts | bouts sur l'axe de la vue si le mur est parallèle à la vue |
| Étage | — | **étiquette de niveau** glissable : `sol` de l'étage (au moins 3,1 m d'écart avec les voisins). Tirets du plafond du dernier étage : `hauteur` |
| Porte, débris, passage | — | gauche/droite = `largeur` (1 à 6 m, pas de 0,5 m), si le mur est face à la vue |
| Effet (`taille`) et zones d'effet | selon le travail en cours sur les zones d'effet | mêmes grandeurs projetées, plus la hauteur de la zone si elle existe ; à aligner sur ce travail (§ 9, risque R3) |

Une poignée tirée affiche la cote de la grandeur (« Plafond 4,20 m (+1,00) »).
Une grandeur ramenée à sa valeur par défaut retire sa clé du fichier, comme
aujourd'hui.

### 6.3 Règles, cotes, saisie

- **Règles** : `MapRules` reste en 2D et vérifie l'emprise sur l'étage cible.
  Un nouveau `MapVertical.check_z(doc, e, k, z)` vérifie le reste :
  - bornes du type ;
  - plafond réel (`ceil_at`) ;
  - étage existant ;
  - `plafond` d'une pièce de 2,8 à 9 (bornes rendues identiques partout).

  Les étages passent par `check_floors`.
- **Cotes** (D10), en Bahnschrift 12 sur pastille #121214 bordée #38383D :
  - hauteur au-dessus du sol de l'étage (trait de cote vertical avec flèches) ;
  - écart depuis le début du glissement (« ΔZ +0,60 m ») près du curseur ;
  - distance horizontale au mur le plus proche sur l'axe de la vue ;
  - largeur ou hauteur de la poignée tirée.
- **Saisie précise** :
  - pendant un glissement, taper une valeur puis Entrée fixe l'écart sur l'axe verrouillé (ou vertical par défaut en élévation), dans le même champ près du curseur qu'aujourd'hui ;
  - dans le panneau Propriétés, une ligne **Position** remplace la note actuelle : champs **X**, **Y** (m, pas de la grille) et **Z** (m au-dessus du sol pour une hauteur de pose ; sinon une liste **Étage**) ;
  - un champ validé = une étape d'annulation ;
  - une valeur refusée est remise et la raison s'affiche.
- **Curseurs** :

  | Situation | Curseur |
  |---|---|
  | Au-dessus d'un élément déplaçable | déplacement (⤧) |
  | Flèche d'axe | ↔ ou ↕ |
  | Poignée | redimensionnement orienté |
  | Vue en cours de déplacement | main fermée |

  Les mêmes curseurs sont ajoutés à la vue Dessus.
- **Annulation** : inchangée, un glissement = un `push_undo_snapshot` + `changed()` au relâché.

### 6.4 Collaboration et MCP

- **Ops** : aucune nouvelle. Un déplacement vertical produit des `put` d'éléments, plus un `carte` pour les étages.
- **Présence** : clés facultatives en plus, `z` (hauteur du curseur, m) et `vue` (plan de la vue survolée). Ainsi le curseur d'un participant est dessiné dans les élévations à sa vraie hauteur (s'il est dans une élévation), sinon par un trait vertical dans la colonne de sa position.
- **`CollabView`** dessine les silhouettes, sélections et éclairs à travers un adaptateur de projection (`view.project_elem`) au lieu de `cv.to_px`. Une vieille version de l'éditeur ignore ces clés : compatibilité garantie.
- **MCP** :
  - `editor_screenshot` reçoit `view` (`dessus` par défaut, `avant`, `arriere`, `gauche`, `droite`), plus `coupe` [p0, p1] facultative ;
  - `editor_get_element` renvoie `z_monde` (altitude absolue) et `z_min` / `z_max` pour aider l'agent ;
  - les instructions du serveur décrivent `z`, `descente` et `hauteur` ;
  - `editor_apply` est inchangé.

## 7. Format 12 (nouvelles clés, toutes facultatives)

| Type | Clé | Sens | Bornes | Par défaut (jamais écrite) |
|---|---|---|---|---|
| `prefab` | `z` | hauteur de pose du décor au-dessus du sol (m) | 0 à 30, pas de 0,01 | 0 (au sol) |
| `luminaire` (au sol) | `hauteur` | aujourd'hui réservée aux appliques ; s'étend au sol | `WALL_LIGHT_HEIGHT` | dessus du meuble dessous (`support`) |
| `luminaire` (au plafond), `effet` (au plafond) | `descente` | distance sous le plafond (m) | 0 à 3 | `drop` du catalogue / 0 |

- Fichiers touchés :
  - `EditorMap.FORMAT` = 11 et commentaire de version ;
  - `_migrate` sans conversion ;
  - `_normalize` (via `MapCatalog.tidy_*`) retire les valeurs illisibles ou par défaut ;
  - `MapCatalog.allowed_kinds()` déclare les clés (le contrôle des cartes reçues `CustomMapGuard` s'en sert) ;
  - `MapLayoutExport` (`_fixture`, `_effects`, décor : `_world(k, c, z)` et pavés de collision décalés de `z`) ;
  - surbrillance de l'aperçu 3D.
- Une carte au format 12 est refusée par un jeu au format 11 (règle actuelle `format ≤ FORMAT`).
- **Décor surélevé** (Q1) :
  - un décor « solide » ou « barrière » posé à `z > 0` doit reposer sur le `support` (ou le haut `h`) d'un autre décor sous lui, aimanté ;
  - sinon il est refusé avec la raison « décor en l'air : posez-le sur un autre » ;
  - un décor sans collision (« non ») peut flotter librement (lustre tombé accroché, débris).

  Ainsi le navmesh et les collisions restent cohérents.

## 8. Identité visuelle

On reste dans le thème actuel (§ 1.1). On le professionnalise sans gadget :
- **En-têtes de vue** : #1C1D20, texte BONE ; nom du plan en capitales espacées (+0,06 em) ; séparateur de 1 px #2C2D31 ; vue active #26272B avec cadre #D99940.
- **Règles** :
  - fond #121214 à 95 % ;
  - graduations fines tous les pas, chiffres tous les 5 m ;
  - curseur marqué en or ;
  - lettre d'axe colorée dans le coin.
- **Axes** :

  | Axe | Couleur |
  |---|---|
  | X | #E5484D |
  | Y | #46A758 |
  | Z | #3E7BFA |

  Ces couleurs sont désaturées pour rester lisibles sur #1A1B1D sans concurrencer le jaune de sélection. Un **trièdre** de 28 px en bas à gauche de chaque vue montre les deux axes de l'écran et un point pour l'axe de profondeur.
- **Poignées** :
  - carrés jaunes #FFD94D bordés de noir (inchangés) ;
  - poignée de hauteur en losange, pour la distinguer d'un coin ;
  - flèches d'axe de 36 px.
- **Cotes** : trait de cote 1 px BONE, flèches pleines, pastille sombre ; écart en or.
- **ViewCube** : faces #2A2B2F, bord #4D4D54, texte DIM ; face courante #3A3B40, texte BONE ; survol #4D4233, bord #D99940. Pas d'ombre ni de dégradé.
- **Textes** : Bahnschrift. Toutes les tailles suivent `EditorUi.fs` et la taille d'interface.

## 9. Plan d'implémentation

Chaque étape se livre seule, avec ses tests, et sans régression de la vue
actuelle.

| Étape | Contenu | Fichiers | Tests |
|---|---|---|---|
| **1. Moteur de vue** | `MapView` (Control) : transformation générique plan ↔ écran (`project(Vector3)`, `unproject(px, profondeur)`), zoom et déplacement, grille, règles, en-tête, trièdre. `MapCanvas` hérite de `MapView` (plan Dessus) sans changer de comportement. La barre rapide et l'inventaire passent de `canvas` à un conteneur de vues. `CollabView` et `MapPreviewPanel.draw_on_canvas` passent par la vue. | nouveau `scripts/editor/views/map_view.gd` ; `map_canvas.gd`, `map_editor.gd` (`_build_ui`), `collab_view.gd`, `map_preview_panel.gd`, `map_agent_link.gd` (capture) | Tous les tests et scénarios de l'éditeur inchangés et verts (`test_map_editor*`, `map_editor`, `map_editor_freeform`, `map_editor_diagonal`, `map_editor_ui_size`, `map_preview`) ; nouveau `test_map_view.gd` (aller-retour project / unproject pour les 6 plans, règles inversées) |
| **2. Élévations en lecture** | `MapElevation` (hérite de `MapView`) : projection de tous les éléments, profondeur, estompage, étages, coupe, lignes et étiquettes de niveau, choix au clic (sélection commune), survol. Cache des boîtes projetées refait à chaque `changed()` (version de la carte), pas à chaque image. Disposition provisoire : 2 vues côte à côte (sans menu). | nouveaux `views/map_elevation.gd`, `views/map_elevation_items.gd` (boîtes 3D par type, logique pure), `map_vertical.gd` (`z_of`, `ceil_at` partagé avec `MapLayoutExport`) | `test_map_vertical.gd` (hauteurs de tous les types sur DRAFT ARENA : double hauteur, passerelle, escalier, plafond sous dalle) ; scénario `map_views` @rendu (captures Avant, Droite, Dessous, avec coupe) ; mesure : dessin < 4 ms sur la carte de 50 pièces et 2000 objets |
| **3. Édition verticale** | Glissement en élévation, verrouillage d'axe, flèches d'axe, poignées verticales (plafond, hauteur, sol d'étage, largeur), aimants verticaux, cotes dans toutes les vues, X/Y/Z du panneau Propriétés, format 12 (`z`, `descente`, `hauteur` au sol), export en jeu, contrôle des cartes reçues, bornes du plafond unifiées. | `map_vertical.gd` (`check_z`, `set_z`, aimants), `map_elevation.gd`, `map_canvas.gd` (cotes, flèches), `map_editor.gd` (`try_move_z`, `try_handle_z`), `map_panels.gd`, `map_catalog.gd`, `editor_map.gd`, `map_layout_export.gd`, `map_validator.gd`, `custom_map_guard.gd` (via le schéma) | Unitaires : chaque type × chaque vue (bouge / ne bouge pas / refus), changement d'étage d'une pièce avec son contenu, une action = une annulation, aller-retour fichier format 12, carte format 11 lue sans changement, carte reçue avec `z` hors bornes refusée ; scénario `map_views_edit` (glisser une torche de 1,8 à 2,4 m, plafond de pièce, étiquette d'étage, X/Y/Z) ; scénario de partie : décor posé sur une caisse, collision vérifiée |
| **4. ViewCube** | `MapViewCube` : dessin (net ortho, cube iso en 3D), détection de face, arête et coin, survol, bulles d'aide, maison, flèches, menu, transition, raccourcis du pavé numérique. | nouveau `views/map_view_cube.gd`, `map_elevation.gd`, `map_preview_camera.gd` (pose isométrique sur une direction) | Unitaires : détection des 26 cibles, voisins de chaque face ; scénario @rendu (clic sur chaque face, arête vers 3D, maison) |
| **5. Dispositions** | `MapViewLayout` : 6 dispositions, séparateurs, vue active, agrandir, liaison, menu Disposition, mémorisation, 3D intégrée (l'aperçu quitte son panneau flottant), barre rapide ancrée. | nouveau `views/map_view_layout.gd`, `map_editor.gd`, `map_preview_panel.gd`, `map_hotbar.gd`, `editor_options.gd` | Unitaires : mémorisation, tailles minimales, liaison des axes ; scénario @rendu à 60, 80 et 150 % d'interface ; mesure : 4 vues sur la carte de 2000 objets, redessin à chaque mouvement de souris seulement dans la vue survolée |
| **6. MCP, collaboration, docs** | Présence `z` et `vue`, curseurs et silhouettes des autres dans les élévations, `editor_screenshot(view, coupe)`, `editor_get_element` (z), instructions du serveur, documentation (`MAP_AUTHORING.md` § 2 et format, `MAP_COLLAB.md`, `MAP_OBJECTS.md`), aide « ? », notes de version. | `collab_view.gd`, `map_editor.gd` (présence), `map_agent_link.gd`, `tools/mcp/map_editor_mcp.py`, docs | `test_collab_view` (adaptateur de projection), `test_map_agent_link`, `tools/mcp/test_map_editor_mcp.py` ; scénario collaboratif hôte + invité (curseur en élévation) |

Les captures de scénario ne servent que pendant le développement de chaque
étape, puis sont retirées. Les scénarios tournent hors écran
(`tools/scenario.sh`), une instance à la fois.

**Risques** :
- **R1 Régression de la vue Dessus** (étape 1) : `MapCanvas` est le cœur de l'éditeur (1737 lignes).
  - Parade : extraction mécanique en commits courts, sans changement de dessin. Les scénarios existants pilotent `cv._gui_input` avec `cv.to_px` : ces deux fonctions gardent leur nom et leur sens.
- **R2 Performances** : 4 vues redessinées à chaque modification.
  - Parade : boîtes projetées en cache par version de carte ; seule la vue survolée se redessine au mouvement de souris ; tri par profondeur une fois par modification ; découpe hors champ comme aujourd'hui (`_draw_object`).
- **R3 Conflits avec le travail en cours** (zones redimensionnables des effets, `map_canvas.gd`, `map_editor.gd`, `map_catalog.gd`, `map_panels.gd`).
  - Parade : l'étape 1 commence **après** la fusion de ce travail ; les poignées d'effet sont reprises telles quelles en Dessus et projetées en élévation.
- **R4 Clavier** : pavé numérique déjà utilisé par la barre rapide.
  - Parade : la règle « souris sur une vue » (§ 4). À vérifier dans `test_map_editor_mouse`.
- **R5 Décor surélevé en jeu** (Q1) : collisions et navmesh.
  - Parade : reposer obligatoirement sur un autre décor s'il est bloquant ; scénario de partie dédié.

## 10. Décisions de la revue (03/10/2026)

Maquette validée par l'utilisateur, l'écran 2 (« Déplacement vertical en vue Avant », avec son ViewCube) servant de référence visuelle : tailles, couleurs, flèches d'axe, cotes et ViewCube à reproduire tels quels.

1. **Q1. Hauteur de pose du décor (`z`)** : oui, dans cette version, avec la règle du § 7 (un décor bloquant repose sur un autre).
2. **Q2. Disposition au premier lancement** : 2 vues empilées, Dessus au-dessus d'Avant (écran 2) ; les autres dispositions restent au menu.
3. **Q3. Panneau 3D flottant** : gardé quand aucune fenêtre n'est en 3D (D14).

Hors périmètre (à proposer plus tard si besoin) :
- hauteur propre des murs et piliers (murets) ;
- hauteur par porte ;
- demi-niveaux dans un étage ;
- sélection multiple et sélection par rectangle (la présence l'accepte déjà) ;
- pose d'éléments directement en élévation.

## 11. Réalisation : écarts et précisions

Notés au fil des étapes (à valider avec l'utilisateur).

- **Étape 2 : disposition par défaut directement**. La disposition
  provisoire « 2 côte à côte » est sautée : la revue du 03/10/2026 a fixé
  le premier lancement à 2 vues empilées (Dessus au-dessus d'Avant), mise en
  place dès l'étape 2 avec la bande de la barre rapide.
- **Vue Dessus unique**. La vue Dessus (`MapCanvas`) porte les outils de
  pose, l'aimantation et le tracé en cours : il n'y en a qu'une. Donner le
  plan Dessus à une fenêtre (ViewCube, menu) **échange** les plans des deux
  fenêtres. Une disposition sans vue Dessus la garde cachée (ses réglages
  restent ceux de l'éditeur).
- **Menu des étages** : l'en-tête n'a pas de puce « Étages ▾ » en plus ; un
  clic sur le texte « étages : tous » (surligné au survol) ouvre le menu,
  pour garder l'en-tête de la maquette.
- **Zoom affiché** : 100 % = 15 px par mètre (valeurs de la maquette : 22
  px/m → 147 %).
- **Choix au clic en élévation** : ouvertures d'abord, puis le plus petit
  objet sous le curseur, puis la pièce la plus proche ; exception : une
  pièce d'un autre étage contenue dans le volume de la plus proche (la
  passerelle dans l'entrepôt en double hauteur) est choisie à sa place. En
  Avant, la caméra est au sud : la salle des machines (au sud) est DEVANT
  l'atelier et l'entrepôt (la légende de l'écran 3 de la maquette dit
  l'inverse ; le tableau du § 3.1 fait foi).
- **Performances** (mesurées par `test_map_vertical`, carte de 50 pièces et
  2000 objets) : dessin du contenu d'une élévation ≈ 2,2 ms (objectif 4 ms) ;
  projection (une fois par version de la carte et par plan) ≈ 30 ms. Le
  contenu est une couche à part, redessinée seulement quand la carte, le
  zoom, la coupe ou l'étage changent ; un déplacement de la vue la décale ;
  la souris ne redessine que la couche du dessus (règles, sélection,
  survol). Deux boîtes de même rectangle à l'écran ne sont dessinées qu'une
  fois (la plus proche).
- **Pilier et mur libre dans une double hauteur** : ils montent jusqu'en
  haut de l'étage du dessus (comme `MapRaster`, qui les prolonge dans la
  trémie).
- **Étape 3 : aimants verticaux** actifs en grille fine et en libre (pas en
  grille 1 m), rayon de 6 px : on les croise sans y rester collé (maquette :
  linteau « croisé puis dépassé »). La valeur tapée pendant un glissement
  (Tab, ou directement un chiffre ou « - ») ignore les aimants.
- **Hauteurs de pose (format 12)** : en plus du § 7, la `descente` vaut aussi
  pour le **décor accroché au plafond** (câble suspendu) ; la `hauteur` d'un
  luminaire au sol va de 0 à 30 m (0 : par terre, même sur un meuble), le
  contrôle des cartes reçues accepte donc 0 pour la `hauteur` d'un
  luminaire. Un luminaire du plafond descendu au-delà de son `drop` descend
  avec sa lumière (l'objet ne monte jamais au-dessus du plafond).
- **Décor posé sur un autre** : un décor dont la tranche de hauteur est
  au-dessus d'un autre ne le « chevauche » pas pour les règles de pose
  (`MapRules._stacked`) ; un décor bloquant au-dessus du sol doit reposer
  sur le dessus d'un autre (à 2 cm près), sinon « décor en l'air ».
- **Plafond d'une pièce** : bornes 2,8 à 9 m partout (panneau, catalogue et
  contrôle des cartes reçues, erreur du validateur) ; la poignée losange
  s'arrête au dessous de la dalle quand une pièce de l'étage du dessus
  couvre toute la pièce (sinon 9 m), message vérifié en direct au-dessus.
- **Barrière invisible sans hauteur** : en jeu et en élévation, jusqu'au
  plafond réel de la pièce à son milieu (et plus le haut de l'étage).
- **Objets muraux et ouvertures** : en élévation, ils glissent sur l'axe de
  l'écran seulement si leur mur est face à la vue ; en vue Dessus, seule la
  flèche de l'axe de leur mur est montrée.
- **Panneau Propriétés** : la ligne Position (X, Y, Z) est ajoutée en tête ;
  les champs « Hauteur » existants (applique, effet, décor mural) restent
  (scénarios et habitudes) et suivent la même valeur que Z.
- **Étape 4 : ViewCube**. Opacité : 75 % hors de la fenêtre active, 100 %
  dans la fenêtre active et au survol (valeurs de la maquette, au lieu de
  60 % au repos). Le jeu n'a pas d'option « Réduire les animations » : la
  transition de 180 ms est toujours jouée (fondu de l'image d'avant et
  glissement le long de l'axe qui change). Le cube isométrique est aussi
  sur le panneau flottant de l'aperçu 3D : une face y tourne la caméra de
  face (dans une fenêtre 3D de la disposition, elle bascule la fenêtre vers
  ce plan) ; arête et coin : caméra en orbite sur cette direction, même
  point visé. Pavé 5 : la 3D vue du coin avant-droite-dessus du plan montré
  (ou de la face, en Dessus et Dessous).
