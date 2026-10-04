# Règles de conception des cartes (level design)

Ce fichier rassemble les **règles générales** que doit suivre toute carte
faite avec l'éditeur (voir `MAP_AUTHORING.md`) pour être **agréable, lisible
et difficile**. Il ne décrit aucune carte en particulier : ce sont des
principes et des valeurs chiffrées, valables pour n'importe quel thème.

Le validateur de l'éditeur dit si une carte est *jouable* ; ce fichier dit si
elle est *bonne*.

Niveaux des règles :

- **[OBLIGATOIRE]** : une carte qui la viole n'est pas livrée ;
- **[CIBLE]** : valeur visée ; s'en écarter demande une raison écrite dans le
  compte rendu de la carte ;
- **[CONSEIL]** : bonne pratique.

---

## 1. Vocabulaire

| Terme | Définition |
|---|---|
| **Ligne de vue** | Segment droit entre l'œil du joueur (1,62 m du sol) et un point de la carte, que rien d'opaque ne coupe. Sa **longueur** est la distance à laquelle le joueur peut voir — et donc tirer sur — un zombie qui arrive. Voir §4. |
| **Ligne de passage** | Trajet qu'un joueur ou un zombie peut suivre à pied. Un obstacle bas coupe la ligne de passage sans couper la ligne de vue. |
| **Obstacle bas** | Moins de 1,2 m de haut (fauteuils, tonneaux, sacs de sable, table) : on voit et on tire par-dessus, on ne passe pas. |
| **Obstacle haut** | Plus de 1,8 m (pile de caisses, étagère, pilier, cloison) : coupe la vue et le passage. |
| **Zone** | Groupe de pièces qui s'ouvre d'un coup (une porte payante l'ouvre, ses fenêtres s'activent ensemble). |
| **Boucle** | Suite de pièces dont on peut faire le tour sans revenir sur ses pas. |
| **Training** | Tourner en rond en emmenant la horde derrière soi, puis se retourner pour tirer. |
| **Goulot** | Passage étroit (1,5 à 2 m) que la horde et le joueur doivent emprunter. |
| **Impasse** | Pièce ou recoin qui n'a qu'un accès. |
| **Refuge** | Endroit d'où l'on peut tirer longtemps sans risque : à éviter. |

---

## 2. Les chiffres du jeu (base de tout calcul)

