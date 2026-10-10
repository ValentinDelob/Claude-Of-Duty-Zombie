# Concept du jeu — nouvelle direction (document vivant)

Ce document décrit la nouvelle direction du jeu : un jeu original de survie et de
farm, détaché de la franchise Call of Duty, en vue d'une sortie commerciale
(Steam ou autre plateforme). Il sépare trois choses :

- **Gameplay visé** : l'expérience que l'on veut faire vivre au joueur.
- **Fonctionnalités prévues** : règles validées, pas encore implémentées.
- **Mécaniques prototypées** : ce qui existe déjà dans le code (héritage du
  clone de Black Ops 1 Zombies) et ce qu'on en fait.

Il sera complété et modifié au fil des décisions. Chaque règle porte un statut :

| Statut | Sens |
|---|---|
| ✅ Validé | Décidé, à implémenter tel quel |
| 🧪 Prototypé | Existe dans le code actuel |
| 💡 Piste | Idée retenue, pas encore décidée |
| ❓ Ouvert | Question à trancher |
| ❌ Écarté | Abandonné (gardé pour mémoire) |
| ✔️ Fait | Décision appliquée dans le code (§5) |

---

## 1. Vision

- **Nom provisoire** : « Zombie Apocalypse ». ❓ Ce titre existe déjà
  (Konami, 2009), il est trop générique pour être protégé et quasi introuvable
  sur Steam. Il pourra servir de sous-titre. Le nom actuel « Claude of Duty
  Zombie » doit disparaître (marque *Call of Duty*, marque *Claude*).
- **Pitch** : un FPS coopératif de vagues de zombies sans fin, où l'on farme des
  armes et des échantillons pour un scientifique qui cherche un antidote, et où
  l'on reconstruit son arsenal à chaque partie.
- **Piliers** :
  1. **Survivre plus longtemps rapporte plus** : le niveau du butin dépend de la
     manche atteinte.
  2. **Armes à collectionner et à améliorer** : armes de niveaux et de raretés
     différents, avec des pièces à modificateurs ; on chasse la meilleure version.
  3. **Progression longue** : niveaux, arsenal, contrats du scientifique.
