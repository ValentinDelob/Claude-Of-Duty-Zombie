# Objets de l'éditeur de cartes : variantes et barrière invisible

Complément de `docs/MAP_AUTHORING.md` (éditeur, format des cinq JSON,
partage réseau) pour deux ajouts du **format 5** des cartes :

1. les **variantes d'aspect** d'un type d'objet (plusieurs modèles de porte,
   de débris, d'arme murale) ;
2. la **barrière invisible** (« clip » de BO1) : un pavé qui arrête joueurs et
   zombies sans se voir en jeu.

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

## 4. Versions du format

`EditorMap.FORMAT` = **5**. Toutes les nouvelles clés sont facultatives : une
carte au format 1 à 4 se lit telle quelle (`EditorMap._migrate`, rien à
convertir) et s'enregistre au format 5 ; DRAFT ARENA (format 1) reste
identique octet pour octet dans sa description en maillage. Un jeu plus
ancien signale une carte au format 5 comme « plus récente » (et son contrôle
refuserait les clés qu'il ne connaît pas).

## 5. Ajouter une variante ou un type à variantes

1. `MapCatalog.VARIANTS` : `[identifiant, nom FR, nom EN]`, la première
   ligne étant l'aspect d'avant (par défaut). Le contrôle des cartes, la liste
   « Aspect (V) », la touche V et la lecture suivent tout seuls.
2. Construire le modèle dans la classe du jeu (`Door`, `WallBuy`…) en lisant
   `m.data.variant` ; une valeur inconnue doit donner l'aspect par défaut.
3. Pour un nouveau type : transmettre la variante dans `MapLayoutExport`
   (`md.variants[eid]`, seulement si elle existe) et dans `MeshMapLayout`.
4. Tests : `tests/test_map_objects.gd`.

## 6. Preuves automatiques

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