Lus dans le code (à revérifier s'ils changent) :

| Donnée | Valeur | Source |
|---|---|---|
| Marche du joueur | 4,4 m/s | `player.gd` `WALK_SPEED` |
| Sprint | 6,8 m/s pendant 4 s (≈ 27 m) | `SPRINT_SPEED`, `SPRINT_DURATION` |
| Visée / accroupi | 2,9 / 2,3 m/s | `ADS_SPEED`, `CROUCH_SPEED` |
| Hauteur des yeux debout / accroupi | 1,62 / 1,05 m | `EYE_HEIGHT`, `CROUCH_EYE_HEIGHT` |
| Rayon du joueur | 0,35 m | `RADIUS` |
| Zombies, de la marche au sprint | 1,25 / 2,3 / 3,7 / 5,0 m/s | `zombie.gd` `SPEEDS` |
| Portée d'attaque d'un zombie | 1,25 m | `ATTACK_RANGE` |
| Chiens | 6,3 m/s | `dog_rules.gd` |
| Points de départ | 500 | `player_data.gd` |
| Planche réparée | 10 points | `barricade_rules.gd` |
| Boîte / piège / téléporteur / Pack-a-Punch | 950 / 1000 / 1500 / 5000 | `COST` de chaque script |

Conséquences pour le dessin :

- un zombie qui sprinte (5,0) va plus vite qu'un joueur qui marche (4,4) :
  le joueur ne survit qu'avec **un chemin libre devant lui** ; toute impasse
  devient mortelle quand les zombies courent ;
- un sprint complet couvre environ 27 m : une boucle doit être **bien plus
  longue** qu'un sprint, et traverser plusieurs pièces (§7.2), pour qu'on
  ne puisse pas la tenir sur place ;
- en visée, le joueur recule à 2,9 m/s, plus lentement qu'un zombie qui
  court (3,7) : une longue ligne droite n'est sûre que face aux marcheurs ;
- deux zombies côte à côte et un joueur qui les évite demandent **2,5 m** :
  c'est la largeur de base d'un passage.

---

## 3. Surfaces vides, couloirs et pièces

Ces règles n'imposent **ni taille ni forme** aux pièces : chaque carte a son
propre plan, et une carte faite de petites pièces est aussi valable qu'une
carte de grandes salles. Elles interdisent seulement ce qui tue le jeu :
**une grande surface vide où le joueur tourne en rond sur place**, en
emmenant la horde derrière lui sans jamais avoir à se déplacer. C'est de
l'anti-jeu : la carte doit **forcer le joueur à bouger**.

### 3.1 Surface vide [OBLIGATOIRE]

- **Surface vide** : un carré de sol, dans n'importe quelle orientation,
  qui ne contient **ni mur, ni obstacle qui bloque le passage** (décor
  solide ou barrière, pilier, escalier, rambarde). Le décor qui ne bloque
  pas (débris, planches au sol) ne compte pas : on marche dessus.
- **Aucune surface vide de 15 m² ou plus** sur toute la carte, soit aucun
  carré libre de plus de **3,9 × 3,9 m**. Sur la grille de 0,5 m du
  validateur : aucun carré libre de 4 × 4 m (le plus grand permis fait
  3,5 × 3,5 m).
- La règle vaut **partout** : salle de départ, grandes salles, extérieurs,
  cours, paliers, sous une double hauteur. Il n'y a pas d'exception.
- Conséquence : dans toute pièce de plus de 3,9 m dans les deux sens, les
  obstacles sont espacés de **moins de 4 m** les uns des autres et des
  murs. Les passages qu'ils laissent font **1,5 à 3,5 m** (minimums au
  §6.3).

### 3.2 Couloirs [OBLIGATOIRE]

- **Couloir** : pièce ou partie de pièce nettement plus longue que large,
  qui sert à aller d'un endroit à un autre.
- Largeur : **3 m au plus**, **2 m au moins** sur un trajet principal
  (1,5 m sur un trajet secondaire).
- **12 m au plus en ligne droite**, puis un coude, une ouverture latérale
  ou un élargissement (qui respecte toujours §3.1).
- Un couloir plus large que 3 m n'est pas un couloir : c'est une salle, à
  encombrer d'obstacles.

### 3.3 Toutes les pièces sont différentes [OBLIGATOIRE]

Aucune pièce de la carte ne ressemble à une autre, couloirs compris. Deux
pièces sont différentes si :

- leurs **contours** ne sont pas identiques, même tournés ou retournés
  (à 1 m près sur chaque côté) ;
- leurs **obstacles** sont disposés autrement (pas la même disposition
  recopiée) ;
- leur **habillage** diffère : combinaison des textures du sol, des murs et
  du plafond, objet repère, éclairage (voir §10).

Il faut les trois. Une pièce copiée-collée puis retexturée reste une copie.

---

## 4. Lignes de vue

### 4.1 Pourquoi elles comptent

La longueur des lignes de vue règle la **difficulté** et la **tension** :

- **trop longues** : le joueur voit chaque zombie de loin, a le temps de
  viser et de recharger ; la manche devient un stand de tir, sans surprise ;
- **trop courtes partout** : les zombies surgissent sans prévenir, le joueur
  subit sans pouvoir décider ; c'est injuste et confus ;
- **bien dosées** : le joueur voit la menace assez tôt pour réagir (une à
  deux secondes), mais jamais assez tôt pour être tranquille.

Repère : un zombie qui court (3,7 m/s) parcourt 15 m en 4 s, le temps de
viser, tirer une rafale et commencer à reculer.

### 4.2 Comment on la mesure

