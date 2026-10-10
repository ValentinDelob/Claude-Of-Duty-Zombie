# XP et niveaux — barème de référence

Référence de l'XP gagnée en partie (GAME_CONCEPT.md §4.15) : barème par type
d'ennemi et par source, formule, règles de la coop, calibrage, et **méthode à
suivre pour fixer l'XP de tout nouveau mob**. Valeurs provisoires (§6 bis),
à re-mesurer en jeu.

Code : `scripts/game/profile/xp_rules.gd` (`XpRules`, règles pures),
`xp_system.gd` (`XpSystem`, comptage par l'hôte pendant la partie),
`match_xp.gd` (`MatchXp`, ajout au profil), `xp_calibration.gd`
(`XpCalibration`, simulation). Tests : `tests/test_xp_rules.gd`,
`tests/test_profile.gd`, scénarios `xp_match`, `career_record`, `evacuation`,
`evac_edges`, `loot_defeat`, `loot_evac`, `sh tools/mp_test.sh xp`.

## 1. Principe

- L'XP est comptée **pendant la partie**, par joueur, **par l'hôte** (comme la
  ferraille), dans un « relevé » envoyé au seul joueur concerné.
- Elle est **toujours gardée** (§4.6) : évacuation, mort de toute l'équipe,
  ou départ en cours de partie (menu pause, hôte perdu ; sans bonus
  d'évacuation).
- Elle est ajoutée **une seule fois** au profil, à la fin de la partie
  (`MatchXp.apply`, seule voie). Le niveau ne change donc pas pendant une
  partie : le niveau annoncé à l'hôte au départ reste celui de la partie.
- Courbe des niveaux inchangée : `100 × niveau^1,8` XP pour passer au niveau
  suivant, niveau maximum 50, l'XP continue d'être comptée au-delà.

## 2. Barème

### Par type d'ennemi (XP de base, manche 1)

| Type | Identifiant | Catégorie | XP de base | Manche 10 | Manche 20 | Manche 28+ |
|---|---|---|---|---|---|---|
| Marcheur | `walker` | commun | **4** | 9 | 15 | 20 |
| Coureur | `runner` | commun | **4** | 9 | 15 | 20 |
| Sprinteur | `sprinter` | commun | **4** | 9 | 15 | 20 |
| Rampant | `crawler` | commun | **4** | 9 | 15 | 20 |
| Chien (meute, vague spéciale) | `dog` | spécial | **12** | 28 | 46 | 60 |
| Mini-boss (référence, aucun encore) | `miniboss` | mini-boss | **60** | 141 | 231 | 300 |
| Boss (référence, aucun encore) | `boss` | boss | **240** | 564 | 924 | 1 200 |

- **Marcheur, coureur, sprinteur et rampant rapportent autant** : c'est le
  même zombie. Sa vitesse est tirée au hasard (le joueur ne la choisit pas) et
  devient « sprinteur » presque toujours après la manche 10 : la difficulté
  qui monte est déjà payée par le bonus de manche. Un rampant est un zombie
  démembré par le joueur : le payer moins pénaliserait le démembrement, le
  payer plus pousserait à garder des rampants en vie pour bloquer la manche.
  Les types restent comptés à part pour l'écran de fin.
- Le type se lit sur l'entité au moment de la mort (`XpRules.enemy_type`) :
  chien (`Hellhound`), rampant (`Zombie.is_crawler`), sinon classe de vitesse
  (`RoundRules.WALK` / trot et `RUN` / `SPRINT`).

### Autres sources

| Source | XP | Qui la reçoit |
|---|---|---|
| Manche survécue | **3 × numéro de la manche** (manche 10 : 30) | chaque joueur **non mort** à la fin de la manche |
| Vague spéciale vaincue | **60** × bonus de manche (manche 5 : 96, 10 : 141) | chaque joueur non mort |
| Vague de boss vaincue | **240** × bonus de manche | chaque joueur non mort |
| Évacuation réussie | **+25 %** de l'XP de la partie du joueur | chaque joueur (l'équipe part ensemble) |
| Contrat rempli (§4.2, à venir) | XP de base du contrat × (1 + 0,02 × (niveau − 1)), ajoutée au hub à la remise (proposition provisoire, `docs/HUB_PLAN.md` §5 et §7) | le joueur |

Une défaite garde toute l'XP déjà gagnée, sans le bonus d'évacuation ; la
manche en cours à la mort de l'équipe n'est pas comptée (elle n'est pas
survécue).

## 3. Formule

```
bonus de manche  f(m) = min(1 + 0,15 × (m − 1), 5)       (×5 dès la manche 28)
élimination      = arrondi(XP de base du type × f(manche))
manche survécue  = 3 × m
vague vaincue    = arrondi(XP de la vague × f(manche))
évacuation       = arrondi(0,25 × (éliminations + manches + vagues))
```

Pourquoi l'XP d'élimination monte avec la manche (alors que la ferraille par
élimination est fixe, §4.8) : la ferraille équilibre une partie (elle
repart de zéro), l'XP mesure la progression du joueur. « Survivre plus
longtemps rapporte plus » (pilier 1) : un joueur qui va plus loin gagne plus
d'XP par heure (voir §4). Le plafond (×5) garde les manches très hautes dans
des valeurs raisonnables ; au-delà, l'XP monte encore avec le nombre de
zombies.

## 4. Calibrage

Cibles du concept (§4.15) : niveau 10 vers 3 h, 25 vers 25 h, 50 vers 120 h.
XP totale nécessaire : 19 473 (niveau 10), 276 919 (niveau 25), 1 984 718
(niveau 50).

Simulation `XpCalibration` (pure, déterministe ; affichée par
`godot --headless --path . res://tests/test_runner.tscn -- --files=test_xp_rules.gd`,
vérifiée à ±20 % par `test_calibrage`), à partir des vraies règles
(`RoundRules.zombie_count`, `DogRules.dog_count`, schéma des vagues par
défaut, `XpRules`) et d'un joueur type :

- 3 s par zombie et par joueur, 4 s par chien ; 25 s de plus par manche
  (entracte de 10 s, trajet) ; 30 s d'évacuation ; 90 s par partie
  (chargement, écran de fin, hub) ;
- évacuation après la vague spéciale de la manche 5 (niveaux 1 à 4),
  10 (5 à 9), 15 (10 à 24), 20 (25 à 39), puis 25 (40 et plus) ;
- aucune mort, aucun contrat.

Résultat :

| Partie type (solo) | XP | Éliminations | Durée | XP / h |
|---|---|---|---|---|
| Évacuation manche 10 | 2 274 | 169 | 15,1 min | 9 066 |
| Évacuation manche 15 | 5 191 | 327 | 25,3 min | 12 319 |
| Évacuation manche 20 | 9 894 | 541 | 38,3 min | 15 493 |
| Évacuation manche 25 | 17 100 | 825 | 54,9 min | 18 706 |

| Niveau | Visé | Solo | 4 joueurs |
|---|---|---|---|
| 10 | 3 h | **2,5 h** | 2,7 h |
| 25 | 25 h | **23,5 h** | 24,0 h |
| 50 | 120 h | **123,3 h** | 120,3 h |

Le niveau 10 arrive un peu avant 3 h (progression visible dès les premières
parties, §2 du concept). En coop, chaque joueur tue moins de zombies (le
nombre de zombies ne croît pas linéairement avec les joueurs), mais les
manches et vagues partagées compensent : le rythme reste proche du solo.

**Re-calibrer** : changer une valeur de `XpRules`, relancer `test_xp_rules.gd`
(les temps s'affichent), mettre à jour ce tableau et `test_bareme`. Quand des
mesures réelles existeront (durée des manches, manche d'évacuation moyenne),
corriger d'abord les hypothèses d'`XpCalibration`, puis le barème.

## 5. Règles de la coop (anti-farm)

- **Élimination : au seul tueur** (celui qui porte le coup fatal, comme la
  ferraille ; rien pour les assistances). Un piège compte pour le joueur qui
  l'a activé (il l'a payé). Aucune XP n'est partagée par élimination : un
  joueur qui ne joue pas ne profite pas des éliminations des autres.
- **Manches et vagues : à chaque joueur non mort** à la fin de la manche,
  montant entier (pas divisé) : jouer ensemble ne pénalise personne. Un joueur
  mort (spectateur) ne les reçoit pas : rester mort ne rapporte rien.
- **Boss et mini-boss** : l'élimination va au tueur ; la **vague** vaincue
  rapporte à toute l'équipe vivante (c'est elle qui récompense le travail
  d'équipe).
- **Évacuation** : bonus en pourcentage de l'XP de chacun, jamais multiplié
  par le nombre de joueurs.
- Aucune source ne grandit avec le nombre de joueurs : quatre joueurs ne
  gagnent pas plus par personne qu'un joueur seul (voir §4).

## 6. Méthode pour un nouveau mob

1. **Choisir la catégorie** (`XpRules.CATEGORY_RANGE`, fourchettes d'XP de
   base vérifiées par `test_categories`) :

   | Catégorie | Qui | Fourchette |
   |---|---|---|
   | commun (`common`) | zombie des manches normales, apparaît en nombre | 2 à 8 |
   | spécial (`special`) | ennemi en groupe d'une vague spéciale (meute) | 8 à 30 |
   | mini-boss (`miniboss`) | ennemi seul et fort d'une vague spéciale (Brancardier, Infirmière) | 40 à 120 |
   | boss (`boss`) | ennemi d'une vague de boss (Chirurgien) | 150 à 600 |

2. **Estimer sa valeur dans la fourchette**, en partant de la référence de la
   catégorie (commun 4, spécial 12, mini-boss 60, boss 240) :
   - **résistance** : XP ∝ temps pour l'abattre. PV du mob ÷ PV d'un zombie
     commun de la même manche (`RoundRules.zombie_health`), × 4 XP, puis
     arrondir. Exemple : le chien (400 à 1 600 PV, ≈ 2 à 3 fois un zombie de
     sa manche) → 12.
   - **rareté** : un mob qui apparaît rarement (une fois toutes les 5 ou 15
     manches, en petit nombre) peut monter vers le haut de la fourchette ; un
     mob fréquent reste bas, sinon il domine l'XP de la partie.
   - **dangerosité** : +25 à +50 % pour un mob qui met vraiment le joueur en
     danger (charge, étourdit, attaque à distance, explose) ; rien pour un
     mob seulement résistant.
   - un mob commun « variante » du zombie (même PV, autre animation) garde
     la valeur du zombie commun.
   - la valeur de base est celle de la **manche 1** : ne pas y intégrer la
     manche d'apparition, le bonus de manche s'en charge.
3. **L'ajouter au code** :
   - `scripts/game/profile/xp_rules.gd` : constante d'identifiant et ligne de
     `ENEMIES` (`category`, `xp`, noms pluriels `fr` / `en` de l'écran de fin) ;
   - `XpRules.enemy_type` (ou `XpSystem.enemy_type_of`) : reconnaître
     l'entité (sa classe, comme `Hellhound`) et rendre son identifiant ;
   - un boss ou une nouvelle sorte de vague : sa valeur de vague dans
     `XpRules.WAVE_XP`.
4. **Mettre à jour les tests** :
   - `tests/test_xp_rules.gd` : `test_bareme` (valeur attendue du nouveau
     type), `test_type_d_ennemi` (reconnaissance de l'entité) ;
     `test_categories` vérifie seul la fourchette et les noms FR / EN ;
   - si le mob change la partie type (vague spéciale ou de boss nouvelle,
     apparition fréquente) : l'ajouter à `XpCalibration.simulate_match` et
     vérifier que `test_calibrage` passe toujours ;
   - le scénario du mob (comme `dog_round`) : vérifier qu'une élimination
     ajoute bien son type au relevé (`Game.instance.xp.my_ledger`).
5. **Documenter** : ligne du tableau §2 de ce fichier et, si la valeur est
   provisoire, GAME_CONCEPT.md §6 bis.

## 7. Affichage

- **En jeu** : « +N XP » léger (bleu pâle, 18 px) sous le viseur à chaque
  gain, les gains rapprochés s'additionnent (1,1 s) ; compteur discret
  « XP DE PARTIE n » en haut à droite, au-dessus du compteur d'échantillons.
- **Écran de fin** (évacuation ou défaite) : « XP GAGNÉE : +n », niveau avant
  et après (« NIVEAU 7 → 8 NIVEAU SUPÉRIEUR ! », niveau maximum signalé),
  barre et texte de progression vers le niveau suivant, détail (éliminations
  par type, manches, vagues, bonus d'évacuation).
- **Tableau des scores** : colonne NIV. (niveau annoncé au départ).
- **Menu principal** : écran DOSSIER DE COMBAT, niveau du profil et barre de
  progression (en attendant le hub, qui reprendra cet affichage).
