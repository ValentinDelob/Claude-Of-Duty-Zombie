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
  ✔️ Modèle cubique fait (cubes de 2,5 cm, équipe fictive, numéro 27) :
  casquette, sous-maillot, liserés, numéros et chaussettes à la couleur du
  joueur (ambre, cyan, rose, vert anis) ; il remplace les sept personnages
  vus par les autres (docs/ART_DIRECTION.md « Joueur de baseball »). ⏳ Ses
  répliques restent à écrire et à valider : en attendant, les voix des sept
  anciens personnages sont gardées (docs/CHARACTERS.md). ❓ Nom et caractère
  du joueur de baseball.
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
- 💡 **Proposition provisoire** (plan complet, écrans et lots :
  `docs/HUB_PLAN.md` ; maquettes : `docs/hub_mockup/`) :
  - contrats écrits dans un **fichier de données** (`assets/data/hub/contracts.json`,
    titres et textes FR / EN) remplissable sans coder ;
  - **rotation par partie jouée** (pas par l'heure) : après chaque partie d'au
    moins une manche, la plus ancienne proposition est remplacée et les cases
    vides sont remplies ; tirage pondéré, sans doublon, selon le niveau ;
  - un contrat daté expiré disparaît aussi des contrats actifs (rien n'est
    consommé avant la remise) ; abandonner un contrat ne coûte rien ;
  - le contrat ne se remet **qu'au hub** ; en partie, un message prévient que
    l'objectif est atteint (« évacuez pour garder vos échantillons ») ;
  - contrats **locaux** à chaque joueur, même en coop.

### 4.2 ter Catalogue d'échanges du scientifique ✅
- En plus des contrats, le scientifique propose un **catalogue d'échanges
  permanent** : le joueur échange ses échantillons contre une **récompense
  précise**, connue d'avance, quand il le veut.
- Exemples : 5 crocs + 3 touffes de poils → une garniture à crocs ; 2 bracelets
  + 1 sangle → une crosse.
- Le farm devient ciblé : le joueur sait quels échantillons il lui faut pour la
  récompense qu'il vise.
- ❓ Contenu du catalogue et niveau des récompenses.
- 💡 **Proposition provisoire** (`docs/HUB_PLAN.md` §6 et §7) : catalogue dans
  `assets/data/hub/exchanges.json` ; récompense précise (pièce aux
  modificateurs exacts ou arme précise de rareté fixée) **au niveau du
  joueur** ; **pas d'XP**, échanges **illimités**, plus chers qu'un contrat
  équivalent (prix de la certitude) ; un échange d'un niveau trop haut reste
  visible, grisé.

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

- ✔️ **Plusieurs types de vagues spéciales par carte** (format de carte 21,
  docs/MAP_AUTHORING.md) : l'éditeur coche les types permis (défaut : tous) ;
  ils reviennent **à tour de rôle** : la k-ième vague spéciale du schéma est
  du type n° (k − 1) modulo le nombre de types (manches de boss exclues).
  Par défaut : meute à la manche 5, Brancardier à la 10, **boss à la 15**,
  Infirmière hurlante à la 20, meute à la 25, boss à la 30, Brancardier à la
  35…
- ✔️ **Vagues de boss** (format de carte 22) : schéma configurable par carte
  dans l'éditeur comme les vagues spéciales (défaut 💡 : toutes les 15
  manches ; 1re manche 0 : carte sans boss) ; types de boss permis
  (`types_boss`, défaut : tous) en rotation ; une manche prévue pour les
  deux est une vague de boss. L'évacuation s'ouvre après une vague de boss
  vaincue comme après une vague spéciale.
- ✔️ **Le Chirurgien**, premier boss (provisoire, §6 bis) : ancien chef du
  bloc opératoire, géant voûté de 2,3 m en cubes de 2,5 cm, blouse verte
  ensanglantée, coiffe, masque déchiré, loupes, gants de latex et un
  **scalpel géant** ; **un seul** par vague, PV selon le nombre de joueurs,
  plus fort à chaque apparition ; **escorte** de 6 zombies par joueur ;
  attaques **télégraphiées** : combo au scalpel au contact (la lame brille,
  « chiing », puis 2 entailles, 3 enragé), **éventail de scalpels** lancés à
  distance (projectiles visibles qu'on esquive), **opération** à 75 % et
  25 % des PV (il se penche sur un patient invisible et relève des zombies
  autour de lui), **phase 2** sous 50 % (il rugit, onde de choc qui
  projette, puis enragé : plus rapide, plus de coups) ; **point faible** :
  son **cœur mutant** qui bat et brille à vif dans sa poitrine ; jauge de
  vie en haut de l'écran ; mort : main sur le cœur, il tombe en arrière
  d'un bloc ; échantillons **scalpel** et **cœur mutant** (20 % sur chaque
  zombie de sa vague, à coup sûr sur lui) ; 2 armes par joueur, plus rares
  que celles d'un mini-boss ; bandeau « LE CHIRURGIEN ENTRE AU BLOC ».
- ✔️ **Le Brancardier** (provisoire, §6 bis) : ancien brancardier de
  l'hôpital devenu une brute de 2,25 m en cubes de 2,5 cm, son brancard
  sanglé dans le dos ; **un par joueur**, avec une **escorte** de 5 zombies
  par joueur ; **charge** en ligne droite **télégraphiée** (il s'arrête,
  gratte le sol du pied, rugit, ses yeux flamboient) qui blesse et
  **projette** les joueurs sur sa route ; contre un mur, il reste **étourdi**
  3 s ; au contact, coup des deux poings ; point faible : la **tête** ; PV
  d'un mini-boss (10 fois un zombie de la manche, +20 % à chaque nouvelle
  apparition dans la partie) ; échantillons **sangle de cuir** et **bracelet
  d'identification**, 20 % chacun sur chaque zombie de la vague (escorte
  comprise) ; bandeau « UN BRANCARDIER APPROCHE ».
- ✔️ **L'Infirmière hurlante** (provisoire, §6 bis ; « The Screaming
  Nurse ») : infirmière de nuit de l'hôpital, grande et décharnée, en cubes
  de 2,5 cm (blouse blanche tachée, coiffe, cheveux noirs filasse, bouche
  béante, gorge déchirée où luisent ses cordes vocales, badge sur la
  poitrine, seringue cassée à la main) ; **une par joueur**, avec une
  **escorte** de 6 zombies par joueur ; elle **garde ses distances** : elle
  fuit quand on s'approche, revient quand on s'éloigne, et ne se bat (coup
  de seringue) qu'acculée ; **cri télégraphié** (elle s'arrête, renverse la
  tête, écarte les bras, sa gorge flamboie, sifflement qui monte) qui
  **étourdit** les joueurs en vue (vue qui tangue, image en cubes,
  déplacement ralenti, légers dégâts ; derrière un mur : rien) et
  **ameute** les zombies proches (ils foncent sur sa proie, les yeux
  allumés) ; point faible : la **gorge** (et la tête) ; une balle dans la
  gorge pendant la préparation **étrangle** le cri ; PV d'un mini-boss
  (8 fois un zombie de la manche, +20 % à chaque nouvelle apparition) ;
  échantillons **cordes vocales**, **seringue cassée** et **badge**, 20 %
  chacun sur chaque zombie de la vague ; bandeau « L'INFIRMIÈRE FAIT SA
  RONDE ». Aucun son du jeu n'est baissé pendant le cri (pas de
  « ducking ») : le joueur étourdi entend un acouphène en plus.

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