- À hauteur des yeux debout (**1,62 m**).
- Coupée par : un mur, une porte fermée, un obstacle haut (> 1,8 m), un
  plafond bas ou un plancher (lignes entre deux étages).
- **Pas** coupée par : un obstacle bas, une fenêtre barricadée (on voit entre
  les planches), un garde-corps de mezzanine, une porte ouverte.

### 4.3 Règles

- **[OBLIGATOIRE]** Dans une salle, la plus longue ligne de vue fait
  **15 m au plus**.
- **[OBLIGATOIRE]** Au plus **une longue ligne de vue assumée** par carte
  (allée, grand couloir, nef), jusqu'à 25 m, avec des arrivées de zombies
  **sur son côté** pour qu'elle ne soit pas un refuge.
- **[CIBLE]** Depuis n'importe quel point, au moins une fenêtre de la zone
  est **hors de vue** : le joueur ne surveille jamais toutes les arrivées à
  la fois.
- **[CIBLE]** Deux portes ne sont jamais alignées sur plus de deux pièces :
  on décale l'axe d'une pièce à l'autre.
- Moyens de casser une ligne de vue : coude de couloir (45 ou 90°), pilier,
  obstacle haut, cloison libre (outil Mur), décalage des ouvertures,
  changement de hauteur de plafond.
- **[CONSEIL]** Les obstacles bas servent à garder la vue tout en coupant le
  passage : le joueur voit la horde, mais doit la contourner.

---

## 5. Hauteur et verticalité

La hauteur est un outil de rythme autant que d'architecture.

### 5.1 Hauteurs de plafond [CIBLE]