- **Références** (mécaniques seulement, rien n'est copié) : Borderlands
  (niveaux requis, raretés), Killing Floor 2 et Black Ops 1 Zombies (vagues),
  Deep Rock Galactic (coop et méta-progression).

## 2. Gameplay visé

### Boucle de 30 secondes
Tirer, tuer (chaque touche et chaque élimination rapportent de la ferraille),
ramasser son butin (à sa couleur), se replacer, recharger.

### Boucle d'une partie
1. Au hub, le joueur choisit jusqu'à **3 armes de départ** parmi les armes de
   base communes de niveau 1, et éventuellement un **contrat** à suivre.
2. La partie **ne se termine jamais** d'elle-même : les vagues s'enchaînent, de
   plus en plus fortes.
3. Chaque élimination rapporte de la **ferraille**. Elle sert à ouvrir des
   **portes** et à **construire les armes de son arsenal** à la station de
   construction : le joueur repart de zéro et devient de plus en plus puissant.
4. Les **vagues spéciales** et les **vagues de boss** lâchent des **armes** dont
   le niveau dépend de la manche, et des **échantillons**.
5. Après chaque vague spéciale ou de boss vaincue, l'équipe peut **s'évacuer**
   par la porte d'évacuation et rapporter son butin au hub. Un **rapport de fin
   de partie** montre ce qui est gardé et ce qui est perdu.

### Boucle méta (hub)
1. Le joueur remplit des **contrats** du scientifique avec ses échantillons, ou
   les échange contre des récompenses précises dans son **catalogue
   d'échanges**.
2. Il gère son **arsenal** : armes, versions, pièces, recyclage.
3. Il gagne de l'**XP**, monte de niveau et peut utiliser des armes de plus haut
   niveau.

### Ce que doit ressentir le joueur
- Une progression visible dès les 30 premières minutes.
- L'envie de relancer « encore une partie » pour une arme ou un échantillon
  précis.
- L'envie d'aller toujours plus loin : meilleur butin, nouveaux zombies.

## 3. Lore

- ✅ Un **scientifique** cherche à mettre au point un **vaccin et un antidote**.
  Il a besoin d'**échantillons** prélevés sur les zombies et engage les joueurs
  pour les récupérer (contrats).
- ✅ Tous les joueurs incarnent le **même personnage**, un **joueur de
  baseball**. En coop, quatre joueurs identiques (distingués par leur couleur).
- 💡 Scène d'introduction à l'hôpital (réveil après un coma, rencontre avec le
  scientifique caché dans une armoire) : **reportée**, pourra revenir plus tard
  comme chapitre de lore.
- 💡 Le joueur serait **immunisé** (mordu sans se transformer), ce qui explique
  pourquoi le scientifique a besoin de lui.
- ❓ Nom, personnalité et motivation du scientifique ; origine de l'épidémie ;
  fin envisagée.

Règles de droits pour le lore : aucune ligue, équipe ou marque réelle de
baseball ; pas de batte à fil barbelé (Lucille de *The Walking Dead*) ; ne pas
reprendre les scènes reconnaissables de *28 jours plus tard* ou de *The Walking
Dead* ; aucun élément du lore Aether / Élément 115 de Call of Duty.

## 4. Fonctionnalités prévues

### 4.1 Tutoriel et premières parties ✅
- Au premier démarrage, le joueur joue obligatoirement une **carte tuto** de
  **3 vagues**, terminée par une **évacuation** (exception : la partie s'arrête
  après l'évacuation de la vague 3).
- Déroulé :
  1. Manches 1 et 2 : le joueur gagne sa première **ferraille** en tuant et
     ouvre une **porte** avec.
  2. Il découvre la **station de construction** et y construit une arme de base.
  3. Manche 3 : **vague spéciale tuto**, faible. Elle lâche **à coup sûr, une
     seule fois**, une arme et un échantillon.
  4. La **porte d'évacuation** s'ouvre : le joueur s'évacue.
  5. Au hub : **rapport de fin de partie**, premier **contrat** rempli avec
     l'échantillon, découverte de l'arsenal.
- 💡 Présentation : court briefing du scientifique au hub et indications à
  l'écran pendant la première partie.

### 4.2 Contrats ✅
- Un contrat est **seulement un objectif** proposé par le scientifique : il ne
  force jamais la fin d'une partie. Le joueur est prévenu quand l'objectif est
  atteint et peut continuer à jouer.
- Les contrats demandent des **échantillons** (exemple : 50 griffes). Les
  échantillons s'accumulent d'une partie à l'autre ; quand le joueur clôt le
  contrat, seule la quantité demandée est consommée (200 griffes − 50 = 150
  restantes).
- Un contrat peut être **daté** : une fois la date dépassée, il est supprimé.
- Les contrats existent pour **inciter à farmer** par l'appât du gain.
- Au hub, le scientifique propose **5 contrats en rotation** ; le joueur en
  garde **3 actifs** au maximum.
- Un contrat rempli rapporte de l'**XP** et une **arme** ou une **pièce** au
  niveau du joueur.
- ❓ Contenu précis des contrats et rythme de la rotation : définis plus tard par
  l'auteur du jeu.

### 4.2 ter Catalogue d'échanges du scientifique ✅
- En plus des contrats, le scientifique propose un **catalogue d'échanges
  permanent** : le joueur échange ses échantillons contre une **récompense
  précise**, connue d'avance, quand il le veut.
- Exemples : 5 crocs + 3 touffes de poils → une garniture à crocs ; 2 bracelets
  + 1 sangle → une crosse.
- Le farm devient ciblé : le joueur sait quels échantillons il lui faut pour la
  récompense qu'il vise.
- ❓ Contenu du catalogue et niveau des récompenses.

### 4.3 Partie sans fin et vagues ✅
- **Une partie ne se termine jamais** d'elle-même : seule l'évacuation ou la
  mort de toute l'équipe y met fin.
- On conserve le système de vagues actuel. Le **nombre** de zombies dépend du
  nombre de joueurs ; leur **force** dépend du numéro de la manche, pas du niveau
  des joueurs.
- La force d'un zombie, ce sont ses **points de vie** : il n'existe pas de
  notion de résistance.
- **PV linéaires** : **PV = 150 + 100 × (manche − 1)**, soit 150 PV à la manche
  1, 1 050 à la 10, 2 050 à la 20, 4 950 à la 50. Cette formule remplace celle
  de BO1 du code actuel (`RoundRules.zombie_health` : +10 % par manche après la
  9, qui atteindrait des millions de PV).
- En face, les **dégâts d'une arme augmentent de 10 % de son dégât de base par
  niveau** (§4.9).

### 4.4 Vagues spéciales et vagues de boss ✅
- Chaque carte a des **vagues spéciales** (mini-boss) et des **vagues de boss**,
  avec un **schéma d'apparition configurable** par carte (dans l'éditeur).
- Une carte peut avoir **un seul** type de vague spéciale et de boss, ou
  **plusieurs**.
- 💡 Schéma par défaut : une vague spéciale toutes les **5 manches**, un boss
  toutes les **15 manches**.
- 💡 Chaque nouvelle apparition d'un même mini-boss dans la partie est plus forte.
- Exemple de pool pour une carte d'hôpital (💡 à valider) :

| Ennemi | Échantillons |
|---|---|
| Meute errante (chiens, en groupe) | croc, touffe de poils, collier |
| Brancardier (gros zombie qui charge) | sangle de cuir, bracelet d'identification |
| Infirmière hurlante (cri qui attire et étourdit) | cordes vocales, seringue cassée, badge |
| Le Chirurgien (boss) | scalpel, cœur mutant |

### 4.5 Évacuation ✅
- L'évacuation devient possible **après avoir vaincu une vague spéciale ou une
  vague de boss**. Si l'équipe ne part pas, la prochaine occasion est la
  prochaine vague spéciale ou de boss.
- **Porte d'évacuation** : un lieu de la carte où les joueurs doivent se rendre.
  Elle est **obligatoire sur chaque carte** et **accessible dès le départ** (à
  ajouter au jeu et à la vérification des cartes de l'éditeur).
- L'évacuation reste ouverte **2 minutes**, **sans zombies**.
- Chaque joueur vote **« prêt »** (continuer) ou **« partir »**.
  - Si tout le monde a voté « prêt », la partie reprend immédiatement.
  - L'équipe s'évacue quand **tous les joueurs vivants sont dans la zone de la
    porte**.
  - À la fin des 2 minutes sans évacuation, la partie continue.
- En coop, **toute l'équipe part ensemble** : personne ne s'évacue seul.

### 4.6 Mort, réanimation et fin de partie ✅
- Un joueur qui tombe peut être **réanimé** exactement comme aujourd'hui dans le
  jeu.
- En coop, un joueur mort passe en **mode spectateur**. Si ses coéquipiers
  terminent la vague, il **réapparaît avec toutes ses affaires**.
- Si **tous les joueurs meurent**, la partie se termine : **tout ce qui a été
  amassé pendant la partie est perdu**, armes, échantillons et améliorations
  des armes de l'arsenal comprises. Les pièces du stock montées pendant la
  partie sont **détruites**. **Seule l'XP est gardée.**

### 4.7 Butin ✅
- **Butin personnel** : chaque joueur fait ses propres tirages ; chaque joueur a
  une **couleur**, et son butin au sol porte sa couleur.
- 💡 Affichage : couleur du joueur sur le contour au sol (anneau, faisceau),
  rareté sur l'objet lui-même, nom du joueur sur l'étiquette (daltoniens).

**Armes**
- Les armes se trouvent sur les **vagues spéciales** et les **vagues de boss** :
  **1 arme par joueur** par vague spéciale, **2 armes par joueur** par vague de
  boss.
- Chaque arme définie a un **niveau de base** : c'est le niveau minimum auquel
  elle peut être trouvée.
- La **version trouvée** a un niveau compris **entre −6 et +2 par rapport à la
  manche** (au minimum 1, et jamais sous le niveau de base de l'arme). Le
  niveau du butin dépend de la manche, **pas du niveau du joueur**.
- Une arme trouvée d'un niveau supérieur à celui du joueur se garde pour plus
  tard : il ne peut ni l'équiper ni la construire tant qu'il n'a pas le niveau.
- 💡 À terme : pouvoir **démarrer une partie à une manche avancée** (50, 100,
  200…) pour montrer la progression des joueurs.
- Rareté d'une arme trouvée :

| Rareté | Probabilité |
|---|---|
| Commune | 60 % |
| Rare | 20 % |
| Épique | 12,5 % |
| Légendaire | 5 % |
| Unique | 2,5 % |

**Échantillons**
- Les zombies des vagues spéciales et de boss lâchent des **échantillons**
  propres à leur type (2 ou 3 sortes par mini-boss, 1 ou 2 par boss).
- Chaque échantillon a environ **20 % de chances** de tomber **par zombie tué**
  (pour une meute, chaque chien fait son tirage). **Hasard pur**, sans protection
  contre la malchance.
- **Aucune limite** de quantité portée.

**Pièces**
- Les pièces tombent **rarement** sur les vagues spéciales et de boss : environ
  **5 % de chances**.
- Une pièce trouvée a un niveau compris **entre le niveau du joueur − 10** (au
  minimum 1) **et le niveau du joueur** : elle peut toujours être installée sur
  une arme que le joueur peut utiliser.

### 4.8 Ferraille ✅
- **Monnaie de partie** : chaque joueur commence la partie avec **0 ferraille**.
- **Personnelle** : elle n'est pas ramassée au sol, elle est **gagnée
  directement par le joueur qui touche ou qui tue** le zombie (rien pour les
  assistances).
- **Touches** : toucher un zombie **d'une balle ou d'un coup de couteau**
  rapporte **un peu de ferraille** au tireur. Les explosions (grenades, armes
  à zone), les brûlures et les pièges ne rapportent rien pour une simple
  touche. Le nombre de touches payées est **plafonné par zombie**, pour qu'un
  zombie très résistant ne rapporte pas une fortune. Un zombie déjà mort ne
  rapporte plus rien.
- **Éliminations** : le coup qui tue rapporte le montant de l'élimination (pas
  la touche en plus), quelle que soit l'arme, sauf un piège (rien).
- Le montant par élimination est **fixe** : il n'augmente pas avec la manche,
  car le nombre de zombies augmente déjà.
- Elle sert à **construire les armes** de l'arsenal (§4.11), à **recharger les
  munitions** à la station et à **ouvrir les portes payantes**.
- Elle est remise à zéro à la fin de la partie : ce n'est pas une monnaie
  permanente.
- C'est elle qui **équilibre une partie**, y compris pour le défi hebdomadaire.
- ⚠️ Le prix en ferraille doit augmenter avec le niveau et la rareté de l'arme.

### 4.9 Armes ✅
- Les armes **ne sont pas générées** : elles sont **définies une par une** par
  l'auteur du jeu, chacune avec un **niveau de base requis** pour l'utiliser.
- Un joueur ne peut **ni équiper ni construire** une arme dont le niveau dépasse
  le sien. Il peut en revanche la **garder** (dans son inventaire de partie puis
  dans son arsenal) pour plus tard.
- Le niveau maximum des armes est celui des joueurs (50).

**Statistiques** (valeurs à définir pour chaque arme)

| Arme de corps à corps (batte, couteau…) | Arme à feu |
|---|---|
| Dégâts | Dégâts |
| Coups par seconde | Cadence de tir |
| Énergie consommée par coup (§4.14) | Temps de rechargement |
| | Recul |
| | Précision |
| | Rayon d'action (explosifs) |
| | Capacité du chargeur |
| | Munitions de réserve |

- **Évolution avec le niveau** : les dégâts augmentent de **10 % du dégât de
  base par niveau** (une arme niveau 11 fait le double de son niveau 1).

**Raretés**

| Rareté | Emplacements de pièces | En plus |
|---|---|---|
| Commune | 1 | |
| Rare | 2 | |
| Épique | 3 | |
| Légendaire | 4 | effet visuel sur l'arme |
| Unique | 4 | effet visuel sur l'arme + une statistique bonus (ex. « rechargement +20 % ») |

- L'**effet légendaire** est **purement visuel** et ne donne aucun avantage :
  éclats de brillance, éclairs… Il ne touche que l'arme elle-même, pas les
  balles ni le reste.
- Pas d'autre rareté pour l'instant : trop de raretés perdraient le joueur.

**Pièces**
- Chaque pièce porte des **modificateurs** (bonus et malus, par exemple
  « +25 % de dégâts », « −5 % de coups par seconde »).
- Une pièce se **monte** sur une arme si son niveau est **inférieur ou égal au
  niveau de l'arme**, et si le joueur a **au moins le niveau de la pièce**.
- Les pièces s'installent **au hub ou en cours de partie, depuis l'inventaire,
  n'importe où** : il n'y a pas de table d'amélioration.
- Les pièces ramassées sont **illimitées** et rangées dans un **onglet à part**
  de l'inventaire.
- Une pièce **retirée** d'une arme est **détruite**.
- 💡 Familles d'emplacements : armes à feu (canon, culasse, chargeur, crosse,
  viseur, accessoire), corps à corps (manche, tête, garniture, poignée).

**Score de l'arme**
- **Score = niveau de l'arme + somme des niveaux de ses pièces.**
- Exemple : légendaire niveau 25 avec des pièces 22 + 25 + 19 + 24 → score 115.
- Le score indique l'investissement dans l'arme, pas sa puissance exacte : la
  fiche de l'arme affiche aussi ses vraies statistiques.

**Droits** : ne pas reprendre les noms de fabricants de Borderlands, ni ses
fiches d'armes, ni son style visuel. Les armes réelles du jeu actuel (AK-74u,
FAMAS, Galil, HK21, AUG…) doivent être renommées et leurs silhouettes
retravaillées.

