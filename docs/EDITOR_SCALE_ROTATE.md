# Échelle et rotation 3D du décor dans l'éditeur

Spécification de conception **validée** par l'utilisateur (03/10/2026, avec
la maquette et les décisions du § 8) ; réalisée en 7 étapes (§ 7). Maquette :
`docs/editor_scale_rotate_mockup/index.html` (taille réelle 1280 × 720,
carte DRAFT ARENA, même style que `docs/editor_views_mockup/`). Elle montre
3 écrans et une planche de composants :
1. agrandissement d'une pile de caisses en vue Dessus (×1,50), vue Avant qui
   suit, panneau Propriétés (Échelle, Rotation) ;
2. inclinaison d'une poutre à +30° par le gizmo à 3 anneaux de la vue 3D,
   avec la vue Avant (anneau Y) et la vue Dessus ;
3. prefab contenant un Pack-a-Punch : poignées d'échelle bloquées et
   avertissement.

Demande : changer l'échelle des objets décoratifs et des prefabs, et les
faire pivoter comme dans Fusion 360 ou SolidWorks. Un objet comme le
Pack-a-Punch ne change jamais d'échelle ; un prefab qui en contient un non
plus, et l'éditeur le dit.

S'appuie sur `docs/EDITOR_VIEWS.md` (vues, ViewCube, axes X rouge #E5484D /
Y vert #46A758 / Z bleu #3E7BFA, cotes, aimants, D1 à D14), dont il reprend
les conventions sans les changer.

## 0. Résumé des décisions