| Espace | Hauteur sous plafond | Effet |
|---|---|---|
| Couloir, passage, réduit | 2,8 à 3 m | oppression, la horde paraît plus proche |
| Pièce courante | 3 à 3,5 m | neutre |
| Grande salle | 4 à 5 m | respiration, espace de combat |
| Double hauteur (ouverte sur l'étage) | 6 à 7 m | repère visuel, vue plongeante |

- **[CIBLE]** **Compression puis détente** : un passage bas et étroit qui
  débouche sur une pièce haute et large. Le joueur ressent l'ouverture ; il
  sait qu'il entre dans un espace important.
- **[CIBLE]** Une ou deux doubles hauteurs par carte au plus : rares, elles
  restent des repères.
- **[CONSEIL]** Plafond bas au-dessus d'un goulot, haut au-dessus d'une
  grande salle : la sensation suit le danger.

### 5.2 Étages [OBLIGATOIRE sauf mention]

- Escaliers de **2 m de large au moins** sur un trajet principal (le
  validateur accepte 1,5 m) ; paliers dégagés de 2 m en haut et en bas.
- Un étage qui contient plus de deux zones a **deux accès** (deux escaliers,
  ou un escalier et un téléporteur) ; sinon c'est une impasse géante.
- **[CIBLE]** Un escalier ne monte pas plus de 6 m en ligne droite sans
  palier ; deux volées sont plus lisibles et cassent la ligne de vue.
- **[CIBLE]** Une mezzanine ou un balcon au-dessus d'une double hauteur
  donne une **vue plongeante** et un poste de tir ; il a toujours une arrivée
  de zombies (fenêtre ou escalier proche) pour ne pas être un refuge.
- **[CONSEIL]** Monter doit rapporter quelque chose (achat, raccourci, vue
  sur une grande salle) et coûter quelque chose (un seul accès étroit, un trajet
  plus long pour fuir).

---

## 6. Obstacles et décor

### 6.1 Densité [OBLIGATOIRE]

- La densité découle de la règle des surfaces vides (§3.1) : aucun carré
  libre de 15 m² ou plus. Il n'y a pas de nombre minimal d'obstacles à
  atteindre, seulement des vides à combler.
- **[CIBLE]** Les obstacles n'occupent pas plus de **30 %** du sol d'une
  pièce : au-delà, la pièce devient un labyrinthe illisible.
- **[CONSEIL]** Combler un vide avec un obstacle qui a une fonction (§6.2)
  plutôt qu'avec un objet posé au hasard.

### 6.2 Rôle des obstacles [CIBLE]

Chaque obstacle qui bloque a une fonction :

| Fonction | Type d'obstacle | Collision conseillée |
|---|---|---|
| Bloc : oblige à contourner, coupe l'espace en passages | haut, massif | solide |
| Ralentisseur : la horde se resserre, on tire à travers | bas | barrière |
| Couverture : coupe une ligne de vue, crée un angle mort | haut | solide |
| Goulot : resserre un trajet à 1,5–2 m | haut ou bas | solide |
| Repère : identifie la pièce de loin | grand, unique dans la carte | au choix |

- **[CONSEIL]** Mélanger obstacles bas et hauts dans une même pièce.
- **[CONSEIL]** Poser les obstacles en **îlots**, décollés des murs de 1,5 à
  3 m, pour couper l'espace en passages ; un obstacle collé au mur ne fait que
  rétrécir la pièce.
- **[CONSEIL]** Le décor qui ne bloque pas (débris, planches) habille sans
  gêner ; il ne compte pas comme obstacle (§3.1).

### 6.3 Dégagements [OBLIGATOIRE]

| Devant… | Zone libre de tout obstacle |
|---|---|
| une fenêtre à zombies (côté intérieur) | 2 m de profondeur × 2 m de large |
| une porte, des débris, un passage | 1,5 m de chaque côté, sur toute la largeur |
| un atout, le Pack-a-Punch, la boîte | 1,5 m devant (boîte posée au sol, format 15 : 1,5 m devant, 1 m sur les autres côtés — on l'achète de partout) |
| une arme murale, un levier, l'interrupteur | 1 m devant |
| le pied et le haut d'un escalier | 2 m |
| le départ des joueurs | 2 m autour |

- Tout passage entre deux obstacles, ou entre un obstacle et un mur, fait
  **1,5 m au moins**, **2 m** sur un trajet principal ou une boucle.

### 6.4 Placement naturel, pas sur la grille [CIBLE]

Une pièce où tout est droit, parallèle aux murs et calé sur la grille ne
ressemble pas à un lieu abandonné et n'est pas intéressante à parcourir.

- Les objets ne sont **pas tous alignés** sur la grille ni parallèles aux
  murs : la plupart sont **tournés** de quelques degrés à quelques dizaines
  de degrés (rotation au degré près, poignée ronde ou champ « Angle ») et
  **décalés** hors des cases (aimantation fine ou libre).
- **[CIBLE]** Dans une pièce, au moins **la moitié** des objets du décor
  (hors objets muraux) ont une rotation qui n'est ni 0, ni 90, ni 180, ni
  270°.
- Deux objets voisins de même type n'ont jamais la même rotation ni un
  espacement régulier : pas de rangées au cordeau, sauf quand le thème
  l'impose (rangée de fauteuils, bancs, lits d'un dortoir), et même alors
  un ou deux éléments sont déplacés, renversés ou manquants.
- Ce qui est droit l'est **par choix** : un comptoir, une étagère contre un
  mur, une machine. Ce qui est tombé, poussé ou abandonné est de travers.
- Les distances des §3 et §6.3 se mesurent sur l'emprise **tournée** de
  l'objet (pas sur sa position avant rotation).

### 6.5 Objets infranchissables : barrières invisibles [OBLIGATOIRE]

Le joueur saute à environ **0,8 m** (vitesse de saut 5 m/s, gravité
16 m/s²). Un objet plus bas que cela, ou dont le modèle offre une prise
(lit, table, bureau, banc, comptoir, caisse basse), peut servir de marche
pour monter dessus et échapper aux zombies : c'est de l'anti-jeu.

- Quand un objet doit **empêcher le joueur de monter dessus**, on pose une
  ou plusieurs **barrières invisibles** (outil « Barrière invisible », type
  `bloc_invisible`) par-dessus. Elles bloquent joueurs et zombies, laissent
  passer balles et grenades, et ne se voient pas en jeu.
- **L'objet est couvert en entier** : l'union des barrières recouvre toute
  son emprise, **sans aucun rebord, coin ni bout qui dépasse**. Une partie
  non couverte (un pied, un accoudoir, le bout d'un matelas, l'angle d'un
  objet tourné) suffit au joueur pour y poser le pied et monter.
- Marge : chaque barrière déborde de l'emprise de l'objet d'au moins
  **0,1 m** de chaque côté.
- Même **rotation** que l'objet : une barrière droite sous un objet tourné
  laisse dépasser ses angles. La barrière se trace en **polygone** (format
  9) : pour un objet tourné ou qui n'est pas un simple rectangle (en L, en
  croix, irrégulier), un seul polygone qui épouse son emprise (marge
  comprise) ; si l'on en pose plusieurs, elles **se chevauchent** : jamais
  de jour entre deux barrières. Elle se pose n'importe où, même à cheval sur
  un mur ou par-dessus l'objet.