### 4.10 Armes de départ ✅
- Au hub, chaque joueur choisit **jusqu'à 3 armes de départ** (au moins 1).
- Ce choix se fait uniquement parmi les **armes de base** : **niveau 1,
  communes, sans amélioration**, données à tous les joueurs. Exemple : une
  **batte de baseball** et un **pistolet de départ** peu efficace.
- Un emplacement non choisi reste vide au départ.
- Une arme de base améliorée en partie et ramenée devient une **nouvelle
  version** dans l'arsenal ; l'arme de base reste toujours disponible.

### 4.11 Arsenal et station de construction ✅
- Au hub, l'**arsenal** contient des **armes physiques**, chacune avec ses
  pièces. Sa taille est **illimitée**.
- **Plusieurs versions** d'une même arme peuvent coexister (pièces différentes
  pour des usages différents) : rien n'est jamais remplacé automatiquement.
- En partie, une **station de construction**, accessible à tout moment, liste
  les armes de l'arsenal avec leur **prix en ferraille**. Elle ne construit que
  les armes **de l'arsenal**, pas celles trouvées pendant la partie.
- La station **recharge aussi les munitions** contre de la ferraille (prix selon
  l'arme).
- La ferraille est **dépensée dès le lancement** de la construction.
- La station **travaille seule** : plus une arme est exigeante en ferraille,
  plus la construction est longue, de **1 à 3 manches** au maximum.
- Pour **récupérer** l'arme construite, le joueur doit avoir un **emplacement
  d'arme libre** dans son inventaire.
- **Pas d'accélération** de la construction.
- Une arme de l'arsenal construite en partie reste **toujours dans l'arsenal**,
  même si la partie est perdue.
- Améliorer en partie une arme construite depuis l'arsenal met à jour **cette
  version** de l'arme, **seulement si l'équipe s'évacue**. Sinon, l'amélioration
  est annulée.
- **Recyclage au hub** : possible, ne rapporte rien pour le moment.

### 4.12 Équipement et inventaire de partie ✅
- **Équipement** : **3 armes** en main.
- **Inventaire** : **4 places** d'armes, en plus de l'équipement, pour les armes
  ramassées ou construites en cours de partie.
- Le joueur peut **intervertir** à tout moment une arme de l'inventaire avec une
  arme équipée.
- **Recyclage en partie** : recycler une arme rapporte **50 % de la ferraille**
  nécessaire pour la construire. Recycler un exemplaire construit depuis
  l'arsenal ne retire pas l'arme de l'arsenal.
- On ne peut **jamais recycler sa dernière arme** (armes en main et
  inventaire ; le couteau et les grenades ne comptent pas, ni une arme encore
  en construction à la station) : « Impossible de recycler votre dernière
  arme ».
- **Butin d'une partie** : seules les armes **gardées sur soi au moment de
  l'évacuation** (équipement et inventaire) sont ajoutées à l'arsenal.

### 4.12 bis Caisse au hasard ✅
- Une caisse placée sur la carte tire un objet au hasard contre de la
  **ferraille** (remplace la boîte mystère).
- Elle ne donne **que des objets qui ne peuvent pas entrer dans l'arsenal** :
  explosifs et gadgets à lancer ou à poser. Exemples : mine directionnelle,
  grenade collante, grenade, peluche leurre qui attire les zombies, grenade
  surpuissante « Hallelujah ».
- Ces objets se placent sur l'**emplacement de grenade**, comme les grenades du
  jeu actuel.
- ❓ Nombre maximum porté, prix d'un tirage, perte en fin de partie, dégâts face
  aux PV des hautes manches.
- ⚠️ Droits : « Semtex » est une marque réelle et la mine « Claymore » est le nom
  d'une arme réelle très associée à Call of Duty : utiliser des noms originaux.

### 4.13 Puissance ✅
- La **puissance** est la **somme des scores des 3 armes équipées**.
  L'inventaire ne compte pas.
- Elle sert à **informer les autres joueurs**, en plus de son niveau.
- Elle **évolue pendant la partie** et n'est **jamais affichée au hub**.

### 4.14 Énergie du joueur ✅
- L'**énergie** est une jauge **invisible** : aucun affichage au HUD.
- Elle se vide quand le joueur **saute**, **court** ou **frappe avec une arme de
  corps à corps**. Plus une arme demande d'énergie par coup, plus le joueur se
  fatigue vite.
- Le joueur ressent la fatigue par des signes, par exemple un **essoufflement
  audible**.
- À **énergie nulle** :
  - le joueur **ne peut plus courir** ;
  - ses coups de corps à corps sont **50 % plus lents** ;
  - il peut toujours sauter, mais ses sauts sont **plus petits** ;
  - la recharge de l'énergie est **25 % plus lente**.

### 4.15 XP et niveaux ✅
- **Niveau maximum : 50** pour l'instant ; il pourra augmenter avec le temps.
- XP pour passer au niveau suivant : **`100 × niveau^1,8`** (100 XP du niveau 1
  au 2, environ 6 300 au niveau 10, environ 110 000 au niveau 49), à ajuster
  après mesure de l'XP gagnée par partie.
- Au niveau 50, l'XP continue d'être comptée mais le niveau ne bouge plus ; elle
  servira si de nouveaux niveaux sont ajoutés.
- L'XP gagnée pendant une partie est **toujours gardée**, même si la partie est
  perdue.
- 💡 Temps de jeu visé : niveau 10 vers 3 h, niveau 25 vers 25 h, niveau 50
  vers 120 h.
- 💡 Sources d'XP : éliminations, vagues survécues, mini-boss et boss, contrats,
  bonus d'évacuation.

### 4.16 Rapport de fin de partie ✅
- Au retour au hub, un rapport montre le butin gardé : armes ajoutées à
  l'arsenal, versions d'armes mises à jour, échantillons, XP.
- Il mentionne aussi **ce que le joueur n'a pas pu garder** : armes,
  échantillons et améliorations perdus faute d'évacuation.

### 4.17 Bestiaire de profondeur ✅
- De nouveaux types de zombies n'apparaissent qu'à partir de certaines manches
  (par exemple 20, 30, 40).
- Leur fiche reste grisée (« ??? ») au codex tant que le joueur ne les a pas
  rencontrés : la curiosité pousse à aller plus loin.

### 4.18 Défi hebdomadaire ✅
- Un défi identique pour tout le monde chaque semaine (même carte, mêmes
  conditions).
- L'équilibre vient de la ferraille : tout le monde part des mêmes armes de
  base.
- ❓ Contenu exact d'un défi et récompense.

### 4.19 Direction artistique : tout en cubes ✅
- Le jeu **quitte le rendu réaliste** de BO1 pour une identité propre : un style
  **entièrement cubique (voxel)**, dans l'esprit de Trove.
- Les cubes ne sont **ni trop gros ni trop petits** : deux échelles seulement,
  l'une sous-multiple de l'autre (personnages et mobs ; décor et objets).
- **Règle absolue** : aucun élément qui n'est **pas cubique** ou qui ne
  **respecte pas l'échelle des cubes** ne peut entrer dans le jeu. Pas de
  courbe, de biseau, de lissage ni de détail plus fin qu'un cube.
- Les textures sont **toutes à refaire** dans ce style (un pixel de texture = un
  cube, couleurs unies par cube), tout en **respectant l'univers du jeu**
  (hôpital, laboratoire, zombies, survie).
- **Échelle des personnages et des mobs : 1 cube = 2,5 cm** (40 cubes par
  mètre). Un personnage de 1,80 m mesure 72 cubes. Valeur choisie en mesurant
  la planche de référence du zombie (Gemini), dont un pixel fait environ 2 cm
  (environ 90 pixels de haut, une dent = 1 pixel, une jambe = 7 pixels) :
  2,5 cm garde ce niveau de détail tout en restant un sous-multiple exact de
  l'échelle du décor (2 cubes de personnage = 1 cube de décor).
- **Échelle du décor et des objets de la carte : 1 cube = 5 cm** (20 cubes par
  mètre) : une porte fait 40 cubes, un mur de 3 m en fait 60.
- Le **rendu** de référence (planche Gemini) a aussi un **contour noir** autour
  des pièces et un ombrage simple : à reproduire en jeu (❓ contour par shader).
- Pour appliquer la règle :
  - les arêtes des objets sont alignées sur la grille des cubes, et les objets
    posés sur la carte tournent par quarts de tour ;
  - les personnages et zombies en cubes articulés peuvent tourner leurs membres
    à n'importe quel angle quand ils sont animés ;
  - les pentes deviennent des marches de cubes ;
  - les effets (sang, étincelles, flammes, fumée, éclats) sont des particules
    cubiques ;
  - l'éditeur de cartes et l'import de modèles **refusent** un modèle qui ne
    respecte pas la grille (vérification automatique) ;
  - les modèles libres de droits téléchargés doivent être convertis au style
    cubique avant d'entrer dans le jeu.
- L'**interface** (HUD, menus) n'a pas besoin d'être cubique, mais elle doit
  rester **en harmonie** avec le style du jeu.
- ❓ Lumières, post-traitement (brume, lueur) et ciel.

## 5. Mécaniques prototypées (code actuel)

Ce qui existe déjà, hérité du clone de Black Ops 1 Zombies, et ce qu'on en fait.

| Mécanique | Statut | Devenir |
|---|---|---|
| Manches et vagues, nombre de zombies selon les joueurs, PV selon la manche | 🧪 | **Garder** (cœur du jeu) |
| Vagues de chiens (`scripts/game/dogs`) | 🧪 | **Adapter** en première vague spéciale ; refaire la mise en scène (pas d'éclair ni de brouillard façon BO1) |
| Points par élimination | 🧪 | **Adapter** en ferraille personnelle (§4.8) |
| Portes payantes | 🧪 | **Garder**, payées en ferraille |
| Achats muraux | ✔️ | **Supprimés** (remplacés par la station de construction) |
| Atouts (machines à boissons) | ✔️ | **Supprimés** |
| Fenêtres barricadées, reconstruction | 🧪 | **Garder** |
| Pièges à levier | 🧪 | **Garder** |
| État « à terre », réanimation, spectateur | 🧪 | **Garder** tels quels (§4.6) |
| Coop réseau (hôte / client par IP) | 🧪 | **Garder** |
| Couteau | 🧪 | **Garder** comme attaque rapide séparée, en plus de la batte |
| Deux emplacements d'armes (BO1) | ✔️ | **Adaptés** : 3 armes en main + inventaire de 4 places, armes à niveau, rareté et pièces, puissance au tableau des scores (§4.9, §4.12, §4.13) |
| Grenades, singe-tambour | ✔️ | **Adaptés** en objets de la caisse au hasard, sur l'emplacement de grenade (§4.12 bis) |
| Bonus au sol (munitions max, mort instantanée, points doubles…) | ✔️ | **Supprimés** |
| Boîte mystère | ✔️ | **Adaptée** en caisse au hasard payée en ferraille (§4.12 bis) |
| Machine d'amélioration (Pack-a-Punch) | ✔️ | **Supprimée** (les pièces s'installent depuis l'inventaire) |
| Téléporteur, courant | 🧪 | ❓ Selon les cartes |
| Armes merveilles (Claude-Ray, Tonnerre-7) | ✔️ | **Supprimées** (à recréer de façon originale plus tard, si besoin) |
| Sept personnages et leurs voix FR / EN | 🧪 | **Remplacer** par le joueur de baseball unique |
| Dossier de combat (`CareerStats`) | 🧪 | **Adapter** au profil du joueur (XP, niveau, arsenal) |
| Éditeur de cartes, bouton TESTER | 🧪 | **Garder** ; ajouter la **porte d'évacuation** obligatoire et le **schéma des vagues spéciales et de boss** |
| Modèles, textures et décors réalistes (zombies, armes, cartes, `docs/ART_DIRECTION.md`) | 🧪 | **Refaire** en style cubique (§4.19) |
| Lanceur et mises à jour | 🧪 | **Garder** |
| Journal des plantages | 🧪 | **Garder** |

## 6. Éléments liés à Call of Duty à retirer avant toute sortie

- **Nom du jeu** « Claude of Duty Zombie ».
- **Carte KINO** (Kino der Toten à l'échelle 1) : à supprimer.
- **Lore** : Institut Aether, aethérium tombé d'une météorite (calque de
  l'Élément 115).
- **Équipe de quatre archétypes** (Marine américain, Russe, Japonais, savant
  allemand) : copie de l'équipe de BO1.
- **Noms et présentation reconnaissables** : Pack-a-Punch, boîte mystère et
  tableaux à la craie, noms des bonus (Max Ammo, Insta-Kill, Nuke, Carpenter,
  Fire Sale, Death Machine), compteur de manche à la craie, HUD calqué sur BO1,
  machines d'atouts.
- **Armes réelles** sous leurs noms de fabricants.
- **Direction artistique** décrite comme « fidèle à BO1 » (`docs/ART_DIRECTION.md`).

Les mécaniques (vagues, points, portes, barricades) ne sont pas protégées et
peuvent rester. Un avis en propriété intellectuelle est recommandé avant une
commercialisation.

## 6 bis. Valeurs provisoires choisies pendant l'implémentation

Valeurs fixées par l'orchestrateur en l'absence de l'auteur, à confirmer ou
corriger.

| Sujet | Valeur provisoire | Où |
|---|---|---|
| Ferraille par élimination | **50**, quel que soit le coup (tête, couteau, explosion) ; 0 pour un piège ; le coup qui tue ne paie pas la touche en plus | `PointsRules.KILL` |
| Ferraille par touche | **10** par touche de balle ou de couteau qui ne tue pas (tir de fusil à pompe : une touche par zombie) ; 0 pour une explosion, une brûlure, un piège ou le téléporteur ; au plus **10 touches payées par zombie**, tous joueurs confondus | `PointsRules.HIT`, `HIT_CAP` |
| Énergie | 0 à 100 ; course 25/s ; saut 10 ; couteau 8, couteau de chasse 10 ; recharge 40/s après 0,4 s ; **épuisé** de 0 jusqu'à 50 | `docs/ENERGY_PLAN.md` |
| Essoufflement | silencieux au-dessus de 35 % ; halètement tant que le joueur est épuisé ; la respiration de santé basse passe avant | `BreathFeedback` |
| XP d'une partie | 10 par élimination, 50 par manche survécue | `MatchXp` |
| Armes de base | pistolet de départ et couteau (en attendant la batte) | `BaseWeapons` |
| Évacuation : vote | touche d'interaction près de la porte ; 1er appui « partir », puis alterne « prêt » / « partir » | `EvacRules` |
| Évacuation : départ | tous les joueurs non morts ont voté « partir » et sont debout dans la zone (4 m × 3,5 m devant la porte) | `EvacRules` |
| Évacuation : reprise | tous « prêt », ou fin des 2 min : manche suivante 3 s plus tard | `EvacRules` |
| Vague spéciale et boss la même manche | vague de boss si la carte a un boss, sinon vague spéciale | `WaveRules` |
| Commandes de l'équipement | 1 / 2 / 3 : arme en main ; Q (A en AZERTY) et molette : arme suivante ; I : panneau d'inventaire (Échap ferme). Manette : Y arme suivante, croix gauche / bas / droite armes 1 à 3, croix haut inventaire (B ferme) | `Settings` |
| Panneau d'inventaire | la partie continue (même en solo), le joueur ne bouge plus et ne tire plus tant qu'il est ouvert ; une case en main puis une case d'inventaire : échange ; une case vide d'un côté : l'arme passe simplement | `InventoryPanel`, `GameWeapon.swap` |
| Modificateurs des pièces | fractions additionnées par statistique, **positif = bonus** : dégâts, cadence, chargeur, réserve × (1 + m) ; rechargement, recul, précision (dispersion) ÷ (1 + m) ; facteur jamais sous 0,1 ; noms `damage`, `fire_rate`, `reload`, `recoil`, `accuracy`, `mag`, `reserve` | `GameWeapon.MODS` |
| Niveau d'une arme | dégâts × (1 + 0,1 × (niveau − 1)), explosions et brûlure comprises ; multiplié ensuite par les pièces | `GameWeapon.apply` |
| Couteau choisi comme arme de départ | il reste l'attaque de mêlée séparée et ne prend pas d'emplacement en main (en attendant la batte, qui se tiendra en main) | `Session.starting_hands` |
| Mains vides | permis (tout rangé, ou départ au couteau seul) : couteau et grenade restent ; à la réapparition, pistolet de départ seulement si ni main ni inventaire | `MatchRules` |
| Effet légendaire / unique | aucun pour l'instant ; point d'accroche `GameWeapon.visual_effect` | `GameWeapon` |
| Prix de construction | 500 × (1 + 0,15 × (niveau − 1)) × rareté (commune 1, rare 1,5, épique 2,2, légendaire 3,2, unique 4), arrondi à 10 : arme de base 500, niveau 10 rare 1 760, niveau 50 unique 16 700 ; pièces non comptées | `BuildRules.price` |
| Durée de construction | prix < 1 500 : 1 manche, < 4 000 : 2, sinon 3 ; prête à la fin de la manche en cours + durée − 1 (lancée entre deux manches : la suivante compte) | `BuildRules.rounds`, `ready_round` |
| Recharge des munitions (station) | 30 % du prix de construction de l'arme en main, arrondi à 10 (pistolet de base : 150) | `BuildRules.refill_price` |
| Recyclage en partie | 50 % du prix de construction, arrondi à 10 ; arme de base (donnée à tous) : 0 ; arme prêtée à terre : impossible ; dernière arme (main + inventaire, hors arme prêtée, couteau, grenades et arme en construction) : impossible, bouton grisé et refus de l'hôte ; depuis l'inventaire ou la station, deux appuis | `BuildRules.recycle_value`, `recycle_refusal` |
| Station de construction | [F] : interface (la partie continue) ou récupération de l'arme prête ; armes de mêlée non listées (le couteau reste l'attaque séparée) | `BuildStation`, `StationPanel` |
| Armes de butin possibles | toutes les armes à feu de `WeaponDB` **sauf les armes de base** (pistolet de départ), tirage uniforme ; niveau de base de chaque arme = 1 (`WeaponDB.base_level`) | `LootRules` |
| Pose du butin d'arme | à 1,5 m devant chaque joueur à la fin de la vague (2 armes : écartées), visible de tous, ramassable par son seul propriétaire | `LootSystem` |
| Modificateurs d'une pièce trouvée | un premier modificateur toujours en bonus ; 35 % de chances d'un second (autre statistique), malus une fois sur deux ; valeurs de 5 à 25 % par pas de 1 % ; identifiant `part_<1er modificateur>` | `LootRules.roll_part` |
| Pièces et échantillons | rangés directement dans l'onglet de partie (pas d'objet au sol) ; compteur discret à droite du HUD | `LootSystem` |
| Échantillons des chiens | `dog_fang` (croc), `dog_fur` (touffe de poils), `dog_collar` (collier) | `LootRules.SAMPLES` |
| Butin rapporté | armes en main et inventaire, sauf armes de base intactes et pistolet prêté ; exemplaire construit depuis l'arsenal (même `uid`) et amélioré en partie : cette version mise à jour (niveau, rareté, pièces), intact : rien, second exemplaire différent : nouvelle version ; pièces non montées ; échantillons | `ProfileLoot` |

## 7. Questions ouvertes

- Nom définitif du jeu.
- Identité du scientifique, origine de l'épidémie, fin.
- Gains des contrats, déblocage, nombre de contrats actifs.
- Liste des armes, leurs niveaux de base et leurs statistiques.
- Durées et prix exacts de construction et de recharge des munitions.
- Contenu du défi hebdomadaire.
- Liste des cartes et de leurs vagues spéciales et boss.

## 8. Idées écartées

- ❌ **Loot box** (clés de caisses) : abandonnées.
- ❌ **Prestige** : abandonné, car remettre le niveau à zéro rendrait l'arsenal
  inéquipable.
- ❌ **Protection contre la malchance** : le hasard reste pur.
- ❌ **Monnaie permanente** (crédits, marché noir) : pas pour l'instant. La
  ferraille, monnaie de partie remise à zéro, est validée (§4.8).
- ❌ **Armes générées aléatoirement** : les armes sont définies une par une.
- ❌ **Niveau du butin basé sur le niveau du joueur** (plage −13 / +2 et ses
  probabilités) : remplacé par le niveau selon la manche.
- ❌ **Niveaux de difficulté** (normal, difficile, cauchemar) et part du butin
  gardée selon la difficulté.
- ❌ **Objet de soin** améliorable.
- ❌ **Bonus au sol** (munitions max, mort instantanée, points doubles…).
- ❌ **Ferraille qui augmente avec la manche** : le montant par élimination est
  fixe.
- ❌ **Compétence spéciale et arbre de compétences** du personnage.
- ❌ **Ferraille pour les assistances** : seul le joueur qui touche ou qui tue
  gagne de la ferraille.
- ❌ **Atouts** et **achats muraux**.
- ❌ **Table d'amélioration** : les pièces s'installent depuis l'inventaire.
- ❌ **Accélérer une construction**.
- ❌ **Classement du défi hebdomadaire**.
- ❌ **Évacuation individuelle en coop** : toute l'équipe part ensemble.
- ❌ **Plusieurs personnages jouables** : un seul personnage, le joueur de
  baseball.
- ❌ **Machine d'amélioration** (Pack-a-Punch).
- ❌ **Pistes de la recherche d'idées non retenues** : système « Relève +
  Rodage » (trophées qui mûrissent, pièces brutes), labo de terrain, grille de
  fioles, perçage et sceaux.
- ❌ **Scène d'introduction à l'hôpital** : reportée (voir §3).