| # | Décision |
|---|---|
| E1 | Seul le **décor de type `prefab`** change d'échelle : décor du catalogue (« Décor et obstacles », au sol, mural ou au plafond) et **prefabs de la carte** (groupe ou modèle importé). Tout le reste garde sa taille ou ses propres poignées (§ 1). |
| E2 | Un **prefab de la carte** qui contient un objet non redimensionnable (objet de jeu) est **bloqué** : pas de poignées d'échelle, champs grisés, message qui **nomme l'objet** (« contient un Pack-a-Punch »). Calculé d'après sa définition, jamais écrit dans le fichier. |
| E3 | Échelle **par axe** (largeur X, profondeur Y, hauteur Z, dans le repère de l'objet) et **uniforme** (cadenas du panneau, poignées de coin). Bornes **0,25× à 4×** par axe ; dimension finale de 0,05 à 30 m, emprise au sol de 20 m au plus. |
| E4 | Pas de l'échelle selon l'aimantation : **grille 1 m → 0,25**, **grille fine → 0,05**, **libre → 0,01** avec aimants (×1, ×0,5, ×2, taille d'un décor voisin). Maj inverse, comme partout. |
| E5 | **Rotation à 3 axes** façon Fusion 360 : anneaux par axe (gizmo), crans de **15°**, **Maj (ou Alt, comme la poignée ronde d'avant) = libre** au degré près, angle affiché pendant le geste, valeur tapée au clavier, champs **Rotation X / Y / Z** dans Propriétés. Anneaux alignés sur les **axes du monde**. |
| E6 | **Inclinaison (X, Y)** : seulement le décor **au sol** de type `prefab` (catalogue ou prefab de la carte sans objet de jeu). Tout le reste ne tourne qu'autour de Z, comme aujourd'hui (ou pas du tout). |
| E7 | Un décor incliné reste **posé** : son point le plus bas reste sur son support (option « Rester posé », cochée par défaut). |
| E8 | Anneau par vue : **Dessus → Z**, **Avant → Y**, **Droite → X** (l'axe vu de bout) ; **3D → les trois** (premier outil d'édition de la fenêtre 3D). Poignées d'échelle dans Dessus et les élévations, pas en 3D. |
| E9 | **Une action = une annulation** (un glissement, un champ validé, un bouton ↺). Aucune nouvelle op de collaboration ; MCP par `put`. |
| E10 | **Format 14** : `echelle` [x, y, z] et `incl` [x, y] sur les objets `prefab`, facultatives, jamais écrites à leur valeur par défaut. `rot` (Z, degrés entiers) inchangé. Cartes ≤ 13 lues telles quelles. |
| E11 | En jeu : modèle et **pavés de collision** (`CollisionBox`) mis à l'échelle et inclinés avec l'objet ; cases bloquées (trajets des zombies) = projection au sol de la boîte de l'objet. |

## 1. Ce qui change d'échelle, ce qui pivote

### 1.1 Tableau par type

Relevé dans `MapCatalog` (`_build`, `PREFABS`, `LIGHTS`, `EFFECTS`,
`DECOR_TYPES`, `rotates`) et `MapTransform.can_rotate`.

| Élément (`type`) | Échelle | Rotation Z | Inclinaison X / Y |
|---|---|---|---|
| **Décor du catalogue au sol** (`prefab` : gravats, gros éboulement, mur effondré, débris épars, planches, poutre tombée, lustre tombé, pile de caisses, tonneaux, sacs de sable, table et chaise renversées, chaise pliante, bureau, étagère, fauteuils de cinéma, fauteuil arraché, pupitre, projecteur de cinéma, chariot, épave de voiture, bûches, foyer de pierres, planches calcinées, électrodes, bobine Tesla, flaques) | **oui** | oui (existe) | **oui** |
| **Décor mural** (`prefab` monté « mur » : torche murale, tuyau à vapeur, boîtier électrique, tuyau qui fuit) | **oui** (depuis la face du mur) | non : suit son mur (existe) | non |
| **Décor au plafond** (`prefab` « plafond » : câble suspendu) | **oui** (depuis le plafond) | oui (existe) | non |
| **Prefab de la carte, groupe** (`prefab` « map:… », « parties ») | **oui**, sauf s'il contient un objet de jeu (E2) | oui | oui, sauf objet de jeu |
| **Prefab de la carte, modèle importé** (« modele ») | **oui** | oui | oui |
| Caisse, baril (types historiques du format 1) | non (bloc sur la grille, pas de rotation) : utiliser « Pile de caisses » ou « Tonneaux » | non | non |
| Luminaires, lampe | non dans cette version (Q1) | oui / non (existe) | non |
| Effets (flammes, fumées…) | non : leur **zone** a déjà ses poignées (format 11) | oui au sol et au plafond (existe) | non |
| **Objets de jeu** : atouts, armes murales et couteau, grenades, boîte mystère (et boîte de départ), **Pack-a-Punch**, interrupteur du courant, poste central, levier de piège, téléporteur, arrivée du téléporteur, départ des joueurs, zombie qui sort du sol | **jamais** : taille fixe (lisibilité BO1, zones d'achat et d'interaction, tableaux de prix) | comme aujourd'hui (objets muraux : suivent leur mur) | **jamais** |
| **Ouvertures** : porte payante, débris à dégager, porte du courant, passage, fenêtre à zombies (fenêtre, porte simple ou double : barricades) | **jamais** (seule la `largeur` des portes et passages, existante) | suivent leur mur | **jamais** |
| **Construction** : pièces, murs, murs courbes, piliers, escaliers, pièges électriques, barrière invisible, zones | **jamais** : elles ont leurs propres dimensions et poignées (rectangle, sommets, plafond, hauteur) | comme aujourd'hui (poignée ronde) | **jamais** |

Règle du code : `MapScale.scalable(o)` = `type == "prefab"` et
`MapScale.blockers_of(o)` vide ; `MapScale.tiltable(o)` = scalable, monté
au sol, non porteur d'un autre décor (§ 3.4).

### 1.2 Prefab qui contient un objet non redimensionnable

Aujourd'hui un prefab groupe ne contient que du décor du catalogue posé au
sol (`MapPrefabLib.check_def` : `MapCatalog.floor_prefab`) : il est toujours
redimensionnable. Le travail en cours (sélection multiple, menu clic droit,
création de prefab) peut y mettre des objets de jeu ; la règle est donc
écrite pour un contenu quelconque :

- `MapPrefabLib.unscalable_parts(def)` rend la liste des parties non
  redimensionnables (récursive si un prefab en contient un autre), d'après
  le tableau du § 1.1. Elle est calculée à la lecture de la bibliothèque
  (comme `MapCatalog.set_map_prefabs`) : rien n'est écrit dans `prefab.json`.
- Prefab bloqué :
  - **vues** : pas de poignées d'échelle ; aux coins, des **cadenas gris**
    (#55555C) ; survol d'un cadenas : curseur interdit et bulle « Échelle
    bloquée par : Pack-a-Punch » ;
  - **panneau Propriétés** : champs d'échelle grisés et cadenas, encadré
    d'avertissement : « Ce prefab ne peut pas changer d'échelle : il contient
    un Pack-a-Punch. Les objets de jeu (atouts, armes murales, boîte,
    Pack-a-Punch, portes, fenêtres…) gardent leur taille. » ;
  - **inclinaison** grisée de même (« objet de jeu : reste droit ») ; la
    rotation Z reste permise ;
  - **barre d'état** au moindre essai (raccourci, champ, MCP) : « Échelle
    impossible : « Coin Pack-a-Punch » contient un Pack-a-Punch (objet de jeu
    à taille fixe) » ;
  - **inventaire** : la bulle du prefab ajoute « échelle fixe (Pack-a-Punch) ».
- Nommage : le nom de l'objet dans la langue du jeu ; 2 noms au plus puis
  « et 3 autres » (« contient un Pack-a-Punch, l'atout Juggernog et 2 autres »).
- Si la définition d'un prefab change (travail en cours) et devient bloquée
  alors que des copies posées ont une échelle ≠ 1 : le changement est
  **refusé** (« 3 copies posées sont redimensionnées : remettez-les à ×1 ») ;
  une carte reçue dans ce cas est refusée par le contrôle (§ 5.3).

### 1.3 Sélection multiple

- **Rotation Z d'un groupe** : autour du centre du rectangle englobant les
  pivots (comme une pièce aujourd'hui, `MapTransform.rotated`), pour tout
  élément qui tourne ; un élément qui ne tourne pas est seulement déplacé
  (objet mural : refus s'il quitte son mur, raison affichée).
- **Inclinaison d'un groupe** : seulement si tous les éléments sont
  inclinables ; autour du centre de la boîte englobante 3D ; les positions
  et `z` changent ; refus si un décor bloquant finit en l'air (§ 3.4).
- **Échelle d'un groupe** : seulement si **tous** les éléments sont
  redimensionnables (Q2). Positions et échelles multipliées depuis le centre
  (ou le coin opposé). Sinon : cadenas gris et message qui nomme le premier
  élément bloquant (« Échelle impossible : la sélection contient l'atout
  Juggernog »).

## 2. Échelle

### 2.1 Valeurs

- `echelle` = [sx, sy, sz] dans le **repère de l'objet** : X = largeur
  (`fp[0]`), Y = profondeur (`fp[1]`), Z = hauteur (`h`), avant rotation.
- Bornes par axe **0,25 à 4** ; dimension finale (fp × 0,5 m × s, h × s)
  de **0,05 à 30 m** (`MapPrefabLib.MAX_SIZE`) ; emprise au sol finale de
  **40 cases (20 m)** au plus par côté (`MapPrefabLib.MAX_FP`).
- **Uniforme seulement** quand l'objet a une partie, une copie ou un pavé
  tourné en biais dans son repère (angle non multiple de 90° : parties d'un
  groupe, `copies`, `boxes.yaw`) : une échelle par axe le déformerait. Le
  cadenas est alors forcé (bulle : « parties tournées en biais : échelle
  uniforme seulement »), les poignées de face sont masquées. Les décors du
  catalogue n'ont pas ce cas aujourd'hui.
- Modèle importé : échelle finale = `modele.echelle` (réglage du prefab,
  dialogue ⚙, renommé « Échelle du modèle » pour ne pas confondre) ×
  `echelle` de l'objet posé.

### 2.2 Point fixe selon le montage

| Montage | X (largeur) | Y (profondeur) | Z (hauteur) |
|---|---|---|---|
| Au sol | côté opposé fixe ; Alt : centre fixe | idem | **base fixe** (l'objet reste sur son support, Alt sans effet) |
| Mural | le long du mur, comme X au sol | **face du mur fixe** (l'objet ne sort pas du mur) | côté opposé fixe ; Alt : centre (la `hauteur` est au centre) |
| Plafond | comme au sol | comme au sol | **attache au plafond fixe** (`descente` inchangée) |

### 2.3 Effets sur les règles et le jeu

- **Emprise** : rectangle orienté (fp × s, tourné de `rot`) pour toutes les
  règles de pose (`MapRules`, chevauchements du § 10 de MAP_OBJECTS.md,
  « devant une porte », départ à 1 m) et pour les cases de `MapRaster`.
- **Hauteur** : `h × sz` ; `support × sz` (une lampe posée sur un bureau
  agrandi monte avec lui) ; borne sous le plafond réel comme `z` aujourd'hui
  (`MapVertical.pose_bounds` : « trop haut pour le plafond (3,20 m) »).
- **Décor porteur** : un décor sur lequel repose un autre ne change pas
  d'échelle seul (« un décor est posé dessus : sélectionnez-les ensemble »),
  comme pour le déplacement (EDITOR_VIEWS § 6.1).
- **Collisions** : chaque pavé `{center, size, yaw}` devient
  `center × s`, `size × s` (axes échangés si `yaw` vaut 90° ou 270°) ; il
  reste un `CollisionBox` (jamais une collision de modèle).
- **Pas de nouvelle limite de nombre** : l'échelle n'ajoute aucun objet
  (`MAX_OBJECTS` 2048 inchangé) ni triangle.

### 2.4 Poignées d'échelle

| Vue | Coins (carrés jaunes #FFD94D) | Faces | Hauteur |
|---|---|---|---|
| **Dessus** | 4, sur le rectangle orienté : **uniforme** (X, Y et Z ensemble) | 4 carrés aux couleurs de l'axe : X rouge (est, ouest), Y vert (nord, sud) | — (puce de cote « H 2,25 m » en lecture) |
| **Avant / Arrière** | 4 : uniforme | gauche / droite : X (rouge) | **losange bleu** en haut : Z |
| **Droite / Gauche** | 4 : uniforme | gauche / droite : Y (vert) | losange bleu : Z |
| **3D** | aucune (anneaux seulement, § 3) | — | — |

- Les poignées de face n'existent que si l'axe local de l'objet est parallèle
  à l'écran (en élévation : `rot` multiple de 90° et pas d'inclinaison ; en
  Dessus : pas d'inclinaison). Sinon, seuls les coins (uniforme) sur le
  rectangle englobant à l'écran ; l'échelle par axe se règle au panneau.
- **Alt** : depuis le centre (§ 2.2). **Maj** : inverse l'aimantation (E4).
  Taper une valeur pendant le geste (Tab ou directement un chiffre) : le
  facteur (« 1.5 » ou « 1,5 ») ; « 3m » : la dimension en mètres.
- Pendant un geste d'échelle, les flèches de déplacement et l'anneau sont
  estompés (25 %) ; l'ancien contour reste en pointillés ; le point fixe est
  marqué d'une petite croix.
- **Cotes** (style EDITOR_VIEWS § 6.3) : dimension de chaque axe touché sur
  un trait de cote (« 3,75 m ») ; près du curseur, pastille or du facteur
  (« ×1,50 ») ; aimant actif en bleu (« ×1,00 », « = Bureau ») ; barre d'état
  « Échelle uniforme : ×1,00 → ×1,50 · 2,50 × 2,00 × 1,50 → 3,75 × 3,00 ×
  2,25 m ».
- Curseurs : redimensionnement orienté sur les poignées, interdit (⦸) sur
  un cadenas gris.

### 2.5 Panneau Propriétés

Après la ligne Position (X, Y, Z) existante, deux sections :

- **Échelle** :
  - ligne **Uniforme** : champ « ×1,50 » et **cadenas** (fermé : les trois
    axes ensemble ; ouvert : par axe) ;
  - ligne **X / Y / Z** : trois champs (lettres aux couleurs des axes),
    0,25 à 4 ; cadenas fermé : modifier l'un modifie les trois en
    proportion ;
  - note : « 3,75 × 3,00 × 2,25 m (d'origine 2,50 × 2,00 × 1,50) » ;
  - bouton **↺ ×1** (remet [1, 1, 1], retire la clé).
  - Le cadenas est une préférence d'interface (`_editeur.cfg`, fermé par
    défaut), pas une donnée de la carte.
- **Rotation** :
  - trois champs **X / Y / Z** en degrés ; X et Y de −180 à 180, Z de 0 à
    359 (l'ancien champ « angle » devient Z) ;
  - X et Y grisés pour ce qui ne s'incline pas, avec la raison en bulle ;
  - case **Rester posé** (cochée) ; bouton **↺ Remettre droit** (X = Y = 0).
- Un champ validé = une annulation ; valeur refusée remise, raison affichée
  (barre d'état, comme aujourd'hui).

## 3. Rotation

### 3.1 Angles et sens

- Orientation = **Rz(`rot`) · Ry(`incl`[1]) · Rx(`incl`[0])** (lacet puis
  inclinaisons, dans le repère de la carte : X est, Y sud, Z haut). Sans
  inclinaison, rien ne change par rapport à aujourd'hui.
- **Sens positif** pour les trois axes : **horaire à l'écran dans la vue qui
  regarde l'axe de bout** : Dessus pour Z (le `rot` d'aujourd'hui), Avant
  pour Y, Droite pour X.
- Précision : `rot` au degré (entier, inchangé) ; `incl` au dixième de
  degré. Un anneau tourne autour d'un **axe du monde** ; le résultat est
  redécomposé en (rot, incl) puis arrondi (écart < 0,5°, invisible).

### 3.2 Anneaux (gizmo)

- **Dessus : anneau Z** (bleu) autour du décor choisi, rayon = demi-diagonale
  + 14 px (36 à 140 px), avec une **prise ronde** au nord. Il remplace la
  poignée ronde pour le décor, les luminaires et les effets. Les éléments de
  construction (pièces, murs, piliers, escaliers, pièges, barrières) gardent
  leur poignée ronde (leur rotation emporte leur contenu).
- **Avant : anneau Y** (vert) ; **Droite : anneau X** (rouge) ; Arrière et
  Gauche : mêmes anneaux, sens inversé à l'écran (le signe reste celui du
  § 3.1). Montrés seulement si l'élément s'incline.
- **3D : les trois anneaux**, centrés sur le centre de la boîte de l'objet,
  taille fixe à l'écran (rayon 90 px à 100 % d'interface) ; X et Y seulement
  si l'élément s'incline. La 3D devient éditable pour ce seul geste
  (sélection au clic déjà là, D6).
- **Geste** : glisser le long d'un anneau ; bande de prise de 8 px ;
  l'anneau survolé s'épaissit (3 px, couleur éclaircie), les autres
  s'estompent pendant le geste.
- **Affichage pendant le geste** :
  - secteur balayé rempli de la couleur de l'axe (25 %) ;
  - graduations tous les 15° (plus longues tous les 45°) ;
  - pastille or près du curseur : « +30° » précédée de la lettre de l'axe ;
  - position d'avant en pointillés ;
  - barre d'état : « Rotation Y : 0° → +30° · cran 15° · Maj : libre · tapez
    une valeur ».
- **Crans de 15°** ; **Maj** (ou **Alt**, comportement actuel de la poignée
  ronde) : libre au degré près. Taper un nombre pendant le geste puis
  Entrée : angle exact ; Échap : annule. **R** garde son effet : +90° autour
  de Z (Maj+R : −90°).

### 3.3 Pivot

- **Rotation Z** : la `position` de l'objet (comme aujourd'hui).
- **Inclinaison** : le centre de la boîte de l'objet ; puis, si **Rester
  posé** est coché, l'objet est remonté ou descendu pour que son **point le
  plus bas** revienne sur son support (sol ou dessus d'un décor) : `z` reste
  la hauteur de ce point.
- Groupe : § 1.3.

### 3.4 Règles de l'inclinaison

- Décor bloquant incliné : collisions inclinées avec lui (`CollisionBox`
  orienté). Il doit rester posé (règle « décor en l'air » d'aujourd'hui,
  appliquée à son point le plus bas) et ne traverse pas le sol (« traverse
  le sol »).
- Un décor incliné **ne porte rien** : son `support` est ignoré, on ne pose
  rien dessus ; un décor qui en porte un autre ne s'incline pas (« un décor
  est posé dessus »).
- Hauteur, emprise et cases bloquées : celles de la **boîte orientée**
  (projection au sol pour l'emprise et `MapRaster`, point le plus haut pour
  le plafond).

## 4. Dans chaque vue (récapitulatif)

| Vue | Déplacer (existe) | Échelle | Rotation |
|---|---|---|---|
| Dessus | flèches X, Y | coins (uniforme), faces X / Y | anneau Z |
| Avant / Arrière | flèches X, Z | coins, faces X, losange Z | anneau Y |
| Droite / Gauche | flèches Y, Z | coins, faces Y, losange Z | anneau X |
| 3D | — | — | anneaux X, Y, Z |

## 5. Format 14

### 5.1 Clés (objets.json, type `prefab` seulement)

| Clé | Sens | Bornes | Par défaut (jamais écrite) |
|---|---|---|---|
| `echelle` | [sx, sy, sz] facteurs dans le repère de l'objet | chacun 0,25 à 4, pas de 0,01 | [1, 1, 1] |
| `incl` | [x, y] inclinaisons en degrés (§ 3.1) | chacune −180 à 180, pas de 0,1 | [0, 0] |

```json
{"id":"d12","type":"prefab","prefab":"caisses","etage":0,"position":[14.63,8.5],"echelle":[1.5,1.5,1.5]}
{"id":"d13","type":"prefab","prefab":"poutre","etage":0,"position":[12.5,14.5],"incl":[0,30]}
```

- Fichiers touchés : `EditorMap.FORMAT` = 14 et commentaire de version ;
  `_migrate` sans conversion ; `_normalize` / `MapScale.tidy` (valeur
  illisible ou par défaut retirée, `incl` retirée d'un décor qui ne
  s'incline pas, échelle d'un prefab bloqué retirée avec un message de
  chargement) ; `MapCatalog.allowed_kinds()` (spec `{"t": "dims", "min": 3,
  "max": 3, "lo": 0.25, "hi": 4}` et `{"t": "dims", "min": 2, "max": 2, "lo":
  -180, "hi": 180}`).
- Compatibilité : une carte ≤ 13 se lit telle quelle et s'affiche à
  l'identique ; la description en jeu (`layout`) d'une carte sans ces clés
  est **octet pour octet la même** qu'avant (test). Une carte au format 14
  est refusée par un jeu au format 13 (règle `format ≤ FORMAT`). En
  collaboration, des éditeurs de versions différentes sont déjà refusés à la
  connexion (`MapCollab`, « version de l'éditeur différente »).

### 5.2 Export en jeu (`MapLayoutExport`, `MeshMapBuilder`, `CollisionBox`)

- **Props** : clé facultative `basis` (9 nombres : rotation × échelle) quand
  l'objet est incliné ou d'échelle non uniforme ; sinon `yaw` et `scale`
  (nombre) d'aujourd'hui, avec `scale` = facteur uniforme × échelle du
  modèle. `MeshMapBuilder._xf` lit `basis` en priorité.
- **Prefab groupe** : chaque partie reçoit sa position × (sx, sy), puis
  l'orientation du prefab ; son échelle est (sx, sy, sz) exprimée dans son
  propre repère (parties à 90° près, § 2.1).
- **Blockers** : clé facultative `basis` (rotation orthonormée) ; la taille
  porte l'échelle. `CollisionBox.make` accepte une `Basis` complète
  (`BoxShape3D` orienté) ; `yaw` seul reste lu.
- **Trajets des zombies** : cases pleines = projection au sol de la boîte
  orientée, pour un décor qui bloque (comme aujourd'hui pour son emprise).
- **Aperçu 3D** (`MapPreviewWorld`, même description) et surbrillance : la
  boîte orientée.

### 5.3 Contrôle des cartes reçues (`CustomMapGuard._check_object`)

- Bornes du § 5.1 (texte, NaN, 0, 5, 200° : refusés) ;
  `echelle` et `incl` seulement sur `type` « prefab » ; `incl` seulement sur
  un décor au sol ; dimensions finales ≤ 30 m et emprise ≤ 20 m ;
  `echelle` ≠ [1, 1, 1] sur un prefab de la carte bloqué (§ 1.2) : refusée
  (« échelle d'un prefab qui contient un objet de jeu ») ; uniforme exigée
  pour un objet à parties en biais.
- Le validateur (onglet Vérification) signale les mêmes cas en erreur pour
  une carte ouverte malgré tout (fichier modifié à la main).

## 6. Collaboration et MCP

- **Collaboration** : aucune nouvelle op ; un geste = un `put` de l'élément
  (`echelle`, `incl`, `rot`, `position`, `z`). La présence `live` (geste en
  cours) porte l'élément transitoire ; les autres voient l'objet changer en
  direct, en contour pulsé comme aujourd'hui.
- **MCP** (`map_agent_link.gd`, `tools/mcp/map_editor_mcp.py`) :
  - `editor_apply` : `put` avec `echelle` / `incl` ; un refus rend la raison
    qui nomme l'objet (« échelle impossible : contient un Pack-a-Punch ») ;
  - `editor_get_element` ajoute `dimensions` [l, p, h] finales,
    `echelle_possible`, `inclinaison_possible` et `raison` ;
  - `editor_catalog` marque `echelle: false` sur les objets non
    redimensionnables ;
  - instructions du serveur : clés, bornes, sens des angles, règle des
    prefabs ;
  - `editor_screenshot` dessine les objets mis à l'échelle et inclinés (vues
    et 3D).

## 7. Plan d'implémentation

Chaque étape se livre seule, testée, sans régression. Elle commence **après
la fusion** du travail en cours sur la sélection multiple, le menu clic
droit et la création de prefab (mêmes fichiers).

| Étape | Contenu | Fichiers | Tests |
|---|---|---|---|
| **1. Modèle et règles** | `MapScale` (nouveau, logique pure) : `scalable`, `tiltable`, raisons nommées, `dims`, boîte orientée, emprise, pavés transformés, `unscalable_parts` ; format 14 (lecture, tidy, schéma, contrôle) ; règles de pose et `MapVertical` avec la boîte orientée | nouveau `scripts/editor/map_scale.gd` ; `map_catalog.gd`, `editor_map.gd`, `map_rules.gd`, `map_vertical.gd`, `map_raster.gd`, `map_validator.gd`, `map_prefab_lib.gd`, `custom_map_guard.gd` | `tests/test_map_scale.gd` : tableau du § 1.1 type par type, prefab avec Pack-a-Punch bloqué et message, bornes, aller-retour format 14, carte 13 inchangée, carte reçue hors bornes refusée, boîte orientée (rot 37°, incl 30°) |
| **2. Jeu** | Export `basis`, `CollisionBox` orienté, cases des trajets, aperçu 3D | `map_layout_export.gd`, `mesh_map_builder.gd`, `collision_box.gd`, `map_preview_world.gd` | unitaires : layout identique sans les clés, pavés à l'échelle ; scénario de partie `map_decor_scale` : pile de caisses ×1,5 et poutre inclinée de 30° (rayon arrêté sur la pente, joueur arrêté, zombie qui contourne) |
| **3. Panneau** | Sections Échelle et Rotation, cadenas, ↺, Rester posé, messages | `map_panels.gd` | scénario `map_scale_panel` : champs, une annulation par champ, prefab bloqué grisé |
| **4. Poignées d'échelle** | Dessus et élévations, aimantation, Alt, cotes, valeur tapée, cadenas gris | `map_canvas.gd`, `views/map_elevation_tools.gd`, `map_editor.gd` | unitaires de géométrie des poignées ; scénario `map_scale_handles` (coin ×1,5, face X, losange Z, prefab bloqué) |
| **5. Anneaux en vue plane** | Anneau Z (Dessus, à la place de la poignée ronde du décor), Y / X (élévations), crans, saisie, groupe | `map_canvas.gd`, `views/map_elevation_tools.gd`, `map_transform.gd` | unitaires : sens des 3 axes, décomposition, Rester posé ; scénario `map_rotate_rings` |
| **6. Gizmo 3D** | Prise rayon / anneau, geste, rafraîchissement d'un seul objet dans l'aperçu | `views/map_view_3d.gd`, `map_preview_world.gd`, `map_preview_camera.gd` | scénario @rendu `map_rotate_3d` ; mesure : < 2 ms par mouvement de souris sur la carte de 2000 objets |
| **7. MCP, collaboration, docs** | Clés MCP, instructions, captures ; docs `MAP_AUTHORING.md`, `MAP_OBJECTS.md`, aide « ? », notes de version | `map_agent_link.gd`, `tools/mcp/*`, docs | `test_map_agent_link`, `tools/mcp/test_map_editor_mcp.py`, `mp_editorplay` (échelle vue chez l'invité) |

Les captures de scénario servent pendant le développement de chaque étape
puis sont retirées ; une instance du jeu à la fois, hors écran.

**Risques** :
- **R1 Conflit** avec la sélection multiple (`map_canvas.gd`,
  `map_editor.gd`, `map_panels.gd`). Parade : commencer après sa fusion ;
  la logique (étapes 1-2) ne touche pas ces fichiers.
- **R2 Sens des angles et décomposition** (repère X est, Y sud, Z haut).
  Parade : une seule fonction `MapScale.basis_of(o)` partagée par l'éditeur,
  l'export et l'aperçu ; tests de sens vue par vue.
- **R3 Zombies bloqués par un décor incliné** (pente qu'on croit
  franchissable). Parade : cases pleines sur toute la projection
  (prudent) ; scénario de partie dédié.
- **R4 Échelle par axe des modèles à parties en biais** (cisaillement).
  Parade : uniforme imposée (§ 2.1).
- **R5 Gizmo 3D** : premier geste d'édition dans la 3D (prise, coût de
  rafraîchissement). Parade : seul l'objet modifié est reconstruit pendant
  le geste, la carte entière au relâché.

## 8. Questions tranchées (décisions du 03/10/2026)

Les trois questions ouvertes ont été tranchées par l'utilisateur
(« c'est parfait », recommandations retenues) :

1. **Q1. Luminaires** : **pas d'échelle dans cette version** (la place de la
   lumière dépend du modèle) ; à ajouter ensuite si besoin. Un luminaire reste
   à sa taille, comme au § 1.1.
2. **Q2. Sélection mixte** (décor + objet de jeu) : l'échelle du groupe est
   **bloquée**, même règle que pour un prefab : cadenas gris et message qui
   nomme le premier élément bloquant (« Échelle impossible : la sélection
   contient l'atout Juggernog », `MapScale.group_refusal`).
3. **Q3. Axes des anneaux** : **axes du monde seulement** ; le repère local
   (bascule « Local » de Fusion 360) pourra venir plus tard par une touche.

Hors périmètre : miroir (échelle négative), échelle des objets de jeu, des
ouvertures et de la construction, rotation d'un décor mural dans le plan du
mur, pose directe en élévation (D13).

## 9. Réalisation (03/10/2026) : écarts et précisions

Réalisé en 7 étapes (un commit chacune). Fichiers : `MapScale` (logique),
`MapGizmo` (géométrie des poignées et des anneaux), `MapGizmoTop` (vue
Dessus), `MapGizmoElev` (élévations), `MapGizmo3D` (vue 3D),
`MapPanelsScale` (panneau). Écarts à valider :

- **Groupes** : la rotation Z d'un groupe reste celle de la poignée ronde
  (MapGroup) ; l'échelle et l'inclinaison d'un groupe par poignées ne sont
  pas faites (la règle Q2 existe : `MapScale.group_refusal`).
- **Prefab qui contient un objet de jeu** : aujourd'hui `prefab.json` ne
  peut pas en contenir (`MapPrefabLib.check_def` : décor du catalogue au sol
  seulement). Toute la chaîne (blocage, cadenas, encadré, messages, MCP,
  contrôle) est en place et testée avec une définition injectée ; le refus
  d'une définition modifiée qui deviendrait bloquée alors que des copies sont
  redimensionnées (§ 1.2) viendra avec ce contenu.
- **Pavés en biais** (pile de caisses : pavés du modèle légèrement tournés) :
  échelle par axe permise ; un tel pavé devient sa boîte englobante droite
  mise à l'échelle (un peu plus grande, jamais cisaillée) au lieu d'imposer
  l'échelle uniforme.
- **Hauteur d'origine sous 5 cm** (flaques) : la borne de 5 cm ne vaut que
  pour un axe réduit (× < 1), celle de 30 m pour un axe agrandi.
- **Panneau** : libellés de 76 px (le panneau de l'éditeur est plus étroit
  que celui de la maquette) ; la note « Z : hauteur… » du décor passe en
  bulle du champ Z ; « Collision » : « pavés du décor », « pavés à
  l'échelle » ou « pavés inclinés avec lui / elle ».
- **Zombies** : l'emprise d'un décor incliné qui bloque est retirée du
  navmesh (obstruction projetée) ; un zombie peut frôler son bord (rayon de
  0,4 m) mais ne monte jamais sur la pente.
- **Vue 3D** : pendant le geste, le surlignage reste celui d'avant (il suit
  au relâché, avec la reconstruction) ; mesure : 0,9 ms par mouvement en
  moyenne sur 2000 objets (pire ≈ 2,5 ms quand l'angle change de cran).
- **Aimant « taille d'un décor voisin »** : sur les faces et le losange (un
  axe), pas sur les coins.