- Hauteur : du sol au plafond (hauteur par défaut), ou au moins **1 m
  au-dessus du point le plus haut** de l'objet.
- La barrière compte comme obstacle : passages, dégagements (§6.3) et
  surfaces vides (§3.1) se mesurent depuis **la barrière**, pas depuis le
  modèle.
- Contrôle : vérifier dans l'aperçu 3D (vue de dessus et vue joueur) que
  chaque objet bloquant est entièrement couvert, puis essayer de monter
  dessus en partie test.

---

## 7. Circulation

### 7.1 Sorties [OBLIGATOIRE]

- La salle de départ a **deux sorties payantes** qui mènent à **deux
  branches différentes**.
- Toutes portes ouvertes, chaque zone a **deux accès** au moins, sauf au
  plus **deux impasses assumées** (§9.3).

### 7.2 Boucles [OBLIGATOIRE]

- Au moins **une grande boucle** de **60 à 150 m** de tour, ouvrable avant
  ou juste avec le courant.
- **[CIBLE]** Deux grandes boucles sur une carte complète, qui se croisent
  dans une grande salle.
- **[CIBLE]** Une boucle traverse au moins trois pièces différentes (§3.3).

### 7.3 Pas de manège sur place [OBLIGATOIRE]

- Aucun circuit **contenu dans une seule pièce** ne permet de tourner
  indéfiniment avec la horde derrière soi : autour d'un obstacle, les
  passages sont étroits (3,5 m au plus, §3.1) et encombrés, les zombies
  coupent la route par l'autre côté.
- Le training se fait sur les **boucles entre pièces** (§7.2) : le joueur
  traverse des portes, des couloirs et des pièces différentes, et croise
  de nouvelles arrivées de zombies à chaque tour.
- Chaque boucle a des arrivées de zombies **sur son trajet**, dans au moins
  deux pièces : on ne la parcourt jamais sans danger devant soi.

### 7.4 Couloirs [CIBLE]

- Largeur et longueur droite : voir §3.2.
- Un couloir de plus de 20 m au total a une fenêtre ou une ouverture
  latérale.

### 7.5 Goulots [CIBLE]

- **Un à trois goulots volontaires** par carte : des points de tension où
  l'on choisit de passer ou non.
- **[OBLIGATOIRE]** Jamais un goulot obligatoire entre le départ et la grande
  boucle : deux chemins y mènent.

---

## 8. Arrivées des zombies

### 8.1 Nombre [CIBLE]

- Une fenêtre pour **40 à 70 m²** de zone.
- Salle de départ : **3 à 4 fenêtres**, pour que la manche 1 arrive de
  plusieurs côtés.

### 8.2 Placement [OBLIGATOIRE]

- Les fenêtres d'une pièce sont sur **au moins deux murs différents** (sauf
  petite salle à une fenêtre).
- De tout point d'une zone ouverte, la fenêtre la plus proche est à
  **25 m à pied au plus**.
