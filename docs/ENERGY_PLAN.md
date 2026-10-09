# Plan : énergie du joueur (GAME_CONCEPT §4.14)

Objectif : remplacer l'endurance de sprint actuelle (`Player.stamina`, héritée
de BO1) par l'**énergie** décrite dans `GAME_CONCEPT.md` §4.14 :

- jauge **invisible** (rien au HUD) ;
- vidée par la **course**, le **saut** et les **coups de corps à corps** (coût
  par coup = statistique « énergie » de l'arme) ;
- fatigue **audible** (essoufflement) ;
- à **énergie nulle** : plus de course, coups de corps à corps 50 % plus lents,
  sauts plus petits, recharge 25 % plus lente.

## Décisions prises en l'absence de l'auteur (à valider)

| Sujet | Décision | Pourquoi |
|---|---|---|
| Unité | Énergie de **0 à 100** | Lisible, indépendante des durées |
| Course | **25 / s** (4 s de course pleine, comme aujourd'hui) | Garde la sensation actuelle |
| Recharge | **40 / s** hors course après **0,4 s** sans dépense (2,5 s pour tout remplir, comme aujourd'hui) | Idem |
| Saut | **10** par saut | Environ 10 sauts d'affilée |
| Coup de corps à corps | statistique `energy` de l'arme : couteau **8**, couteau de chasse **10** (batte à venir : 15) | Statistique demandée par le concept |
| « Énergie nulle » | État **épuisé** : commence quand l'énergie atteint 0, finit quand elle remonte à **50** | Sinon les pénalités disparaîtraient à la première image de recharge |
| Épuisé : coups | cadence de frappe divisée par 2 (durée ×2) | « 50 % plus lents » |
| Épuisé : saut | vitesse de saut ×0,75 (environ 56 % de la hauteur) | « Sauts plus petits » |
| Épuisé : recharge | 40 × 0,75 = **30 / s** | « Recharge 25 % plus lente » |
| Relance de la course | il faut au moins **12,5** d'énergie (0,5 s, comme `SPRINT_RESTART_MIN`) et ne pas être épuisé | Pas de sprint d'une image |
| Atout STRIDE SODA (à supprimer plus tard) | son bonus de secondes de sprint devient de l'énergie max en plus (bonus × 25) | Rien ne casse avant la suppression des atouts |
| Coût si l'énergie manque | l'action se fait quand même, l'énergie tombe à 0 | Pas de saut ou de coup refusé : la pénalité suffit |
| Retour sonore | respiration qui s'accélère et monte sous 35 %, halètement fort tant que le joueur est épuisé ; sons existants `player_breath_1/2` | Le concept demande un essoufflement audible |
| Coop | l'énergie est calculée chez le joueur qui la vit (comme l'endurance actuelle) ; les autres n'entendent pas sa respiration pour l'instant | Pas de nouveau message réseau |

## Découpage

### Lot 1 : modèle et intégration (agent « cœur »)
1. `scripts/game/player/player_energy.gd` (`class_name PlayerEnergy`,
   `RefCounted`, sans nœud) : constantes ci-dessus, état (`value`, `max_value`,
   `exhausted`), méthodes pures (`tick(delta, sprinting)`, `spend(amount)`,
   `can_start_sprint()`, `jump_velocity_mult()`, `melee_time_mult()`,
   `ratio()`).
2. Tests unitaires `tests/test_player_energy.gd` (style `TestCase` du projet).
3. `scripts/game/player/player.gd` : remplacer `stamina` / `SPRINT_DURATION` /
   `SPRINT_RECOVERY` par `PlayerEnergy` ; saut et coup de couteau dépensent de
   l'énergie ; pénalités d'épuisement appliquées ; propriétés publiques
   `energy` (objet) pour le retour sonore et les tests.
4. `scripts/game/weapons/knife_db.gd` : statistique `energy` par couteau ;
   cadence du couteau multipliée par `melee_time_mult()`.
5. Perk : `perk_system.gd` passe le bonus en énergie max.
6. Adapter les scénarios qui écrivent `p.stamina` (`sprint_restart`,
   `sprint_smooth`, `barricade_wall_slide`) et ajouter un scénario sans fenêtre
   `energy_exhaustion` : courir jusqu'à épuisement, vérifier course refusée,
   saut plus bas, couteau plus lent, recharge plus lente, fin de l'épuisement à
   50.

### Lot 2 : essoufflement audible (agent « retour sonore », en parallèle)
1. `scripts/game/player/breath_feedback.gd` (`class_name BreathFeedback`,
   `Node`) : lit `ratio()` et `exhausted` d'un objet énergie (contrat du lot 1)
   et joue la respiration locale (2D, bus SFX) avec un rythme et un volume qui
   dépendent de l'énergie. Aucune image, aucun HUD.
2. Ne pas entrer en conflit avec la respiration de la santé basse
   (`hud.gd`, battement de cœur) : priorité à la santé basse.
3. Tests unitaires de la logique de rythme (fonction pure).
4. Le branchement dans `player.gd` est fait à l'intégration.

### Lot 3 : intégration et sortie (orchestrateur)
1. Fusion des deux lots sur `feat-energy`, branchement de `BreathFeedback`.
2. `tools/check.sh` complet.
3. Notes de version FR / EN, fusion dans `main`, release par un agent dédié.

## Hors périmètre
- Batte de baseball (arme à créer avec le système d'armes).
- Respiration entendue par les coéquipiers en coop.
- Retrait de l'atout STRIDE SODA (avec la suppression des atouts).
