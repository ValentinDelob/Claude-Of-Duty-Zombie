# Concevoir une carte : l'éditeur de cartes

But : concevoir une carte **simplement, sans bug et amusante**, puis la jouer
aussitôt. L'**éditeur de cartes** est une scène du jeu (menu principal >
ÉDITEUR DE CARTES) : on y dessine les pièces vues de dessus, on pose portes,
fenêtres, atouts, armes, boîte… depuis un inventaire façon Minecraft, un
validateur vérifie la carte avec des règles « façon BO1 », et le bouton
**TESTER** lance une partie solo dessus. La carte est enregistrée en cinq
fichiers JSON lisibles et écrivables à la main (un outil peut aussi les
écrire), exportables en archive `.zip`.

Preuve : la carte d'essai **DRAFT ARENA** (`assets/maps/draft_arena/`, hors
menus, `--map=draft_arena`) est faite dans ce format et se joue (scénarios
`draft_arena` et `map_editor_play`).

![L'éditeur : trois pièces, portes, fenêtres, objets, onglet Vérification](map_authoring/editeur.png)
![L'inventaire (touche E), catégorie Ouvertures](map_authoring/inventaire.png)
![DRAFT ARENA dans l'éditeur (rez-de-chaussée)](map_authoring/draft_arena_editeur.png)
![DRAFT ARENA, étage : passerelle au-dessus de l'entrepôt à double hauteur](map_authoring/draft_arena_etage1.png)
![En jeu : la passerelle au-dessus de l'entrepôt](map_authoring/jeu_passerelle.png)

---

## 1. Lancer l'éditeur

- Depuis le jeu : menu principal > **ÉDITEUR DE CARTES** (aussi dans le `.exe`).
- Directement : `godot --path . res://scenes/editor/map_editor.tscn`, ou
  double-clic sur `tools/map_editor.bat` (Godot dans le PATH, ou `set GODOT=…`).
- Vérifier une carte sans fenêtre (outil, intégration) :
  `godot --headless --path . res://scenes/editor/map_editor.tscn -- --check=<dossier ou archive.zip>`
  affiche le rapport du validateur ; code de sortie 0 si la carte est jouable.

Au démarrage, l'éditeur rouvre la dernière carte ; s'il reste une sauvegarde
automatique non enregistrée, il propose de la reprendre.

## 2. L'écran

| Zone | Rôle |
|---|---|
| Barre du haut | **Fichier** (Nouvelle, Ouvrir, Enregistrer, Enregistrer sous, exporter / importer l'archive .zip, cartes récentes, retour au menu), **Édition** (annuler, rétablir, copier, coller, pivoter, supprimer, inventaire, recadrer), étage courant (◄ ►), **▶ TESTER**, état de la vérification. |
| Vue de dessus | Grille de 1 m (traits forts tous les 5 m), règles graduées en mètres en haut et à gauche, coordonnées du curseur en bas à droite. |
| Barre rapide | 9 cases au bas de la vue (touches 1 à 9, molette) : l'objet tenu. |
| Inventaire | Touche **E** ou **Tab** : toutes les catégories ; cliquer un objet le met dans la case choisie, ou le glisser sur une case. |
| Panneaux | **Propriétés** (élément choisi, sinon la carte), **Pièces**, **Zones**, **Étages**, **Vérification**. |
| Barre d'état | Aide de l'outil, raison d'un refus, résultat des actions. |

### Commandes

| Action | Commande |
|---|---|
| Poser / choisir | clic gauche |
| Annuler le tracé, désélectionner | clic droit, Échap |
| Zoom | Ctrl + molette (ou + / -) |
| Déplacer la vue | clic milieu + glisser, ou Espace + glisser |
| Aimantation | 1 m ; 0,5 m en maintenant Maj |
| Case de la barre rapide | 1 à 9, molette |
| Inventaire | E ou Tab |
| Pivoter de 90° | R (une pièce pivote avec son contenu) |
| Supprimer | Suppr (une pièce emporte ses objets et ses ouvertures) |
| Copier / coller sous le curseur | Ctrl+C / Ctrl+V |
| Annuler / rétablir (illimité) | Ctrl+Z / Ctrl+Y (ou Ctrl+Maj+Z) |
| Enregistrer | Ctrl+S |
| Étage du dessous / du dessus | Page préc. / Page suiv. |
| Recadrer sur la carte | Origine |
| Fermer un polygone | double-clic, clic sur le premier point, ou Entrée ; Retour arrière retire le dernier point |

Outil **Sélection** (case 1) : clic sur un élément pour le choisir, glisser
pour le déplacer (il reste accroché à son mur), **poignées** jaunes pour
redimensionner (coins et milieux des côtés d'une pièce rectangle, sommets d'un
polygone, coins d'un pilier, d'un escalier ou d'un piège, bouts d'un mur). Un
élément devenu invalide (une fenêtre restée sur l'ancien mur d'une pièce
agrandie…) est entouré de rouge avec la raison dans la barre d'état.

## 3. Ce que l'on pose (inventaire)

Les catégories et leurs objets viennent des **bases de données du jeu**
(`MapCatalog` lit `PerkDB`, `WeaponDB`, `KnifeDB`, `MysteryBox.COST`,
`PackAPunch.COST`, `ElectricTrap.COST`…) : un atout ou une arme murale ajouté
au jeu apparaît tout seul dans l'inventaire, avec son prix. Icônes dessinées
par code (`MapIcons`).

| Catégorie | Objets | Pose |
|---|---|---|
| Construction | Sélection, Gomme, Pièce rectangle, Pièce polygone, Mur, Pilier / obstacle, Escalier | glisser (rectangle, mur, pilier, escalier), clics successifs (polygone) |
| Ouvertures | Porte payante, Débris à dégager, Porte ouverte par le courant, Passage libre, Fenêtre à zombies | sur un mur (voir les règles) |
| Atouts | un distributeur par atout du jeu | contre un mur |
| Armes murales | chaque arme à prix mural, couteau de chasse, grenades | contre un mur |
| Boîte mystère | emplacement, emplacement de départ | contre un mur |
| Machines | Pack-a-Punch, interrupteur du courant, téléporteur, arrivée du téléporteur, poste central | contre un mur, ou au sol (téléporteur, arrivée) |
| Pièges | zone de piège électrique, levier | zone : glisser au sol ; levier : contre un mur, à moins de 10 m |
| Joueurs et apparitions | départ des joueurs, zombie qui sort du sol | au sol |
| Décor et lumières | lampe, caisse, baril | au sol |

### Règles imposées à la pose

L'aperçu est **vert** si l'élément peut être posé, **rouge** sinon, avec la
raison à côté du curseur (`MapRules`) :

- **Pièce** : contour simple (les côtés ne se croisent pas), 1,5 m de côté au
  moins, x et y positifs ; deux pièces peuvent **se toucher, jamais se
  recouvrir**. Ses murs sont générés sur son contour ; le bord commun de deux
  pièces collées devient **un seul mur mitoyen**. Par défaut, chaque pièce a
  sa propre zone.
- **Porte payante, débris, porte ouverte par le courant, passage libre** :
  seulement sur le **bord commun de deux pièces collées** du même étage (une
  porte ne donne que sur une autre pièce) ; elle relie exactement ces deux
  pièces. Mur droit (horizontal ou vertical), 0,5 m de mur plein à chaque
  bout et entre deux ouvertures. Prix réglable ; par défaut ceux de BO1 : la
  première 750, la deuxième 1000, les suivantes 1250. Largeur réglable (2 m par
  défaut ; BO1 : 1,5 à 3 m). Le passage libre n'a pas de porte : les deux
  zones sont « ouvertes l'une sur l'autre » (ou n'en font qu'une).
- **Fenêtre à zombies** (barricade de 6 planches) : 1 m, sur un **mur
  extérieur** d'une pièce (pas un mur commun, pas le bord d'une mezzanine), avec
  2,5 × 3 m de vide dehors : le jeu y construit la cour où les zombies
  apparaissent, derrière la fenêtre.
- **Objets muraux** (atouts, armes, grenades, boîte, Pack-a-Punch, courant,
  poste central, levier) : dans une pièce, accrochés au mur le plus proche,
  **face vers l'intérieur** ; il faut du mur plein derrière (pas une ouverture)
  et la place devant (boîte : 2 × 1 m ; atout, Pack-a-Punch : 1,5 × 1 m ;
  arme : 1 × 0,5 m), sans chevaucher un autre objet.
- **Objets au sol, pilier, escalier, zone de piège** : à l'intérieur d'une
  pièce, sans toucher ses murs, sans chevauchement (les lampes, au plafond,
  peuvent surplomber un objet). L'escalier monte à l'étage du dessus : il faut
  un étage au-dessus.

## 4. Pièces, zones, étages

- **Pièce** (onglet Propriétés) : nom, zone, hauteur de plafond (sinon celle
  de l'étage), **double hauteur** (ouverte sur l'étage du dessus : à l'étage,
  son contour reste un mur et son intérieur est un vide ; ses piliers montent
  jusqu'en haut). Une pièce posée à l'étage au-dessus d'une double hauteur est
  une **mezzanine** : ses bords au-dessus du vide ont un garde-corps.
- **Zone** (onglet Zones) : un groupe de pièces qui s'ouvre d'un coup (ses
  fenêtres s'activent ensemble, comme les zones de BO1). Par défaut une zone
  par pièce. Renommer en français et en anglais (noms affichés en jeu selon la
  langue), matériaux du sol et des murs, **fusionner** (les pièces d'une zone
  rejoignent une autre), **séparer** (une zone par pièce), **zone de départ**
  (★, ouverte au début). Les pièces d'une même zone doivent être reliées par
  un passage libre.
- **Étage** (onglet Étages) : hauteur du sol, hauteur sous plafond ; ajouter un
  étage au-dessus, supprimer le dernier s'il est vide ; l'étage du dessous
  s'affiche en transparence (réglable), ses escaliers aussi. Entre deux sols :
  3,1 m au moins (2,8 m sous plafond + dalle de 0,3 m). Un escalier dessiné
  sur l'étage du bas **monte dans le sens du glisser** (du pied vers le haut) ;
  le vide au-dessus des marches est automatique ; son haut doit arriver sur le
  plancher d'une pièce de l'étage du dessus.

## 5. Vérification (onglet Vérification)

Le validateur (`MapValidator`, repris de l'ancien outil de cartes dessinées)
tourne sur une **grille de 0,5 m** tirée de la carte (`MapRaster`, voir §7) :
chaque message est en français et en anglais, avec sa position en mètres ;
**cliquer un problème centre la vue dessus** et entoure ses cases. TESTER
refuse une carte qui a des erreurs.

Erreurs (la carte est refusée) :
- sol au bord du vide sans mur, pièces qui se chevauchent ;
- zone coupée en morceaux sans passage (ses pièces ne se touchent pas) ;
- zone ou passage **inaccessible depuis le départ**, toutes portes ouvertes ;
- porte hors d'un mur commun, entre deux pièces de la même zone, trop étroite ;
- fenêtre qui ne donne pas dehors, sans place pour la cour des zombies ;
- **zone sans fenêtre** (sauf l'arrivée du téléporteur) ;
- départ hors de la zone de départ, collé à un mur, ou à moins de 7 m de toutes
  les fenêtres de la zone de départ (le jeu n'y ferait apparaître aucun zombie) ;
- objet mural qui ne touche pas de mur, sans la place devant, sans mur derrière ;
- aucune boîte, deux « boîte (départ) », deux interrupteurs, deux distributeurs
  du même atout, téléporteur sans arrivée, levier sans piège à moins de 10 m,
  piège sans levier ;
- passage de 0,5 m (trop étroit pour les zombies et les joueurs) ;
- escalier sans palier, sens ambigu, trop étroit (1,5 m), trop raide (40°),
  recouvert par l'étage du dessus ; vide d'étage ouvert sur le vide ;
- étages trop rapprochés, plafond trop bas.

Avertissements et indicateurs d'amusement (BO1, jamais bloquants) : boucles
entre zones et coût pour les ouvrir, blocs autour desquels on tourne
(« training », 25 à 40 m de tour), impasses (le départ doit avoir 2 sorties),
passages obligés, courbe d'ouverture (la porte la moins chère d'abord ;
première porte à 750-1000), emplacements de boîte (3 au moins, dans plusieurs
zones), atouts et coût pour les atteindre, coin TITAN BREW (rôle du
Juggernog : jamais dans la salle de départ), arme bon marché et LAZARUS au
départ, distance à pied au plus loin d'une fenêtre (25-30 m au plus).

## 6. Enregistrer, reprendre, partager

- **Enregistrer** (Ctrl+S) : dans le dossier des cartes du joueur,
  `user://maps/<id>/` (sous Windows :
  `%APPDATA%\Godot\app_userdata\Call of Claude Zombie\maps\<id>\`), aussi
  depuis le `.exe`. `<id>` est tiré du nom de la carte ; **Enregistrer sous**
  choisit le dossier. Un exemple livré (DRAFT ARENA) s'ouvre en lecture seule :
  Enregistrer en fait une copie.
- **Sauvegarde automatique** toutes les 60 s et à la fermeture si la carte a
  changé (`user://maps/_autosave/`) ; au démarrage suivant, l'éditeur propose
  de reprendre le travail non enregistré. **Cartes récentes** : menu Fichier
  (`user://maps/_editeur.cfg`).
- **Archive .zip** : Fichier > Exporter / Importer ; l'archive contient les cinq
  JSON à la racine (ZIPPacker / ZIPReader). Une archive importée s'enregistre
  comme une nouvelle carte.
- **Jouer** : ▶ **TESTER** vérifie, enregistre et lance une partie solo sur la
  carte (`perso:<id>`) ; la fin de la partie ramène dans l'éditeur, sur la même
  carte. Les cartes jouables de `user://maps` apparaissent aussi dans l'écran
  **SOLO**, sous « CARTES PERSO », et dans le **salon multijoueur** de l'hôte
  (ligne CARTE, « (perso) ») : voir « Cartes perso en multijoueur » ci-dessous.
- **Contrôle de légitimité** : une carte perso qui vient d'ailleurs (archive
  importée, carte reçue d'un hôte, carte locale ouverte pour jouer) passe par
  `CustomMapGuard` avant d'être ouverte (voir ci-dessous) ; une carte refusée
  n'est jamais chargée et la raison est affichée (FR/EN).

### Cartes perso en multijoueur

L'hôte choisit une carte perso dans le salon : elle est envoyée
automatiquement à chaque invité (y compris ceux qui arrivent après), qui la
vérifie puis la garde dans un cache. Le salon montre à tous le nom de la
carte, son aperçu (dessiné sur place depuis la carte vérifiée), sa taille et
l'état de chaque joueur (« télécharge 45 % », « carte prête », « carte
refusée ») ; **DÉMARRER** reste grisé, avec la raison, tant que tous les
joueurs ne l'ont pas. Un invité qui refuse la carte reste dans le salon avec
un message clair ; un joueur qui part pendant le transfert ne bloque pas les
autres. Protocole réseau : `docs/ARCHITECTURE.md`, « Cartes perso en
multijoueur ».

![Salon : l'hôte a choisi une carte perso, l'invité la télécharge](map_authoring/salon_carte_perso.jpg)

- **Paquet canonique** : seulement les cinq JSON, tels que l'éditeur les
  réécrit (`EditorMap.file_texts`), dans un JSON trié
  `{"format": 1, "fichiers": {"carte.json": "…", …}}` en UTF-8. Son
  **SHA-256** identifie la carte : même carte = même empreinte sur toutes les
  machines. Tout le monde, hôte compris, joue la carte depuis son cache
  `user://maps_cache/<sha256>/` (identifiant de jeu `partage:<sha256>`) : les
  géométries sont identiques partout.
- **Cache** : le dossier est nommé par l'empreinte (jamais par un nom venu de
  l'hôte) ; une carte déjà en cache n'est pas retéléchargée (elle est
  revérifiée : empreinte recalculée, contrôle complet) ; 32 cartes au plus,
  les plus anciennes sont effacées.
- **Contrôle de légitimité** (`scripts/game/map/custom_map_guard.gd`), à la
  réception, à l'import d'une archive et à l'ouverture d'une carte locale pour
  jouer. Une carte n'est **que des données** : jamais `load()`,
  `ResourceLoader`, `.tres`, `.tscn`, script ni image venant du réseau ou d'une
  archive (une ressource Godot peut embarquer du code) ; les textes sont lus en
  UTF-8 strict puis par le lecteur JSON du moteur. Limites dures :

  | Limite | Valeur |
  |---|---|
  | Paquet (et total des cinq fichiers) | 2 Mo |
  | Morceaux réseau | 16 Ko (1 Ko au moins) |
  | Archive .zip | 4 Mo, 64 entrées, tailles décompressées lues avant d'extraire |
  | Profondeur JSON | 6 (lue avant l'analyse) |
  | Pièces / ouvertures / objets / zones / étages | 256 / 512 / 1024 / 64 / 6 |
  | Sommets | 64 par pièce, 4096 en tout |
  | Coordonnées | nombres finis, 0 à 256 m ; surface des pièces (rectangles englobants) 100 000 m² au plus |
  | Étages | sol -20 à 200 m, hauteur 2 à 30 m ; plafond 1,5 à 30 m ; portes 1,5 à 10 m |
  | Prix | entiers, 0 à 100 000 |
  | Textes | identifiants 32 caractères (lettres, chiffres, `_`, `-`) ; identifiant de carte en minuscules, chiffres et `_` ; noms 64 caractères ; descriptions 600 |

  **Liste blanche** des clés et des valeurs, tirée du catalogue de l'éditeur
  (`MapCatalog`) et donc des bases du jeu : types d'objets et d'ouvertures
  (champ `make` des objets du catalogue), clés de géométrie de chaque outil de
  pose, atouts (`PerkDB`), armes (`WeaponDB`, `KnifeDB`), surfaces
  (`WorldLook.SURFACES`), musiques (`assets/audio/ambience_*`), directions ; une
  clé ou une valeur inconnue est refusée. Tout passe par **une seule fonction
  adaptatrice**, `CustomMapGuard.catalog_source()` : dès qu'elles existent,
  elle prend la table typée `MapCatalog.allowed_kinds()` (format 2 : chaque
  type d'ouverture et d'objet, ses clés, ses clés obligatoires et leurs
  valeurs : identifiant, entier ou nombre borné, vrai / faux, liste de
  valeurs, point, rectangle, couleur `#rrggbb`), `MapCatalog.room_keys()`,
  `MapCatalog.zone_keys()` et `MapCatalog.allowed_surfaces()` (préfabriqués,
  luminaires, textures par pièce, plafond de zone) ; sinon le schéma est
  déduit des objets du catalogue. Les limites dures ci-dessus s'appliquent en
  plus (elles sont plus strictes que celles de l'éditeur : 256 m et 6 étages). **Noms** : pas de
  caractère de contrôle ni de contrôle bidirectionnel, pas de `[` `]` (BBCode),
  `<` `>`, `{` `}`, `\` ni `..` ; affichés dans des `Label` (jamais
  interprétés), nettoyés une seconde fois à l'affichage. Enfin la carte doit
  passer le **validateur de jouabilité** de l'éditeur (`MapRaster` +
  `MapValidator`).

### Format des fichiers

Cinq fichiers JSON dans le dossier de la carte (ou à la racine de l'archive).
Une entrée par ligne (diffs lisibles). Coordonnées en **mètres** dans le plan
de l'éditeur : x vers l'est, y vers le sud, x et y positifs ; le jeu place la
carte en (x + 4,25 ; z = y + 4,25). Chaque élément a un **identifiant stable**
(`p1`, `o3`, `a2`…). Les nombres entiers s'écrivent sans décimale.

**`carte.json`** — la carte :

```json
{
 "format": 1,
 "id": "draft_arena",
 "nom": {"fr":"DRAFT ARENA","en":"DRAFT ARENA"},
 "description": {"fr":"…","en":"…"},
 "musique": "ambience_bunker",
 "hauteur_portes": 2.5,
 "lampes_auto": true,
 "etages": [
  {"sol":0,"hauteur":3.2},
  {"sol":3.5,"hauteur":3.3}
 ]
}
```

`format` : version du format (1) ; `id` : dossier ; `musique` : un son
`assets/audio/ambience_*` ; `hauteur_portes` (m) ; `lampes_auto` : une lampe
tous les 6 m dans chaque zone ; `etages` : du bas vers le haut, `sol` (m) et
`hauteur` sous plafond (m) des pièces sans rien au-dessus.

**`pieces.json`** — les pièces :

```json
{
 "pieces": [
  {"id":"p3","nom":"Entrepôt","etage":0,"zone":"z3","contour":[[2.5,4.5],[17,4.5],[17,17],[2.5,17]],"double_hauteur":true},
  {"id":"p5","nom":"Passerelle","etage":1,"zone":"z5","contour":[[2.5,4.5],[7.5,4.5],[7.5,9.5],[2.5,9.5]]}
 ]
}
```

`contour` : les sommets (au moins 3) du trait des murs ; `zone` : un `id` de
`zones.json` ; facultatifs : `plafond` (hauteur sous plafond, m),
`double_hauteur` (true). Une pièce rectangle a 4 sommets alignés sur les axes.

**`ouvertures.json`** — portes, débris, passages, fenêtres :

```json
{
 "ouvertures": [
  {"id":"o1","type":"porte","etage":0,"position":[17,26.75],"largeur":2,"prix":750},
  {"id":"o3","type":"debris","etage":0,"position":[5.75,21.5],"largeur":2,"prix":1250},
  {"id":"o4","type":"passage","etage":0,"position":[11.75,17],"largeur":4},
  {"id":"o5","type":"fenetre","etage":0,"position":[11.25,4.5]}
 ]
}
```

`type` : `porte`, `debris`, `porte_courant` (sans prix), `passage` (sans
prix), `fenetre` (1 m, sans largeur) ; `position` : le **milieu** de
l'ouverture, **sur le trait du mur** ; `largeur` (m, multiple de 0,5 ; pour
un nombre pair de demi-mètres, le milieu tombe à 0,25 m de la grille).

**`objets.json`** — tout le reste :

```json
{
 "objets": [
  {"id":"x1","type":"pilier","etage":0,"rect":[9,9.5,11.5,12]},
  {"id":"x2","type":"escalier","etage":0,"rect":[2.5,9.5,5,16],"monte":"n"},
  {"id":"m1","type":"mur","etage":0,"a":[4,4],"b":[4,9],"epaisseur":0.5},
  {"id":"s1","type":"depart","etage":0,"position":[12,26]},
  {"id":"a2","type":"atout","atout":"titan","etage":0,"position":[17,14],"mur":"e"},
  {"id":"w1","type":"arme","arme":"m14","etage":0,"position":[13.25,33],"mur":"s"},
  {"id":"b2","type":"boite","etage":0,"position":[20.5,29.25],"mur":"e","depart":true},
  {"id":"t1","type":"piege","etage":0,"rect":[5,5,7,9]},
  {"id":"c1","type":"courant","etage":1,"position":[2.5,7.5],"mur":"o"}
 ]
}
```

- Rectangles (`pilier`, `escalier`, `piege`) : `rect` = [x0, y0, x1, y1]. Un
  pilier a son contour sur le trait (comme un mur de pièce) ; les marches et la
  zone de piège sont les cases à l'intérieur. `monte` : `n`, `e`, `s`, `o`.
- `mur` libre : segment `a` → `b`, `epaisseur` 0,5, 1,5 ou 2,5 m.
- Objets muraux (`atout` + `atout`, `arme` + `arme`, `grenades`, `boite` +
  `depart`, `pap`, `courant`, `poste_central`, `levier`) : `position` = milieu
  de l'objet **sur le trait du mur**, `mur` = direction du mur vu depuis
  l'objet (`n` : le mur est au nord). Identifiants d'atouts et d'armes : ceux
  de `PerkDB` / `WeaponDB` / `KnifeDB` (`titan`, `lazarus`, `m14`, `bowie`…).
- Objets au sol (`depart`, `apparition`, `teleporteur`, `arrivee`, `lampe`,
  `caisse`, `baril`) : `position` = centre. Un seul départ : les 4 joueurs se
  placent autour ; 2 à 4 départs : un joueur sur chacun.

**`zones.json`** — zones et zone de départ :

```json
{
 "depart": "z1",
 "zones": [
  {"id":"z1","nom":{"fr":"Salle des machines","en":"Engine room"},"sol":"concrete_dark","murs":"wall_concrete"},
  {"id":"z5","nom":{"fr":"Passerelle","en":"Catwalk"},"sol":"wood"}
 ]
}
```

`sol`, `murs` (facultatifs) : clés de `WorldLook.SURFACES`. Un fichier illisible
est signalé à l'ouverture (fichier, ligne, erreur) ; un format plus récent que
celui du jeu aussi.

## 7. Comment le jeu construit la carte

| Fichier | Rôle |
|---|---|
| `scripts/editor/editor_map.gd` | `EditorMap` : la carte (cinq JSON), lecture, écriture, archive .zip, dossier des cartes. |
| `scripts/editor/map_geom.gd` | `MapGeom` : géométrie 2D (contours, bords communs, cases). |
| `scripts/editor/map_rules.gd` | `MapRules` : règles de pose et leurs raisons (FR/EN). |
| `scripts/editor/map_catalog.gd`, `map_icons.gd` | Inventaire tiré des bases du jeu, icônes. |
| `scripts/editor/map_raster.gd` | `MapRaster` : carte -> grille de cases de 0,5 m par étage. |
| `scripts/editor/map_validator.gd` | `MapValidator` : validateur et indicateurs BO1. |
| `scripts/editor/map_layout_export.gd` | `MapLayoutExport` : grille validée -> description en maillage (format de `MeshMapLayout`). |
| `scripts/editor/map_editor.gd`, `map_canvas.gd`, `map_panels.gd`, `map_hotbar.gd`, `map_inventory.gd`, `map_slot.gd` | L'interface (`scenes/editor/map_editor.tscn`). |
| `scripts/game/map/editor_map_def.gd` | `EditorMapDef` : carte de l'éditeur côté jeu (`perso:<id>`, `partage:<sha256>`, ou script de carte livré). |
| `scripts/game/map/custom_map_guard.gd` | `CustomMapGuard` : contrôle de légitimité, paquet canonique et SHA-256, cache, lecture sûre d'un dossier ou d'une archive. |
| `scripts/game/map/map_share.gd`, `map_transfer.gd` | `MapShare` (envoi aux invités, `/root/Net/MapShare`) et `MapTransfer` (réception par morceaux). |
| `scripts/game/map/mesh_map_geometry.gd` | `MeshMapGeometry` : architecture 3D construite par le jeu (portage de `tools/blender/mesh_map.py`). |

1. **Grille** (`MapRaster`) : une case de 0,5 m **centrée** sur chaque multiple
   de 0,5 m. Les cases que traverse le contour d'une pièce sont des murs (un
   mur de 0,5 m centré sur le trait ; le bord commun de deux pièces = les mêmes
   cases : un seul mur), celles dont le centre est à l'intérieur son sol, de la
   zone de la pièce. Ouvertures : les cases du mur sur leur largeur. Double
   hauteur : à l'étage du dessus, contour en mur, intérieur en vide ; une pièce
   d'étage au-dessus du vide y pose son plancher (mezzanine). Escalier : cases
   de marches, vide au-dessus. Objets : leurs cases. Zones : la zone de départ
   devient `a` (celle que le jeu ouvre au début), les autres `b`, `c`…
2. **Validation** (`MapValidator`, §5).
3. **Description en maillage** (`MapLayoutExport`) : salles (sols, plafonds,
   dalles d'étage), murs, allèges et linteaux en blocs, garde-corps,
   escaliers (marches et rampe de collision), cours des fenêtres, zones,
   marqueurs (objets muraux par la face du mur), lampes, réglages de la carte
   (`map_def` : noms des zones dans la langue du jeu, prix des portes, zones
   ouvertes l'une sur l'autre, départ de la boîte, téléporteur à relier si un
   poste central est posé).
4. **Géométrie** (`MeshMapGeometry`) : les mêmes objets que le `.glb` de
   `mesh_map.py` (`<matériau>__<salle>__<type>`, collisions en pavés et prismes),
   branchés par `MeshMapBuilder` ; `MeshNav` cuit le navmesh, `MeshMapLayout`
   fournit zones et emplacements aux systèmes du jeu. **Aucune étape Blender** :
   une carte de l'éditeur se joue aussitôt, y compris dans le `.exe`.

Déclarer une carte livrée avec le jeu : ses JSON dans `assets/maps/<id>/`, un
script de 3 lignes (`scripts/game/map/maps/<id>.gd` : `extends EditorMapDef`
et `_init_editor("res://assets/maps/<id>/", "<id>")`), une ligne dans
`Game.MAP_SCRIPTS` ; l'ajouter à `Game.MENU_MAPS` la propose dans les menus.

## 8. DRAFT ARENA

Carte d'essai de 18 × 28,5 m sur 2 étages (`assets/maps/draft_arena/`) :
salle des machines (départ, M14, LAZARUS), couloir de service (MP5K, boîte de
départ), entrepôt à double hauteur avec son pilier (TITAN BREW, boîte,
escalier), atelier (ouvert sur l'entrepôt par un passage), passerelle à
l'étage (boîte, courant) ; portes 750 et 1000, débris 1250 ; 7 fenêtres.
Recréée dans ce format à partir de l'ancien dessin : même grille case par
case, donc la même carte en jeu (mêmes salles, murs, escaliers, fenêtres,
portes, zones et objets ; seules les deux armes murales se décalent de
0,25 m). Rapport du validateur : 0 erreur, 0 avertissement ; boucle
Couloir → Salle des machines → Atelier → Entrepôt (3000 points de portes),
grande boucle de training de 63 m, passerelle en impasse (poste de camping),
TITAN BREW à 1250 points de portes.

Preuves automatiques :
- `tests/test_map_editor.gd` : règles de pose (porte refusée sans deux pièces
  collées, acceptée sur le bord commun et reliant ces deux pièces ; fenêtre
  seulement sur un mur extérieur avec la place des zombies ; objets muraux
  contre un mur, face vers l'intérieur ; objets au sol dans une pièce sans
  chevauchement ; pièces collées mais pas superposées), mur mitoyen unique,
  validateur (erreurs pointées, messages FR/EN), passage libre, double
  hauteur, mezzanine et escalier, JSON lisibles, enregistrement et archive
  .zip relus à l'identique, JSON écrit à la main, annuler / rétablir dans
  l'éditeur, inventaire tiré des bases du jeu, conversion en carte jouable
  (emplacements, zones, géométrie construite par le jeu), DRAFT ARENA migrée
  valide, cartes perso trouvées par le jeu.
- `tests/autotest/map_editor.gd` (captures) : bouton du menu principal, trois
  pièces au glisser, porte refusée puis posée, objets par l'inventaire,
  vérification, Ctrl+S, rechargement, Ctrl+Z / Ctrl+Y, archive, polygone,
  copier / coller, poignée.
- `tests/autotest/map_editor_play.gd` : TESTER sur DRAFT ARENA, partie solo sur
  la carte de l'éditeur, retour dans l'éditeur.
- `tests/autotest/draft_arena.gd` : la carte se joue (zombies aux fenêtres,
  portes, débris, escalier, tout accessible à pied).
- `tests/test_map_share.gd` : paquet canonique et empreinte stable, morceaux
  dans le désordre, manquants, en double, trop gros, empreinte fausse,
  contrôle de légitimité (clé ou type inconnu, chaîne géante, infini,
  coordonnée énorme, chemin `../`, faux JSON, JSON trop profond, BBCode dans
  le nom, fichier en plus...), DRAFT ARENA acceptée, cache par hash, archive
  .zip piégée refusée.
- `sh tools/mp_test.sh custommap` : hôte + invité sans fenêtre ; carte perso
  choisie avant l'arrivée de l'invité, téléchargée, DÉMARRER grisé pendant le
  téléchargement, cartes corrompue et piégée refusées (partie non démarrée),
  cache réutilisé, partie sur la même carte.

## 9. Conseils de conception (BO1)

- **Départ** : 150 à 250 m², 2 à 4 fenêtres à plus de 6 m du départ, deux
  sorties (Kino : hall avec deux portes à 750), une arme à 500 au mur (M14 ou
  Olympia), LAZARUS (Quick Revive).
- **Rythme des portes** : 750 pour la première, puis 1000, 1250 (Kino : 750,
  750, 1000, 1000, 1250 × 4) ; 5 à 10 portes ; ce qu'il y a derrière chaque
  porte doit valoir le prix (une arme, un atout, un emplacement de boîte, le
  courant, un raccourci qui ferme une boucle).
- **Boucles** : au moins une grande boucle de salles (Kino : deux) et un
  espace dégagé pour tourner autour d'un obstacle (25 à 40 m de tour) ;
  couloirs de 2 à 4 m, jamais moins de 1,5 m sur un trajet de training.
- **Fenêtres** : environ une pour 50 à 80 m² de zone ; à moins de 25 m à pied
  de tout point ; jamais dans le dos immédiat d'une arme au mur.
- **Boîte** : un emplacement par grande salle (Kino : 9), départ souvent une
  porte plus loin que le départ ; **courant** au bout d'un chemin qui coûte ;
  **TITAN BREW** (Juggernog) derrière 1 à 3 portes, dans un coin défendable.
- **Étages** : une passerelle ou un balcon donne un poste de tir et une impasse
  ; escaliers de 2 m ou plus de large pour que la horde passe.

## 10. Limites et prochaines étapes

- **Sols plats par étage** : pas encore de pente ni de petites marches entre
  deux pièces d'un même étage.
- **Grille de 0,5 m** : les murs en biais d'une pièce polygone deviennent un
  escalier de cases dans le jeu ; portes et fenêtres seulement sur les murs
  droits (horizontaux ou verticaux).
- Pas de porte en haut ou en bas d'un escalier (les deux zones d'un escalier
  sont ouvertes l'une sur l'autre) ; pas de portes liées ; pièges électriques
  seulement ; décor limité à des caisses et barils (pas encore les modèles de
  Kino).
- Cartes perso en multijoueur : réseau local ou IP directe seulement (pas de
  serveur de cartes) ; une carte en cours de téléchargement ne se joue pas
  hors du salon où elle a été reçue (elle reste dans le cache).
- Architecture en maquette grise (matériaux par zone seulement).