- Une fenêtre est à **3 m au moins** d'un atout, d'une arme murale ou de la
  boîte, et jamais pile dans le dos de qui achète : la menace se voit du coin
  de l'œil.
- Le départ des joueurs est à **7 à 12 m** de la fenêtre la plus proche.
- **[CONSEIL]** Une fenêtre près d'une porte encore fermée : qui hésite à
  ouvrir reste sous pression.

### 8.3 Trajets [CIBLE]

- Un zombie sorti d'une fenêtre atteint le joueur le plus proche en **moins
  de 10 s en marchant** (environ 12 m) : pas de longue marche à découvert.
- Les zombies qui sortent du sol servent dans les **extérieurs** (cour, rue,
  terrain) où une fenêtre n'a pas de sens : 2 à 4 points par zone extérieure, à 6 m au
  moins de tout achat et du départ.

---

## 9. Économie et progression

### 9.1 Points gagnés [CIBLE, ordre de grandeur, en solo]

| Moment | Points cumulés | Doit permettre |
|---|---|---|
| fin de manche 1-2 | 1 000 à 1 800 | la première porte |
| manches 3-4 | 3 000 à 4 500 | une arme murale et une deuxième porte, ou la boîte |
| manches 5-7 | 6 000 à 10 000 | le chemin du courant, un premier atout |
| manches 8-12 | 12 000 à 20 000 | TITAN BREW, Pack-a-Punch |

### 9.2 Portes [CIBLE]

- Prix : **750** pour la première, puis 1000, puis 1250 ; 1000 à 1500 pour
  un escalier ou un grand passage.
- **5 à 10 portes** payantes, **9 000 à 16 000 points** pour tout ouvrir.
- **[OBLIGATOIRE]** Derrière chaque porte, une récompense : arme murale,
  atout, emplacement de boîte, courant, piège, ou un raccourci qui ferme une
  boucle. Jamais une porte vers une pièce vide.
- Le **courant** est à **3 ou 4 portes** du départ (3 000 à 5 000 points).
- **[CONSEIL]** Les deux sorties du départ offrent des récompenses
  différentes : un vrai choix dès la manche 2.

### 9.3 Placement des achats [CIBLE]

| Achat | Où |
|---|---|
| Arme à 500 | au départ, sur le chemin d'une sortie |
| LAZARUS (réanimation rapide) | au départ ou derrière la première porte |
| Armes murales à 1 200-1 500 | une par branche, derrière la 1ʳᵉ ou la 2ᵉ porte |
| Arme lourde, fusil à pompe | à mi-parcours |
| Couteau de chasse | loin du départ, dans une zone dangereuse |
| Boîte mystère | **6 à 9 emplacements** dans **4 zones** au moins ; premier emplacement une porte après le départ ; contre un mur le plus souvent (BO1), au milieu d'une grande salle quand elle se voit de loin (format 15 : au sol, avant tourné vers l'entrée de la salle) |
| TITAN BREW (endurance) | **2 à 3 portes** du départ, coin défendable mais pas une impasse sans fenêtre ; jamais au départ |
| Autres atouts | répartis sur les branches, un seul par pièce |
| Pack-a-Punch | le plus loin, après le courant ; exposé pendant l'amélioration |
| Pièges | sur un goulot ou le trajet d'une boucle ; levier à 3-8 m, d'où l'on voit le piège |

- **Impasses assumées** (deux au plus) : elles contiennent une récompense
  forte, ont **au moins une fenêtre** et une entrée de 2 m au moins.

---

## 10. Lisibilité et ambiance

### 10.1 Un thème par pièce, une suite logique [CIBLE]

- Chaque pièce a un **thème** clair : cuisine, salon, salle de contrôle,
  dortoir, bureau, atelier, chaufferie, bibliothèque, infirmerie…
- Tout dans la pièce **sert ce thème** : son nom, ses textures, ses
  obstacles (fourneaux et plans de travail dans une cuisine, pupitres et
  armoires électriques dans une salle de contrôle), ses lumières. Les
  obstacles demandés par les §3 et §6 sont choisis parmi les objets du
  thème, pas posés au hasard.
