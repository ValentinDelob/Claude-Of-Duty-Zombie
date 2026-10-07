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

---

## 1. Vision

- **Nom provisoire** : « Zombie Apocalypse ». ❓ Ce titre existe déjà
  (Konami, 2009), il est trop générique pour être protégé et quasi introuvable
  sur Steam. Il pourra servir de sous-titre. Le nom actuel « Claude of Duty
  Zombie » doit disparaître (marque *Call of Duty*, marque *Claude*).
- **Pitch** : un FPS coopératif de vagues de zombies où l'on farme des objets et
  des échantillons pour un scientifique qui cherche un antidote, en améliorant un
  arsenal d'armes modulaires.
- **Piliers** :
  1. **Survivre plus longtemps rapporte plus** : boss, butin de meilleur niveau.
  2. **Armes à construire** : armes de niveaux et de raretés différents,
     composées de pièces à modificateurs ; on chasse l'arme parfaite.
  3. **Progression longue** : niveaux, arsenal, missions du scientifique.
- **Références** (mécaniques seulement, rien n'est copié) : Borderlands
  (armes générées, niveaux requis), Killing Floor 2 et Black Ops 1 Zombies
  (vagues), Deep Rock Galactic (coop et méta-progression).

## 2. Gameplay visé

### Boucle de 30 secondes
Tirer, tuer, ramasser son butin (à sa couleur), se replacer, recharger.

### Boucle d'une partie
1. Le joueur choisit un **contrat** sur une carte et part avec son équipement.
2. Il survit à des **vagues** de zombies de plus en plus fortes.
3. Toutes les 5 vagues, un **mini-boss** ; toutes les 15 vagues, un **gros
   boss**. Ils lâchent des **objets à collectionner** et du meilleur butin.
4. Il s'**extrait** à la fin du contrat et rapporte son butin au hub.

### Boucle méta (hub)
1. Le **scientifique** échange les objets à collectionner contre des armes et des
   améliorations (missions).
2. Le joueur gère son **arsenal** : armes, pièces, montage.
3. Il gagne de l'**XP**, monte de niveau, peut équiper de meilleures armes et
   tenter des contrats plus longs.

### Ce que doit ressentir le joueur
- Une progression visible dès les 30 premières minutes.
- L'envie de relancer « encore une partie » pour un objet ou une arme précise.
- Des parties qui ne se ressemblent pas : mini-boss variés, butin aléatoire.

## 3. Lore

- ✅ Un **scientifique** cherche à mettre au point un **vaccin et un antidote**.
  Il a besoin d'échantillons et d'objets prélevés sur les zombies, et engage le
  joueur pour les récupérer.
- 💡 Le joueur est un **joueur de baseball** (arme de départ thématique possible :
  batte).
- 💡 Scène d'introduction à l'hôpital (réveil après un coma, rencontre avec le
  scientifique caché dans une armoire) : **reportée**, pourra revenir plus tard
  comme chapitre de lore.
- 💡 Le joueur serait **immunisé** (mordu sans se transformer), ce qui explique
  pourquoi le scientifique a besoin de lui.
- 💡 Marché noir, autres survivants recrutables (personnages jouables).
- ❓ Nom, personnalité et motivation du scientifique ; origine de l'épidémie ;
  fin envisagée.

Règles de droits pour le lore : aucune ligue, équipe ou marque réelle de
baseball ; pas de batte à fil barbelé (Lucille de *The Walking Dead*) ; ne pas
reprendre les scènes reconnaissables de *28 jours plus tard* ou de *The Walking
Dead* ; aucun élément du lore Aether / Élément 115 de Call of Duty.

## 4. Fonctionnalités prévues

### 4.1 Tutoriel et premières parties ✅
- Au premier démarrage, le joueur joue obligatoirement une **carte tuto** de
  **3 vagues**, suivie d'une **extraction**.
- Un **mini-boss tuto**, faible, apparaît à la **vague 3**. Il lâche son objet
  **à coup sûr, une seule fois**.
- Au hub, le joueur fait son **premier échange** avec le scientifique et voit
  toute la boucle (partie, objets, troc, amélioration).
- 💡 Présentation sans la scène de l'hôpital : court briefing du scientifique
  au hub et indications à l'écran pendant la première partie.

### 4.2 Contrats ✅
- Les premiers contrats ont une **durée fixe** : survivre 5 vagues puis
  extraction ; les contrats de 10, puis 15 vagues se débloquent ensuite.
- ❓ Ce qui débloque les contrats suivants (niveau, mission, contrat précédent
  réussi).
- 💡 Plus tard : contrats plus libres, où l'extraction est un choix (fenêtre
  d'extraction après chaque vague de boss) ; contrats journaliers avec
  modificateurs (zombies rapides, obscurité, munitions rares…).

### 4.3 Équipement de départ ✅
- Chaque joueur démarre avec une **arme faible et rudimentaire** (pistolet
  simple), qui ne permet pas de survivre longtemps.
- 💡 Le pistolet de départ ne se perd jamais et a des munitions de réserve
  illimitées (rechargement lent) : le joueur ne peut jamais être bloqué sans arme.

### 4.4 Vagues ✅
- On conserve le système de vagues actuel.
- **Coop** : rien ne change. Le **nombre** de zombies dépend du nombre de
  joueurs, leur **force** dépend du numéro de la manche, pas du niveau des
  joueurs.

### 4.5 Mini-boss et boss ✅
- Une vague de **mini-boss** toutes les **5 manches** (comme les vagues de
  chiens actuelles).
- **Plusieurs mini-boss différents par carte**, pour varier les parties.
- Un **gros boss** toutes les **15 manches**.
- 💡 Chaque nouvelle apparition d'un mini-boss dans la même partie est plus forte.
- Exemple de pool pour une carte d'hôpital (💡 à valider) :

| Ennemi | Objets à collectionner |
|---|---|
| Meute errante (chiens, en groupe) | croc, touffe de poils, collier |
| Brancardier (gros zombie qui charge) | sangle de cuir, bracelet d'identification |
| Infirmière hurlante (cri qui attire et étourdit) | cordes vocales, seringue cassée, badge |
| Le Chirurgien (gros boss) | scalpel d'aethérium, cœur mutant |

### 4.6 Objets à collectionner et butin ✅
- Chaque **mini-boss** a **2 ou 3 objets** à collectionner ; chaque **gros
  boss** en a **1 ou 2**.
- Chaque objet a environ **20 % de chances** de tomber **par mob tué** (pour une
  meute, chaque chien fait son tirage).
- **Hasard pur**, pas de protection contre la malchance.
- **Butin personnel** : chaque joueur fait ses propres tirages ; chaque joueur a
  une **couleur**, et ses objets au sol portent sa couleur.
- 💡 Affichage : couleur du joueur sur le contour au sol (anneau, faisceau),
  rareté sur l'objet lui-même, nom du joueur sur l'étiquette (daltoniens).
- ❓ Le butin d'une partie ratée (extraction manquée) : ce qui est perdu ou gardé.

### 4.7 Troc avec le scientifique ✅
- Le scientifique **échange des objets à collectionner contre des armes et des
  améliorations**, sous forme de missions (par exemple « 5 crocs + 3 touffes de
  poils → garniture à crocs »).
- **Pas de monnaie** pour l'instant.
- 💡 Une arme reçue en échange a le **niveau du joueur au moment de l'échange**,
  pour que les anciennes missions restent utiles.
- 💡 Les missions font avancer la recherche de l'antidote, découpée en phases qui
  débloquent du contenu (cartes, personnages, emplacements…).

### 4.8 Armes ✅

**Niveau des armes trouvées**
- Plage : du **niveau du joueur − 13** (au minimum 1) au **niveau du joueur + 2**.
  Exemple : niveau 23 → armes de niveau 10 à 25 ; niveau 5 → armes de niveau 1
  à 7.
- Un joueur ne peut **équiper** une arme que s'il a **au moins son niveau**.
- Tirage pondéré (mobs et mini-boss) :

| Écart avec le niveau du joueur | Probabilité |
|---|---|
| −13 à −6 | 20 % |
| −5 à 0 | 65 % |
| +1 / +2 | 15 % |

- **Gros boss** : 70 % entre −5 et 0, 30 % à +1 / +2.
- Le niveau des armes trouvées ne dépasse pas le niveau maximum du joueur (50).

**Pièces**
- Chaque arme est composée de **pièces** posées dans des emplacements ; chaque
  pièce porte des **modificateurs** (bonus et malus, par exemple « +25 % de
  dégâts », « −5 % de vitesse d'attaque »).
- Niveau d'une pièce : du **niveau de l'arme − 25** (au minimum 1) au **niveau
  de l'arme**. Exemple : arme niveau 50 → pièces de niveau 25 à 50.
- Une pièce se **monte** sur une arme si son niveau est **inférieur ou égal au
  niveau de l'arme**, et si le joueur a **au moins le niveau de la pièce**.
- 💡 Familles d'emplacements : armes à feu (canon, culasse, chargeur, crosse,
  viseur, accessoire), corps à corps (manche, tête, garniture, poignée).

**Raretés**

| Rareté | Emplacements de pièces | En plus |
|---|---|---|
| Commune | 1 | |
| Rare | 2 | |
| Épique | 3 | |
| Légendaire | 4 | effet unique propre à l'arme |
| Unique | 4 | effet unique + petit bonus fixe (ex. « rechargement +20 % ») |

Pas d'autre rareté pour l'instant : trop de raretés perdraient le joueur.

**Score de l'arme**
- **Score = niveau de l'arme + somme des niveaux de ses pièces.**
- Exemple : légendaire niveau 25 avec des pièces 22 + 25 + 19 + 24 → score 115.
- Le score indique l'investissement dans l'arme, pas sa puissance exacte : la
  fiche de l'arme affiche aussi ses vraies statistiques (dégâts, cadence…).

**Droits** : armes générées et raretés colorées sont des mécaniques libres ; ne
pas reprendre les noms de fabricants de Borderlands, ni ses fiches d'armes, ni
son style visuel. Les armes réelles du jeu actuel (AK-74u, FAMAS, Galil, HK21,
AUG…) doivent être renommées et leurs silhouettes retravaillées.

### 4.9 XP et niveaux ✅
- **Niveau maximum : 50** pour l'instant ; il pourra augmenter avec le temps.
- XP pour passer au niveau suivant : **`100 × niveau^1,8`** (100 XP du niveau 1
  au 2, environ 6 300 au niveau 10, environ 110 000 au niveau 49), à ajuster
  après mesure de l'XP gagnée par partie.
- Au niveau 50, l'XP continue d'être comptée mais le niveau ne bouge plus ; elle
  servira si de nouveaux niveaux sont ajoutés.
- 💡 Temps de jeu visé : niveau 10 vers 3 h, niveau 25 vers 25 h, niveau 50
  vers 120 h.
- 💡 Sources d'XP : éliminations, vagues survécues, mini-boss et boss, missions,
  bonus d'extraction, multiplicateur selon la difficulté.

### 4.10 Difficultés 💡
- Niveaux « normal », « difficile », « cauchemar ».
- Plus la difficulté est haute, plus l'XP gagnée est importante.
- ❓ Part du butin gardée en cas d'échec de l'extraction (0 / 50 / 75 / 100 %) :
  dans quel sens selon la difficulté.

### 4.11 Personnages 💡
- Chaque personnage aurait une **compétence spéciale** et un **arbre de
  compétences**.
- ❓ Personnage imposé (le joueur de baseball) ou choix parmi plusieurs
  survivants recrutés au fil du jeu.

## 5. Mécaniques prototypées (code actuel)

Ce qui existe déjà, hérité du clone de Black Ops 1 Zombies, et ce qu'on en fait.

| Mécanique | Statut | Devenir |
|---|---|---|
| Manches et vagues, nombre de zombies selon les joueurs, force selon la manche | 🧪 | **Garder** (cœur du jeu) |
| Vagues de chiens (`scripts/game/dogs`) | 🧪 | **Adapter** en premier mini-boss ; refaire la mise en scène (pas d'éclair ni de brouillard façon BO1) |
| Points par élimination, portes payantes, achats muraux | 🧪 | ❓ Rôle à redéfinir avec le butin et les armes du joueur |
| Fenêtres barricadées, reconstruction | 🧪 | **Garder** |
| Pièges à levier | 🧪 | **Garder** |
| État « à terre » et réanimation | 🧪 | **Garder** |
| Coop réseau (hôte / client par IP) | 🧪 | **Garder** |
| Couteau, grenades | 🧪 | **Garder**, présentation à revoir |
| Atouts (machines à boissons) | 🧪 | ❓ À renommer et repenser |
| Bonus au sol (munitions max, mort instantanée, points doubles…) | 🧪 | ❓ À renommer et repenser |
| Boîte mystère | 🧪 | ❓ À repenser ou supprimer |
| Machine d'amélioration (Pack-a-Punch) | 🧪 | ❓ À repenser ou supprimer (doublon avec les pièces) |
| Téléporteur, courant | 🧪 | ❓ Selon les cartes |
| Armes merveilles (Claude-Ray, Tonnerre-7, singe-tambour) | 🧪 | **Supprimer** ou recréer de façon originale |
| Sept personnages et leurs voix FR / EN | 🧪 | ❓ Réécrire (l'équipe de quatre copie celle de BO1) |
| Dossier de combat (`CareerStats`) | 🧪 | **Adapter** au profil du joueur (XP, niveau, arsenal) |
| Éditeur de cartes, bouton TESTER | 🧪 | **Garder** (outil de création des cartes) |
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

## 7. Questions ouvertes

- Nom définitif du jeu.
- Identité du scientifique, origine de l'épidémie, fin.
- Déblocage des contrats suivants.
- Butin gardé en cas d'échec d'extraction, selon la difficulté.
- Rôle des points en partie, des achats muraux, de la boîte et des atouts face au
  système d'armes du joueur.
- Personnages : imposé ou choix ; compétences et arbres.
- Liste des cartes et de leurs mini-boss et boss.

## 8. Idées écartées

- ❌ **Loot box** (clés de caisses) : abandonnées.
- ❌ **Prestige** : abandonné, car remettre le niveau à zéro rendrait l'arsenal
  inéquipable.
- ❌ **Protection contre la malchance** : le hasard reste pur.
- ❌ **Monnaie** (crédits, marché noir) : pas pour l'instant, le troc suffit.
- ❌ **Scène d'introduction à l'hôpital** : reportée (voir §3).
