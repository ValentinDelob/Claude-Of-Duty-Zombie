# Concevoir une carte : l'éditeur de cartes

But : concevoir une carte **simplement, sans bug et amusante**, puis la jouer
aussitôt. L'**éditeur de cartes** est une scène du jeu (menu principal >
ÉDITEUR DE CARTES) : on y dessine les pièces vues de dessus, on pose portes,
fenêtres, atouts, armes, boîte… depuis un inventaire façon Minecraft, un
validateur vérifie la carte avec des règles « façon BO1 », et le bouton
**TESTER** lance une partie solo dessus (sans l'enregistrer). La carte est
enregistrée (seulement par Fichier > Enregistrer, Ctrl+S) en cinq
fichiers JSON lisibles et écrivables à la main (un outil peut aussi les
écrire), exportables en archive `.zip`.

Preuve : la carte d'essai **DRAFT ARENA** (`assets/maps/draft_arena/`, hors
menus, `--map=draft_arena`) est faite dans ce format et se joue (scénarios
`draft_arena` et `map_editor_play`).

![L'éditeur : trois pièces, portes, fenêtres, objets, onglet Vérification](map_authoring/editeur.png)
![L'inventaire (touche E), catégorie Ouvertures](map_authoring/inventaire.png)
![DRAFT ARENA dans l'éditeur (rez-de-chaussée)](map_authoring/draft_arena_editeur.png)
![DRAFT ARENA, niveau 3,5 m : passerelle au-dessus de l'entrepôt haut (plafond de 6,8 m)](map_authoring/draft_arena_etage1.png)
![En jeu : la passerelle au-dessus de l'entrepôt](map_authoring/jeu_passerelle.png)
![Onglet « Objets sur la carte » : le bureau survolé sur la carte, sa ligne surlignée](map_authoring/objets.png)
![Textures d'une pièce (sol, murs, plafond) dans l'onglet Propriétés](map_authoring/textures.png)
![L'inventaire, catégorie Décor et obstacles](map_authoring/inventaire_decor.png)
![En jeu : murs de brique, parquet, plafond en bois, fauteuils, bureau, applique et suspension](map_authoring/jeu_decor.png)

---

## 1. Lancer l'éditeur

- Depuis le jeu : menu principal > **ÉDITEUR DE CARTES** (aussi dans le `.exe`).
- Directement : `godot --path . res://scenes/editor/map_editor.tscn`, ou
  double-clic sur `tools/map_editor.bat` (Godot dans le PATH, ou `set GODOT=…`).
- Vérifier une carte sans fenêtre (outil, intégration) :
  `godot --headless --path . res://scenes/editor/map_editor.tscn -- --check=<dossier ou archive.zip>`
  affiche le rapport du validateur ; code de sortie 0 si la carte est jouable.

Au démarrage, l'éditeur rouvre la dernière carte ; s'il reste une copie de
récupération (plantage, fermeture forcée), il propose de la récupérer
(§ 6, « Enregistrement explicite et récupération »).

## 2. L'écran

| Zone | Rôle |
|---|---|
| Barre du haut | **Fichier** (Nouvelle, Ouvrir, Enregistrer, Enregistrer sous, exporter / importer l'archive .zip, cartes récentes, options, retour au menu), **Édition** (annuler, rétablir, copier, coller, pivoter, supprimer, inventaire, recadrer), barre des niveaux (◄ « Niveau 3,5 m (2/3) ▾ » ►, § 4), **▶ TESTER**, état de la vérification, aimantation, aperçu 3D, **Disposition** (1 à 4 fenêtres de vue, §2 quater), **⚙** (options du jeu), nom de la carte, **?** (raccourcis). Elle passe sur deux lignes si elle ne tient pas en largeur (grande taille d'interface). |
| Vues | Par défaut **deux vues empilées** : la vue **Dessus** (le plan, grille de 1 m, traits forts tous les 5 m, traits fins au pas de la grille fine) au-dessus de la vue **Avant** (élévation : tous les niveaux à leur vraie altitude). Règles graduées en vraies coordonnées, en-tête de 22 px (plan, niveaux, axes, coupe, zoom, ⛶), **ViewCube** en haut à droite, trièdre en bas à gauche ; coordonnées du curseur aimanté en bas à droite. 1 à 4 fenêtres au choix (menu **Disposition**) : §2 quater. |
| Barre rapide | 9 cases (touches 1 à 9, molette) : l'objet tenu ; posée au bas de la vue en 1 vue, ancrée dans une bande de 48 px sous les vues dès 2 vues (outil à gauche, aimantation à droite). À gauche, la case fixe **Souris** (outil Sélection) : outil au démarrage, jamais remplacée ; une case vide se comporte comme la souris. |
| Inventaire | Touche **E** ou **Tab** : toutes les catégories ; cliquer un objet le met dans la case choisie (souris en main : la première case vide, sinon la dernière case choisie), ou le glisser sur une case. |
| Panneaux | **Propriétés** (élément choisi, sinon la carte), **Pièces**, **Zones**, **Niveaux**, **Vérification**. |
| Objets sur la carte | Onglet déployable à gauche de la vue (languette, bouton ◂ ou touche **L** ; ouvert / replié : mémorisé) : voir §2 bis. |
| Aperçu 3D | Bouton **APERÇU 3D** de la barre du haut ou touche **P** : la carte telle qu'en jeu, en direct, dans un panneau flottant ou une fenêtre séparée : voir §2 ter. |
| Barre d'état | Aide de l'outil, raison d'un refus, résultat des actions. |

**Taille de l'interface** : tout l'éditeur (textes, barres, panneaux,
onglets, barre rapide, inventaire, liste des objets, bulles d'aide, messages,
aperçu 3D, cotes et étiquettes dessinées sur le plan) suit un seul réglage,
OPTIONS > JEU > INTERFACE > **TAILLE DE L'INTERFACE DE L'ÉDITEUR**, de 60 à
150 % par pas de 5 %, **80 % par défaut**. Dans l'éditeur : **Ctrl + « + »**
/ **Ctrl + « - »** (5 % de plus ou de moins), **Ctrl + 0** (80 %), ou le
bouton **⚙** (les options s'ouvrent par-dessus l'éditeur, sur ce réglage, et
le changement se voit en direct derrière). Le plan garde son zoom et ne bouge
pas : il gagne la place libérée. Chaque panneau latéral prend au plus 30 % de
la largeur (le plan garde au moins 40 %) ; à grande taille, la barre du haut
passe sur deux lignes, la barre rapide et l'inventaire se resserrent.
Enregistré dans `settings.cfg` (section `interface`, clé `editor_ui_scale`,
ramenée dans la plage à la lecture). Mise en œuvre : `scripts/editor/editor_ui.gd`.

### Commandes

| Action | Commande |
|---|---|
| Poser / choisir | clic gauche |
| Tracer (pièce, forme, mur, pilier, escalier, piège) | glisser, ou clic puis clic (le tracé suit le curseur entre les deux) |
| Annuler le tracé ou le glissement en cours | clic droit, Échap |
| Menu du clic droit (rien en cours) | clic droit, dans toutes les vues : Créer une prefab…, Dupliquer, Copier, Couper, Coller ici, Pivoter, Supprimer, Tout sélectionner, Désélectionner (voir « Sélection multiple et groupes ») ; sur un sommet ou un côté du contour choisi, en tête : Supprimer ce point / Ajouter un point ici |
| Désélectionner | Échap, clic dans le vide, **reclic** : simple clic (sans glisser) sur l'élément déjà choisi seul, dans la vue Dessus, les élévations et la 3D (glissé, il est déplacé). Poignées, flèches et anneaux suivent toujours la sélection ; un geste en cours sur l'élément quitté est annulé |
| Sélection multiple | **Maj + clic** : ajouter / retirer un élément (vue Dessus, élévations, 3D, liste des objets) ; **rectangle** : glisser depuis le vide (ou Maj + glisser n'importe où) ; **Ctrl+A** : tout le niveau affiché |
| Groupe choisi | glisser l'un de ses éléments ; **flèches** : d'un pas de grille ; **R** / poignée ronde : pivoter autour du centre ; **Ctrl+D** : dupliquer ; **Ctrl+X** : couper ; Suppr |
| Créer une prefab de la sélection | **Ctrl+G**, clic droit > Créer une prefab…, ou le panneau Propriétés |
| Zoom | Ctrl + molette (ou + / -) |
| Taille de l'interface de l'éditeur | Ctrl + « + » / Ctrl + « - » (pas de 5 %, de 60 à 150 %), Ctrl + 0 : 80 % ; aussi OPTIONS > JEU (bouton ⚙) |
| Déplacer la vue | clic milieu + glisser, ou Espace + glisser |
| Aimantation | **G** : grille 1 m → grille fine → libre (sans grille) ; **Maj+G** : pas de la grille fine (0,5 / 0,25 / 0,1 m) ; **Maj** maintenu : inverse le mode (grille ↔ libre) ; mémorisé ; bouton « Aimantation » de la barre du haut |
| Angle d'un mur ou d'un côté de polygone | sur la grille : 0, 45 ou 90° ; sans grille : par pas de 15° ; angle libre en maintenant Alt ; longueur et direction affichées pendant le tracé |
| Saisie au clavier pendant le tracé | taper la longueur, **Tab**, l'angle (degrés depuis l'est, sens trigonométrique : 90 = nord), **Entrée** ; rectangle, ellipse, triangle, L : largeur, hauteur ; cercle : rayon, points ; mur courbe : rayon, ouverture ; Retour arrière efface, Échap annule la saisie |
| Points d'un cercle ou d'une ellipse, segments d'un mur courbe | molette ou + / - pendant le tracé ; puis dans l'onglet Propriétés |
| Rotation libre | **poignée ronde** au-dessus de l'élément choisi : pas de 15°, au degré près avec Alt ; champ « Angle » des propriétés |
| Rectangle à 45° | Pièce rectangle en main : R (le glisser va d'un coin au coin opposé du losange) |
| Case de la barre rapide | 1 à 9, molette (la souris est la position avant la case 1) |
| Souris (outil Sélection) | ² (touche à gauche du 1, ` en QWERTY), clic sur sa case, ou Échap (après l'annulation du tracé en cours et de la sélection) |
| Inventaire | E ou Tab |
| Pivoter de 90° | R (une pièce pivote avec son contenu ; un décor ou un luminaire tenu pivote avant d'être posé) |
| Liste des objets sur la carte | L |
| Aperçu 3D (afficher / masquer) | P (voir §2 ter pour ses caméras) |
| Placer la caméra de l'aperçu à un endroit | Ctrl + double-clic sur la carte (aperçu affiché) |
| Supprimer | Suppr (une pièce emporte ses objets et ses ouvertures) |
| Ajouter / retirer un point d'un contour (pièce, barrière invisible) | glisser la poignée **« + »** d'un côté, ou **double-clic** sur un côté ; **Suppr** sur un sommet survolé (ou glissé), ou clic droit > Supprimer ce point (3 sommets au moins) |
| Copier / couper / coller sous le curseur | Ctrl+C / Ctrl+X / Ctrl+V (un élément ou tout un groupe) |
| Annuler / rétablir (illimité) | Ctrl+Z / Ctrl+Y (ou Ctrl+Maj+Z) |
| Enregistrer / Enregistrer sous | Ctrl+S / Ctrl+Maj+S |
| Nouvelle carte / Ouvrir | Ctrl+N / Ctrl+O (Suppr dans la fenêtre Ouvrir : supprimer la carte choisie) |
| Recadrer sur la carte | Origine |
| Fermer un polygone | double-clic, clic sur le premier point, ou Entrée ; Retour arrière retire le dernier point |
| Niveau du dessous / du dessus | Page préc. / Page suiv. ; **Maj** + Page préc. / suiv. : la sélection descend / monte au niveau voisin (§ 4) |
| Pièce empilée suivante sous le curseur | **Alt + clic** (vue Dessus) : de la plus haute à la plus basse, la vue va à son niveau |
| Disposition des vues | bouton **Disposition** (1 vue, 2 côte à côte, 2 empilées, 3 : 1 + 2, 3 : 2 + 1, 4 vues) ; **Ctrl+Alt+Q** : 4 vues ; **Ctrl+Espace**, ⛶ ou double-clic sur l'en-tête : agrandir la vue active (une seconde fois : retour) ; séparateurs : glisser, double-clic : partage égal |
| Changer le plan d'une vue | **ViewCube** (face voisine, ◄ ► : façade suivante, maison : vue d'origine, ▾ : menu) ; souris sur la vue : **pavé 7** Dessus, **1** Avant, **3** Droite (Ctrl : la vue opposée), **5** : 3D ; ailleurs le pavé choisit une case de la barre rapide |
| Déplacer en élévation | glisser l'élément (deux axes de la vue : hauteur de pose ou altitude) ; **flèches d'axe** (X rouge, Y vert, Z bleu) : un seul axe ; **X / Y / Z** pendant le glissement : verrouiller ; chiffres ou **Tab** : taper l'écart, **Entrée** ; Échap ou clic droit : annuler |
| Plafond, hauteur, altitude d'un niveau | en élévation : **losange** du haut (plafond d'une pièce, hauteur d'une barrière ou d'une zone d'effet), carrés des côtés (largeur sur l'axe de la vue), **étiquette « +3,50 m »** de la règle Z (sol du niveau : glissée, elle déplace tout le niveau) ; glisser une pièce verticalement change son altitude (§ 4) |
| Coupe d'une élévation | **K** : autour de la sélection (de nouveau K : enlevée) ; puce « Coupe ▾ » de l'en-tête ; poignées des traits pointillés dans la vue Dessus |

Outil **Sélection** (la **Souris**, case fixe à gauche de la barre) : clic sur un élément pour le choisir, glisser
pour le déplacer (une ouverture ou un objet mural suit le curseur, dans tous les
modes d'aimantation, et reste accroché à son mur, calé sur les cases de 0,5 m
d'un mur de la grille), **poignées** jaunes pour
redimensionner (coins et milieux des côtés d'une pièce rectangle, sommets d'un
polygone ou d'une forme, coins d'un pilier, d'un escalier ou d'un piège, même
tournés, bouts d'un mur), **poignée ronde** au-dessus pour tourner. Un
élément devenu invalide (une fenêtre restée sur l'ancien mur d'une pièce
agrandie…) est entouré de rouge avec la raison dans la barre d'état.

**Ajouter ou retirer un point** d'un contour libre (pièce, barrière
invisible ; MapVertex) :

- **Ajouter** : l'élément choisi montre une petite poignée ronde **« + »** au
  milieu de chaque côté (au quart et aux trois quarts des côtés d'une pièce
  rectangle, dont le milieu garde sa poignée de redimensionnement ; aucune
  sur un côté trop court à l'écran : zoomez). **Glisser le « + »** crée un
  sommet et le déplace (aimanté comme le reste) ; un simple clic dessus
  n'ajoute rien. **Double-clic sur un côté** : un sommet y est ajouté (au
  point aimanté s'il tombe sur le côté, sinon au point du côté le plus
  proche, au centimètre). **Clic droit sur un côté** > « Ajouter un point
  ici ». Une pièce rectangle devient un polygone (ses 4 coins forment le
  contour) au premier point ajouté ; une forme de base (cercle, L…) devient
  un polygone libre.
- **Supprimer** : **Suppr** avec la souris sur un sommet (cerclé de blanc
  au survol), ou pendant qu'on le glisse ; **clic droit sur un sommet** >
  « Supprimer ce point ». Suppr ailleurs supprime l'élément choisi, comme
  avant. Jamais moins de **3 sommets** (entrée grisée sur un triangle).
- Chaque ajout ou suppression est **une étape d'annulation** (Ctrl+Z),
  partagée avec les autres participants, et suit les règles d'un sommet
  déplacé : un contour qui se croise, qui recouvre une autre pièce, trop
  petit ou au-delà de 128 sommets (64 pour une barrière) est **refusé**, la
  raison dans la barre d'état. Comme pour un sommet déplacé, les ouvertures
  et objets muraux restent où ils sont : un objet resté hors du nouveau mur
  est entouré de rouge.

### Sélection multiple et groupes

Plusieurs éléments se choisissent ensemble et s'éditent d'un bloc
(`scripts/editor/map_group.gd`, `map_context_menu.gd`) :

- **Maj + clic** sur un élément l'ajoute à la sélection, ou l'en retire ;
  marche dans la vue Dessus, les élévations, la 3D et la liste des objets.
  Maj ne sert à la sélection qu'**au moment de l'appui** : pendant un
  glissement commencé sans Maj, Maj garde son rôle (inverser l'aimantation).
- **Rectangle de sélection** (vue Dessus) : glisser depuis le vide, ou Maj +
  glisser n'importe où (il s'ajoute alors à la sélection). Comme dans les
  logiciels de CAO (Fusion, AutoCAD) : tracé **de gauche à droite**, il prend
  les éléments **entièrement dedans** (cadre bleu plein) ; **de droite à
  gauche**, ceux qu'il **touche** (cadre vert en tirets). Les éléments qu'il
  prendrait sont entourés pendant le tracé, avec leur nombre. Un simple clic
  dans le vide désélectionne.
- **Ctrl+A** : tous les éléments du niveau affiché ; **Échap** : désélectionner ;
  un **simple clic sur l'élément déjà choisi seul** (sans glisser, pas un
  double-clic) le désélectionne aussi, dans la vue Dessus, les élévations et
  la 3D.
- La sélection est **commune à toutes les vues** : chaque élément est surligné
  (Dessus, élévations, 3D, liste des objets), un **cadre en tirets** entoure le
  groupe avec son nombre d'éléments et sa **poignée ronde** de rotation ; le
  panneau Propriétés affiche « N éléments sélectionnés » : ce qu'ils sont,
  l'altitude et la rotation quand elles sont communes, l'encombrement, les éléments
  invalides, les actions de groupe et la liste (un clic : cet élément seul).

**Actions de groupe** : **glisser** un de ses éléments déplace tout le groupe
(au pas de l'aimantation ; flèches d'axe, X / Y : verrouiller ; dans une
élévation : sur l'axe de la vue et en **altitude** (pas de 0,25 m, aimants), ou en hauteur de pose si tout
le groupe est du décor posé) ; un simple clic sans bouger sur un élément du
groupe le choisit seul. **Flèches** : d'un pas de grille (0,1 m sans grille).
**R** ou la poignée ronde : pivoter autour du **centre du groupe** (pas de
15°, Alt : au degré). **Ctrl+D** : dupliquer à côté (à droite, sinon dessous,
à gauche, dessus : la première place où tout tient). **Ctrl+C / Ctrl+X /
Ctrl+V** : copier, couper, coller sous la souris (le centre du groupe va au
point aimanté ; pièces renommées, une zone neuve par zone d'origine).
**Suppr** : supprimer. Comme pour un seul élément, une pièce emporte son
contenu et les portes de ses bords (déplacer, pivoter, supprimer) ; copier ne
prend que ce qui est choisi.

**Tout ou rien** : chaque action vérifie TOUT le groupe à sa nouvelle place
(règles de pose : les éléments du groupe se voient les uns les autres) ; si
un seul élément ne tient pas, rien ne change : son nom et la raison sont
affichés près du curseur et dans la barre d'état, et il est entouré de rouge à
la place refusée. **Une action = une étape d'annulation** (Ctrl+Z), et un seul
lot d'opérations pour les autres participants d'une session ; la sélection
multiple est montrée chez eux (présence) ; Claude la lit
(`editor_get_selection`) et peut la donner (`editor_highlight` avec
`select: true`).

**Menu du clic droit** (toutes les vues, quand aucun tracé ni glissement
n'est en cours : sinon le clic droit les annule ; dans la 3D, un clic droit
sans tourner la caméra) : sur un élément non choisi, il est choisi d'abord.
Entrées avec leur raccourci, grisées (bulle : pourquoi) quand elles sont
impossibles : **Créer une prefab…** (Ctrl+G), Dupliquer (Ctrl+D), Copier
(Ctrl+C), Couper (Ctrl+X), Coller ici (Ctrl+V ; vue Dessus), Pivoter de 90°
(R), Supprimer (Suppr), Tout sélectionner (Ctrl+A), Désélectionner (Échap).
Les mêmes actions sont dans le menu **Édition**.

### Murs en biais

![Octogone et losange collés par un côté en biais, porte et fenêtres en biais](map_authoring/murs_biais_editeur.png)
![En jeu : porte dans le mur en biais, murs obliques lisses](map_authoring/murs_biais_jeu.png)

- **Tracer** : avec la Pièce polygone ou le Mur, chaque côté part du point
  précédent à 0, 45 ou 90° (sur la grille, les sommets restent sur la
  grille) ; **Alt** maintenu : angle libre. La longueur et la direction du
  côté en cours s'affichent à côté du curseur (« 5,66 m · 45° », degrés
  depuis l'est). **Pièce rectangle + R** : rectangle tourné de 45°
  (losange), glissé d'un coin au coin opposé. Sans grille, voir « Formes
  libres » ci-dessous.
- **Mur mitoyen** : deux pièces qui partagent un côté en biais n'ont qu'un
  mur, qui montre de chaque côté la texture de sa pièce.
- **Ouvertures** (porte, débris, porte du courant, passage, fenêtre) et
  **objets muraux** (atouts, armes, boîte, machines, levier, applique) se
  posent aussi sur un mur en biais, orientés selon le mur, avec les mêmes
  règles (porte seulement sur le bord commun de deux pièces collées, fenêtre
  sur un mur extérieur avec 2,5 × 3 m de vide dehors, 0,5 m de mur plein aux
  bouts, mur plein derrière un objet). Sur un côté à 45°, le milieu d'une
  ouverture tombe sur la grille de 0,25 m.
- **En jeu** : de vrais murs droits obliques (pas de marches), collisions en
  pavés `CollisionBox` tournés (balles, grenades, joueurs et zombies suivent le
  vrai mur), un raccord aux angles entre deux murs en biais ; le sol et le
  plafond suivent le vrai contour.

### Formes libres

![Salle ronde de 32 points, annexe tracée sans grille, mur courbe, pilier tourné de 30° (poignée de rotation)](map_authoring/formes_libres_editeur.png)
![En jeu : mur rond en brique, mur courbe et pilier tourné](map_authoring/formes_libres_jeu.png)

- **Aimantation au choix** (touche **G**, ou le bouton « Aimantation » de la
  barre du haut ; mémorisée) : **grille 1 m** (comme avant), **grille fine**
  (0,5, 0,25 ou 0,1 m : **Maj+G** change le pas ; traits fins affichés quand
  le zoom le permet) ou **libre** (sans grille : coordonnées au centimètre,
  lisibles dans le JSON). **Maj** maintenu inverse le mode courant (grille →
  libre, libre → la dernière grille). En libre : **aimants** aux sommets des
  pièces et aux bouts des murs (carré bleu), sinon aux côtés des pièces (rond
  bleu) pour coller deux pièces ; un côté part du point précédent **à 15°
  près** (Alt : angle libre) ; une pièce déplacée se colle par son sommet le
  plus proche au sommet ou au côté d'une autre pièce.
- **Saisie au clavier** pendant un tracé (côté de polygone, mur, rectangle,
  forme, mur courbe, pilier, escalier, piège) : taper la longueur, **Tab**,
  l'angle, **Entrée** (« 4 Tab 30 Entrée » : 4 m à 30°) ; l'angle se compte
  depuis l'est, dans le sens trigonométrique (90 = nord, -90 = sud), comme la
  direction affichée à côté du curseur ; un champ laissé vide suit le curseur.
  Rectangle, ellipse, triangle, L : largeur, hauteur ; cercle : rayon,
  nombre de points ; mur courbe : rayon, ouverture. Un **simple clic** (sans
  glisser) commence le tracé, qui suit le curseur jusqu'au clic suivant ou à
  Entrée. Le champ s'affiche près du curseur ; Retour arrière efface, Échap
  annule la saisie.
- **Formes de base** (inventaire, Construction) : **cercle / polygone
  régulier** (glisser du centre au bord ; **3 à 64 points**, à la molette ou
  avec + / - pendant le tracé, aperçu en direct ; à 0°, un côté est à plat au
  sud, et avec un nombre de points multiple de 4 les côtés nord, est, ouest et
  sud sont droits : une pièce s'y colle), **ellipse** (d'un coin à l'autre,
  N points), **triangle** (pointe en haut ; glissé vers le haut : pointe en
  bas), **pièce en L** (épaisseur des branches réglable), **mur courbe** (arc
  de cercle en 1 à 64 segments droits : glisser du centre vers le premier
  bout, 90° dans le sens horaire ; rayon, ouverture et segments réglables).
  Une forme posée reste un **polygone éditable** ; elle garde son type et
  ses paramètres (clé `forme`) : dans l'onglet Propriétés, changer le nombre
  de points, le rayon, la largeur, la hauteur, les branches ou l'angle la
  **régénère** (ses ouvertures et ses objets muraux se raccrochent au mur le
  plus proche). Déplacer, ajouter ou retirer un sommet à la main en fait un
  polygone libre (§ 2, « Ajouter ou retirer un point »).
- **Rotation libre** : **poignée ronde** au-dessus de l'élément choisi (pièce,
  pilier, escalier, piège, décor, luminaire au sol ou au plafond, mur, mur
  courbe) : pas de **15°**, au **degré près avec Alt** ; champ **Angle** de
  l'onglet Propriétés (« Pivoter de » pour une pièce quelconque) ; **R** :
  90° comme avant. Une pièce tourne **avec son contenu** : ses ouvertures et
  ses objets muraux restent collés à leur mur (face vers l'intérieur), son
  décor, ses piliers, escaliers et pièges tournent avec elle. Les objets
  muraux ne tournent pas seuls : ils suivent leur mur.
- **Portes sur un côté court** (côté d'un cercle) : posée à la souris, une
  porte trop large pour le mur visé est réduite par pas de 0,5 m (1 m au
  moins) ; il faut toujours 0,5 m de mur plein à chaque bout (un côté de
  2,5 m pour une porte de 1,5 m : un cercle de 32 points de 13 m de rayon).
- **En jeu** : tout côté qui n'est pas un côté droit de la grille (en biais,
  ou droit mais hors de la grille de 0,5 m) est un **vrai mur oblique**
  (collisions `CollisionBox` tournées), sol et plafond découpés selon le vrai
  contour ; deux pièces collées **sans grille** (côtés parallèles à moins de
  3 cm) n'ont qu'**un mur mitoyen** ; une pièce sans grille collée au côté
  d'une pièce de la grille garde ce mur de la grille (pas de second mur).
  Piliers tournés : un pavé plein tourné ; escaliers tournés : marches et
  rampe dans le sens de montée ; pièges tournés : zone électrifiée tournée ;
  décor tourné au degré près : modèle et `CollisionBox` tournés. Les murs
  obliques sont **fusionnés en un maillage par matériau** (un cercle de 64
  côtés ne coûte pas plus de rendu qu'un mur droit).

## 2 bis. Objets sur la carte (liste)

Onglet déployable à gauche de la vue (`MapObjectList`) : **tous les éléments
posés** (pièces, ouvertures, objets de jeu, construction, décor, luminaires),
une ligne chacun avec son icône, son nom, son type, son altitude (« 0 m », « 3,5 m »…) et sa
position en mètres ; triés par identifiant (ordre naturel : `p2` avant `p10`).

- **Pages de 50** : ◄ ► et « page 2/7 » au bas de la liste.
- **Filtre** par catégorie (Tout, Pièces, Ouvertures, Construction, Objets de
  jeu, Décor et obstacles, Luminaires ; mémorisé) et **recherche** dans le
  nom, le type et l'identifiant.
- **Survol** d'un élément sur la carte : sa ligne est surlignée et la liste
  saute à sa page ; survol d'une ligne : l'élément s'entoure d'un **contour
  lumineux** sur la carte (portée d'un luminaire en cercle), sans déplacer la
  vue. **Clic** sur une ligne : choisir l'élément et centrer la vue (change
  de niveau au besoin) ; **double-clic** : centrer et zoomer.
- Fluide avec 2000 éléments : la liste n'est refaite qu'après une
  modification de la carte (et seulement onglet ouvert), les 50 lignes sont
  dessinées par un seul contrôle, le survol ne cherche que parmi les objets
  proches (index par cases de 4 m). Mesuré par les tests : survol < 1 ms,
  pose d'un objet ≈ 0,6 s avec 2000 objets.

## 2 ter. Aperçu 3D en direct

![L'éditeur avec l'aperçu 3D ouvert (DRAFT ARENA)](map_authoring/apercu_3d.png)
![L'aperçu agrandi, en vue joueur dans l'entrepôt](map_authoring/apercu_vue_joueur.png)

Bouton **APERÇU 3D** (barre du haut) ou touche **P** : un panneau flottant
au-dessus de la vue 2D montre la carte **telle qu'elle sera en jeu** (mêmes
murs, sols, plafonds et textures, portes et débris, fenêtres barricadées,
décor, luminaires, atouts, armes, boîte, courant, niveaux, ciel de la carte
au-dessus des pièces sans plafond), construite par le
**même code que la partie** (`MapLayoutExport`, `MeshMapGeometry`,
`MeshMapBuilder`, `MapProps.add_lamp`, et les fonctions de construction de
`Game` pour les objets de jeu), avec l'éclairage du jeu (`WorldLook`,
`RenderQuality`, grain de film).

- **Fenêtre** : glisser la barre de titre pour la déplacer, le coin en bas à
  droite pour la redimensionner ; **⛶** (ou double-clic sur le titre) :
  agrandie à tout l'éditeur ; **⧉** : détachée dans une vraie fenêtre (à
  mettre sur un deuxième écran ; la fermer la ramène dans l'éditeur) ;
  **✕** ou P : masquée. Position, taille, fenêtre détachée, caméra et
  options sont mémorisées (`_editeur.cfg`, clé `apercu`).
- **En direct** : après chaque modification (pose, déplacement, suppression,
  annuler / rétablir, propriétés), l'aperçu se met à jour tout seul 0,3 s
  après la dernière retouche. La conversion de la carte tourne **hors du fil
  principal** ; seuls les morceaux qui ont changé sont refaits
  (architecture, décor, lampes, objets de jeu), un par image, l'ancien
  restant affiché jusque-là : l'éditeur ne se fige pas. Une carte pas encore
  jouable (sans départ, sans fenêtre...) s'affiche quand même, avec la
  mention « aperçu indicatif ».
- **Fil de travail sans état partagé** (`MapPreviewWorld.Job`, règle
  `ThreadGuard` de ARCHITECTURE.md « Fils de travail ») : le fil principal
  prépare tout avant de le lancer (copie profonde de la carte, catalogue
  construit puis figé en lecture seule, langue des textes) ; le fil fait
  `MapRaster` → étapes du validateur utiles à la géométrie (dont le
  rattachement des leviers aux pièges) → `MapLayoutExport` sur SA copie, sans
  créer de nœud ni de ressource, sans lire d'autoload (`Settings`) ni de cache
  du fil principal (lot de vérification et cases intérieures de `MapRules`,
  statistiques de `WeaponDB` : refusés hors du fil principal, recalculés
  localement ou notés comme un bogue et signalés). Le fil principal ne
  construit l'aperçu qu'avec le résultat rendu. Vérifié par
  `tests/test_preview_thread.gd` (aucun accès noté, même description que sur
  le fil principal) et le scénario de contrainte `map_preview_stress` (60 s :
  un second fil calcule en boucle pendant que l'éditeur pose, glisse,
  vérifie, annule et vide ses caches à chaque image).
- **Caméras** (liste de la barre d'outils) :
  - **Orbite** : clic droit glisser pour tourner autour du point visé,
    molette pour zoomer, clic milieu glisser pour déplacer le point ;
  - **Vol libre** : touches de déplacement du jeu (ZQSD / WASD, celles des
    options), Maj pour aller plus vite, clic droit maintenu pour regarder,
    Espace / accroupi pour monter / descendre ;
  - **Joueur** : à hauteur d'yeux (1,62 m), avec la capsule, la gravité, les
    vitesses et le saut du joueur ; les murs, fenêtres et décor arrêtent,
    les portes fermées se traversent (pour visiter).
  - Les touches vont à l'aperçu quand la souris est dessus.
  - **⌖ Sélection** : centre la caméra sur l'élément choisi ; **Carte** :
    recadre sur toute la carte ; **Suivre la 2D** : la caméra vise ce que
    montre la vue 2D ; **Ctrl + double-clic** sur la carte 2D : la caméra va
    à cet endroit (un clic avec Ctrl ne pose rien tant que l'aperçu est
    affiché).
  - La vue 2D montre un **repère orange** : position de la caméra, son champ
    de vision et, en orbite, le point visé (estompé si la caméra est à un
    autre niveau).
- **Sélection** : l'élément choisi (jaune) et celui survolé dans la vue 2D ou
  la liste (bleu) sont surlignés dans l'aperçu, vus à travers les murs ; un
  **clic dans l'aperçu** choisit l'élément touché (rayon sur les collisions
  visibles), un double-clic le choisit et centre la caméra dessus.
- **Affichage ▾** : courant rétabli ou coupé (luminaires liés au courant),
  éclairage plein (tout voir, sans brume), plafonds masqués (vue de dessus
  en coupe), barrières invisibles, niveaux (tous, jusqu'au niveau affiché en 2D, ou seulement
  celui-là), résolution du rendu (100, 75, 50 ou 35 %, en plus de celle de
  la qualité graphique), pause quand l'éditeur n'a pas le focus.
- **Performances** : aperçu masqué, rien n'est construit ni rendu ; au repos,
  24 images/s au plus (chaque mouvement de caméra est rendu aussitôt) ;
  objets de jeu figés (ni son ni animation). Mesures : **DRAFT ARENA**
  (scénario `map_preview`, avec rendu) : conversion ≈ 0,15 s hors du fil
  principal, construction ≈ 17 ms (la toute première ≈ 0,2 s : chargement
  des modèles des machines), mise à jour visible ≈ 0,5 s après la retouche
  (délai de 0,3 s compris) ; un luminaire : seules les lampes, ≈ 11 ms.
  **Carte de 50 pièces** (test `test_update_time_on_a_50_room_map`) :
  conversion ≈ 1,4 à 2,5 s hors du fil principal, construction ≈ 80 à
  220 ms en 6 étapes (la plus longue, l'architecture, ≈ 60 à 150 ms), mise
  à jour visible ≈ 2 s après la retouche ; un luminaire : ≈ 20 à 30 ms sur le
  fil principal.

## 3. Ce que l'on pose (inventaire)

Les catégories et leurs objets viennent des **bases de données du jeu**
(`MapCatalog` lit `PerkDB`, `WeaponDB`, `KnifeDB`, `MysteryBox.COST`,
`PackAPunch.COST`, `ElectricTrap.COST`…) : un atout ou une arme murale ajouté
au jeu apparaît tout seul dans l'inventaire, avec son prix. Icônes dessinées
par code (`MapIcons`).

| Catégorie | Objets | Pose |
|---|---|---|
| Construction | Gomme, Pièce rectangle, Pièce polygone, Mur, Cercle / polygone régulier, Ellipse, Pièce triangle, Pièce en L, Mur courbe, Pilier / obstacle, Escalier qui monte (↑), Escalier qui descend (↓), Barrière invisible | glisser ou clic-clic (rectangle, formes, mur, mur courbe, pilier, escalier), clics successifs (polygone, barrière invisible : n'importe où) ; saisie au clavier |
| Ouvertures | Porte payante, Débris à dégager, Porte ouverte par le courant, Passage libre, Fenêtre à zombies | sur un mur (voir les règles) |
| Atouts | un distributeur par atout du jeu | contre un mur |
| Armes murales | chaque arme à prix mural, couteau de chasse, grenades | contre un mur |
| Boîte mystère | emplacement, emplacement de départ | format 15 : au sol n'importe où dans une pièce, tournée librement (R, anneau, Angle ; flèche = avant) ; près d'un mur (1,3 m), elle s'y colle face à la pièce (Alt : sans aimant) |
| Machines | Pack-a-Punch, interrupteur du courant, téléporteur, arrivée du téléporteur, poste central | contre un mur, ou au sol (téléporteur, arrivée) |
| Pièges | zone de piège électrique, levier | zone : glisser au sol ; levier : contre un mur, à moins de 10 m |
| Joueurs et apparitions | départ des joueurs, zombie qui sort du sol | au sol |
| Décor et obstacles | caisse, baril, tas de gravats, gros éboulement, mur effondré, débris épars, planches au sol, poutre tombée, lustre tombé, pile de caisses, tonneaux, sacs de sable, table et chaise renversées, chaise pliante, bureau, étagère, rangée de fauteuils de cinéma, fauteuil arraché, pupitre, projecteur de cinéma, chariot, épave de voiture ; format 11, objets des effets : bûches, foyer de pierres, planches calcinées, électrodes, bobine Tesla, flaque d'eau, petite flaque, torche murale, tuyau à vapeur, boîtier électrique ouvert, tuyau qui fuit, câble suspendu | au sol, pivote avec R (90°) ou au degré près (poignée, Angle) ; torche, tuyaux et boîtier contre un mur (hauteur réglable, comme une applique) ; câble au plafond |
| Prefabs de la carte (format 10) | « + Créer… » (grouper du décor posé), « Importer… » (modèle .glb / .gltf), puis les prefabs de la carte ouverte (⚙ régler, ✕ supprimer) | comme le décor ; rangés dans le dossier de la carte (`docs/MAP_OBJECTS.md` § 11) |
| Luminaires | lampe (historique), ampoule nue, suspension, néon, lustre, applique murale, lampe de bureau, projecteur de chantier, bougies, brasero | plafond, mur (applique) ou sol ; pivote avec R |
| Effets (format 10, sous-onglets ; effets purs et zones : format 11) | **Flammes** : petit feu, grand feu, flammes de baril, flamme de torche, incendie ; **Fumées** : fumée légère, fumée noire épaisse, jet de vapeur, brouillard au sol ; **Étincelles** : pluie d'étincelles, gerbe de soudure, court-circuit ; **Électricité** : arc électrique, arcs en boule, étincelles de câble ; **Eau** : goutte-à-goutte, filet d'eau, ronds dans l'eau ; **Ambiance** : poussière, braises, cendres, feux follets (115) | au sol, au mur ou au plafond, par-dessus n'importe quoi ; zone agrandie aux poignées ; aucun objet, aucune collision |

### Effets (format 10 ; effets purs et zones : format 11)

Une rangée de sous-onglets au-dessus de la grille de l'inventaire range les
22 effets (Flammes, Fumées, Étincelles, Électricité, Eau, Ambiance). Un effet
ne contient QUE de l'effet : particules, lumières animées, arcs électriques ;
**aucun objet** (format 11) et aucune collision, aucun dégât ; il ne gêne ni
la pose ni les trajets et se pose par-dessus le décor et les objets de jeu
(des flammes de baril sur un baril, une fumée sur des gravats). L'objet qui
va avec un effet est un **décor de l'onglet Décor** posé à part : bûches ou
foyer de pierres sous un feu, torche murale sous la flamme de torche, tuyau à
vapeur, boîtier électrique ouvert, électrodes, bobine Tesla, câble suspendu,
tuyau qui fuit, flaque d'eau (le panneau des propriétés de l'effet le
rappelle).

Chaque effet a une **zone** en mètres, dessinée sur le plan (rectangle
translucide en tirets, icône au milieu, dimensions écrites à côté quand il
est choisi) et centrée sur sa position : au sol et au plafond, largeur ×
profondeur, tournée avec lui (R, poignée ronde, champ Angle) ; au mur,
largeur le long du mur et hauteur. On l'agrandit aux **poignées** (4 coins
et 4 milieux ; au mur, ses 2 bouts : le côté opposé reste en place) ou dans
les propriétés (Largeur, Profondeur, Hauteur de zone pour les volumes :
brouillard, poussière, feux follets). Chaque effet a ses bornes (fumées de
0,5 à 20 m, brouillard de 2 à 40 m, flamme de torche de 0,2 à 0,6 m…). En
jeu, l'effet REMPLIT sa zone : une zone plus grande a plus de particules
(même densité, × intensité), jamais de plus grosses, jusqu'au plafond de
l'effet puis au budget de la carte ; ses lumières portent plus loin.
Autres propriétés : intensité, hauteur de pose, couleur (effets qui se
teintent : fumée légère, brouillard, électricité, feux follets). 64 effets
au plus par carte. L'aperçu 3D montre l'effet animé, choisi : sa zone
surlignée : la boîte de son VOLUME (format 13), où tout ce qu'il affiche
reste (étincelles et gouttes jusqu'au sol compris) ; une carte au format 12
ou moins est convertie au chargement (même taille, même place). Détails,
budget de particules et format : `docs/MAP_OBJECTS.md` §
12.

### Décor (prefabs) et luminaires

Tous décrits à un seul endroit, `MapCatalog.PREFABS` et `MapCatalog.LIGHTS`
(`scripts/editor/map_catalog.gd`) : emprise au sol (cases de 0,5 m), modèle
(`assets/models/kino/*.glb`, déjà livrés avec KINO) ou objet construit par le
jeu (`EditorPrefabs` : sacs de sable, table et chaise renversées, chariot,
épave de voiture, et les luminaires sans modèle), collisions.

- **Empreinte** dessinée dans l'éditeur (hachurée si le décor bloque), flèche
  du devant ; **R** pivote de 90° (la largeur et la profondeur s'échangent) ;
  la poignée de rotation et le champ Angle le tournent au degré près
  (emprise tournée, cases dont le centre est dedans pour la vérification).
- **Collisions** : chaque décor bloque ou non selon son modèle : « solide »
  (joueurs, zombies et balles : gravats, bureau, sacs de sable…), « barrière »
  (joueurs et zombies, les balles passent : fauteuils, tonneaux, lustre
  tombé…) ou « non » (débris épars, planches : on marche dessus). Toujours des
  `CollisionBox` du jeu (pavés du catalogue ou `<modèle>.collision.json`),
  jamais une collision de modèle Blender. Les cases d'un décor qui bloque sont
  pleines pour le validateur et pour les trajets des zombies.
- **Luminaires** : couleur, intensité (× 0,1 à 4), portée (2 à 20 m), « liée
  au courant » (faibles avant le courant, allumées en cascade quand on le
  rétablit ; sinon toujours allumées : bougies, brasero) et « vacille »
  (grésillement), réglés dans l'onglet Propriétés. Ils passent par le code
  commun des lampes (`MapProps.add_lamp` : `PowerGrid`, `LightFlicker`,
  `RenderQuality` pour les ombres et le fondu) ; leurs objets ne projettent
  pas d'ombre.

Règles de pose en plus (`MapRules.layer_of`) :
- décor et luminaires au sol : dans une pièce, sans toucher ses murs, sans
  chevauchement (sauf réglage « chevauchements décor / obstacles » de la
  carte, format 9) ; une **lampe de bureau** ou des **bougies** peuvent se poser
  **sur un meuble** qui a un dessus (`support` : bureau, chariot, sacs de
  sable) : la lumière monte à sa hauteur ;
- luminaires du plafond : dans une pièce ; ils surplombent le décor mais pas
  un autre luminaire du plafond ;
- applique : contre un mur plein de la pièce, face vers l'intérieur, à 2 m du
  sol (elle ne gêne pas les objets posés dessous).

### Prefabs de la carte (format 10)

En plus du catalogue, chaque carte peut avoir **ses propres prefabs**, rangés
dans son dossier (`prefabs/<pid>/prefab.json`, et `model.glb` pour un modèle
importé) : un **groupe** de décors du catalogue ou un **modèle** .glb / .gltf importé du disque
(« Importer… », copié dans la carte, sans limite de taille ni de nombre :
c'est au concepteur de gérer ses ressources ; collision : un pavé de
sa boîte englobante, solide, barrière ou aucune). Posés, ce sont des décors
comme les autres ; ils voyagent avec la carte (Enregistrer, Enregistrer sous,
copie d'un invité, archive .zip, carte partagée en multijoueur). Détails,
format et limites de sûreté : `docs/MAP_OBJECTS.md` § 11.

**Créer une prefab (groupe)** :

1. sélectionner le décor posé au sol à grouper (Maj + clic, ou un rectangle ;
   choisir une pièce prend aussi son contenu) ;
2. clic droit > **Créer une prefab…** (ou Ctrl+G, le bouton du panneau
   Propriétés, « + Créer… » de l'inventaire ; sans sélection, « + Créer… »
   fait glisser un rectangle autour du décor) ;
3. la boîte donne le **nom**, le **contenu** (nombre et liste des décors), ce
   qui **n'est pas repris et pourquoi**, le point d'ancrage, et « Remplacer ce
   décor par la prefab, à la même place » (coché : le décor devient une prefab
   posée, Ctrl+Z le rend ; décoché : la prefab est mise **en main**) ;
4. **poser** : la prefab est dans l'inventaire (E), catégorie « Prefabs de la
   carte » ; la prendre, puis cliquer sur le plan, comme un décor (R :
   pivoter).

Ce qu'une prefab peut contenir (format 10, `prefab.json` : des « parties »
de décor du catalogue) : **seulement du décor du catalogue posé au sol**. Sont
exclus, et listés avec leur raison dans la boîte : les **pièces** (une prefab
se pose dans une pièce : ni sol, ni murs, ni zone), les **portes, fenêtres et
passages** (ils relient des pièces ou donnent dehors), les **murs, piliers et
barrières invisibles** (construction), les **objets de jeu** (armes, atouts,
boîte, pièges, escaliers… : le jeu gère chacun), les **effets** et les
**luminaires** (ils ont leur propre zone ou leur lumière), le **décor mural
ou au plafond** et les **autres prefabs de la carte**. Le point d'ancrage est
le **centre de l'emprise** : la prefab se pose, s'aimante et pivote autour de
lui (le format ne garde pas d'autre point).

### Échelle et rotation 3D du décor (format 14)

Le décor (catalogue au sol, mural ou au plafond, prefabs de la carte) change
d'**échelle** et s'**incline**, comme dans Fusion 360 ou SolidWorks
(spécification `docs/EDITOR_SCALE_ROTATE.md`, maquette
`docs/editor_scale_rotate_mockup/`, détails `docs/MAP_OBJECTS.md` § 14) :

- **Poignées d'échelle** du décor choisi : en vue Dessus, coins jaunes
  (uniforme, coin opposé fixe ; Alt : depuis le centre), faces X rouges et Y
  vertes (un axe) ; en élévation, coins, côtés de l'axe de la vue et losange
  bleu de la hauteur. Au sol la base reste sur son support, un décor mural
  garde la face du mur, un décor du plafond son attache. Pas : 0,25 en grille
  1 m, 0,05 en grille fine, 0,01 sans grille (aimants ×1, ×0,5, ×2 et taille
  d'un décor voisin) ; Maj inverse ; taper « 1,5 » (facteur) ou « 3m »
  (dimension) pendant le geste, Entrée ; Échap annule.
- **Anneaux de rotation** : anneau Z bleu en vue Dessus (à la place de la
  poignée ronde du décor, des luminaires et des effets), anneau Y vert en
  vue Avant / Arrière, anneau X rouge en vue Droite / Gauche, les trois dans la
  vue 3D ; crans de 15° (Maj ou Alt : au degré), valeur tapée puis Entrée.
  Les anneaux tournent autour des axes du monde ; sens positif horaire vu de
  l'axe de bout. **R** : +90° autour de Z.
- **Panneau Propriétés** : Échelle (Uniforme et cadenas, X / Y / Z, « ↺ ×1 »)
  et Rotation (X / Y / Z, « Rester posé », « ↺ Remettre droit »). Un champ
  validé, un geste = une annulation.
- **Ce qui ne change jamais d'échelle** : objets de jeu, ouvertures,
  construction, luminaires, effets. Un prefab de la carte qui contient un
  objet de jeu est bloqué (cadenas gris, message qui nomme l'objet) ; une
  sélection qui mêle décor et objet de jeu aussi. Seul le décor posé au sol
  s'incline ; incliné, il reste posé (point le plus bas sur son support) et ne
  porte rien.

### Règles imposées à la pose

L'aperçu est **vert** si l'élément peut être posé, **rouge** sinon, avec la
raison à côté du curseur (`MapRules`) :

- **Pièce** : contour simple (les côtés ne se croisent pas), 1,5 m de côté au
  moins, côtés de 10 cm au moins, 128 sommets au plus, x et y positifs ; deux
  pièces peuvent **se toucher, jamais se recouvrir** (sans grille : une bande
  de recouvrement de moins de 1,5 cm compte comme un contact) ; une pièce
  **tracée par-dessus** d'autres les **découpe**, après confirmation
  (ci-dessous, « Pièce tracée sur une autre »). Ses murs sont
  générés sur son contour ; le bord commun de deux pièces collées (côtés
  parallèles à moins de 3 cm) devient **un seul mur mitoyen**. Par défaut,
  chaque pièce a sa propre zone.
- **Porte payante, débris, porte ouverte par le courant, passage libre** :
  seulement sur le **bord commun de deux pièces collées** de même altitude (une
  porte ne donne que sur une autre pièce) ; elle relie exactement ces deux
  pièces. Mur droit ou en biais, 0,5 m de mur plein à chaque
  bout et entre deux ouvertures. Prix réglable ; par défaut ceux de BO1 : la
  première 750, la deuxième 1000, les suivantes 1250. Largeur réglable (2 m par
  défaut ; BO1 : 1,5 à 3 m). Le passage libre n'a pas de porte : les deux
  zones sont « ouvertes l'une sur l'autre » (ou n'en font qu'une). Il est
  ouvert jusqu'au plafond le plus **bas** des deux pièces ; au-dessus, le mur
  continue jusqu'au plus haut (chaque face avec la texture de sa pièce).
- **Fenêtre à zombies** (barricade de 6 planches) : 1 m, sur un **mur
  extérieur** d'une pièce (pas un mur commun, pas le bord d'une mezzanine), avec
  2,5 × 3 m de vide dehors : le jeu y construit la cour où les zombies
  apparaissent, derrière la fenêtre.
- **Objets muraux** (atouts, armes, grenades, boîte, Pack-a-Punch, courant,
  poste central, levier, applique) : dans une pièce, accrochés au mur le plus
  proche, **face vers l'intérieur** ; il faut du mur plein derrière (pas une
  ouverture) et la place devant (boîte : 2 × 1 m ; atout, Pack-a-Punch :
  1,5 × 1 m ; arme : 1 × 0,5 m), sans chevaucher un autre objet. Ils se posent
  aussi sur un **mur libre** (outil Mur, droit, en biais ou épais, et mur
  courbe), **des deux côtés** : face tournée vers le côté du curseur, sans
  dépasser les bouts du mur, à 0,25 m au moins de la face des murs de la pièce
  (près d'un mur collé à la pièce, l'objet glisse le long du mur), sans toucher
  un autre mur libre (ni, dans le creux d'un mur courbe, ses segments voisins).
  Ils suivent leur mur libre quand on le déplace ou le tourne (et partent avec
  lui s'il est supprimé).
- **Boîte mystère** (format 15, docs/MAP_OBJECTS.md § 15) : au sol, n'importe
  où dans une pièce et tournée librement (emprise de 2 × 1 m tournée, à
  0,1 m au moins de la face des murs, sans chevauchement), ou contre un mur
  comme un objet mural : l'outil (et le glisser) la colle au mur quand le
  curseur en est à moins de 1,3 m, face à la pièce (Alt : sans aimant) ; si
  ce mur la refuse, elle reste au sol. En jeu, une boîte au sol s'achète de
  tous les côtés ; aucune boîte ne s'achète à travers un mur.
- **Objets au sol, pilier, escalier, zone de piège** : à l'intérieur d'une
  pièce, sans toucher ses murs, sans chevauchement (les lampes, au plafond,
  peuvent surplomber un objet ; un élément tourné compte par son rectangle
  englobant). L'escalier relie deux niveaux (`altitude` → `altitude_haut`,
  en sautant au besoin des niveaux) : départ (pied) sur le sol libre de sa
  pièce, arrivée sur le plancher libre d'une pièce à l'altitude d'arrivée
  (ou dans le mur commun de deux pièces côte à côte, ou sur le côté avec
  `sortie`), rien au-dessus des marches (trémie), ni dans la trémie, ni sur
  le départ ou l'arrivée d'un autre escalier (docs/MAP_OBJECTS.md § 4,
  « Plusieurs niveaux »). Réglage de la carte **Autoriser les chevauchements décor /
  obstacles** (format 9, onglet Propriétés sans rien de choisi) : le décor
  (caisses, barils, prefabs, luminaires) et les piliers peuvent alors se
  recouvrir entre eux ; les objets de jeu jamais (docs/MAP_OBJECTS.md § 10).
- **Barrière invisible** (format 9) : polygone de 3 à 64 sommets posé
  **n'importe où** (dehors, à cheval sur un mur, par-dessus un objet) ;
  seuls refus : côtés qui se croisent, côté de moins de 5 cm, moins de
  0,04 m² (coordonnées libres, négatives comprises). Hauteur : jusqu'au plafond, ou 0,5 m et plus (sans maximum, format 17) au
  dixième de mètre (docs/MAP_OBJECTS.md § 2).
- **Mur courbe** : 1 m de rayon au moins, ouverture de 5 à 360°, 1 à 64
  segments ; pas de rayon maximal (seule la mémoire du validateur borne un
  très grand arc).

### Pièce tracée sur une autre (découpe)

Tous les outils de pièce (rectangle, rectangle à 45°, polygone, cercle,
ellipse, triangle, L) peuvent tracer une pièce **par-dessus** une ou
plusieurs pièces de même altitude : la nouvelle « gratte » leur territoire
(`MapCarve`, soustraction de polygones `Geometry2D.clip_polygons`). Les
pièces des autres niveaux ne sont jamais découpées : une pièce qui en
recouvre une autre en plan à moins de 3,1 m d'écart d'altitude est refusée
(§ 4, « Superposition »).

- **Pendant le tracé** : la partie qui sera retirée de chaque pièce est
  **hachurée en orange**, avec son nom et la surface retirée sous le curseur
  (« découpe « Atelier » : −12 m² ») ; une pièce qui sera supprimée est
  hachurée **en rouge** ; une ouverture qui sera retirée est entourée de rouge.
  Une découpe impossible (escalier, contour) met le tracé en rouge avec la
  raison.
- **Au relâcher** (ou au clic qui ferme le polygone) : boîte **« Découper des
  pièces »** (français / anglais) qui dit tout ce qui va changer : « La pièce
  « Atelier » sera découpée (12 m² retirés). », pièce coupée en morceaux,
  pièce supprimée, ouvertures déplacées ou retirées, objets supprimés,
  éléments à revoir. **Découper** (Entrée) ou **Annuler** (Échap, croix) :
  Annuler ne crée rien. Le tracé et les hachures restent affichés tant que la
  boîte est ouverte.
- **Découper** : la nouvelle pièce est posée et chaque pièce recouverte perd
  la partie recouverte. **Une seule étape d'annulation** (Ctrl+Z défait tout)
  et un seul lot d'opérations pour la session de collaboration.

Choix faits (le format n'a **pas de trou** : une pièce est un contour simple) :

- **Nouvelle pièce entièrement dedans** (l'ancienne ferait un anneau) :
  l'ancienne est coupée en **deux morceaux** par une ligne de la grille de
  0,5 m qui traverse la nouvelle pièce ; la ligne choisie laisse la place
  d'un passage des deux côtés, ne coupe aucun objet et passe au plus près du
  milieu. Les deux morceaux gardent la **même zone** et sont reliés par un
  **passage libre** (aussi large que possible, 0,5 m de mur à chaque bout) sur
  chaque bord commun : la pièce reste d'un seul tenant pour le validateur.
- **Ancienne pièce coupée en plusieurs morceaux** (la nouvelle la traverse) :
  **une pièce par morceau**, mêmes réglages (altitude, plafond, plafond masqué,
  textures), noms « Atelier », « Atelier (2) »… ; le plus grand morceau garde
  l'identifiant. Un morceau qui ne touche pas les autres (ou sans place pour
  un passage) reçoit **sa propre zone**, copie de celle de la pièce (nom du
  morceau) : la boîte le dit.
- **Morceau trop petit** (moins de 1,5 m de côté ou 2 m², règles de
  `MapRules.check_room`) ou **trop mince** (moins de 0,6 m de large en
  moyenne) : retiré ; plus aucun morceau : la pièce est **supprimée** (pièce
  avalée), sa zone vide aussi. Un morceau dont le contour serait invalide
  (côté de moins de 10 cm, plus de 128 sommets) fait **refuser** la découpe
  (déplacer un peu la nouvelle pièce).
- **Zone de la nouvelle pièce** : la sienne, comme toute pièce posée (une
  zone par pièce) ; une porte la relie ensuite aux autres.
- **Contenu** (objets, décor, effets, luminaires, objets muraux) : il suit sa
  position ; celui de la partie découpée est désormais **dans la nouvelle
  pièce** (il bouge avec elle). Celui d'un morceau retiré, hors de toute pièce,
  est supprimé (compté dans la boîte).
- **Ouvertures** dont le mur disparaît : **déplacées** sur le bord commun le
  plus proche (1,6 m au plus) qui relie **les mêmes zones**, sinon **retirées**
  (listées dans la boîte). Une ouverture dont le mur devient celui de la
  nouvelle pièce reste où elle est (elle donne alors sur la nouvelle pièce) :
  la boîte le signale (« « Porte payante 750 » (Atelier ↔ Couloir) donnera
  désormais sur : Couloir ↔ Réserve »).
- **Zone de départ** : si la pièce avalée portait la zone de départ, celle-ci
  devient la zone de la nouvelle pièce (annoncé dans la boîte).
- **Plafonds de la carte** (256 pièces, 512 ouvertures, 64 zones) : une
  découpe qui les dépasserait (morceaux, passages, zones propres compris) est
  refusée.
- **Escaliers et trémies** : un escalier que la découpe rendrait invalide
  (pied, arrivée ou trémie) fait **refuser** la découpe, avec l'endroit et la
  raison. Les autres éléments devenus invalides sont gardés (en rouge) et
  listés « à revoir ».
- Déplacer, coller ou pivoter une pièce sur une autre reste **refusé** (seuls
  les outils de tracé découpent).
- **Claude (MCP)** : `editor_apply` d'une pièce qui en recouvre d'autres est
  refusé avec l'explication, sauf avec `"decouper": true` (la pièce passe
  alors les mêmes contrôles que le tracé : contour simple,
  1,5 m de côté ; sinon tout le lot est refusé) : la découpe est
  faite dans le **même lot** (une annulation) et détaillée dans le résultat
  (`decoupe`).

## 4. Pièces, zones, niveaux

Depuis le format 17, il n'y a **plus d'étages** : chaque pièce a sa propre
**altitude** (celle de son sol, en m) et un **niveau** n'est que l'ensemble des
pièces posées à la même altitude (à 5 mm près, `EditorMap.ALT_EQ`). Les
niveaux sont libres : de toute hauteur et de toute forme, demi-niveaux
compris, sans nombre maximal, sans pas imposé (l'interface aimante, le fichier
garde la valeur) ; une altitude peut être négative (sous-sol).

- **Pièce** (onglet Propriétés) : nom, zone, **Z** de la ligne Position (altitude du sol : déplace la
  pièce et tout son contenu, une étape d'annulation ; refusée avec la raison
  si elle recouvre une autre pièce de trop près ; une altitude nouvelle crée
  un niveau), **Hauteur sous plafond** (2,8 m au moins, sans maximum ; une
  note dit si une pièce posée au-dessus la coupe), case **Afficher le
  plafond** (décochée : plafond masqué, voir plus bas). La case « Double
  hauteur » n'existe plus : une **pièce haute** est simplement une pièce au
  grand plafond.
  **Textures** : sol, murs et plafond, parmi les surfaces du jeu
  (`WorldLook.SURFACES` : plâtre, béton, brique, bois, parquet, carrelage,
  pierre, pavés, moquette…) ou parmi les **textures de la carte** (images
  importées, format 16 : voir plus bas), avec un aperçu ; par défaut, celles
  de la zone. Un **mur mitoyen montre de chaque côté la texture de sa pièce**
  (le jeu construit les murs par demi-cases de 0,25 m). Sous une pièce posée
  au-dessus, on voit d'en bas le **plafond de la pièce du bas** (sa texture,
  juste sous la dalle) et, d'en haut, le sol de la pièce du dessus.
- **Zone** (onglet Zones) : un groupe de pièces qui s'ouvre d'un coup (ses
  fenêtres s'activent ensemble, comme les zones de BO1). Par défaut une zone
  par pièce. Renommer en français et en anglais (noms affichés en jeu selon la
  langue), textures par défaut du sol, des murs et du plafond, **fusionner** (les pièces d'une zone
  rejoignent une autre), **séparer** (une zone par pièce), **zone de départ**
  (★, ouverte au début). Les pièces d'une même zone doivent être reliées par
  un passage libre ; une zone peut s'étendre sur plusieurs niveaux (achat et
  textures communs).

### Superposition, pièces hautes et mezzanines

- **Deux pièces qui se recouvrent en plan** sont à **3,1 m au moins** l'une
  de l'autre en altitude (2,8 m sous plafond + dalle de 0,3 m,
  `EditorMap.MIN_STACK`) : refus à la pose et au déplacement, erreur du
  validateur pour un fichier écrit à la main. À la même altitude, la règle
  d'avant reste : elles se touchent sans se recouvrir (sinon, découpe : § 3).
- **Plafond réel** d'un endroit : le plus bas de son plafond réglé (altitude +
  hauteur sous plafond) et du **dessous de la dalle** de la première pièce
  posée au-dessus. Les trémies d'escalier et le vide d'une pièce haute ne sont
  pas des dalles.
- **Pièce haute** : une pièce **traverse** un niveau situé 3,1 m au moins
  au-dessus de son sol quand son plafond dépasse ce niveau de 2,1 m au moins :
  à ce niveau, son contour est un mur et son intérieur un vide (hachuré dans
  la vue Dessus) ; ses piliers et ses murs libres montent jusqu'en haut. Elle
  peut traverser plusieurs niveaux. Un demi-niveau posé à côté d'elle ne la
  coupe pas.
- **Mezzanine** : une pièce d'un niveau traversé, posée au-dessus du vide
  d'une pièce haute (3,1 m au moins plus haut) ; ses bords au-dessus du vide
  ont un garde-corps.
- **Mur mitoyen entre niveaux** : deux pièces côte à côte à des altitudes
  différentes partagent leur mur ; celui du haut monte au moins jusqu'au haut
  de celui du bas, et un mur monte jusqu'à la dalle du dessus si elle est à
  3 m au plus.
- **Portes, débris, passages** : seulement entre deux pièces de **même
  altitude** ; une pièce montée ou descendue garde ses portes vers une
  voisine restée en place, et le validateur les signale (« reliez deux
  niveaux par un escalier ») : rien n'est supprimé en silence. Une cour de
  fenêtre qui couperait le volume d'une pièce d'un autre niveau est une
  erreur.
- **Élément orphelin** (ouverture ou objet dont l'altitude ne correspond à
  aucune pièce) : signalé par le validateur.

### Plafond masqué et ciel de la carte

- Décocher **Afficher le plafond** d'une pièce (`sans_plafond`) : ni plafond
  dessiné ni collision au-dessus d'elle ; ses murs montent jusqu'à son plafond
  réglé ; pas de lampe automatique sous le ciel ouvert. Sous une pièce posée
  au-dessus, le dessous de la dalle reste dessiné. Rien n'empêche un joueur
  de sortir par le haut : c'est au concepteur de **fermer sa carte** (murs
  assez hauts, barrière invisible).
- Luminaires, effets et décor **accrochés au plafond** d'une pièce sans
  plafond : construits au plafond « virtuel » (altitude + hauteur sous
  plafond), avec un avertissement du validateur (« accroché à un plafond
  masqué : il flotte à X m »). Les élévations dessinent ce plafond en
  pointillés.
- **Ciel de la carte** (`carte.ciel`), vu au-dessus des pièces sans plafond,
  en jeu et dans l'aperçu 3D : **Sans fond (noir)** (défaut), **Ciel** (jour)
  ou **Nuit étoilée**, avec une **Luminosité** de 10 à 200 % (100 % par
  défaut). Il n'éclaire pas les pièces. Réglé dans les propriétés de la carte
  (rien de sélectionné, onglet Propriétés) ou dans l'onglet Niveaux.

### Coordonnées négatives, aucune limite

- On construit **où l'on veut** : x, y négatifs compris, sans étendue
  maximale, sans plafond ni hauteur maximale (décor, appliques, barrières,
  effets : seule une garde technique de 10 km, `MapVertical.TECH_Z`). La
  seule borne d'une carte est **technique** : la mémoire que demanderait la
  grille du validateur (cases × niveaux), refus propre et expliqué au-delà
  (§ 6, « Cartes perso en multijoueur »).
- Le validateur construit sa grille sur une copie décalée d'un multiple de
  0,5 m (`MapValidator.shift`) : mêmes cases, mêmes messages et même export
  qu'à la position d'origine ; une carte entièrement en positif n'est pas
  décalée. Les règles graduées, les textes de position et la liste des objets
  donnent les vraies coordonnées (négatives comprises).

### Interface des niveaux

- **Barre des niveaux** (barre du haut) : « ◄ Niveau 3,5 m (2/3) ▾ ► ».
  ◄ ► : niveau voisin ; le libellé est un **menu** de tous les niveaux, du
  plus haut au plus bas, avec leur nombre de pièces, et « **Autre
  altitude…** » (boîte d'altitude : un niveau vide est créé au besoin ; il
  n'est pas enregistré tant qu'il est vide). La vue Dessus édite le niveau
  affiché.
- **Raccourcis** : **Page préc. / Page suiv.** : niveau du dessous / du
  dessus ; **Maj + Page préc. / suiv.** (ou clic droit > « Descendre / Monter
  d'un niveau ») : la sélection va au niveau voisin (sans voisin : 3,5 m plus
  loin), une étape d'annulation, et la vue la suit ; **Alt + clic** (vue
  Dessus) : pièce empilée suivante sous le curseur, de la plus haute à la
  plus basse, et la vue va à son niveau. Dans une élévation, un clic sur une
  pièce va aussi à son niveau.
- **Plan** : **fantôme** du niveau du dessous en transparence (ses sommets
  aimantent même sans grille), vides des pièces hautes **hachurés** (sauf
  sous une mezzanine), option **pièces du dessus en pointillés**.
- **Onglet Niveaux** : liste du plus haut au plus bas (altitude, pièces,
  zones ; clic : choisir, double-clic ou **Voir ce niveau** : l'afficher) ;
  **Altitude du sol** du niveau et **Déplacer de … m** (tout ce qui y est
  posé suit, et l'arrivée des escaliers qui y montent) ; **Dupliquer
  au-dessus** (écart : plus haut plafond du niveau + dalle, 3,1 m au moins ;
  escaliers non copiés) ; **Nouveau niveau vide à … m** ; **Supprimer le
  niveau…** (confirmation ; emporte ce qui y est posé et les escaliers qui y
  arrivent ; Ctrl+Z le rétablit) ; cases du fantôme et des pointillés ; ciel
  de la carte.
- **Glissement vertical** (élévations) : une pièce (ou un groupe qui en
  contient une) se glisse librement vers le haut ou le bas, au pas de 0,25 m
  sur l'écart, avec des **aimants** (sols des autres niveaux, juste au-dessus
  ou au-dessous des pièces recouvertes) ; l'**étiquette « +3,50 m »** d'un
  niveau sur la règle Z déplace tout le niveau. Un déplacement refusé est
  nommé ; la dernière place correcte est gardée.
- **Escaliers quand une pièce bouge verticalement** : un escalier rattaché à
  la pièce par son **pied** n'emporte que son pied (`altitude` suit) ; un
  escalier qui **arrive** dans la pièce (une case d'arrivée dans son contour)
  n'a que son arrivée qui suit (`altitude_haut`) ; les deux pièces déplacées
  ensemble : tout l'escalier suit. L'escalier est revérifié (son côté de
  sortie ne change jamais tout seul) ; une arrivée qui ne serait plus
  au-dessus du pied, ou plus sur une pièce, fait refuser le déplacement.
- **Escaliers** : **qui monte** (↑) : tracé sur le niveau du pied, il monte
  dans le sens du glisser (du pied vers le haut) jusqu'au premier niveau
  au-dessus dont une pièce contient l'arrivée. **Qui descend** (↓) : tracé
  depuis le niveau du haut, du haut (où l'on est) vers le bas ; il est
  enregistré avec son pied au premier niveau plus bas dont une pièce le
  contient et son arrivée (`altitude_haut`) ici. Le vide au-dessus des
  marches (trémie) est automatique sur chaque niveau traversé ; un escalier
  peut **sauter des niveaux**. Propriétés **Arrivée : altitude** (niveaux
  nommés comme dans le menu) et **Sortie en haut** : en face, à gauche, à
  droite. Si le haut des marches touche un mur, la pose choisit une sortie
  sur le côté (droite, puis gauche) et le dit (« Arrivée sur le côté
  droit… ») ; docs/MAP_OBJECTS.md § 4. Un escalier se voit (« monte à
  3,5 m » / « descend à 0 m ») et se choisit depuis ses deux niveaux.

### Anciennes cartes (format 16 et avant)

Une carte à étages est **convertie au chargement** (`EditorMap.migrate_levels`,
en dernier dans `_migrate` ; une carte reçue est d'abord contrôlée avec le
schéma figé de son format, puis convertie) :

- sol de l'étage k = `etages[k].sol` (absent : k × 3,5 m) ; chaque pièce,
  ouverture et objet reçoit `altitude` = sol de son étage (sans `etage` :
  étage 0) ; un escalier reçoit `altitude_haut` = sol de l'étage du dessus
  (au dernier étage : pied + 3,5 m, l'erreur reste signalée) ;
- la hauteur sous plafond de l'étage est écrite sur chaque pièce qui n'avait
  pas la sienne (seulement si elle diffère de 3,2 m) ;
- **double hauteur** → plafond jusqu'en haut de l'étage du dessus (sol +
  hauteur de l'étage k+1 − sol de l'étage k) ; au dernier étage, la clé est
  simplement retirée ;
- une pièce **entièrement** recouverte par des pièces de l'étage du dessus
  voit son plafond porté au moins jusque sous leur dalle (avant, son plafond
  était cette dalle) ;
- `carte.etages`, `etage` et `double_hauteur` disparaissent.

**Différences** : l'export en jeu de toutes les cartes de référence (DRAFT
ARENA, cartes des tests) est **identique** à celui du code du format 16
(`tests/test_levels_reference.gd`, références
`tests/fixtures/levels/*_layout_f16.json`, aucune différence admise). Ce qui
change : le fichier (clés ci-dessus, enregistré au format 17) ; le validateur
contrôle les pièces empilées par paires (plus d'« étages trop rapprochés ») ;
un ancien indice d'étage n'a plus de sens (il changerait dès qu'une pièce est
posée plus bas : l'outil MCP refuse `floor`, docs/MCP.md § 3.1) ; plus de
maximum de 8 étages ni de plafond de 9 m. DRAFT ARENA est livrée au format
17 ; l'originale est gardée dans `tests/fixtures/maps/legacy_draft_arena/`.

### Textures de la carte (format 16)

Des **images à soi** (PNG ou JPEG) pour les sols, murs et plafonds, rangées
**dans le dossier de la carte** et transportées avec elle (Enregistrer,
Enregistrer sous, copie de récupération, archive .zip, carte partagée en
multijoueur, cache). Code : `scripts/game/map/map_texture_lib.gd` (format,
contrôle, matériau), `scripts/editor/map_texture_tools.gd` (éditeur),
`scripts/editor/collab/map_agent_textures.gd` (Claude, MCP).

**Dans l'éditeur** : chaque choix de texture (Propriétés d'une pièce : Sol,
Murs, Plafond ; formulaire d'une zone) liste les surfaces du jeu, puis la
section **Textures de la carte** (aperçu de l'image, nom), puis :

- **Importer une texture…** : l'explorateur du système (`FilePick`), une
  image `.png`, `.jpg` ou `.jpeg`. Elle est vérifiée (vraie image décodée,
  16384 px de côté au plus), **copiée** dans la carte (écrite à
  l'enregistrement dans `textures/<id>/` : le fichier d'origine n'est plus
  lu) et posée aussitôt sur la partie choisie. **Aucune limite** de nombre ni
  de taille : c'est au concepteur de garder sa carte légère (une texture de
  1024 px suffit presque toujours ; chaque image voyage avec la carte).
- **Gérer les textures…** : toutes les textures de la carte (aperçu, nom,
  `map:<id>`, nombre d'utilisations), **⚙** et **✕** sur chacune.
- **⚙** (aussi à côté d'une liste dont la valeur est une texture de la
  carte) : **nom**, **taille du motif** (m : largeur d'une répétition de
  l'image ; la hauteur suit ses proportions ; même échelle au sol, aux murs
  et au plafond), **rugosité** (0 brillant, 1 mat), **métal**, **teinte**
  (multiplie l'image), **carte des normales** (Importer… / Retirer,
  convention OpenGL) et **Supprimer la texture…**.
- **Supprimer** : refusé tant qu'une pièce ou une zone l'utilise, sauf
  confirmation : elles reprennent leur surface par défaut (zone, ou celle du
  jeu) dans une modification annulable (Ctrl+Z).

Choisir une texture pour une pièce ou une zone est une modification normale
(Ctrl+Z). La **bibliothèque** des textures (import, réglages, suppression)
n'est pas dans l'historique, comme les prefabs de la carte. En session
collaborative, **seul l'hôte** la change ; les invités reçoivent la carte
sans les images (surface par défaut dans leur aperçu 3D,
docs/MAP_COLLAB.md § 6). Claude la pilote par MCP (`editor_texture_list`,
`editor_texture_import`, `editor_texture_update`, `editor_texture_delete`,
`editor_texture_import_from_map` ; docs/MAP_COLLAB.md § 5.2) et l'applique
avec `editor_apply`.

**Format** : dossier de la carte

```
textures/<id>/texture.json   définition
textures/<id>/image.png      l'image (ou image.jpg)
textures/<id>/normal.png     carte des normales facultative (ou normal.jpg)
```

`<id>` : 1 à 32 caractères parmi a-z, 0-9, `_`, sans `__` ni `_` au début
ou à la fin (`MapTextureLib.tid_ok`). Une pièce la cite par
`"surface_sol": "map:<id>"` (ou `surface_murs`, `surface_plafond`), une
zone par `"sol"`, `"murs"`, `"plafond"`. Exemple :

```json
{
 "format": 1,
 "nom": {"fr": "Carrelage bleu", "en": "Blue tiles"},
 "taille": 1.2,
 "rugosite": 0.4,
 "couleur": "#6f7c95"
}
```

| Clé | Valeur |
|---|---|
| `format` | 1 |
| `nom` | `{"fr", "en"}` (64 caractères, sans balise) |
| `taille` | largeur d'une répétition de l'image, m (0,05 à 100) |
| `rugosite`, `metal` | 0 à 1 (absents : 0,85 et 0) |
| `teinte` | `#rrggbb` multipliée à l'image (absente : `#ffffff`) |
| `couleur` | couleur moyenne de l'image (calculée à l'import : aperçus sans image) |

Réglages jamais écrits à leur valeur par défaut. Dans les textes d'une carte
(`EditorMap.file_texts`, paquet réseau au format 2, cache), une texture est
une entrée de plus : `textures/<id>/texture.json` (texte) et
`textures/<id>/image.png` (base64 en mémoire et dans le paquet réseau,
fichier binaire sur le disque et dans l'archive .zip). Une carte sans
texture n'a pas de dossier `textures/` (formats 1 à 14 lus tels quels).

**En jeu** : `MapRaster` traduit `map:<id>` en matériau `tex-<id>` (et
emporte la texture dans la description du jeu, clé `map_textures`) ;
`MeshMapBuilder` décode l'image (`Image.load_png_from_buffer` /
`load_jpg_from_buffer`, aucun pipeline d'import : marche dans le jeu
exporté), crée la texture avec ses mipmaps (filtrage anisotrope, répétition)
et le matériau `assets/shaders/map_texture.gdshader` : l'image est répétée
en **coordonnées du monde** comme les surfaces du jeu (aucune couture entre
morceaux, même échelle partout ; au mur, le bas de l'image touche le sol et
elle se lit dans le bon sens des deux côtés). Une texture **absente**
(citée mais pas dans la carte, ou sans image) ou **illisible** : la surface
par défaut (celle de la zone, sinon béton / plâtre / plafond sombre), avec
un **avertissement** de la vérification.

**Sûreté** (cartes reçues, `CustomMapGuard.check_texts` →
`MapTextureLib.check_entries`) : noms d'entrée exacts, `texture.json` en
liste blanche, une seule image et au plus une carte des normales par
texture, aucune image sans `texture.json`, base64 strict, signature PNG /
JPEG conforme au nom, côtés lus dans l'en-tête (16384 px au plus) puis vrai
décodage par `Image` ; une texture citée mais absente n'est pas un refus
(surface par défaut). Aucun quota (seules les bornes générales du paquet,
40 Mo, et des archives, 30 Mo, s'appliquent). Preuves :
`tests/test_map_textures.gd` ; captures pour revue :
`tests/autotest/map_textures_look.gd` (`@rendu`, hors check).

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
- escalier dont le départ ou l'arrivée tombe dans un mur, le vide, une
  trémie ou un autre escalier (le message dit quoi, où, et à quel niveau ;
  les cases en cause sont montrées), sens ambigu (fichier sans « monte »),
  trop étroit (1,5 m), trop raide (40°), trémie occupée (escalier, pilier,
  décor au-dessus des marches), plancher d'un niveau traversé au-dessus des
  marches, moins de 2,1 m de passage au-dessus des marches, de l'arrivée ou
  du palier ; vide de trémie ouvert sur le vide ;
- pièces empilées à moins de 3,1 m l'une de l'autre, plafond trop bas ; porte,
  débris ou passage entre deux altitudes ; cour de fenêtre qui coupe le volume
  d'une pièce d'un autre niveau ; élément orphelin (aucune pièce à son
  altitude). Avertissement : élément accroché à un plafond masqué (il flotte).

Avertissements et indicateurs d'amusement (BO1, jamais bloquants) : boucles
entre zones et coût pour les ouvrir, blocs autour desquels on tourne
(« training », 25 à 40 m de tour), impasses (le départ doit avoir 2 sorties),
passages obligés, courbe d'ouverture (la porte la moins chère d'abord ;
première porte à 750-1000), emplacements de boîte (3 au moins, dans plusieurs
zones), atouts et coût pour les atteindre, coin TITAN BREW (rôle du
Juggernog : jamais dans la salle de départ), arme bon marché et LAZARUS au
départ, distance à pied au plus loin d'une fenêtre (25-30 m au plus).

## 6. Enregistrer, reprendre, partager

### Enregistrement explicite et récupération

Le dossier de la carte n'est écrit **que** par Fichier > **Enregistrer**
(Ctrl+S), **Enregistrer sous** (Ctrl+Maj+S) et le premier enregistrement
d'une nouvelle carte (`MapUnsaved`, `MapEditor.save`). Rien d'autre n'y
touche : ni les modifications (les siennes, celles des autres participants,
celles de Claude par MCP, qui marquent seulement la carte modifiée ; il n'y
a pas d'outil MCP d'enregistrement), ni TESTER, ni la fermeture.

- **Étoile « * »** après le nom de la carte (barre du haut) : modifications
  non enregistrées. Elle compare le contenu de la carte à celui du dernier
  enregistrement (empreinte `MapUnsaved.signature`, indépendante de l'ordre
  des éléments) : annuler (Ctrl+Z) jusqu'à l'état enregistré l'efface ; une
  archive importée ou la carte ouverte supprimée du disque restent « à
  enregistrer » jusqu'au prochain Enregistrer.
- **Confirmation** avant de perdre des modifications non enregistrées :
  fermer la fenêtre (croix, Alt+F4), Retour au menu principal, Nouvelle carte,
  Ouvrir (ou Cartes récentes) une autre carte, Importer une archive,
  Collaboration > Rejoindre (la carte de l'hôte remplacerait la vôtre). Boîte
  « Modifications non enregistrées » : **Enregistrer** (Entrée), **Quitter
  sans enregistrer**, **Annuler** (Échap). Si l'enregistrement échoue, on
  reste ; une carte jamais enregistrée (ou un exemple livré) ouvre
  Enregistrer sous et l'action n'a pas lieu (enregistrer, puis recommencer).
  Quitter la session en tant qu'hôte ne perd rien (la carte reste ouverte) :
  pas de confirmation.
- **TESTER** n'enregistre pas : la carte telle qu'elle est est écrite dans une
  copie de travail (`user://maps/_tester/`, jouée sous l'identifiant
  `perso:_tester`, effacée au retour) ; en solo, la session d'édition (carte,
  historique d'annulation) est gardée pendant la partie et reprise au retour,
  étoile comprise (comme TESTER à plusieurs, docs/MAP_COLLAB.md § 5.3).
- **Copie de récupération** (`user://maps/_recuperation/` : cinq JSON et
  `meta.json` avec le dossier d'origine, le nom et la date ; jamais dans la
  carte) : écrite toutes les 60 s s'il y a des modifications non enregistrées
  nouvelles, et juste avant TESTER. Effacée après un enregistrement réussi,
  « Quitter sans enregistrer » et toute sortie sans modification en attente.
  Si elle est encore là au lancement suivant (plantage, fermeture forcée, jeu
  fermé pendant un TESTER), l'éditeur propose **Récupérer** (Entrée, et aussi
  Échap ou la croix : rien n'est perdu) ou **Ignorer** (la copie est
  effacée), avec le nom de la carte et la date de la copie. Récupérée, la
  carte revient dans son dossier d'origine, modifiée (étoile) : Enregistrer
  l'y écrit (dossier d'origine repris seulement s'il est une carte du
  dossier des cartes, `MapUnsaved.source_ok` ; sinon elle revient non
  enregistrée). Tant que la question est posée, la copie n'est ni écrasée ni
  effacée ; une copie périmée (annulé jusqu'à l'état enregistré, autre carte
  ouverte) est effacée.
- **Enregistrer sous** propose un nom libre (`nouvelle_carte_2`...) et
  demande « La carte « X » existe déjà. La remplacer ? » avant d'écrire dans
  le dossier d'une AUTRE carte. L'ancien dossier `_autosave` des versions d'avant est proposé de
  la même façon.
- **Collaboration** : seul l'hôte enregistre. Un invité ne peut pas écrire la
  carte de l'hôte, n'a ni confirmation (la carte n'est pas la sienne) ni
  copie de récupération ; son étoile suit les enregistrements de l'hôte
  (message « saved »). Un invité qui quitte la session garde une copie sans
  dossier, sans étoile (rien à lui à confirmer tant qu'il ne la modifie pas).

- **Enregistrer** (Ctrl+S) : dans le dossier des cartes du joueur,
  `user://maps/<id>/` (sous Windows :
  `%APPDATA%\Godot\app_userdata\Call of Claude Zombie\maps\<id>\`), aussi
  depuis le `.exe`. `<id>` est tiré du nom de la carte ; **Enregistrer sous**
  choisit le dossier. Un exemple livré (DRAFT ARENA) s'ouvre en lecture seule :
  Enregistrer en fait une copie.
- **Supprimer une carte** : Fichier > Ouvrir, choisir une de ses cartes puis
  **Supprimer** (ou la touche Suppr) ; confirmation « Supprimer
  définitivement la carte « X » ? ». Le dossier entier part
  (`EditorMap.delete_map`) ; refusé (et noté dans la console) pour les
  exemples livrés (bouton grisé), les dossiers internes (`_recuperation`,
  `_tester`, `_autosave`...), tout
  chemin qui n'est pas un dossier de carte directement dans le dossier des
  cartes (`..`, ailleurs sur le disque) et tout dossier contenant un lien
  symbolique. Si c'est la carte ouverte, elle reste à l'écran, non enregistrée
  et sans dossier (le prochain Enregistrer en redonne un) ; sa copie de
  récupération est effacée (puis réécrite sans dossier d'origine).
- **Session de collaboration** (docs/MAP_COLLAB.md) : ouvrir ou enregistrer
  la carte est l'affaire de l'**hôte**. Chez un invité, Fichier > Nouvelle,
  Ouvrir, Enregistrer, Enregistrer sous, Exporter / Importer et Cartes
  récentes sont grisés (« Réservé à l'hôte de la session ») et leurs
  raccourcis (Ctrl+N, Ctrl+O, Ctrl+S, Ctrl+Maj+S) refusés avec un message dans
  la barre d'état ; pas de copie de récupération non plus. Tout redevient
  possible dès que l'invité quitte la session.
- **Cartes récentes** : menu Fichier (`user://maps/_editeur.cfg`).
- **Choix d'un fichier du disque** (Exporter / Importer une archive, Importer
  un modèle de prefab) : l'**explorateur du système** s'ouvre (Explorateur
  Windows, Finder, portail du bureau sous Linux ; `FilePick`,
  `DisplayServer.file_dialog_show`), avec le filtre d'extension, le dossier
  Documents au départ et, à l'export, le nom proposé (`<id>.zip`, extension
  ajoutée si elle manque). Il est asynchrone et rend un chemin absolu, qui
  repasse par les contrôles habituels ; annulé : rien ne change. La fenêtre
  de fichiers de Godot ne sert que de repli quand le système n'a pas de
  dialogue natif (lancement `--headless`, Linux sans portail). Ouvrir et
  Enregistrer sous restent les fenêtres de l'éditeur : elles listent le
  dossier des cartes, pas le disque. Tests : `FilePick.native_override` et
  `FilePick.native_show` simulent l'explorateur, jamais de vraie fenêtre.
- **Archive .zip** : Fichier > Exporter / Importer ; l'archive contient les cinq
  JSON à la racine (ZIPPacker / ZIPReader). Une archive importée s'enregistre
  comme une nouvelle carte. Elle est contrôlée **avant** toute décompression
  (`EditorMap.import_zip`, `zip_entries` lit le répertoire central) : 2 Mo au
  plus, 32 entrées au plus, seulement les cinq JSON (à la racine ou dans un
  seul dossier), aucun chemin piégé (`..`, `/` en tête, `\`, `:`), chaque
  fichier 2 Mo au plus une fois décompressé (bombe zip refusée) ; sinon elle
  est refusée avec la raison. Les fichiers d'un dossier de carte sont lus
  avec la même limite (`EditorMap.read_text`), le `meta.json` de la
  copie de récupération avec 256 Ko. Format 10 : l'archive porte aussi les
  prefabs de la carte (`prefabs/<pid>/prefab.json`, `model.glb`, dans le
  même dossier que les cinq JSON) ; elle n'a alors pas de taille maximale
  (aucun quota de modèles ; seulement la structure .zip sans ZIP64 : 4 Go,
  65 535 entrées ; 64 Ko par `prefab.json`) et seul son répertoire central est
  lu avant d'extraire (`EditorMap.zip_directory`, jamais l'archive entière) ;
  les entrées de prefab ne comptent pas dans les 32 entrées. Un modèle de
  plus de 16 Mo comprimé plus de 100 fois est refusé (bombe zip).
- **Identifiant de carte** (nom de dossier) : 1 à 48 caractères parmi `a-z`,
  `0-9` et `_` (`EditorMap.valid_id`) ; `EditorMap.map_dir` refuse tout autre
  identifiant (« perso:../x » n'est pas une carte).
- **Jouer** : ▶ **TESTER** vérifie et lance une partie solo sur la carte telle
  qu'elle est, sans l'enregistrer (copie de travail `perso:_tester`) ; la fin
  de la partie ramène dans l'éditeur, sur la même carte, avec son historique
  d'annulation. Les cartes jouables de `user://maps` apparaissent aussi dans l'écran
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
  géométries sont identiques partout. Format 10 : une carte avec des
  **prefabs de la carte** a un paquet au format 2 (les entrées
  `prefabs/<pid>/prefab.json` et `prefabs/<pid>/model.glb` en base64 en plus,
  1 Gio au plus : borne technique d'un paquet en un seul bloc ; avant de le
  recevoir ou de le contrôler, chacun vérifie qu'il a la mémoire libre, environ
  20 fois la taille du paquet, sinon refus « pas assez de mémoire ») ; une
  carte sans prefab garde exactement le paquet et
  l'empreinte d'avant. Contrôle des prefabs : `docs/MAP_OBJECTS.md` § 11.
- **Cache** : le dossier est nommé par l'empreinte (jamais par un nom venu de
  l'hôte) ; une carte déjà en cache n'est pas retéléchargée (elle est
  revérifiée : empreinte recalculée, contrôle complet) ; 32 cartes au plus,
  les plus anciennes sont effacées.
- **Contrôle de légitimité** (`scripts/game/map/custom_map_guard.gd`), à la
  réception, à l'import d'une archive et à l'ouverture d'une carte locale pour
  jouer. Une carte n'est **que des données** : jamais `load()`,
  `ResourceLoader`, `.tres`, `.tscn`, script ni image venant du réseau ou d'une
  archive (une ressource Godot peut embarquer du code) ; les textes sont lus en
  UTF-8 strict puis par le lecteur JSON du moteur. Seule exception (format
  10) : les modèles `.glb` des prefabs de la carte, vérifiés octet par octet
  (en-tête, JSON, aucune adresse externe, images PNG / JPEG de 16384 px de
  côté au plus) puis lus par `GLTFDocument`, qui ne crée ni script ni ressource
  du projet. Limites dures :

  | Limite | Valeur |
  |---|---|
  | Paquet (et total des cinq fichiers) | 2 Mo (avec des prefabs, format 10 : 1 Gio, borne technique, et assez de mémoire libre : `CustomMapGuard.memory_ok`) |
  | Morceaux réseau | 16 Ko (1 Ko au moins) |
  | Archive .zip | sans prefab 2 Mo ; avec des prefabs, structure .zip seulement (4 Go, 65 535 entrées, pas de ZIP64) ; tailles décompressées lues avant d'extraire, bombe zip refusée |
  | Prefabs de la carte (format 10) | **aucun quota** (nombre de prefabs et de modèles, taille, triangles) ; sûreté : structure .glb, aucune adresse externe, extensions admises, images PNG / JPEG de 16384 px au plus (`docs/MAP_OBJECTS.md` § 11) |
  | Profondeur JSON | 6 (lue avant l'analyse) |
  | Pièces / ouvertures / objets / zones | 256 / 512 / 2048 / 64 ; niveaux : aucun maximum (format 16 et avant : 8 étages, schéma figé) |
  | Sommets | 128 par pièce (un cercle de 64 points et de la marge), 4096 en tout |
  | Coordonnées | format 17 : nombres finis, **négatifs compris, sans étendue maximale** ; seule garde, technique : la mémoire de la grille du validateur (cases × niveaux, 1 Gio au plus, `CustomMapGuard.grid_bytes`), refus expliqué au-delà ; somme des rectangles englobants des pièces bornée par la même garde (≈ 2,8 millions de m²) |
  | Formes (format 4) | forme d'une pièce : type connu, centre (nombres finis), rayons 0,1 m à 10 km (garde technique), 3 à 64 points (entier), angle 0 à 360, branches 0,2 à 0,8, aucune autre clé ; mur courbe : rayon 1 m à 10 km, ouverture 5 à 360°, 1 à 64 segments ; rotation `rot` : entier de 0 à 359 |
  | Niveaux (format 17) | `altitude` et `altitude_haut` : nombres finis, sans borne ; plafond d'une pièce 2,8 m au moins, sans maximum ; portes 1,5 à 10 m. Format 16 et avant (schéma figé) : sol d'étage −20 à 200 m, hauteur 2 à 30 m, plafond d'une pièce 2,8 à 9 m |
  | Hauteurs de pose (format 12) | `z` d'un décor, `hauteur` d'un luminaire, d'un effet ou d'une barrière : 0 à 10 km (garde technique `MapVertical.TECH_Z`, plus de maximum de 30 m depuis le format 17) ; `descente` 0 à 3 m |
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
  plus. **Noms** : pas de
  caractère de contrôle ni de contrôle bidirectionnel, pas de `[` `]` (BBCode),
  `<` `>`, `{` `}`, `\` ni `..` ; affichés dans des `Label` (jamais
  interprétés), nettoyés une seconde fois à l'affichage. Enfin la carte doit
  passer le **validateur de jouabilité** de l'éditeur (`MapRaster` +
  `MapValidator`).

### Format des fichiers

Cinq fichiers JSON dans le dossier de la carte (ou à la racine de l'archive),
plus, format 10, le dossier `prefabs/` des prefabs de la carte s'il y en a
(`docs/MAP_OBJECTS.md` § 11) et, format 16, le dossier `textures/` des
textures de la carte (§ 4, « Textures de la carte »). Une entrée par ligne (diffs lisibles). Coordonnées en **mètres** dans le plan
de l'éditeur : x vers l'est, y vers le sud, x et y positifs ; le jeu place la
carte en (x + 4,25 ; z = y + 4,25). Chaque élément a un **identifiant stable**
(`p1`, `o3`, `a2`…). Les nombres entiers s'écrivent sans décimale.

## 2 quater. Vues multiples : élévations, ViewCube, dispositions

Conception complète et écarts de la réalisation : `docs/EDITOR_VIEWS.md`.

- **Plans** : Dessus (le plan, où l'on pose), **élévations** Avant (caméra au
  sud, regard vers le nord), Arrière, Gauche, Droite, et Dessous ; **3D**
  (l'aperçu en direct, intégré dans une fenêtre : une seule 3D, le panneau
  flottant revient quand aucune fenêtre n'est en 3D).
- **Élévation** : tous les niveaux empilés, chaque élément à sa vraie
  hauteur (plafond réel sous la dalle du dessus, pièces hautes, plafond masqué
  en pointillés, portes de
  `hauteur_portes`, fenêtres de l'allège au linteau, escaliers d'un sol à
  l'autre, objets muraux, décor d'après sa hauteur, luminaires et effets à
  leur hauteur avec un trait jusqu'à leur accroche), dessinés du plus
  lointain au plus proche, les lointains estompés ; lignes de niveau (sols
  pleins, plafonds en tirets) et étiquettes « 0,00 m », « +3,50 m »
  (niveau affiché en or ; glisser une étiquette déplace le niveau) ;
  « niveaux : » de l'en-tête : tous, jusqu'au niveau
  affiché, seulement celui-là ; **coupe** (tranche de profondeur, le reste à
  15 % et sans clic). Un clic choisit (sélection commune à toutes les
  vues ; sur une pièce, la vue Dessus va à son niveau) ; la **pose reste en
  vue Dessus**.
- **Édition verticale** (en élévation) : un glissement déplace sur les deux
  axes de la vue. Hauteur de pose continue pour les effets, luminaires et
  décors (aimants nommés en grille fine et en libre : sols, plafonds,
  dessous de dalle, haut des portes, allège, linteau, dessus du décor sous
  l'élément ; changer de niveau en passant un sol ou un plafond) ; altitude
  libre pour les pièces (pas de 0,25 m sur l'écart, aimants : sols des autres
  niveaux, au-dessus ou au-dessous des pièces recouvertes ; § 4), niveau
  aimanté sur les sols pour les escaliers,
  piliers, murs, pièges, objets de jeu ; les ouvertures suivent leur mur.
  Cotes en direct (hauteur au-dessus du sol, écart en or, distance au mur),
  position d'avant en pointillés ; une action = un Ctrl+Z.
- **Panneau Propriétés** : ligne **Position** X, Y, Z (Z : hauteur de pose en
  m au-dessus du sol, sinon la liste des niveaux ; Z d'une pièce : son
  altitude) ; un champ validé = une
  annulation.
- **Vues liées** (menu Disposition, cochée par défaut) : zoom commun, centre
  commun sur l'axe partagé (X entre Dessus et Avant, Y entre Dessus et
  Droite, Z entre Avant et Droite). **Coupe partagée** entre les élévations
  de même direction (option).
- **Mémorisé** dans `_editeur.cfg` (clé `vues`) : disposition, plan et plan
  d'origine de chaque fenêtre, proportions, liaison, coupes, niveaux montrés
  (pas le zoom ni le centre : chaque vue se recadre à l'ouverture).

**`carte.json`** — la carte :

```json
{
 "format": 17,
 "id": "draft_arena",
 "nom": {"fr":"DRAFT ARENA","en":"DRAFT ARENA"},
 "description": {"fr":"…","en":"…"},
 "musique": "ambience_bunker",
 "hauteur_portes": 2.5,
 "lampes_auto": true,
 "ciel": {"type":"nuit","luminosite":0.6}
}
```

`format` : version du format (**17** ; `EditorMap.FORMAT`). Historique : 1 =
premières cartes ; 2 = décor (`prefab`), luminaires (`luminaire`), textures
par pièce et plafond des zones ; 3 = murs en biais (clé `angle` des objets
muraux posés contre un mur en biais) ; 4 = formes libres (coordonnées sans
grille, clé `forme` des pièces, type `mur_courbe`, rotation `rot` au degré
près du décor, des luminaires, des piliers, escaliers et pièges). Une carte
au **format 1, 2 ou 3 se lit telle quelle** (toutes les nouvelles clés sont
facultatives, `EditorMap._migrate`) et s'enregistre au format courant.
Formats 5 à 11 (variantes, barrière invisible, escaliers, décor libre, portes
à zombies, barrière en polygone et chevauchements, effets, effets purs et
zones) : docs/MAP_OBJECTS.md ;
format 12 : hauteurs de pose (`z` du décor posé au sol,
`hauteur` d'un luminaire au sol, `descente` de ce qui est accroché au
plafond ; docs/MAP_OBJECTS.md § 13 ; aucune conversion) ; 13 : volume des
effets (§ 12) ; 14 : échelle et inclinaison du décor (§ 14) ; 15 : boîte
mystère posée au sol (`boite` sans `mur`, avec `rot`, docs/MAP_OBJECTS.md
§ 15 ; une boîte sans `mur` d'une carte plus ancienne reçoit `mur` : `n`,
comme le jeu la posait) ; 16 : textures de la carte (§ 4) ; le format
courant est **17** : **niveaux libres** (§ 4) : `altitude` de chaque pièce,
ouverture et objet, `altitude_haut` et `sortie` des escaliers,
`sans_plafond` des pièces, `ciel` de la carte, coordonnées négatives ;
`etages`, `etage` et `double_hauteur` disparaissent (une carte plus ancienne
est convertie au chargement, § 4, « Anciennes cartes »). Une carte d'un
format plus ancien avec des effets est **convertie au chargement** (effet pur
+ décor équivalent au même endroit, docs/MAP_OBJECTS.md § 12) et réécrite au
format courant à l'enregistrement.
Une carte d'un format plus récent que le jeu est signalée. `id` : dossier ; `musique` : un son
`assets/audio/ambience_*` ; `hauteur_portes` (m) ; `lampes_auto` : une lampe
tous les 6 m dans chaque zone (jamais sous un ciel ouvert) ; format 9 :
`chevauchement_decor` (facultatif, vrai : le décor et les piliers peuvent se
chevaucher entre eux, docs/MAP_OBJECTS.md § 10) ; format 17 : `ciel`
(facultatif, jamais écrit à sa valeur par défaut) = `{"type": "noir" |
"jour" | "nuit", "luminosite": facteur de 0,1 à 2}` (absent : noir ;
luminosité absente : 1), vu au-dessus des pièces sans plafond. Il n'y a
plus de liste `etages` : les niveaux sont les altitudes des pièces. Format
18 : `vagues` (facultatif, jamais écrit à sa valeur par défaut) =
`{"speciale": {"premiere": 5, "intervalle": 5}, "boss": {"premiere": 15,
"intervalle": 15}}` : schéma d'apparition des vagues spéciales (mini-boss :
aujourd'hui la meute de chiens) et des vagues de boss, en manches (entiers de
0 à 999 ; `premiere` 0 : jamais ; `intervalle` 0 : une seule vague). Valeur
par défaut : une vague spéciale toutes les 5 manches (5, 10, 15…), un boss
toutes les 15. Une manche prévue pour les deux est une vague de boss si la
carte a un boss, sinon une vague spéciale ; aucun boss n'existe encore, une
vague de boss ne fait donc rien. Réglable dans le panneau de la carte (rien
de sélectionné) : « Vague spéciale / Vague de boss : 1re manche, toutes les
N manches » (`WaveRules`, `EditorMap.set_waves`). Une carte d'un format plus
ancien a le schéma par défaut.

**`pieces.json`** — les pièces :

```json
{
 "pieces": [
  {"id":"p3","nom":"Entrepôt","zone":"z3","contour":[[2.5,4.5],[17,4.5],[17,17],[2.5,17]],"altitude":0,"plafond":6.8},
  {"id":"p5","nom":"Passerelle","zone":"z5","contour":[[2.5,4.5],[7.5,4.5],[7.5,9.5],[2.5,9.5]],"altitude":3.5,"plafond":3.3,"surface_murs":"brick","surface_sol":"parquet","surface_plafond":"wood"},
  {"id":"p8","nom":"Cour","zone":"z8","contour":[[-12,4.5],[2.5,4.5],[2.5,17],[-12,17]],"altitude":-1.5,"plafond":5,"sans_plafond":true}
 ]
}
```

`contour` : les sommets (au moins 3) du trait des murs (nombres finis,
négatifs compris) ; `zone` : un `id` de `zones.json` ; `altitude` (format
17) : altitude absolue du sol de la pièce (m, nombre fini, sans borne ni pas
imposé ; absente : 0) : les pièces de même altitude (à 5 mm près) forment un
niveau ; facultatifs : `plafond` (hauteur sous plafond, m, 2,8 au moins, sans
maximum ; absent : 3,2 ; les mêmes bornes dans le panneau, le contrôle des
cartes reçues et le validateur ; une pièce dont le plafond dépasse un niveau
du dessus le traverse : pièce haute, § 4), `sans_plafond` (true, jamais
écrit à faux : plafond masqué, ciel de la carte au-dessus), et (format 2)
les **textures** `surface_sol`,
`surface_murs`, `surface_plafond` : clés de `WorldLook.SURFACES` ; absentes,
celles de la zone. Une pièce rectangle a 4 sommets alignés sur les axes ; un
côté en biais est simplement un côté dont les deux sommets ne sont ni sur la
même ligne ni sur la même colonne (rien d'autre à écrire). Les sommets
peuvent être quelconques (au millimètre) : un côté qui n'est pas droit sur la
grille de 0,5 m devient un vrai mur oblique.

Format 4 : `forme` (facultative) = la forme de base d'origine, pour la
régénérer ; le `contour` fait foi (il est écrit à côté) :

```json
{"id":"p1","nom":"Salle ronde","altitude":0,"zone":"z1","contour":[[16,28.937],…],"forme":{"type":"cercle","centre":[16,16],"rx":13,"points":32,"angle":0}}
```

`type` : `cercle` (polygone régulier, `rx` = rayon, `points` 3 à 64),
`ellipse` (`rx`, `ry` : demi-largeur et demi-hauteur, `points`), `triangle`
(`rx`, `ry`), `l` (`rx`, `ry`, `bras` : épaisseur des branches, 0,2 à 0,8) ;
`angle` : rotation en degrés, sens horaire vu de dessus. Une forme illisible
écrite à la main est ignorée (la pièce reste un polygone).

**`ouvertures.json`** — portes, débris, passages, fenêtres :

```json
{
 "ouvertures": [
  {"id":"o1","type":"porte","altitude":0,"position":[17,26.75],"largeur":2,"prix":750},
  {"id":"o3","type":"debris","altitude":0,"position":[5.75,21.5],"largeur":2,"prix":1250},
  {"id":"o4","type":"passage","altitude":0,"position":[11.75,17],"largeur":4},
  {"id":"o5","type":"fenetre","altitude":0,"position":[11.25,4.5]}
 ]
}
```

`type` : `porte`, `debris`, `porte_courant` (sans prix), `passage` (sans
prix), `fenetre` (1 m, sans largeur) ; `position` : le **milieu** de
l'ouverture, **sur le trait du mur** ; `largeur` (m, multiple de 0,5 ; pour
un nombre pair de demi-mètres, le milieu tombe à 0,25 m de la grille). Sur un
mur en biais, `position` est aussi sur le trait et `largeur` se mesure le
long du mur ; son orientation se lit sur le côté de pièce qui passe par là.
`altitude` (format 17, absente : 0) : sol du niveau où l'ouverture est posée,
celui des deux pièces qu'elle relie (une ouverture entre deux altitudes est
une erreur).

**`objets.json`** — tout le reste :

```json
{
 "objets": [
  {"id":"x1","type":"pilier","altitude":0,"rect":[9,9.5,11.5,12]},
  {"id":"x2","type":"escalier","altitude":0,"altitude_haut":3.5,"rect":[2.5,9.5,5,16],"monte":"n"},
  {"id":"m1","type":"mur","altitude":0,"a":[4,4],"b":[4,9],"epaisseur":0.5},
  {"id":"s1","type":"depart","altitude":0,"position":[12,26]},
  {"id":"a2","type":"atout","atout":"titan","altitude":0,"position":[17,14],"mur":"e"},
  {"id":"w1","type":"arme","arme":"m14","altitude":0,"position":[13.25,33],"mur":"s"},
  {"id":"w2","type":"arme","arme":"mp5k","altitude":0,"position":[16,4],"mur":"n","angle":45},
  {"id":"b2","type":"boite","altitude":0,"position":[20.5,29.25],"mur":"e","depart":true},
  {"id":"t1","type":"piege","altitude":0,"rect":[5,5,7,9]},
  {"id":"c1","type":"courant","altitude":3.5,"position":[2.5,7.5],"mur":"o"},
  {"id":"e1","type":"evacuation","altitude":0,"position":[2.5,24],"mur":"o"},
  {"id":"d1","type":"prefab","prefab":"sacs_sable","altitude":0,"position":[10.25,3.25],"rot":90},
  {"id":"lu1","type":"luminaire","luminaire":"suspension","altitude":0,"position":[7.5,5.5],"rot":0,"couleur":"#ffc88a","intensite":2.2,"portee":10,"courant":true,"vacille":false},
  {"id":"lu2","type":"luminaire","luminaire":"applique","altitude":0,"position":[0,5],"mur":"o","couleur":"#40a0ff","intensite":1.4,"portee":7,"courant":true,"vacille":false}
 ]
}
```

- `altitude` (format 17, tous les objets ; absente : 0) : sol du niveau où
  l'objet est posé (celui de sa pièce) ; ses hauteurs de pose (`z`,
  `hauteur`, `descente`, format 12) restent relatives à ce sol. Escalier :
  `altitude` = sol du pied, `altitude_haut` = sol d'arrivée (absolu ;
  écrit par l'éditeur ; un fichier écrit à la main sans lui arrive au
  premier niveau au-dessus dont une pièce contient le haut des marches,
  sinon 3,5 m plus haut), `sortie`
  facultative (`gauche` / `droite` vu en montant ; absente : en face),
  docs/MAP_OBJECTS.md § 4.
- Rectangles (`pilier`, `escalier`, `piege`) : `rect` = [x0, y0, x1, y1]. Un
  pilier a son contour sur le trait (comme un mur de pièce) ; les marches et la
  zone de piège sont les cases à l'intérieur. `monte` : `n`, `e`, `s`, `o`.
  Format 4 : `rot` (facultatif) = rotation du rectangle autour de son centre,
  entier de 0 à 359, sens horaire vu de dessus (`monte` se lit avant la
  rotation) : `{"id":"x1","type":"pilier","altitude":0,"rect":[9,17,11,19],"rot":30}`.
- `bloc_invisible` (barrière invisible, format 9) : polygone `sommets`
  [[x, y], ...] (3 à 64 points, posé n'importe où), `hauteur` facultative
  (absente : jusqu'au plafond) :
  `{"id":"i1","type":"bloc_invisible","altitude":0,"sommets":[[2,2],[6,2],[6,3],[3,3],[3,6],[2,6]],"hauteur":1.2}`
  (cartes d'avant : `rect` + `rot`, lus comme un polygone ; docs/MAP_OBJECTS.md § 2).
- `effet` (format 10 ; format 11 : `zone`) : `effet` (identifiant de `MapCatalog.EFFECTS`), `position`, et facultatifs `rot` (effets au sol et au plafond), `mur` / `angle` (effets muraux), `intensite`, `zone` (m : `[largeur, profondeur]` au sol et au plafond, `[largeur, profondeur, hauteur]` pour un volume — brouillard, poussière, feux follets —, `[largeur, hauteur]` au mur ; bornes propres à chaque effet ; absente : zone par défaut), `hauteur`, `couleur` ; aucun objet, aucune collision ; `taille` (avant le format 11) est encore lue, comme la zone par défaut × taille :
  `{"id":"fx1","type":"effet","altitude":0,"effet":"brouillard","position":[8,6],"rot":30,"zone":[10,6,0.8],"intensite":1.5}` (docs/MAP_OBJECTS.md § 12).
- `prefab` mural (format 11 : torche murale, tuyau à vapeur, boîtier électrique, tuyau qui fuit) : `position` sur le trait du mur, `mur` / `angle` et `hauteur` facultative (m au-dessus du sol, comme une applique), sans `rot` :
  `{"id":"d4","type":"prefab","prefab":"torche_murale","altitude":0,"position":[2,0],"mur":"n","hauteur":2.1}`.
- `mur` libre : segment `a` → `b` (droit ou en biais), `epaisseur` 0,5, 1,5 ou 2,5 m.
- `mur_courbe` (format 4) : arc de cercle en segments droits, `centre`,
  `rayon` (1 m au moins, sans maximum de conception), `debut` (direction du premier bout, degrés dans le sens
  horaire depuis le nord), `ouverture` (5 à 360°, dans le sens horaire),
  `segments` (1 à 64), `epaisseur` :
  `{"id":"m1","type":"mur_courbe","altitude":0,"centre":[16,16],"rayon":7,"debut":290,"ouverture":100,"segments":8,"epaisseur":0.5}`.
- Objets muraux (`atout` + `atout`, `arme` + `arme`, `grenades`, `boite` +
  `depart`, `pap`, `courant`, `poste_central`, `levier`) : `position` = milieu
  de l'objet **sur le trait du mur**, `mur` = direction du mur vu depuis
  l'objet (`n` : le mur est au nord). Contre un mur en biais (format 3) :
  `angle` = direction exacte du mur vue depuis l'objet, en degrés dans le
  sens horaire depuis le nord (`n` = 0, `e` = 90, `s` = 180, `o` = 270 ; 45 :
  mur au nord-est), nombre fini de 0 à 360 ; `mur` garde la direction
  cardinale la plus proche. Sans `angle`, l'objet suit `mur` comme avant. Identifiants d'atouts et d'armes : ceux
  de `PerkDB` / `WeaponDB` / `KnifeDB` (`titan`, `lazarus`, `m14`, `bowie`…).
- Objets au sol (`depart`, `apparition`, `teleporteur`, `arrivee`, `lampe`,
  `caisse`, `baril`) : `position` = centre. Un seul départ : les 4 joueurs se
  placent autour ; 2 à 4 départs : un joueur sur chacun.
- `boite` posée au sol (format 15) : `position` = centre, `rot` = entier de 0
  à 359 (sens horaire vu de dessus ; à 0, l'avant, où s'ouvre le couvercle,
  est au sud), **sans** `mur` ni `angle` (c'est l'absence de `mur` qui la met
  au sol) ; contre un mur : comme les objets muraux ci-dessus, sans `rot` :
  `{"id":"b4","type":"boite","altitude":0,"position":[7,28],"rot":45,"depart":false}`
  (docs/MAP_OBJECTS.md § 15).
- `prefab` (format 2) : `prefab` = une clé de `MapCatalog.PREFABS`
  (`gravats`, `gros_gravats`, `eboulis`, `debris_epars`, `planches`, `poutre`,
  `lustre_tombe`, `caisses`, `tonneaux`, `sacs_sable`, `table_renversee`,
  `chaise_renversee`, `chaise`, `bureau`, `etagere`, `fauteuils`,
  `fauteuil_casse`, `pupitre`, `projecteur_film`, `chariot`, `epave_voiture`) ;
  `position` = centre de l'emprise ; `rot` = 0, 90, 180 ou 270 (degrés, sens
  horaire vu de dessus ; à 0, le devant est au sud) ; format 4 : tout entier
  de 0 à 359 (emprise tournée).
- `luminaire` (format 2) : `luminaire` = une clé de `MapCatalog.LIGHTS`
  (`ampoule`, `suspension`, `neon`, `lustre`, `applique`, `lampe_bureau`,
  `projecteur`, `bougies`, `feu`) ; `position` = centre (applique : sur le
  trait du mur, avec `mur` comme un objet mural) ; `rot` ; `couleur`
  « #rrggbb » ; `intensite` (0,1 à 4) ; `portee` (2 à 20 m) ; `courant`
  (true : s'allume avec le courant) ; `vacille` (true : grésille).

**Types et valeurs admis** (contrôle des cartes reçues) : une seule source,
le catalogue.
- `MapCatalog.allowed_kinds()` : pour chaque `type` de `ouvertures.json` et
  `objets.json`, `{"file", "required": [clés obligatoires], "keys": {clé:
  spec}}` ; spec = `{"t": "id"}` (identifiant a-z, 0-9, _), `{"t": "int" |
  "number", "min", "max"}`, `{"t": "bool"}`, `{"t": "enum", "values": [...]}`
  (atouts, armes, prefabs, luminaires, directions, rotations…), `{"t":
  "point"}` ([x, y] en m, nombres finis, négatifs compris, sans borne : format 17), `{"t": "rect"}`,
  `{"t": "color"}` (« #rrggbb »). Tout type ou toute clé absent est à refuser.
  Format 3 : `angle` des objets muraux et des luminaires = `{"t": "number",
  "min": 0, "max": 360}` (nombre fini ; un NaN, un infini, un texte ou un angle
  sur un objet qui n'est pas mural sont refusés). Format 4 : `rot` du décor,
  des luminaires, des piliers, escaliers et pièges = `{"t": "int", "min": 0,
  "max": 359}` ; type `mur_courbe` (`centre` point, `rayon` et `ouverture`
  nombres bornés, `segments` entier de 1 à 64, `debut`, `epaisseur`).
- `MapCatalog.allowed_surfaces()` : les textures admises (clés triées de
  `WorldLook.SURFACES`).
- `MapCatalog.room_keys()` / `MapCatalog.zone_keys()` : clés admises d'une
  pièce et d'une zone, même format (+ `{"t": "text" | "names" | "polygon" |
  "shape"}` ; `shape` : la forme de base d'une pièce, contrôlée par
  `CustomMapGuard._forme`).

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

`sol`, `murs`, `plafond` (facultatifs ; `plafond` depuis le format 2) : textures par défaut des
pièces de la zone, clés de `WorldLook.SURFACES`. Un fichier illisible
est signalé à l'ouverture (fichier, ligne, erreur) ; un format plus récent que
celui du jeu aussi.

## 7. Comment le jeu construit la carte

| Fichier | Rôle |
|---|---|
| `scripts/editor/editor_map.gd` | `EditorMap` : la carte (cinq JSON), lecture, écriture, archive .zip, dossier des cartes. |
| `scripts/editor/map_geom.gd` | `MapGeom` : géométrie 2D (contours, bords communs avec tolérance, cases, rotations). |
| `scripts/editor/map_shapes.gd`, `map_snap.gd`, `map_transform.gd`, `map_panels_shape.gd` | Formes libres : `MapShapes` (cercle, ellipse, triangle, L, mur courbe), `MapSnap` (grille, grille fine, libre, aimants), `MapTransform` (rotations libres, régénération d'une forme), propriétés des formes et angles. |
| `scripts/editor/map_rules.gd` | `MapRules` : règles de pose et leurs raisons (FR/EN). |
| `scripts/editor/map_carve.gd` | `MapCarve` : pièce tracée sur d'autres (§ 3) : découpe prévue (aperçu hachuré, texte de la confirmation), soustraction sans trou, morceaux, passages, ouvertures déplacées ou retirées, refus d'un escalier ; lot de l'agent (`decouper`). |
| `scripts/editor/map_group.gd`, `map_context_menu.gd` | `MapGroup` : sélection multiple (rectangle) et actions de groupe validées en entier (déplacer, pivoter, dupliquer, copier / coller, supprimer) ; `MapContextMenu` : menu du clic droit. |
| `scripts/editor/map_catalog.gd`, `map_icons.gd` | Inventaire tiré des bases du jeu, décor (`PREFABS`), luminaires (`LIGHTS`), types admis (`allowed_kinds`…), icônes et aperçus des textures. |
| `scripts/editor/map_object_list.gd` | `MapObjectList` : l'onglet « Objets sur la carte » (pages de 50, filtres, survol). |
| `scripts/game/map/editor_prefabs.gd` | `EditorPrefabs` : décor et luminaires construits par le jeu (sans modèle). |
| `scripts/editor/map_raster.gd` | `MapRaster` : carte -> grille de cases de 0,5 m par niveau (altitudes distinctes, copie décalée si la carte a des coordonnées négatives). |
| `scripts/editor/map_validator.gd` | `MapValidator` : validateur et indicateurs BO1. |
| `scripts/editor/map_layout_export.gd` | `MapLayoutExport` : grille validée -> description en maillage (format de `MeshMapLayout`). |
| `scripts/editor/map_editor.gd`, `map_canvas.gd`, `map_panels.gd`, `map_hotbar.gd`, `map_inventory.gd`, `map_slot.gd` | L'interface (`scenes/editor/map_editor.tscn`). |
| `scripts/editor/editor_ui.gd`, `editor_options.gd` | `EditorUi` : taille de l'interface (un facteur : thème, tailles minimales, polices, marges et styles des contrôles depuis leurs valeurs d'origine, dessins de la vue) ; `EditorOptions` : écran d'options du jeu par-dessus l'éditeur. |
| `scripts/editor/map_preview_panel.gd`, `map_preview_world.gd`, `map_preview_camera.gd`, `map_preview_builder.gd` | Aperçu 3D en direct (§2 ter) : panneau et fenêtre détachée, monde de l'aperçu (conversion hors du fil principal, morceaux reconstruits, options, surlignage, sélection par un rayon), caméras (orbite, vol libre, vue joueur), construction par morceaux avec le code de `MeshMapBuilder`. |
| `scripts/game/map/editor_map_def.gd` | `EditorMapDef` : carte de l'éditeur côté jeu (`perso:<id>`, `partage:<sha256>`, ou script de carte livré). |
| `scripts/game/map/custom_map_guard.gd` | `CustomMapGuard` : contrôle de légitimité, paquet canonique et SHA-256, cache, lecture sûre d'un dossier ou d'une archive. |
| `scripts/game/map/map_share.gd`, `map_transfer.gd` | `MapShare` (envoi aux invités, `/root/Net/MapShare`) et `MapTransfer` (réception par morceaux). |
| `scripts/game/map/mesh_map_geometry.gd` | `MeshMapGeometry` : architecture 3D construite par le jeu (portage de `tools/blender/mesh_map.py`). |

1. **Grille** (`MapRaster`) : une case de 0,5 m **centrée** sur chaque multiple
   de 0,5 m. Les cases que traverse le contour d'une pièce sont des murs (un
   mur de 0,5 m centré sur le trait ; le bord commun de deux pièces = les mêmes
   cases : un seul mur), celles dont le centre est à l'intérieur son sol, de la
   zone de la pièce. Ouvertures : les cases du mur sur leur largeur. Pièce
   haute : à chaque niveau qu'elle traverse, contour en mur, intérieur en vide ; une pièce
   de ce niveau au-dessus du vide y pose son plancher (mezzanine). Escalier : cases
   de marches, vide (trémie) sur chaque niveau traversé jusqu'à l'arrivée. Objets : leurs cases. Zones : la zone de départ
   devient `a` (celle que le jeu ouvre au début), les autres `b`, `c`…
   **Murs en biais** : les cases **coupées** par le mur de 0,5 m (même un
   peu : marquage prudent, `MapGeom.slab_cells`) sont des murs, de sorte que
   la grille ne laisse jamais passer à travers ; les côtés colinéaires de deux
   pièces fusionnent en un seul mur oblique (`MapValidator.oblique_walls`,
   pièce de chaque côté) ; une ouverture en biais prend les cases coupées sur
   sa largeur, ses deux côtés sont vérifiés par le validateur
   (`_diag_opening`) ; un objet mural en biais prend les cases de son emprise
   tournée, hors cases du mur. Les cases qui ne sont que des cases de murs en
   biais (`diag_cells`) ne sont pas construites en blocs.
   **Formes libres** : seul un côté droit dont les deux bouts sont sur la
   grille de 0,5 m (`MapGeom.is_grid_seg`) reste en blocs de la grille ; tout
   autre côté (en biais, ou droit hors de la grille) suit le chemin des murs
   en biais. Les côtés colinéaires à 3 cm près (`MapGeom.JOIN_TOL`) forment
   une seule ligne (un mur mitoyen) ; la part d'un mur oblique qui longe un
   côté de la grille n'est pas construite deux fois. Pilier tourné ou hors de
   la grille : un pavé oblique (type `pilier`, cases coupées) ; mur courbe : un
   mur oblique par segment ; escalier tourné : cases dont le centre est dans
   le rectangle tourné, vide au-dessus, pied et palier vérifiés dans son
   repère (`MapValidator.diag_stairs`) ; piège tourné : ses cases, et le vrai
   rectangle pour le jeu (`diag_traps`) ; décor tourné au degré près : cases
   dont le centre est dans l'emprise tournée.
2. **Validation** (`MapValidator`, §5).
3. **Description en maillage** (`MapLayoutExport`) : salles (sols, plafonds,
   dalles sous les pièces posées au-dessus ; pas de plafond sur une pièce
   `sans_plafond`), murs, allèges et linteaux en blocs, garde-corps,
   escaliers (marches et rampe de collision), cours des fenêtres, zones,
   marqueurs (objets muraux par la face du mur), lampes, décor (`props` :
   modèle ou objet construit, `blockers` : ses `CollisionBox`), luminaires
   (lampes avec `color`, `power`, `flicker`, `fixture`), textures (sols et
   plafonds par pièce ; murs fusionnés sur une grille de demi-cases, chaque
   face avec la texture de la pièce qui la touche), réglages de la carte
   (`map_def` : noms des zones dans la langue du jeu, prix des portes, zones
   ouvertes l'une sur l'autre, départ de la boîte, téléporteur à relier si un
   poste central est posé). Murs en biais : clé `obliques` (`a`, `b`, `y0`,
   `y1`, `thick`, `mat_n` / `mat_m` : texture de chaque face, `openings` :
   portes, fenêtres et passages découpés, `joint` : raccord d'angle) ; le sol
   et le plafond le long d'un mur en biais sont les cases coupées par le mur
   **découpées selon le vrai contour** de la pièce (salles `biais_*`,
   triangulées), le reste de la pièce garde ses rectangles de cases ; portes
   et fenêtres en biais : milieu exact, lacet et direction vers l'intérieur
   du mur ; cour d'une fenêtre en biais tournée comme le mur. Formes libres :
   les morceaux de sol le long des murs obliques ont leur boîte de zone
   (testée après celles des salles de la grille) ; escalier tourné : `a` et
   `b` au milieu du pied et du haut des marches ; piège tourné : `area` avant
   rotation et `yaw` (le jeu, `ElectricTrap`, électrifie le rectangle tourné).
4. **Géométrie** (`MeshMapGeometry`) : les mêmes objets que le `.glb` de
   `mesh_map.py` (`<matériau>__<salle>__<type>`, collisions en pavés et prismes),
   branchés par `MeshMapBuilder` ; `MeshNav` cuit le navmesh, `MeshMapLayout`
   fournit zones et emplacements aux systèmes du jeu. Un mur en biais est un
   pavé oblique (type `biais` : le rendu pose le motif le long du mur, sans
   étirement) avec une texture par face, et sa collision un pavé
   `CollisionBox` tourné comme lui (jamais une collision de modèle Blender) :
   balles, grenades, impacts, joueurs et zombies suivent le vrai mur, et le
   navmesh des zombies et des chiens est cuit dessus (chemins qui le
   contournent, porte en biais reliée par son passage). **Aucune étape Blender** :
   une carte de l'éditeur se joue aussitôt, y compris dans le `.exe`.

Déclarer une carte livrée avec le jeu : ses JSON dans `assets/maps/<id>/`, un
script de 3 lignes (`scripts/game/map/maps/<id>.gd` : `extends EditorMapDef`
et `_init_editor("res://assets/maps/<id>/", "<id>")`), une ligne dans
`Game.MAP_SCRIPTS` ; l'ajouter à `Game.MENU_MAPS` la propose dans les menus.

## 8. DRAFT ARENA

Carte d'essai de 18 × 28,5 m sur 2 niveaux, 0 et 3,5 m (`assets/maps/draft_arena/`, format 17) :
salle des machines (départ, M14, LAZARUS), couloir de service (MP5K, boîte de
départ), entrepôt haut (plafond de 6,8 m) avec son pilier (TITAN BREW, boîte,
escalier), atelier (ouvert sur l'entrepôt par un passage), passerelle au
niveau 3,5 m, mezzanine de l'entrepôt (boîte, courant) ; portes 750 et 1000, débris 1250 ; 7 fenêtres.
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
- `tests/test_map_editor_decor.gd` : pagination (0, 50, 51, 2000 éléments),
  tri et filtres de la liste, survol carte ↔ ligne dans l'éditeur, 2000
  éléments fluides, chaque décor et chaque luminaire posé ou refusé selon les
  règles (lampe sur un bureau, suspensions qui se chevauchent, applique hors
  d'un mur), rotation R, textures enregistrées, relues et construites (mur
  mitoyen à deux faces), lecture du format 1, types admis
  (`allowed_kinds`), carte jouable construite par le jeu (décor,
  `CollisionBox`, lumières colorées, feu hors du réseau électrique), archives
  refusées (trop grosse, bombe, trop d'entrées, nom ou chemin inattendu) et
  identifiants invalides.
- `tests/autotest/map_editor.gd` (captures) : bouton du menu principal, trois
  pièces au glisser, porte refusée puis posée, objets par l'inventaire,
  vérification, Ctrl+S, rechargement, Ctrl+Z / Ctrl+Y, archive, polygone,
  copier / coller, poignée ; puis une salle décorée (décor et luminaires de
  l'inventaire, R, refus, couleur, textures), l'onglet « Objets sur la
  carte » (survol, page 2) et la pièce en jeu (TESTER).
- `tests/test_map_carve.gd` : pièce tracée sur une autre (`MapCarve`) :
  découpe simple, nouvelle pièce au centre (deux morceaux, même zone,
  passages), pièce coupée en deux (zone propre), pièce avalée, plusieurs
  pièces, contenu transféré ou supprimé, porte déplacée puis retirée, refus
  d'un escalier coupé, éditeur (découpe prévue au tracé, boîte, Annuler sans
  rien créer, un seul lot, Ctrl+Z / Ctrl+Y), agent (refus sans `decouper`,
  découpe dans le même lot avec, annulation).
- `tests/autotest/map_carve_look.gd` (captures, FR et EN) : tracé hachuré,
  boîte « Découper des pièces », résultat (dessus, avant, droite, 3D),
  pièce à cheval sur deux pièces (porte retirée) et sa boîte.
- `tests/test_map_editor_diagonal.gd` : aimantation d'angle (0, 45, 90°,
  angle libre, rectangle à 45°), mur mitoyen en biais unique, porte, fenêtre
  et objets muraux sur un mur en biais acceptés et refusés selon les règles,
  validateur, sol qui suit le vrai contour (triangulation, pièce concave),
  collisions (un rayon et un corps ne traversent pas le mur oblique, la
  fenêtre laisse passer), navigation (chemin qui contourne le mur, passage par
  la porte en biais), format 3 relu à l'identique, formats 1 et 2 lus, DRAFT
  ARENA sans rien d'oblique.
- `tests/autotest/map_editor_diagonal.gd` (captures) : octogone au polygone,
  losange à la Pièce rectangle + R, mur libre en biais, angle libre (Alt),
  porte refusée puis posée en biais, fenêtres, arme et atout en biais,
  vérification, format 3 ; puis TESTER : rayon et joueur arrêtés par le mur,
  zombies qui entrent par la fenêtre en biais et rejoignent le joueur en
  contournant le mur en biais sans le traverser, un rampant aussi.
- `tests/test_map_editor_freeform.gd` : modes d'aimantation (grille, grille
  fine, libre, inversion Maj, aimants aux sommets et aux côtés, mémorisés),
  saisie au clavier (polygone, mur, rectangle, cercle, mur courbe ; + / - et
  molette), formes de base (points, rayon exact, côtés à plat, ellipse,
  triangle, L, arc), nombre de points d'une forme posée (et refus sans rien
  changer), rotation libre d'une pièce avec son contenu, d'un décor et d'un
  pilier, poignée de rotation (15°, Alt, annuler), mur mitoyen hors de la
  grille à 3 mm près, pièce sans grille contre un mur de la grille (pas de mur
  en double), porte sur un côté à 17°, salle ronde de 32 points (sol continu,
  maillages fusionnés, rayons et corps arrêtés par le mur rond, le mur courbe
  et le pilier tourné, navigation qui les contourne), escalier et piège
  tournés, format 4 relu à l'identique, formats 1 à 3 lus, DRAFT ARENA
  identique octet pour octet, contrôle des cartes reçues (formes, rotations
  et murs courbes piégés refusés).
- `tests/autotest/map_editor_freeform.gd` (captures) : salle ronde de 32
  points au cercle et au clavier, G G (libre), annexe au polygone aimantée au
  cercle, côté tapé au clavier, porte réduite pour tenir sur le côté du
  cercle, fenêtres, mur courbe au clavier, pilier tourné de 30° à la poignée,
  vérification, format 4 ; puis TESTER : rayons arrêtés par le mur rond et le
  pilier, zombies entrés par la fenêtre de la salle ronde qui rejoignent le
  joueur sans traverser le pilier ni le mur courbe.
- `tests/test_map_preview.gd` : l'aperçu 3D construit la même description et
  les mêmes nœuds que le jeu sur DRAFT ARENA (maillages, collisions,
  `CollisionBox`, lampes identiques, portes, 7 fenêtres barricadées, atouts,
  armes, boîte, courant, objets figés), carte inachevée affichée, mise à jour
  toute seule après un ajout, une suppression et une annulation (seules les
  lampes refaites pour un luminaire), options (plafonds, courant, niveaux,
  éclairage plein), sélection par un rayon et surlignage, vue joueur arrêtée
  par un mur et passant la porte, réglages mémorisés (valeurs piégées
  ignorées), aucun rendu aperçu masqué ou sans focus, temps sur 50 pièces.
- `tests/autotest/map_preview.gd` (captures) : P sur DRAFT ARENA, orbite au
  clic droit et à la molette, pièce tracée et luminaire posé qui apparaissent
  dans l'aperçu, clic dans l'aperçu qui choisit la pièce, vol libre à la
  touche d'avance du jeu, vue joueur posée par Ctrl + double-clic et arrêtée
  par le mur, repère sur la 2D, fenêtre détachée (hors écran, sans focus) et
  refermée, P : plus aucun rendu.
- `tests/autotest/map_editor_play.gd` : TESTER sur DRAFT ARENA modifiée, partie
  solo sur la carte de l'éditeur telle qu'elle est, rien d'enregistré, retour
  dans l'éditeur avec la modification et l'historique (Ctrl+Z : plus d'étoile).
- `tests/test_map_unsaved.gd` : aucune écriture de la carte sans Enregistrer
  (modifications, annulations, Claude, minuterie de récupération), étoile
  exacte avec l'annulation, confirmation à chaque façon de quitter (menu,
  fermeture, nouvelle, récente, Ouvrir, import, rejoindre) et choix
  Enregistrer / Quitter sans enregistrer / Annuler (échec, jamais enregistrée),
  récupération après un « plantage » (Récupérer, Ignorer, Échap, ancien
  `_autosave`), session gardée pendant TESTER, collaboration hôte / invité.
- `tests/autotest/map_unsaved_look.gd` (@rendu) : capture de la boîte
  « Modifications non enregistrées » et de la boîte de récupération.
- `tests/autotest/draft_arena.gd` : la carte se joue (zombies aux fenêtres,
  portes, débris, escalier, tout accessible à pied).
- `tests/test_map_share.gd` : paquet canonique et empreinte stable, morceaux
  dans le désordre, manquants, en double, trop gros, empreinte fausse,
  contrôle de légitimité (clé ou type inconnu, chaîne géante, infini,
  coordonnée énorme, chemin `../`, faux JSON, JSON trop profond, BBCode dans
  le nom, fichier en plus...), DRAFT ARENA acceptée, carte à murs en biais
  acceptée (même empreinte) et angles refusés (400, -5, infini, texte),
  cache par hash, archive .zip piégée refusée.
- `sh tools/mp_test.sh custommap` : hôte + invité sans fenêtre ; carte perso
  choisie avant l'arrivée de l'invité, téléchargée, DÉMARRER grisé pendant le
  téléchargement, cartes corrompue et piégée refusées (partie non démarrée),
  cache réutilisé, partie sur la même carte.

## 9. Conseils de conception (BO1)

Les règles complètes de level design (surfaces vides, couloirs, lignes de vue,
hauteur, obstacles, barrières invisibles, décor, circulation, fenêtres,
économie, grille de contrôle) sont dans
[`MAP_DESIGN_RULES.md`](MAP_DESIGN_RULES.md) ; elles priment sur ce résumé.

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
- **Niveaux** : une passerelle ou un balcon donne un poste de tir et une impasse
  ; escaliers de 2 m ou plus de large pour que la horde passe.

## 10. Limites et prochaines étapes

- **Sols plats par pièce** : pas encore de pente ni de petites marches dans une
  pièce (entre deux pièces : un demi-niveau et une rampe ou un escalier).
- **Murs en biais et formes libres** : le bord d'une mezzanine en biais
  au-dessus du vide a encore un garde-corps en escalier de cases ; la
  vérification compte un mur hors de la grille « large » (les cases qu'il
  touche, 0,5 à 1 m) : un couloir sans grille de moins de 2 m peut être
  signalé trop étroit ; une ouverture tient sur un seul côté droit (0,5 m de
  mur plein à chaque bout) : sur un cercle, il faut des côtés assez longs
  (moins de points ou un plus grand rayon) ; les chevauchements d'objets
  tournés se comptent par leur rectangle englobant ; les objets muraux
  suivent leur mur (pas de rotation propre).
- Pas de porte en haut ou en bas d'un escalier (les deux zones d'un escalier
  sont ouvertes l'une sur l'autre) ; pas de portes liées ; pièges électriques
  seulement.
- Décor posé au sol seulement (pas encore de décor accroché aux murs, hors
  appliques) ; les luminaires sont des lampes omnidirectionnelles (le
  projecteur de chantier éclaire tout autour de lui).
- Cartes perso en multijoueur : réseau local ou IP directe seulement (pas de
  serveur de cartes) ; une carte en cours de téléchargement ne se joue pas
  hors du salon où elle a été reçue (elle reste dans le cache).
- Architecture simple : textures par pièce et par zone (sols, murs,
  plafonds), pas encore de plinthes, lambris ni moulures.
- Aperçu 3D : sur une grande carte, la conversion reste la plus longue étape
  (≈ 1,4 s pour 50 pièces, surtout la pose des lampes automatiques et les
  murs de `MapLayoutExport`), faite hors du fil principal ; les objets de jeu
  y sont figés (ni animation, ni son) ; la vue joueur traverse les portes
  fermées.