- Les pièces s'enchaînent dans une **suite logique**, comme dans un vrai
  bâtiment : on passe de l'entrée au couloir, du salon à la salle à manger,
  de la salle à manger à la cuisine, de la cuisine à la réserve ; d'un poste
  de garde à une salle de contrôle, puis à la salle des machines. Pas de
  cuisine qui donne directement sur une salle de contrôle sans pièce de
  transition.
- Le thème de la carte entière (hôtel, usine, hôpital, base…) décide de la
  liste des thèmes de pièces possibles.

### 10.2 Toujours décorer les pièces [OBLIGATOIRE]

Une pièce qui ne contient que ce qu'exige le jeu (quelques obstacles, un
achat) est pauvre : elle n'apporte rien visuellement et le joueur la
traverse sans la regarder. Une salle de quatre lits seuls n'est pas un
dortoir, c'est un couloir meublé. **Chaque pièce est décorée, toujours.**

- **Une raison d'être en jeu** : chaque pièce apporte au moins une chose au
  joueur — un achat, un emplacement de boîte, un piège, une arrivée de
  zombies qui met la pression, un raccourci, une boucle, une vue. Une pièce
  qui ne sert à rien est supprimée ou fusionnée avec sa voisine.
- **Une raison d'être visuelle** : en entrant, le joueur comprend ce
  qu'était la pièce et ce qui s'y est passé.
- **Trois couches de décor** dans chaque pièce :
  1. **le mobilier du thème**, qui fait aussi les obstacles (§6) : lits,
     armoires, tables de chevet et chaises d'un dortoir, pas seulement les
     lits ;
  2. **les petits objets et le désordre au sol**, qui ne bloquent pas :
     débris, planches, papiers, objets renversés, autour et entre les
     meubles ;
  3. **les murs et le plafond** : appliques, suspensions, lustres, néons,
     et tout décor mural disponible, pour que le regard ne tombe jamais sur
     un mur nu sur toute sa longueur.
- **[CIBLE] Quantité** : au moins **un élément de décor pour 6 m²** de
  pièce (obstacles, décor au sol et luminaires comptés ensemble), et au
  moins **4 types d'objets différents** par pièce (3 dans un petit couloir).
- **[CIBLE]** Aucun pan de mur de plus de **6 m** sans rien devant ni
  dessus (meuble, décor, luminaire, achat, ouverture).