✔️ **Liste provisoire appliquée** (`docs/WEAPONS.md`, à valider) : les 27 armes
à feu ont un **nom original** FR / EN (PÉTOIRE, CRÉCELLE, BRISE-OS,
TRIPLETTE, BÉTONNEUSE, LONGUE-VUE, TROMBONE, ÉPROUVETTE…, aucun nom de
fabricant ni de modèle réel ; les identifiants internes restent ceux de
l'ancien arsenal), une **famille** et un **niveau de base** réparti de 1 à
50 selon la puissance (le butin ne tire que les armes de niveau de base
≤ manche + 2) ; statistiques inchangées ; **silhouettes originales en cubes
de 2,5 cm** (§ 4.19).

### 4.10 Armes de départ ✅
- Au hub, chaque joueur choisit **jusqu'à 3 armes de départ** (au moins 1).
- Ce choix se fait uniquement parmi les **armes de base** : **niveau 1,
  communes, sans amélioration**, données à tous les joueurs. Exemple : une
  **batte de baseball** et un **pistolet de départ** peu efficace.
- Un emplacement non choisi reste vide au départ.
- Une arme de base améliorée en partie et ramenée devient une **nouvelle
  version** dans l'arsenal ; l'arme de base reste toujours disponible.
- ✔️ **Armes de base appliquées** : la **PÉTOIRE** (pistolet de départ) et la
  **BATTE** de baseball, arme de corps à corps tenue en main (elle prend un
  emplacement d'arme ; le couteau reste l'attaque rapide séparée) : 250
  dégâts, 1,25 coup par seconde, 15 d'énergie par coup (couteau : 8), fente
  comme le couteau, jusqu'à 2 zombies par coup (`docs/WEAPONS.md`, valeurs
  provisoires). Sélection par défaut : les deux.

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
- ✔️ **Barème appliqué** (référence complète et méthode pour tout nouveau mob :
  `docs/XP_RULES.md`) :
  - chaque élimination rapporte l'XP de son **type d'ennemi** (catégories
    commun / spécial / mini-boss / boss), au seul joueur qui tue, multipliée
    par un **bonus de manche** (+15 % par manche, jusqu'à ×5) : survivre plus
    longtemps rapporte plus ;
  - manche survécue et vague spéciale ou de boss vaincue : à chaque joueur
    non mort ; évacuation réussie : +25 % de l'XP de la partie ;
  - l'XP est comptée par l'hôte pendant la partie, affichée discrètement
    (« +N XP », compteur de partie), puis ajoutée **une fois** au profil à la
    fin, quelle que soit l'issue (ou si le joueur quitte) ; l'écran de fin
    montre le détail, le niveau avant / après et la progression ;
  - simulation de calibrage : niveau 10 en ≈ 2,5 h, 25 en ≈ 20 h, 50 en
    ≈ 116 h (vagues spéciales en rotation, Brancardier, Infirmière et
    Chirurgien compris) ;
  - les contrats (§4.2) ajouteront leur XP au hub ; le niveau du joueur y
    servira pour l'arme ou la pièce offerte.

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
- 🧪 **Implémenté** : onglet **CODEX** du hub, avant PARTIE (docs/HUB_PLAN.md
  §3.10). « Rencontré » = coup porté, coup reçu ou élimination, compté pour
  chaque joueur (coop comprise) et ajouté au profil à la fin de la partie
  avec l'XP. Une fiche inconnue ne montre que la manche à partir de laquelle
  l'ennemi peut apparaître ; une fiche connue montre nom, description,
  éliminations, échantillons et XP. Fiches dans
  `assets/data/hub/codex.json` (Infirmière hurlante active depuis sa vague
  spéciale, manche 20 depuis le boss de la 15 ; le Chirurgien est en jeu :
  manche 15, son propre barème).

### 4.18 Défi hebdomadaire ✅
- Un défi identique pour tout le monde chaque semaine (même carte, mêmes
  conditions).
- L'équilibre vient de la ferraille : tout le monde part des mêmes armes de
  base.
- 💡 **Règles provisoires appliquées** (à valider ; valeurs : §6 bis ;
  code : `WeeklyChallenge`, réserve `assets/data/hub/weekly.json`) :
  - **calculé hors ligne**, sans serveur, depuis le **numéro de semaine ISO**
    (lundi 0 h UTC au lundi suivant) : une **carte** du jeu (avec porte
    d'évacuation et station de construction), une **graine** de partie et
    **1 à 2 modificateurs** tirés dans la réserve ; même semaine et même
    version du jeu = même défi pour tout le monde ;
  - **modificateurs** (noms et textes FR / EN dans la réserve) : Horde pressée
    (zombies et chiens +15 % de vitesse), Peau de cuir (+25 % de PV), En
    retard (départ à la manche 6), Fonds de tiroir (armes trouvées toutes
    communes), Station en panne (pas de station : ni construction ni
    recharge) ;
  - **conditions égales** : tout le monde part avec **toutes les armes de
    base** (PÉTOIRE et BATTE, niveau 1, communes), quelle que soit la
    sélection de DÉPART ; l'**arsenal et les pièces du profil ne servent
    pas** (la station ne construit que les armes de base) ;
  - **butin de la partie jamais gardé** (armes, pièces, échantillons), même
    après une évacuation ; l'**XP** de la partie est gardée comme d'habitude ;
  - **objectif** : s'évacuer à la **manche 10 ou plus** ; **récompense une
    fois par semaine** : XP (400 de base, selon le niveau comme un contrat)
    et des **échantillons** (4 crocs, 3 touffes, 2 colliers) ; le **meilleur
    résultat** de chaque semaine (manche atteinte, manche d'évacuation) est
    gardé au profil (12 dernières semaines) ;
  - au hub, onglet **PARTIE** : ligne **DÉFI DE LA SEMAINE** au-dessus des
    cartes (carte, modificateurs, objectif, meilleur résultat, temps
    restant, récompense, LANCER LE DÉFI) ; en **coop**, l'hôte choisit le
    défi dans CHANGER DE CARTE et **son défi s'applique à tout le groupe** ;
    chacun reçoit sa récompense dans son propre profil.

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
    cubiques ✅ : cubes de 2,5 à 5 cm (éclats, sang, étincelles) ou 5 à 15 cm
    (flammes, fumée), couleur unie, qui disparaissent en rétrécissant ; arcs
    électriques en chaînes de cubes ; trous de balle et taches de sang en
    pixel art aligné (docs/ART_DIRECTION.md « Effets cubiques ») ;
  - l'éditeur de cartes et l'import de modèles **refusent** un modèle qui ne
    respecte pas la grille (vérification automatique) ;
  - les modèles libres de droits téléchargés doivent être convertis au style
    cubique avant d'entrer dans le jeu.
- L'**interface** (HUD, menus) n'a pas besoin d'être cubique, mais elle doit
  rester **en harmonie** avec le style du jeu.
- ✅ **Architecture des cartes en cubes de 5 cm** (docs/VOXEL_ARCHITECTURE_PLAN.md,
  fait) : sols, plafonds, murs droits, en biais et courbes (escaliers de
  marches de 10 cm), piliers, escaliers (marches de 15 ou 20 cm), rampes,
  colimaçon, garde-corps et pentes (terrasses) ; toutes les cartes du jeu
  (BUNKER K-7, DRAFT ARENA, test_levels) et celles de l'éditeur, vérifiées
  automatiquement (`LayoutCheck`).
- ✅ **Objets tenus en cubes de 2,5 cm** (fait, `docs/WEAPONS.md`,
  docs/ART_DIRECTION.md « Armes, mains et objets tenus ») : toutes les armes,
  la batte, le couteau, les mains et avant-bras de la vue FPS (gants de
  batteur, maillot d'une équipe fictive sans logo), la grenade, la peluche
  leurre et les cartouches tenues ; vus de la même façon par les autres
  joueurs ; vérifiés par `voxel_check`.
- ✅ **Textures de toutes les surfaces en pixel art**, un pixel = un cube de
  5 cm, dans l'univers hôpital / laboratoire / bunker (textures importées
  d'une carte réduites au même grain).
- ✅ **Ciel des cartes cubique** (fait) : dégradé en bandes, nuages en
  cubes le jour, étoiles en pixels carrés et lune en pixel art la nuit
  (`cube_sky.gdshader`, mêmes options : noir, jour, nuit, luminosité).
- ✅ **Menus et étiquettes 3D en harmonie** (fait) : police en cubes pour les
  titres, le logo et toutes les `Label3D` ; fond du menu titre cubique
  (couloir du laboratoire, zombie cubique qui passe) ; docs/ART_DIRECTION.md
  « Menus », « Ciel », « Étiquettes 3D ».
- ❓ Lumières, post-traitement (brume, lueur).

## 5. Mécaniques prototypées (code actuel)

Ce qui existe déjà, hérité du clone de Black Ops 1 Zombies, et ce qu'on en fait.

| Mécanique | Statut | Devenir |
|---|---|---|
| Manches et vagues, nombre de zombies selon les joueurs, PV selon la manche | 🧪 | **Garder** (cœur du jeu) |
| Vagues de chiens (`scripts/game/dogs`) | ✔️ | **Adaptées** en première vague spéciale, la « meute » : chiens errants contaminés en cubes de 2,5 cm (`dog_voxel.py`) ; mise en scène propre au jeu : bandeau « LA MEUTE APPROCHE », alerte de confinement (sirène, Geiger), compteur en alerte orange, aboiements lointains, chiens tapis hors de vue qui jaillissent, mort sur le flanc (ni éclair ni brouillard façon BO1) |
| Vague spéciale du Brancardier (`scripts/game/brancardier`) | ✔️ | **Nouveau** mini-boss original (§4.4), en rotation avec la meute ; modèle en cubes de 2,5 cm (`brancardier_voxel.py`), charge télégraphiée, projection, étourdi contre un mur, escorte, sons procéduraux, coop (hôte autoritaire) |
| Vague de boss du Chirurgien (`scripts/game/surgeon`) | ✔️ | **Nouveau** premier boss original (§4.4), toutes les 15 manches par défaut ; modèle en cubes de 2,5 cm (`surgeon_voxel.py`), cœur mutant lumineux (point faible), combo au scalpel, scalpels lancés, opérations qui relèvent des zombies, phase 2 avec onde de choc, jauge de vie, escorte, sons procéduraux, coop (hôte autoritaire) |
| Vague spéciale de l'Infirmière hurlante (`scripts/game/nurse`) | ✔️ | **Nouveau** mini-boss original (§4.4), 3e type de la rotation ; modèle en cubes de 2,5 cm (`nurse_voxel.py`), garde ses distances et fuit, cri télégraphié qui étourdit (effet d'écran en cubes, ralenti) et ameute les zombies, gorge point faible (cri étranglé), escorte, sons procéduraux, coop (hôte autoritaire) |
| Points par élimination | 🧪 | **Adapter** en ferraille personnelle (§4.8) |
| Portes payantes | 🧪 | **Garder**, payées en ferraille |
| Achats muraux | ✔️ | **Supprimés** (remplacés par la station de construction) |
| Atouts (machines à boissons) | ✔️ | **Supprimés** |
| Fenêtres barricadées, reconstruction | 🧪 | **Garder** |
| Pièges à levier | 🧪 | **Garder** |
| État « à terre », réanimation, spectateur | 🧪 | **Garder** tels quels (§4.6) |
| Coop réseau (hôte / client par IP) | 🧪 | **Garder** |
| Couteau | ✔️ | **Gardé** comme attaque rapide séparée, en plus de la batte de baseball (arme de base tenue en main) |
| Deux emplacements d'armes (BO1) | ✔️ | **Adaptés** : 3 armes en main + inventaire de 4 places, armes à niveau, rareté et pièces, puissance au tableau des scores (§4.9, §4.12, §4.13) |
| Grenades, singe-tambour | ✔️ | **Adaptés** en objets de la caisse au hasard, sur l'emplacement de grenade (§4.12 bis) |
| Bonus au sol (munitions max, mort instantanée, points doubles…) | ✔️ | **Supprimés** |
| Boîte mystère | ✔️ | **Adaptée** en caisse au hasard payée en ferraille (§4.12 bis) |
| Machine d'amélioration (Pack-a-Punch) | ✔️ | **Supprimée** (les pièces s'installent depuis l'inventaire) |
| Téléporteur, courant | 🧪 | ❓ Selon les cartes |
| Armes merveilles (Claude-Ray, Tonnerre-7) | ✔️ | **Supprimées** (à recréer de façon originale plus tard, si besoin) |
| Sept personnages et leurs voix FR / EN | ✔️ / 🧪 | **Remplacés** à l'écran par le joueur de baseball unique en cubes (`player_voxel.glb`, couleur du joueur ; sélecteur PERSONNAGE retiré des options) ; ⏳ leurs **voix** restent en attendant les répliques du joueur de baseball (à valider par l'utilisateur) |
| Dossier de combat (`CareerStats`) | 🧪 | **Adapter** au profil du joueur (XP, niveau, arsenal) |
| Éditeur de cartes, bouton TESTER | 🧪 | **Garder** ; ajouter la **porte d'évacuation** obligatoire et le **schéma des vagues spéciales et de boss** |
| Modèles, textures et décors réalistes (zombies, armes, cartes, `docs/ART_DIRECTION.md`) | 🧪 | **Refaire** en style cubique (§4.19) |
| HUD façon BO1 (compteur de manche à la craie et rouge sang, couleurs des joueurs, « GAME OVER », écran de chargement) | ✔️ | **Remplacé** par un HUD propre au jeu : police et chiffres en cubes, palette « laboratoire en alerte », « LA HORDE L'EMPORTE » (§6, `docs/ART_DIRECTION.md`) ; disposition des éléments inchangée |
| Ritournelles imitant BO1 (annonce des chiens avec voix d'annonceur, début et fin de manche, jingle de la boîte) | ✔️ | **Recomposées** : alerte de confinement, sas et bips de moniteurs, carillon, barillet, thème du menu et lancement d'une partie (`docs/ASSETS.md`) ; peluche leurre à suivre (§6) |
| Lanceur et mises à jour | 🧪 | **Garder** |
| Journal des plantages | 🧪 | **Garder** |

## 6. Éléments liés à Call of Duty à retirer avant toute sortie

État au 11/10/2026 (inventaire du lot « retrait de Call of Duty ») :
✔️ fait, ⏳ à faire (raison), 📜 historique (laissé tel quel, marqué).

| Élément | État |
|---|---|
| **Nom du jeu** « Claude of Duty Zombie » (titre de la fenêtre, logo, crédits, salon, lanceur, exécutable) | ⏳ attend le nom définitif (§7) ; à changer partout d'un coup. Dans le jeu, une seule constante : `GameName.NAME` (logo, crédits, journal de démarrage, rapport de plantage ; un test vérifie que project.godot la suit) ; restent project.godot, export_presets.cfg, le lanceur et les contrôles de `tools/release.sh` / `tools/promote.sh` (docs/ARCHITECTURE.md « Nom du jeu ») ; le logo se met en page seul pour un nom d'un, deux ou plusieurs mots |
| **Carte KINO** (Kino der Toten à l'échelle 1) | ✔️ retirée du jeu (`Settings.RETIRED_MAPS`) ; les anciennes notes de version du lanceur la citent encore (📜) |
| **Lore** Institut Aether, aethérium (calque de l'Élément 115) | ✔️ remplacé par le lore du scientifique (§3) ; « Feux follets (115) » de l'éditeur renommés « Feux follets » (lueurs toxiques) ; ⏳ encore dans des répliques des personnages (`assets/voices/arakawa.json`, `berg.json`, `weissmann.json` : « aethérium »), qui partiront avec les 7 personnages |
| **Équipe de quatre archétypes** (Marine, Russe, Japonais, savant allemand), les 7 personnages et leurs voix | ✔️ modèles et tenues vus par les autres remplacés par le joueur de baseball (§3), choix du personnage retiré des options ; ⏳ voix (répliques du joueur de baseball à écrire), tenues des mains FPS (refonte des armes et des mains) et crédits qui les citent encore |
| **Annonceur** | ✔️ aucune voix d'annonceur dans le jeu (la voix démoniaque de l'annonce des chiens est retirée) |
| **Pack-a-Punch**, **boîte mystère**, **machines d'atouts**, **bonus au sol** (Max Ammo, Insta-Kill, Nuke, Carpenter, Fire Sale, Death Machine), **armes murales et tableaux à la craie** | ✔️ supprimés ou adaptés (§5) ; noms internes `pap`, `MysteryBox`, `pap_zap_*` gardés (jamais affichés) ; note de l'éditeur sur les objets retirés : « machine d'amélioration » |
| **Compteur de manche à la craie / rouge sang** (bâtons 1 à 5, chiffres peints, transitions blanc <-> rouge) | ✔️ remplacé par des chiffres en cubes menthe et des transitions propres (cubes qui tombent en place, veille, alerte orange des vagues spéciales) |
| **HUD calqué sur BO1** (couleurs des joueurs blanc / bleu / jaune / vert, invites « [Coût : 500] », titres blanc craie liserés de rouge) | ✔️ palette « laboratoire en alerte », police en cubes pour les grands titres, joueurs ambre / cyan / rose / vert anis, invites « · 950 ferraille » (disposition des éléments inchangée) |
| **Écran de fin** « GAME OVER » / « Vous avez survécu N manches » | ✔️ « LA HORDE L'EMPORTE » / « THE HORDE WINS » ou « ÉVACUATION RÉUSSIE », manche atteinte et durée ; session perdue : « PARTIE INTERROMPUE » / « GAME INTERRUPTED » au menu ; résumé de TESTER dans l'éditeur : « La horde l'emporte — ... » |
| **Écran de chargement** (nom de la carte au pochoir rouge sang) | ✔️ fond bleu-noir, nom en cubes, rangée de cubes qui s'allument |
| **Sons imitant BO1** : annonce des chiens (cuivres, tonnerre, **voix démoniaque d'annonceur**), début et fin de manche (cuivres, glas, boîte à musique), jingle de la boîte mystère, musique des chiens | ✔️ recomposés : alerte de confinement, sas et bips de moniteurs, carillon de fin, barillet de la caisse, thème du menu (néons, moniteurs, synthé, sirène lointaine) et lancement (sas, bips d'alarme) (docs/ASSETS.md) ; ⏳ `monkey_music` (air du singe-tambour encore joué par la peluche leurre, à recomposer avec l'objet leurre) |
| **Menu titre « style BO1 »** (logo au pochoir, rouge sang, chœur) et **options** (« comme BO1 », « comme dans Black Ops ») | ✔️ style propre au jeu : palette du laboratoire en alerte (jaune des bandes de danger, menthe des moniteurs), titres et logo en police en cubes, plus de police pochoir ni de rouge sang, fond 3D cubique (couloir du laboratoire, zombie cubique qui passe) ; options sans référence à BO1 ni à Black Ops (docs/ART_DIRECTION.md « Menus ») |
| **Crédits** (« chiens de l'enfer / hellhounds », « annonces / announcer », personnages Callahan..., « aucune image externe », « polices système ») | ✔️ exacts : chiens errants contaminés, alertes, les 7 personnages et leurs outils de voix (Chatterbox, Kokoro, Qwen3-TTS, Seed-VC), modèles en cubes faits avec Blender (voxel_lib), police en cubes et polices système non fournies ; nom du jeu lu dans `GameName` ; ⏳ personnage unique à venir |
| **Éditeur de cartes** : avertissements « BO1 : ... », « INDICATEURS (BO1) », « BO1 Kino : deux grandes boucles », info-bulles | ✔️ « conseillé : ... », sans référence à BO1 |
| **Armes réelles** sous leurs noms de fabricants | ✔️ renommées (noms originaux FR / EN, identifiants internes gardés, jamais affichés) et silhouettes refaites en cubes : `docs/WEAPONS.md` |
| **Direction artistique** « fidèle à BO1 » (`docs/ART_DIRECTION.md`) | ✔️ style cubique (§4.19) ; les sections BO1 restantes sont marquées « Historique » (📜) |
| Notes de version du lanceur (`changelogs/changelogs.json` : KINO, Pack-a-Punch, Juggernog...) | 📜 historique des versions déjà publiées ; ⏳ à remettre à zéro avec le nouveau nom avant la sortie ; les prochaines notes ne citent plus BO1 |
| Documents de développement (README, docs/) | 📜 références techniques à BO1 (règles de vagues, mesures) gardées, internes |

Ce qui restait dans `scripts/ui/` (lot du menu titre, 11/10/2026) : ✔️ fait.
- `main_menu.gd` : « PARTIE TERMINÉE / GAME OVER » (session perdue) ->
  « PARTIE INTERROMPUE » / « GAME INTERRUPTED » ✔️ ;
- `menu_logo.gd`, `credits_screen.gd` : nom du jeu lu dans `GameName.NAME`
  (seul endroit du code), logo en lettres de cubes ✔️ — ⏳ le nom lui-même
  attend la décision de l'utilisateur ;
- `ui_style.gd`, `menu_style.gd`, `menu_logo.gd`, `menu_backdrop.gd` : plus
  de police pochoir ni de rouge sang (`BLOOD`, `BLOOD_BRIGHT` supprimés),
  palette et police en cubes du HUD et du hub ✔️ ;
- `options_screen.gd` : plus de « comme BO1 » ni de « comme dans Black Ops »
  ✔️ ;
- `credits_screen.gd` : textes exacts ✔️ (voir la ligne « Crédits ») ;
- sons du menu (`tools/gen_audio_menu.gd`) : `menu_theme` et `menu_start`
  recomposés ✔️.

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
| Énergie | 0 à 100 ; course 25/s ; saut 10 ; couteau 8, couteau de chasse 10, batte 15 ; recharge 40/s après 0,4 s ; **épuisé** de 0 jusqu'à 50 | `docs/ENERGY_PLAN.md` |
| Essoufflement | silencieux au-dessus de 35 % ; halètement tant que le joueur est épuisé ; la respiration de santé basse passe avant | `BreathFeedback` |
| XP par élimination | selon le type, à la manche 1 : marcheur, coureur, sprinteur, rampant **4** ; chien **12** ; Brancardier **60** (mini-boss) ; Infirmière hurlante **60** (mini-boss) ; Chirurgien **240** (boss) ; mini-boss (référence) **60** ; boss (référence) **240** ; × bonus de manche **1 + 0,15 × (manche − 1)**, plafonné à **×5** ; au seul tueur (piège : celui qui l'a activé) | `XpRules`, `docs/XP_RULES.md` |
| XP hors élimination | manche survécue **3 × manche** ; vague spéciale vaincue **60**, vague de boss **240** (× bonus de manche) ; à chaque joueur non mort à la fin de la manche ; évacuation **+25 %** de l'XP de la partie | `XpRules` |
| XP gardée | comptée par l'hôte pendant la partie, ajoutée une fois au profil à la fin (évacuation ou défaite) ou au départ d'un joueur en cours de partie (sans bonus) ; le niveau ne change pas pendant la partie | `XpSystem`, `MatchXp` |
| Armes de base | pistolet de départ (PÉTOIRE) et batte de baseball (BATTE, arme de corps à corps tenue en main) ; sélection par défaut : les deux ; un ancien profil qui avait choisi le couteau reçoit la batte | `BaseWeapons` |
| Évacuation : vote | touche d'interaction près de la porte ; 1er appui « partir », puis alterne « prêt » / « partir » | `EvacRules` |
| Évacuation : départ | tous les joueurs non morts ont voté « partir » et sont debout dans la zone (4 m × 3,5 m devant la porte) | `EvacRules` |
| Évacuation : reprise | tous « prêt », ou fin des 2 min : manche suivante 3 s plus tard | `EvacRules` |
| Vague spéciale et boss la même manche | vague de boss si la carte a un boss (vagues de boss prévues : 1re manche > 0 ; par défaut oui, le Chirurgien), sinon vague spéciale | `WaveRules.has_boss` |
| Commandes de l'équipement | 1 / 2 / 3 : arme en main ; Q (A en AZERTY) et molette : arme suivante ; I : panneau d'inventaire (Échap ferme). Manette : Y arme suivante, croix gauche / bas / droite armes 1 à 3, croix haut inventaire (B ferme) | `Settings` |
| Panneau d'inventaire | la partie continue (même en solo), le joueur ne bouge plus et ne tire plus tant qu'il est ouvert ; une case en main puis une case d'inventaire : échange ; une case vide d'un côté : l'arme passe simplement | `InventoryPanel`, `GameWeapon.swap` |
| Modificateurs des pièces | fractions additionnées par statistique, **positif = bonus** : dégâts, cadence, chargeur, réserve × (1 + m) ; rechargement, recul, précision (dispersion) ÷ (1 + m) ; facteur jamais sous 0,1 ; noms `damage`, `fire_rate`, `reload`, `recoil`, `accuracy`, `mag`, `reserve` | `GameWeapon.MODS` |
| Niveau d'une arme | dégâts × (1 + 0,1 × (niveau − 1)), explosions et brûlure comprises ; multiplié ensuite par les pièces | `GameWeapon.apply` |
| Batte de baseball | 250 dégâts, 1,25 coup/s, 15 d'énergie par coup, portée 2,2 m, fente 3 m, jusqu'à 2 zombies par coup ; prend un emplacement en main ; tir = coup (maintenu : coup droit puis revers) ; ni munitions ni visée ; le couteau reste l'attaque de mêlée séparée | `WeaponDB` « bat », `Combat.srv_swing`, `docs/WEAPONS.md` |
| Noms et niveaux des armes | noms originaux FR / EN, familles, niveaux de base de 1 à 50 selon la puissance (statistiques inchangées) | `WeaponDB`, `docs/WEAPONS.md` |
| Mains vides | permis (tout rangé) : couteau et grenade restent ; à la réapparition, pistolet de départ seulement si ni main ni inventaire | `MatchRules` |
| Effet légendaire / unique | aucun pour l'instant ; point d'accroche `GameWeapon.visual_effect` | `GameWeapon` |
| Prix de construction | 500 × (1 + 0,15 × (niveau − 1)) × rareté (commune 1, rare 1,5, épique 2,2, légendaire 3,2, unique 4), arrondi à 10 : arme de base 500, niveau 10 rare 1 760, niveau 50 unique 16 700 ; pièces non comptées | `BuildRules.price` |
| Durée de construction | prix < 1 500 : 1 manche, < 4 000 : 2, sinon 3 ; prête à la fin de la manche en cours + durée − 1 (lancée entre deux manches : la suivante compte) | `BuildRules.rounds`, `ready_round` |
| Recharge des munitions (station) | 30 % du prix de construction de l'arme en main, arrondi à 10 (pistolet de base : 150) | `BuildRules.refill_price` |
| Recyclage en partie | 50 % du prix de construction, arrondi à 10 ; arme de base (donnée à tous) : 0 ; arme prêtée à terre : impossible ; dernière arme (main + inventaire, hors arme prêtée, couteau, grenades et arme en construction) : impossible, bouton grisé et refus de l'hôte ; depuis l'inventaire ou la station, deux appuis | `BuildRules.recycle_value`, `recycle_refusal` |
| Station de construction | [F] : interface (la partie continue) ou récupération de l'arme prête ; la batte (tenue en main) est listée et construite comme une arme à feu, sans recharge de munitions ; le couteau reste l'attaque séparée, non listé | `BuildStation`, `StationPanel` |
| Armes de butin possibles | toutes les armes de `WeaponDB` **sauf les armes de base** (pistolet de départ, batte) dont le niveau de base est ≤ manche + 2, tirage uniforme ; niveaux de base de 1 à 50 (`WeaponDB.base_level`, `docs/WEAPONS.md`) | `LootRules` |
| Pose du butin d'arme | à 1,5 m devant chaque joueur à la fin de la vague (2 armes : écartées), visible de tous, ramassable par son seul propriétaire | `LootSystem` |
| Modificateurs d'une pièce trouvée | un premier modificateur toujours en bonus ; 35 % de chances d'un second (autre statistique), malus une fois sur deux ; valeurs de 5 à 25 % par pas de 1 % ; identifiant `part_<1er modificateur>` | `LootRules.roll_part` |
| Pièces et échantillons | rangés directement dans l'onglet de partie (pas d'objet au sol) ; compteur discret à droite du HUD | `LootSystem` |
| Échantillons des chiens | `dog_fang` (croc), `dog_fur` (touffe de poils), `dog_collar` (collier) | `LootRules.SAMPLES` |
| Rotation des vagues spéciales | types permis par la carte (défaut : meute, Brancardier et Infirmière hurlante) à tour de rôle dans l'ordre meute, Brancardier, Infirmière : la k-ième vague spéciale du schéma est du type n° (k − 1) mod n (manches de boss exclues) ; sans boss : meute 5, 20, 35…, Brancardier 10, 25, 40…, Infirmière 15, 30, 45… ; avec le boss par défaut (15, 30, 45…) : meute 5, 25, 50…, Brancardier 10, 35, 55…, Infirmière 20, 40, 65… ; conséquence : sur une carte aux trois types, chaque type revient trois fois moins souvent (contrats des chiens ≈ 3 fois plus longs à remplir) ; une carte qui listait « meute » et « brancardier » garde ces deux types (pas d'Infirmière) ; pas de changement de format | `WaveRules.special_type_at`, format de carte 21 |
| Brancardier : composition | **1 par joueur** (au plus 6, 4 vivants à la fois), apparition à 12–28 m, hors de vue de préférence, 4 s entre deux ; **escorte** de **5 zombies ordinaires par joueur** (au plus 20) après l'annonce de 6 s ; la vague finit quand Brancardiers et escorte sont tués | `BrancardRules` |
| Brancardier : PV | **10 × PV d'un zombie de la manche × (1 + 0,2 × (rang − 1))**, rang = n° de sa vague dans la partie : manche 10 (1re) 10 500, manche 20 (2e) 24 600, manche 30 (3e) 42 700 ; modificateur « zombies coriaces » du défi appliqué | `BrancardRules.health` |
| Brancardier : charge | portée 4 à 15 m, en vue, même niveau, corps qui passe ; 5 s entre deux ; préparation **1,3 s** (immobile, sabot qui gratte 3 fois, rugissement, yeux qui flamboient) ; charge **8,5 m/s**, 2,2 s au plus, traverse zombies et joueurs ; joueur sur sa route (1,15 m) : **45 dégâts** et projection (7 m/s devant, 4,5 m/s de côté, 3,5 m/s en l'air, 0,35 s), une fois par charge ; mur de face : **étourdi 3 s** (immobile, recule d'un pas) | `BrancardRules` |
| Brancardier : contact et déplacement | marche lourde 1,7 m/s ; coup des deux poings à 1,6 m, **60 dégâts** à 0,6 s (portée 2 m) ; aucun démembrement, ignore la peluche leurre ; point faible : la tête (multiplicateur de tête de l'arme, aucune résistance) | `Brancardier` |
| Échantillons du Brancardier | `brancard_strap` (sangle de cuir), `brancard_bracelet` (bracelet d'identification), 20 % chacun sur **chaque zombie de la vague** (escorte comprise : à un joueur, 6 tirages par vague, comme la première meute) | `LootRules.SAMPLES`, `LootSystem.special_kind` |
| Brancardier : nom anglais | « Stretcher-Bearer » ; bandeau « UN BRANCARDIER APPROCHE » / « A STRETCHER-BEARER IS COMING » (coop : « DES BRANCARDIERS APPROCHENT ») | `BrancardRound` |
| 💡 Vagues de boss : schéma | défaut **toutes les 15 manches** (15, 30, 45…), réglable par carte dans l'éditeur (1re manche, écart ; 0 : aucun boss) ; types de boss permis (`types_boss`, défaut : tous, aujourd'hui le Chirurgien seul) en rotation ; carte d'un format ≤ 21 : défaut | `WaveRules`, format de carte 22 |
| 💡 Chirurgien : composition | **un seul** par vague de boss, apparition à 14–30 m d'un joueur, hors de vue de préférence, après l'annonce de **7 s** ; **escorte** de **6 zombies ordinaires par joueur** (au plus 24) ; la vague finit quand le boss, l'escorte et ses patients sont tués ; égaré loin des joueurs : replacé près d'eux avec ses PV | `SurgeonRules`, `SurgeonRound` |
| 💡 Chirurgien : PV | **30 × PV d'un zombie de la manche × (1 + 0,75 × (joueurs − 1)) × (1 + 0,25 × (rang − 1))** : manche 15 seul 46 500, à 4 151 125 ; manche 30 (2e) seul 114 375 ; modificateur « Peau de cuir » du défi appliqué (comme sa vitesse « Horde pressée ») | `SurgeonRules.health` |
| 💡 Chirurgien : attaques | marche 1,9 m/s (enragé 2,7) ; **combo** au contact (< 2,3 m) : préparation **0,65 s** (0,42 enragé, lame qui brille), **2 entailles** (3 enragé) de 0,42 s avec une fente, **35 dégâts** chacune dans un arc de ±66° à 2,7 m, 1,4 s avant le suivant ; **scalpels** à 5–20 m en vue : préparation **0,85 s** (0,6), éventail de **3** (5) scalpels à 15 m/s, **22 dégâts** chacun, un toutes les 6,5 s (4) ; **opérations** à **75 %** et **25 %** des PV : 3,2 s immobile, **2 patients par joueur** (au plus 8), zombies ordinaires de la manche ; **phase 2** à **50 %** : rugissement 2,2 s, **onde de choc** à 4,5 m (**20 dégâts**, projection) ; point faible : le **cœur** (multiplicateur de tête de l'arme), la tête compte comme le corps ; ni démembrement, ni leurre | `SurgeonRules`, `Surgeon` |
| 💡 Chirurgien : butin | échantillons `surgeon_scalpel` (scalpel), `surgeon_heart` (cœur mutant), **20 %** chacun sur chaque zombie de sa vague (escorte, patients) et **à coup sûr** sur lui, pour chaque joueur (seul : ≈ 3 de chaque par vague) ; **2 armes par joueur**, raretés de boss : commune 40 %, rare 27 %, épique 20 %, légendaire 9 %, unique 4 % | `LootRules.SAMPLES`, `BOSS_SAMPLE_CHANCE`, `RARITY_WEIGHTS_BOSS` |
| 💡 Chirurgien : textes | « The Surgeon » ; bandeaux « LE CHIRURGIEN ENTRE AU BLOC » / « THE SURGEON IS SCRUBBING IN », « IL OPÈRE : LES PATIENTS SE RELÈVENT », « LE CHIRURGIEN PERD PATIENCE », « LE CHIRURGIEN RACCROCHE SA BLOUSE » ; jauge « LE CHIRURGIEN » en haut de l'écran | `SurgeonRound`, `BossBar` |
| Infirmière hurlante : composition | **1 par joueur** (au plus 4, 3 vivantes à la fois), apparition à 12–26 m, hors de vue de préférence, 4 s entre deux ; **escorte** de **6 zombies ordinaires par joueur** (au plus 24) après l'annonce de 6 s ; la vague finit quand Infirmières et escorte sont tuées | `NurseRules` |
| Infirmière hurlante : PV | **8 × PV d'un zombie de la manche × (1 + 0,2 × (rang − 1))** : manche 20 (1re, la 15 étant de boss) 16 400, manche 40 (2e) 38 880 ; plus fragile que le Brancardier (elle fuit) ; modificateurs du défi appliqués | `NurseRules.health` |
| Infirmière hurlante : distances | marche 1,9 m/s ; **fuit** (3,4 m/s) quand un joueur est à moins de **6 m**, vers un point dégagé à 4–12 m d'elle, loin des joueurs (jamais en passant devant eux) ; **approche** au-delà de **12 m** ou hors de vue ; entre les deux, elle guette ; acculée (pas de point, bloquée 1,2 s) : se défend **3 s** ; coup de seringue à 1,3 m, **35 dégâts** à 0,42 s ; ignore la peluche leurre, aucun démembrement | `NurseRules`, `Nurse` |
| Infirmière hurlante : cri | portée **14 m**, en vue, même niveau ; premier cri 2,5 s après l'apparition, puis **8 s** entre deux ; préparation **1,4 s** (immobile, tête renversée, bras écartés, gorge et yeux qui flamboient, inspiration sifflante, cubes roses aspirés) ; cri **1,2 s** ; joueurs **en vue** à moins de **11 m** : **étourdis** 3 s (de près) à 1,2 s (au bord), force 1 à 0,45, déplacement jusqu'à **−50 %**, vue qui tangue, image « en cubes » et dédoublée, acouphène (aucun son baissé), **10 dégâts** ; zombies à moins de **22 m** **ameutés 5 s** : **+45 %** de vitesse vers sa proie, yeux qui flamboient ; onde du cri : anneaux de cubes roses jusqu'à 11 m | `NurseRules` |
| Infirmière hurlante : point faible | la **gorge** (zone de tête sur l'os du cou) et la tête : multiplicateur de tête de l'arme ; une touche à la tête ou à la gorge pendant la préparation **étrangle** le cri : il avorte, elle tousse **2 s**, immobile, prochain cri 4 s plus tard | `Nurse.srv_on_damaged` |
| Échantillons de l'Infirmière | `nurse_vocal_cords` (cordes vocales), `nurse_syringe` (seringue cassée), `nurse_badge` (badge nominatif), 20 % chacun sur **chaque zombie de la vague** (escorte comprise : à un joueur, 7 tirages par vague) | `LootRules.SAMPLES`, `LootSystem.special_kind` |
| Infirmière hurlante : nom anglais | « Screaming Nurse » ; bandeau « L'INFIRMIÈRE FAIT SA RONDE » / « THE NURSE IS DOING HER ROUNDS » (coop : « LES INFIRMIÈRES FONT LEUR RONDE » / « THE NURSES ARE DOING THEIR ROUNDS ») | `NurseRound` |
| Butin rapporté | armes en main et inventaire, sauf armes de base intactes et pistolet prêté ; exemplaire construit depuis l'arsenal (même `uid`) et amélioré en partie : cette version mise à jour (niveau, rareté, pièces), intact : rien, second exemplaire différent : nouvelle version ; pièces non montées ; échantillons | `ProfileLoot` |
| Hub (2D, lots A, B, D et E codés) | **écrans 2D à onglets** (LABO, ARSENAL, PIÈCES, CONTRATS, ÉCHANGES, DÉPART, PARTIE) ; hub 3D (laboratoire) plus tard, qui ouvrira les mêmes panneaux ; menu titre réduit à JOUER, ÉDITEUR, OPTIONS, CRÉDITS, QUITTER ; solo / coop choisis dans PARTIE ; en coop, le salon est l'onglet PARTIE (le groupe reste connecté) ; puissance non affichée (§4.13), meilleur score de l'arsenal à la place ; retirer une pièce et recycler : deux appuis | `docs/HUB_PLAN.md` |
| Contrats : tableau | **5 propositions, 3 actifs** ; rotation **par partie** (≥ 1 manche survécue) : 1 proposition (la plus ancienne) remplacée, cases vides remplies ; une proposition acceptée laisse sa case vide jusqu'à la partie suivante ; tirage pondéré sans doublon, graine du profil ; manches survécues = max(relevé d'XP, manche atteinte − 1) ; une partie quittée après une manche compte aussi ; récompense au niveau du joueur avant l'XP du contrat | `ContractRules`, `MatchContracts`, `docs/HUB_PLAN.md` §5 et lot A |
| Contrats : récompense | XP = XP de base × (1 + 0,02 × (niveau − 1)), arrondie à 10 ; arme ou pièce au niveau du joueur à la remise ; rareté de l'arme selon les parties nécessaires (< 1,5 commune, 1,5 à 3 rare, 3 à 5 épique, > 5 légendaire ; unique : contrats datés exceptionnels seulement) ; qualité d'une pièce : ordinaire (tirage du butin), soignée (2 bonus de 10 à 25 %), d'exception (2 bonus de 18 à 25 %) ; XP ≈ 25 % de l'XP des parties nécessaires, +25 % si daté | `docs/HUB_PLAN.md` §5, §7 |
| Contrats et échanges d'exemple | 17 contrats et 11 échanges : 8 et 5 sur les échantillons des chiens, 3 et 2 sur ceux du Brancardier, 3 et 2 sur ceux de l'Infirmière hurlante, 3 et 2 sur ceux du Chirurgien (niveau 10 et plus) (fichiers `assets/data/hub/`) | `docs/HUB_PLAN.md` §7 |
| Échanges | pas d'XP, illimités, objet précis au niveau du joueur | `docs/HUB_PLAN.md` §6 |
| Taille des menus | nouveau réglage 80 à 130 % (défaut 100 %) pour le hub et les menus, même technique que la taille de l'éditeur | `docs/HUB_PLAN.md` §4.2 |
| Hub : onglet PARTIE et retour | fin d'une partie solo (ou départ en solo) : hub, onglet LABO (« dernière partie ») ; coop : hub, onglet PARTIE (salon) ; session perdue : hub, onglet PARTIE, message sur place ; salon : niveau et armes de départ de chacun affichés (non vérifiés par l'hôte) ; pas de bouton PRÊT (l'état AU SALON en tient lieu) ; QUITTER LE SALON et ÉCRAN TITRE en coop : deux appuis | `HubPlayPanel`, `docs/HUB_PLAN.md` lot E |
| Message « objectif atteint » | une fois par contrat et par partie, quand profil + échantillons de la partie couvrent un contrat actif ; jamais pour un contrat déjà prêt au départ ; sous le compteur d'échantillons, 7 s | `ContractWatch` |
| Défi hebdomadaire : tirage | semaine ISO (lundi 0 h UTC) ; graine = FNV-1a de la clé « 2026-W41 » puis xorshift32 (indépendant du générateur de Godot) ; 1 carte parmi `maps` de la réserve qui ont porte d'évacuation et station (aujourd'hui BUNKER K-7 seule) ; **1 à 2 modificateurs** tirés selon leur poids, sans doublon ; graine de partie appliquée aux tirages du serveur (manches, butin, zombies) | `WeeklyChallenge`, `assets/data/hub/weekly.json` |
| Défi hebdomadaire : modificateurs | Horde pressée **+15 %** de vitesse (zombies et chiens) ; Peau de cuir **+25 %** de PV ; En retard : **départ à la manche 6** (vagues spéciales à leur rythme et leur rotation : Brancardier manche 10, Infirmière 15, meute 20) ; Fonds de tiroir : armes trouvées **communes** ; Station en panne : **pas de station** | `WeeklyChallenge.MODS`, `weekly.json` |
| Défi hebdomadaire : conditions | armes de départ = **toutes les armes de base** pour tous ; station : armes de base seulement (l'arsenal n'est pas listé, l'hôte refuse le reste) ; **butin de la partie jamais gardé**, même évacué ; XP de la partie gardée ; pas de message « objectif atteint » des contrats ; la rotation des contrats compte la partie | `Game`, `Session`, `BuildStation` |
| Défi hebdomadaire : objectif et récompense | **évacuation à la manche 10 ou plus** ; **une fois par semaine** : **400 XP** × (1 + 0,02 × (niveau − 1)), arrondie à 10, et **4 crocs, 3 touffes, 2 colliers** ; donnée à la fin de la partie (rapport « DÉFI S41 RÉUSSI ») ; meilleur résultat (manche atteinte, manche d'évacuation, parties) gardé pour les **12 dernières semaines** ; une partie quittée compte pour le meilleur résultat | `WeeklyChallenge.apply_to`, `WeeklyRecord` (profil v3) |
| Défi hebdomadaire : coop | l'hôte choisit DÉFI DE LA SEMAINE dans CHANGER DE CARTE ; la clé de semaine part avec l'ordre de chargement, chaque machine recalcule le même défi ; chacun sa récompense dans son profil ; au retour au salon, le défi gardé passe à la semaine en cours | `Net.lobby_challenge`, `HubPlayLobby` |

## 7. Questions ouvertes

- Nom définitif du jeu.
- Identité du scientifique, origine de l'épidémie, fin.
- Gains des contrats, déblocage, nombre de contrats actifs (proposition
  provisoire : `docs/HUB_PLAN.md`, à valider avec ses maquettes).
- Échantillons en coop : chaque joueur tire les échantillons de chaque chien,
  et il y a plus de chiens ; à 4 joueurs, un joueur en reçoit ≈ 4 fois plus
  qu'en solo et remplit ses contrats ≈ 4 fois plus vite. Réduire la chance par
  joueur en coop, ou garder ce bonus de la coop ?
- Effet des contrats sur la progression : ≈ +20 à 25 % d'XP, niveau 50 vers
  100 h au lieu de 123 h (cible 120 h) : à re-mesurer.
- Nom et personnalité du scientifique (le hub en a besoin pour ses répliques).
- Liste des armes, leurs niveaux de base et leurs statistiques (liste provisoire
  appliquée : `docs/WEAPONS.md`, à valider).
- Durées et prix exacts de construction et de recharge des munitions.
- Contenu du défi hebdomadaire (proposition provisoire appliquée : §4.18,
  §6 bis ; à valider : modificateurs, objectif, récompense, butin non gardé).
- Liste des cartes et de leurs vagues spéciales et boss.
- Chirurgien : valeurs provisoires (§6 bis) à régler en jeu (PV et part des
  joueurs, durée des préparations, dégâts, nombre de patients, échantillons
  à coup sûr sur le boss, raretés du butin de boss) ; boss toutes les 15
  manches : la rotation des vagues spéciales saute les manches de boss
  (meute 5, Brancardier 10, Infirmière 20, meute 25…) ; l'Infirmière arrive
  donc à la 20 et ses contrats (calculés pour la 15) sont à revoir.
- Rotation des vagues spéciales (§4.4, appliquée) : avec trois types, chaque
  mini-boss revient trois fois moins souvent (contrats d'un type plus longs à
  remplir ; avec le boss, la première meute après la manche 5 arrive à la
  25). Garder la rotation stricte, ou tirer le type au hasard, ou rapprocher
  les vagues spéciales (toutes les 4 manches) ?
- Brancardier : valeurs provisoires (§6 bis) à régler en jeu (PV, durée de
  la préparation, dégâts et projection de la charge, taille de l'escorte).
- Infirmière hurlante : valeurs provisoires (§6 bis) à régler en jeu
  (portée et durée de l'étourdissement, force de l'effet d'écran, vitesse des
  zombies ameutés, distance de fuite, PV). Le cri étourdit tout joueur en
  vue : en coop, faut-il le limiter à sa proie ?

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