- **Une scène par pièce** : au moins un coin qui raconte quelque chose
  (barricade improvisée, table renversée avec des chaises autour, lit
  défait près d'une fenêtre arrachée, éboulement qui a écrasé un meuble).
- Si le catalogue de l'éditeur n'a pas les objets dont le thème a besoin,
  on **les ajoute au catalogue** (modèles 3D libres de droits autorisés)
  plutôt que de laisser la pièce vide ou de la remplir d'objets hors thème.

### 10.3 Repères et ambiance

- **[OBLIGATOIRE]** Chaque pièce a une **identité** : un nom (français et
  anglais), des textures différentes de ses voisines, un objet repère et un
  éclairage propre.
- **[OBLIGATOIRE]** Toutes les pièces sont différentes les unes des autres
  (contour, obstacles et habillage : voir §3.3).
- **[CIBLE]** Avant le courant, la carte est sombre mais les portes, les
  fenêtres et les achats restent visibles ; le courant change l'ambiance.
  Une ou deux zones restent sombres exprès.
- **[CONSEIL]** Le décor raconte ce qui s'est passé : barricades près des
  fenêtres, mobilier renversé, éboulement qui bouche un ancien passage.
- **[CONSEIL]** Une porte payante se voit depuis l'endroit où on l'achète,
  jamais cachée dans un recoin sans lumière.

---

## 11. Difficulté

- **[OBLIGATOIRE]** Aucun refuge : tout endroit d'où l'on peut tirer est
  atteignable par les zombies par **deux directions**, ou a une fenêtre à
  moins de 10 m.
- **[CIBLE]** Plus la récompense est forte, plus l'endroit est exposé.
- **[CIBLE]** Chaque porte ouverte active de nouvelles arrivées : la carte
  devient plus dangereuse à mesure qu'on l'ouvre, jamais plus sûre. Un
  raccourci fait gagner du chemin **et** ajoute une arrivée.
- **[CONSEIL]** Un goulot près de la boîte ou d'un atout rend l'achat tendu.

---

## 12. Démarche

1. **Fiche** : thème de la carte, thème de chaque pièce (§10.1), surface
   visée, nombre de zones, emplacement du courant, des atouts et du
   Pack-a-Punch.
2. **Graphe des zones**, sans dimensions : départ, branches, boucles,
   goulots, impasses, ordre et prix des portes, enchaînement logique des
   thèmes. Vérifier §7, §9 et §10.1.
3. **Tracé** des pièces, libre de forme et de taille ; couloirs du §3.2 ;
   chaque pièce différente des autres (§3.3) ; plafonds et étages du §5.
4. **Lignes de vue** (§4) : les mesurer, les casser là où elles dépassent.
5. **Obstacles** (§6), pris dans le thème de la pièce : combler tout
   carré vide de 15 m² (§3.1), les tourner et les décaler hors de la grille
   (§6.4), couvrir de barrières invisibles ceux sur lesquels on ne doit pas
   monter (§6.5), puis vérifier dégagements et passages.
6. **Arrivées des zombies** (§8), puis achats (§9.3), pièges, téléporteur.
7. **Décor et ambiance** (§10) : les trois couches de décor dans chaque
   pièce, une scène par pièce, puis lumières.
8. **Validateur** à 0 erreur, puis **grille du §13**, puis partie test.
9. **Compte rendu** : la grille remplie, et chaque règle [CIBLE] enfreinte
   avec sa raison.

Une carte qui s'inspire d'un lieu réel ou d'une carte existante reprend son
organisation (graphe, enchaînement des pièces), mais ses dimensions suivent
ce fichier.

---

## 13. Grille de contrôle

| Mesure | Attendu |
|---|---|
| Salle de départ | 2 sorties, 3 à 4 fenêtres, arme à 500 |
| Plus grand carré vide, partout | < 15 m² (≤ 3,5 × 3,5 m sur la grille) |
| Couloirs de plus de 3 m de large / lignes droites de plus de 12 m | 0 / 0 |
| Circuits tenables dans une seule pièce | 0 |
| Plus longue ligne de vue dans une salle | ≤ 15 m |
| Longues lignes de vue assumées | ≤ 1, ≤ 25 m, arrivées sur le côté |
| Doubles hauteurs | 1 à 2 |
| Part du sol occupée par les obstacles | ≤ 30 % par pièce |
| Grandes boucles entre pièces | ≥ 1, avec des arrivées dans 2 pièces |
| Impasses assumées | ≤ 2, chacune avec une fenêtre |
| m² de zone par fenêtre | 40 à 70 |
| Distance à pied max jusqu'à une fenêtre | ≤ 25 m |
| Portes payantes / coût total | 5 à 10 / 9 000 à 16 000 |
| Portes jusqu'au courant | 3 à 4 |
| Emplacements de boîte / zones couvertes | 6 à 9 / ≥ 4 |
| TITAN BREW | 2 à 3 portes du départ |
| Étages de plus de deux zones avec un seul accès | 0 |
| Pièces semblables (contour, obstacles, habillage) | 0 |
| Pièces sans thème, ou enchaînement illogique | 0 |
| Pièces sans raison d'être en jeu | 0 |
| Éléments de décor par pièce / types d'objets | ≥ 1 pour 6 m² / ≥ 4 |
| Pans de mur nus de plus de 6 m | 0 |
| Objets du décor tournés hors 0/90/180/270°, par pièce | ≥ 50 % |
| Objets à bloquer non couverts en entier par des barrières invisibles | 0 |
