# Refonte des tests — Phase 1 : mesures et plan (à valider)

> Document de travail de la phase 1 (voir `docs/PROMPT_REFONTE_TESTS_RELEASE.md`).
> Une fois la phase terminée, son contenu utile passera dans `docs/TESTING.md`.
> Mesures prises le 30/09/2026 sur la machine de développement, Godot 4.7.2.

## 1. Mesures de l'existant

### 1.1 Volume et durée

| Élément | Nombre | Durée cumulée (s) | Remarque |
|---|---|---|---|
| Tâches du check | 93 | **3 310** (≈ 55 min de CPU) | ≈ 12-15 min réelles avec `JOBS=3` |
| Scénarios sans rendu (`head:`) | 59 tâches | 2 264 | 68 % du total |
| Scénarios avec rendu (`gui:`) | 14 tâches | 488 | un seul à la fois (`GUI_JOBS=1`) |
| Multijoueur (`mp:`) | 16 paires | 467 | 2 instances par paire |
| Tests unitaires | 302 tests / 45 fichiers | 35 (sous charge : 82 isolé*) | une seule instance |
| Compilation, smoke réseau, lanceur | 3 | 56 | |

\* 82 s mesurées seul ce jour : `test_audio.gd::test_loudness_of_every_sound`
décode **tous** les sons à chaque passage (18 s), `test_net.gd::test_join_nobody_listening_reports_error`
attend un délai réseau réel (8 s). Ces deux tests font 32 % du temps unitaire.

`tests/_out/durations.txt` est en partie périmé : entrées d'anciens scénarios
(`kino_v2_*`, scénarios entiers devenus `@parts`) et 10 scénarios récents
absents (`map_editor*`, `map_preview`, `verruckt`, `draft_arena`, `net_guard`,
`mp:custommap`…), ordonnancés avec la valeur par défaut de 30 s.

### 1.2 Démarrage d'une instance vs temps utile

Chronométrage ligne par ligne d'un scénario court (`points_system`, sans rendu) :

| Étape | Temps écoulé |
|---|---|
| Moteur + autoloads prêts | 2,6 s |
| Menu principal chargé (le scénario l'attend) | 5,1 s |
| Carte construite, shaders préchauffés, partie en cours | 6,3 s |
| Fin du scénario (8 s de vérifications, surtout des attentes) | 14,5 s |

**≈ 6 s de démarrage par scénario**, soit ≈ 9 min de CPU sur l'ensemble du
check, avant même la moindre vérification.

### 1.3 Attentes fixes et horloge réelle

- **708 attentes fixes** (`seconds(…)`) contre 269 attentes sur condition
  (`until`) ; ≈ 590 s de délais écrits en dur, plus les délais cachés dans les
  aides (`dummy_zombie` 1,7 s, `shoot` 0,24 s, `equip` 0,8 s, `join_game` 1,5 s).
- Les scénarios attendent les minuteurs **réels** du jeu : piège / téléporteur
  25 s, intermission 10 s, Pack-a-Punch 10 s, boîte mystère 9 s, chiens 7 s…
- **Essai `--fixed-fps 60`** (le moteur simule 60 images par seconde de jeu sans
  se caler sur l'horloge réelle, donc aussi vite que le CPU le permet) :

  | Scénario | Temps réel actuel | `--fixed-fps 60` | Résultat |
  |---|---|---|---|
  | perks | 27,2 s | 8,8 s | OK |
  | round_system | 36,0 s | 9,6 s | OK |
  | points_system | 14,0 s | 7,5 s | **ÉCHEC** |

  Cause de l'échec : une dizaine de systèmes de jeu mesurent le temps avec
  l'horloge murale (`Time.get_ticks_msec()`) au lieu du temps de jeu :
  `weapon_controller.gd:119`, `combat.gd:88`, `downed_system.gd:35`,
  `throwable.gd:52`, `throwable_system.gd:68`, `throw_controller.gd:45`,
  `teleporter.gd:226-330`, `vox_system.gd:82-288`. Conséquences : l'accélération
  du temps est impossible, et **sous charge** (plusieurs jeux en parallèle) la
  cadence de tir ne suit plus la simulation, source probable d'instabilités.
  Côté joueur, ces minuteurs continuent aussi de tourner pendant une image
  bloquée (et `Engine.time_scale` ne les touche pas).

### 1.4 Tests instables constatés

| Test | Constat | Cause probable |
|---|---|---|
| points_system « tête + mort à la tête » | 1 échec sur 4 passages ce jour (610 au lieu de 710) | dispersion aléatoire non fixée + cadence en temps réel |
| powerups « nouvelle manche : le bonus dû tombe » | déjà signalé dans `docs/HANDOFF.md` | délai fixe au lieu d'attendre l'événement |
| career_record / downed_solo / zombie_damage / visual_look | concurrence sur un **même fichier** `user://career_autotest.cfg` (`career_stats.gd:8`) quand ils tournent en parallèle | chemin non propre au processus |
| perks2 (dispersion à la hanche) | moyenne de 4 tirs aléatoires comparée à un seuil | aléatoire sans graine |
| zombie_spawning, zombie_entity, mystery_box, dog_round | `randf`/`randi` sans graine | aléatoire sans graine |
| mp_* | client lancé après un `sleep 1`, `join_game` attend 1,5 s fixes | synchronisation par délai |

### 1.5 Scénarios qui ont vraiment besoin du rendu

- **Vraiment** : visual_look (luminance lue dans l'image, coût GPU), options_look
  (pixels lus), map_preview (compteurs de rendu, fenêtre détachée), render_perf,
  startup_smoothness, les mesures de perf de boot / menu_navigation /
  render_quality, la galerie de zombie_look.
- **Captures seulement** (les vérifications passent sans rendu, les captures ne
  sont comparées à rien automatiquement) : kino_theater, perk_look,
  zombie_model_look, map_editor, map_editor_diagonal, map_editor_freeform.
- **Sans rendu mais qui attendent quand même pour des captures / perf ignorées** :
  map_tour, fps_controller, zombie_entity, zombie_navigation, zombie_stress,
  kino_tour (partie 0), weapon_basic. zombie_look n'est pas marqué `@rendu` : il
  passe 63 s sans rendu pour une douzaine de vérifications utiles.
- En exécution parallèle (`AUTOTEST_PARALLEL=1`, toujours le cas dans check.sh),
  **un seuil de perf manqué n'est qu'un avertissement** : les vérifications de
  perf du check ne peuvent jamais échouer. Elles relèvent du niveau perf
  (`tools/perf.sh`).

### 1.6 Tableau classé (tâches les plus coûteuses)

Durée = dernière mesure de `durations.txt` (sous charge, 3 tâches simultanées).
Niveau cible : L1 unitaire pur, L2 intégration dans une instance partagée,
L3 bout-en-bout, PERF.

| # | Tâche(s) | Durée (s) | Attentes fixes (≈ s) | Rendu utile | Niveau cible | Recouvrement principal |
|---|---|---|---|---|---|---|
| 1 | weapon_roster (4 parties) | 179 | 75 + 60 de recharges | non | L2 (+L1) | weapon_basic, weapon_view, test_weapons |
| 2 | weapon_view (3 parties) | 171 | 120 (boucles en temps réel) | non | L2 | weapon_roster, test_gunplay |
| 3 | visual_look (3 parties) | 131 | 73 | **oui** | L3 / PERF | map_tour, render_quality, kino_theater |
| 4 | weapon_aim (3 parties) | 122 | 90 | non | L2 (surtout L1) | test_gunplay, scope |
| 5 | kino_tour (2 parties) | 85 | 12 | perf seulement | L2 | test_kino_map, dog_round |
| 6 | powerups | 68 | 42 | non | L2 | test_powerups, fire_sale_kino |
| 7 | zombie_look | 63 | 45 | galerie oui, 12 vérifs non | L1 + visuel | test_zombie_model |
| 8 | mp:netload | 64 | 48 / 33 | non | PERF (réseau) | mp_sync |
| 9 | mp:dogs | 60 | 9 / 7 + boucles 110 | non | L3 | dog_round |
| 10 | perk_look (2 parties) | 57 | 30 | captures seulement | L2 + visuel | perks |
| 11 | dog_round | 47 | 17 | non | L2 | kino_tour p1, mp_dogs |
| 12 | barricades | 45 | 14 | non | L2 | mp_barricades |
| 13 | mystery_box | 42 | 12 + minuteurs 9 s | non | L2 | fire_sale_kino, test_wonder |
| 14 | grenades | 42 | 37 | non | L2 | mp_grenades, test_throwables |
| 15 | zombie_damage | 40 | 22 | non | L2 | points_system, downed_solo |
| 16 | perks2 | 39 | 28 | non | L2 | test_perks, dive |
| 17 | audio_check | 38 | 23 | non | L1 (fichiers) + L2 | **test_audio** (presque tout) |
| 18 | round_system | 36 | 3 + intermission 10 s | non | L2 | test_rounds |
| 19 | teleporter / traps | 36 / 35 | 5 / 6 + actif 25 s | non | L2 | kino_gameplay |
| 20 | unit:tests | 35 (82 isolé) | — | non | L1 | — |

Tableau complet des 81 scénarios (carte, vérifications, attentes, aléatoire,
niveau, recouvrements) : sera repris dans `docs/TESTING.md`.

### 1.7 Redondances repérées (à fusionner, pas à supprimer sans justification)

1. boot ⊂ menu_navigation ; map_select refait le chemin SOLO de menu_navigation.
2. pause_scoreboard et pause_options testent tous deux la pause ; test_settings
   couvre déjà réaffectation / conflits / réinitialisation.
3. map_tour et visual_look utilisent **la même liste de vues** du Bunker ;
   render_quality, visual_look et render_perf basculent les mêmes préréglages.
4. fire_sale_kino ≈ section vente de feu de powerups.
5. Modèle « carte jouable » répété 5 fois : draft_arena, verruckt,
   map_editor_play, kino_tour, levels_nav.
6. Scénarios d'éditeur ≈ tests unitaires homonymes (map_editor*, map_preview).
7. weapon_roster, weapon_view et weapon_aim équipent chacun les 29 armes
   (3 × 29 × 0,8 s rien qu'en changements d'arme).
8. audio_check refait la plupart de test_audio ; vox refait test_vox.
9. Anti-triche : net_guard, weapon_basic, zombie_damage, melee, buyable_doors
   recoupent test_security.
10. mp_session ≈ mp_downed (mort → spectateur → réapparition).
11. Les 8 miroirs multijoueur (barricades, crawlers, dive, grenades, melee,
    powerups, wonder, zombies) refont le scénario solo ; seule la partie
    réplication / validation serveur leur est propre.

### 1.8 État global qui fuit d'une partie à l'autre

Condition pour enchaîner plusieurs scénarios dans une même instance (niveau 2).
Points bloquants (relevé fichier par fichier) :

- `Autotest` est conçu pour **un** scénario (nom unique, drapeau d'échec
  collant, `finish()` quitte le programme et appelle `Audio.stop_all()`, qui
  coupe l'audio **définitivement** : `audio.gd:224`).
- `Net._reset_peer()` ne remet pas `current_map`, `cast_offset`, ports ;
  `MapShare.reset()` laisse les réglages de test (`test_chunk_size`…).
- `Settings.last_map` modifié par map_select / mp_lobby_host et jamais rendu.
- Drapeaux statiques jamais remis : `ZombieModel.use_model`
  (zombie_model_look), `ZombieGibs.debug_chance` (mp_crawlers_host),
  `ZombieShadows.debug_count`, `ParticlePool.density`, `ViewModel.fov_k`.
- `Router.return_scene`, `Engine.time_scale`, `tree().paused`, actions
  `Input` pressées, réglages RenderingServer modifiés par perf_costs.
- Dossiers indexés sur `Autotest.scenario_name` (cartes de l'éditeur, cache
  des cartes partagées).

## 2. Ce que disent les sources

- **Sea of Thieves, GDC 2019 (R. Masella, Rare)** [1][2] : 70 % de tests
  « actor » (un objet du jeu testé seul, avancé à la main image par image,
  ≤ 0,1 s), 5 % de tests d'intégration (≈ 20 s, **sur de mini-cartes** ne
  contenant que le nécessaire, ne couvrant que le cas nominal, les cas limites
  étant testés au niveau actor), perf / captures / démarrage à part. Le coût de
  chargement est payé une fois : plusieurs vérifications par carte, objet
  joueur conservé entre cartes. Avant commit : seulement les tests liés au
  changement ; un échec est rejoué une fois, les tests instables sont mis en
  quarantaine.
- **Riot, League of Legends** [3] : jamais d'attente fixe, toujours une
  attente sur l'état du jeu ; jeu accéléré pendant les tests ; un nouveau test
  passe par une période « en observation » avant de pouvoir bloquer.
- **Factorio** [4][5] : empreinte (CRC) de l'état après chaque test
  d'intégration pour détecter une perte de déterminisme ; tests d'interface
  sans affichage.
- **Tailles de test Google** [6][7] : petit = un processus, sans E/S ni
  attente ; moyen = une machine, localhost ; grand = plusieurs machines. La
  taille se définit par les ressources utilisées.
- **Pyramide de tests** (M. Fowler / H. Vocke) [8] : beaucoup de petits tests
  rapides, peu de bout-en-bout, pas de doublon entre les étages.
- **Sélection par impact** : Microsoft Test Impact Analysis [9] (tests
  impactés + échoués récemment + nouveaux, tout relancer si le changement
  n'est pas compris), Google TAP [10] (graphe de dépendances inverse).
- **Godot** [11][12][13] : `--fixed-fps N` supprime la synchronisation temps
  réel ; `Engine.time_scale` élevé dégrade la physique (préférer `--fixed-fps`) ;
  un `Timer` avec `ignore_time_scale` échappe à l'accélération ;
  `seed()` / un `RandomNumberGenerator` par système rend l'aléatoire rejouable.
- **GUT 9.7** [14] et **gdUnit4 6.2** [15] : doubles/mocks, simulation
  d'entrées, tests paramétrés, sortie JUnit, détection des nœuds orphelins,
  rejeu des tests instables (gdUnit4). gdUnit4 ne liste pas encore Godot 4.7.2 ;
  GUT 9.7.1 est indiqué compatible 4.7.2 mais marqué « instable ». Aucun des
  deux ne réduit le vrai coût ici : ≈ 100 démarrages complets du jeu.
- **Couverture GDScript** [16][17][18] : aucun outil mûr (projets alpha à
  3 étoiles, ou Godot 3 seulement). Instrumentation maison à prévoir en phase 2.

## 3. Architecture proposée

| Niveau | Contenu | Exécution | Cible de durée |
|---|---|---|---|
| **N0 parse** | compilation de tous les scripts (existe) | 1 instance | ≈ 20 s |
| **N1 unitaire** | logique pure + tests « actor » (un nœud du jeu construit seul, `_physics_process(delta)` appelé à la main) ; tests d'assets **mis en cache par empreinte** (sonie des sons, fichiers de voix) | 1 instance, `test_runner.tscn` | < 30 s |
| **N2 intégration** | scénarios gameplay **enchaînés dans une même instance** : pas de menu, partie chargée directement, scène de jeu libérée et état global remis à zéro entre deux, `--fixed-fps 60`, graine fixée | `JOBS` instances (déf. 3), scénarios répartis par durée | ≈ 2-3 min au total |
| **N3 bout-en-bout** | vrai démarrage + menus, multijoueur hôte/client, smoke réseau, scénarios qui lisent vraiment l'image | comme aujourd'hui (fenêtres hors écran, `GUI_JOBS=1`) | ≈ 3 min |
| **Visuel** | captures pour revue humaine (kino_theater, perk_look, galeries) | seulement `--visual` ou `--full` | hors check par défaut |
| **PERF** | perf_costs, long_endurance, zombie_stress, mp_netload, mesures fps | `tools/perf.sh`, jamais dans le check | — |

Annotations d'en-tête (en plus de `@rendu` et `@parts`) :
`## @niveau 2|3|visuel|perf`, `## @couvre scripts/game/perks/*` (dépendance
manuelle), `## @carte test_arena`.

### Sélection intelligente (`tools/check.sh`)

- **Par défaut : tests impactés** par les fichiers modifiés depuis le dernier
  check réussi (empreinte mémorisée dans `tests/_out/last_ok`). Carte fichier →
  tests générée automatiquement (`preload`, `load`, `class_name` utilisés,
  scènes `.tscn` et leurs scripts, cartes nommées), complétée par `@couvre`.
  Un test modifié ou échoué au dernier passage est toujours relancé.
- **Fichiers « noyau »** (autoloads, `game.gd`, `player.gd`, `net*.gd`,
  `project.godot`, framework de test) → tout le niveau concerné.
- Un fichier que la carte ne sait pas rattacher → check complet (principe de
  Microsoft TIA : dans le doute, tout).
- **Cache** : un test dont l'empreinte (lui + ses dépendances) n'a pas changé
  depuis un succès n'est pas relancé.
- `--full` : tout sauf PERF, obligatoire dans `tools/release.sh` / `ship.sh`.
- Sortie : résumé final, chemin du journal de chaque échec, durée par test,
  rapport JUnit `tests/_out/junit.xml`.
- Un échec est **rejoué une fois** ; s'il passe au second essai, il est signalé
  « instable » dans le bilan (et consigné dans `tests/_out/flaky.txt`), sans
  bloquer. Aucune quarantaine silencieuse.

### Framework : garder le framework maison

Recommandation : **ne pas migrer** vers GUT ou gdUnit4. Raisons : le goulot est
le nombre de démarrages, pas le framework ; les deux suivent Godot avec du
retard (4.7.2 non listé par gdUnit4) ; réécrire 45 fichiers unitaires et 100
scénarios coûterait cher sans gain de temps. On **reprend leurs idées** :
durée par test, sortie JUnit, comptage des nœuds orphelins après chaque test,
rejeu une fois des échecs, cas paramétrés, `wait_until` avec délai maximal.

## 4. Étapes d'implémentation (chacune vérifiable seule)

1. **Horloge de jeu unique** (`GameClock`, temps de jeu cumulé à partir de
   `delta`, respecte pause et `time_scale`) à la place des `now()` en temps
   mural des 10 systèmes listés en 1.3. L'interpolation réseau (`player.gd`,
   `zombie.gd`, `zombie_manager.gd`, `net.gd`) reste en temps réel : elle
   compare des arrivées de paquets. Vérification : check complet vert, puis
   points_system vert 10 fois de suite avec `--fixed-fps 60`.
2. **Aléatoire déterministe en test** : graine fixée par scénario (`seed()` +
   `RandomNumberGenerator` des systèmes qui en ont), fichier de carrière et
   dossiers propres au processus.
3. **`--fixed-fps 60` pour tous les scénarios sans rendu** ; attentes fixes
   remplacées par des attentes sur condition partout où elles attendent un
   événement (les délais qui simulent un joueur humain restent, ils ne coûtent
   presque rien en temps accéléré).
4. **Runner N2** : `--autotest=a,b,c` enchaîne plusieurs scénarios ; entre deux,
   libération de la scène de jeu et `reset_for_test()` des autoloads et
   drapeaux statiques (liste 1.8) ; vérification d'absence de fuite (nœuds
   orphelins, drapeaux) après chaque scénario ; chaque scénario reste lançable
   seul. Démarrage direct de la partie sans passer par le menu.
5. **Tests unitaires** : cache par empreinte des tests d'assets, délai de
   connexion réduit et paramétrable pour `test_join_nobody_listening`, durée
   par test, JUnit.
6. **Reclassement** (niveau, visuel, perf) et fusion des doublons de 1.7,
   chaque déplacement justifié dans le rapport de phase (aucune vérification
   perdue : chaque `check()` supprimé doit exister ailleurs, liste dans le
   rapport).
7. **Sélection par impact** + cache + `--full` + intégration dans
   `commit.sh` (incrémental) et `release.sh` (complet).
8. `docs/TESTING.md` : stratégie, niveaux, comment écrire un test de chaque
   niveau, commandes, sources.

## 5. Chiffres avant / après attendus

| Mesure | Avant | Après (estimation) | Base de l'estimation |
|---|---|---|---|
| CPU cumulé des scénarios sans rendu | 2 264 s | ≈ 600-800 s | ×2 à ×3,7 mesurés avec `--fixed-fps` |
| Démarrages complets par check | ≈ 110 | ≈ 40 (N3 + 3 instances N2) | runner N2 |
| Tests unitaires | 35-82 s | < 30 s | cache des tests d'assets |
| **Check complet** (`JOBS=3`, `GUI_JOBS=1`) | **12-15 min** | **≈ 5 min** | somme des niveaux ci-dessus |
| **Check incrémental typique** | 12-15 min | **< 2 min** | import + parse + unitaires + tests impactés |
| Tests instables connus | ≥ 4 | 0 connu, rejeu signalé | horloge + graines + fichiers par processus |

Le multijoueur reste le plus gros poste du check complet (≈ 470 s cumulées) :
ENet tourne en temps réel, `--fixed-fps` y est plus risqué ; on commence par
retirer les `sleep` de synchronisation et on mesure avant d'aller plus loin.

### 5.1 Résultats mesurés (30/09/2026, même machine, `JOBS=3`, `GUI_JOBS=1`)

| Mesure | Avant | Après |
|---|---|---|
| **Check complet** (`--full`) | 12-15 min (531 s au 1er essai de l'outil, sans séries) | **315 s** (5 min 15), aucun test instable |
| **Check sans changement** | 12-15 min | **32 s** (import + carte des dépendances) |
| **Check après modification d'un fichier de gameplay** (`mystery_box.gd`) | 12-15 min | **≈ 90 s** (12 tâches) |
| CPU cumulé, scénarios sans rendu | 2 264 s (59 tâches) | **220 s** (48 scénarios en 3 séries + 6 seuls) |
| CPU cumulé, multijoueur | 467 s | **254 s** (12 paires ×4, 5 en temps réel) |
| CPU cumulé, avec rendu | 488 s (14 tâches) | 256 s (10 tâches) |
| Démarrages de jeu par check complet | ≈ 125 | ≈ 55 |
| Plus long scénario | weapon_roster 179 s (4 parties) | 9 s en série |

Ce qui a produit le gain, dans l'ordre :
1. **Horloge de jeu** (`GameClock`) + `--fixed-fps 60` : ×3 à ×13 sur les
   scénarios sans rendu (perks 27 → 9 s, weapon_view 171 → 13 s).
2. **Séries** (niveau 2) : 48 scénarios dans 3 processus au lieu de 48 ;
   chaque scénario ne coûte plus que 1 à 9 s.
3. **Multijoueur à cadence fixe ×4** (`--fixed-fps 60 --max-fps 240`) : les
   deux jeux avancent au même rythme (sans plafond, chacun allait à la vitesse
   de son processeur et leurs temps divergeaient : mp_crawlers, mp_melee).
4. **Sélection par impact** : seules les tâches dont les dépendances ont changé.
5. Captures seules passées sans rendu, tests Kino seulement quand Kino change,
   startup_smoothness au niveau perf.

Changements de tests (aucune vérification supprimée) :
- `@parts` retiré de weapon_aim / weapon_roster / weapon_view (entiers en 9 à 15 s) ;
  `@rendu` retiré de kino_theater, perk_look, map_editor, map_editor_diagonal,
  map_editor_freeform (captures seulement : leurs vérifications passent sans rendu).
- startup_smoothness : `@niveau perf` (sa vérification n'était jamais faite en
  parallèle ; lancée par `tools/perf.sh`).
- Mesures de durée de jeu des scénarios : `GameClock.msec()` ; mesures de coût
  CPU : toujours `Time`.

### 5.2 Attentes sur événement, graines, multijoueur accéléré (01/10/2026)

| Mesure | Avant | Après |
|---|---|---|
| Attentes fixes `seconds(…)` (tests/autotest) | 701 (593 s écrites) | **462 (280 s)**, dont ≈ 90 dans les scénarios d'armes et d'éditeur non traités ici |
| Attentes sur condition `until(…)` | 270 | 446 |
| Délais de synchronisation hôte / client | `sleep 1` (mp_test.sh) + 1,5 s (`join_game`) + longues attentes finales (3 à 8 s) | **aucun** : rendez-vous par fichiers (`MpHelpers.signal_peer / wait_peer / finish`) |
| Multijoueur en temps réel (`@temps-reel`) | 7 paires | **3** : mp_custommap, mp_netload (mesures par seconde réelle), mp_dive (voir ci-dessous) |
| mp_barricades + mp_dive + mp_lobby + mp_grenades + mp_melee | 124 s (temps réel) | **43 s** (4 accélérées, mp_dive 18 → 9 s en temps réel) |
| CPU cumulé, multijoueur | 294 s | **193 s** |
| Tests instables | mp:crawlers au check « avant » (rampant 0,22 m en 2 s fixes), mp:sync (tirs perdus) | 0 sur les passages de vérification (chaque scénario modifié ≥ 3 fois) |
| **Check complet** (`--full`, JOBS=3) | **376 s** | **517 s mesurés**, voir la note |

Note sur la durée du check : le second check complet a été ordonnancé avec un
`durations.txt` vidé par les checks ciblés précédents (défaut de check.sh
corrigé depuis : un `SCENARIOS=…` ne réécrivait que ses propres tâches). Les
12 tâches avec rendu (une à la fois, ≈ 300 s en tout, le chemin critique) sont
donc parties en dernier au lieu d'en premier. Avec l'ordre normal, le check
est borné par cette chaîne de rendu : ≈ 330 s + import, soit ≈ 370 s. Le gain
réel de cette étape est côté multijoueur (−100 s de CPU) et fiabilité ; les
séries sans rendu (152 s d'horloge cumulée avant comme après) coûtaient déjà
peu en temps accéléré.

Ce qui a été fait :
1. **Rendez-vous hôte / client** : `tools/mp_test.sh` lance les deux jeux sans
   délai ; le client attend l'annonce « ecoute » de l'hôte, l'hôte l'annonce
   « salon » du client ; chaque étape où l'un attendait l'autre par une durée
   est un `wait_peer` ; fin commune `MpHelpers.finish`.
2. **Pourquoi les mp échouaient en accéléré** : ils attendaient l'autre jeu par
   des durées de jeu (×3 plus courtes en temps réel), alors que la marionnette
   distante est interpolée en temps réel (`Player.INTERP_DELAY` = 0,1 s réelle,
   soit ≥ 0,3 s de jeu à ×3). Ex. mp_barricades : le client appuyait sur [F]
   0,1 s réelle après sa téléportation, le serveur le voyait encore loin
   (« trop loin ») ; maintenant il répare quand l'hôte l'a vu devant la fenêtre.
   mp_lobby : le client rejoignait avant que l'hôte écoute.
3. **mp_dive reste en temps réel** : `Combat.srv_dive_landed` borne la position
   d'atterrissage annoncée par la position interpolée du client ; à ×3 le
   serveur le voit encore au départ (≈ 5 m, > `MAX_ORIGIN_ERROR`) et garde
   cette position (mesuré : client allongé en (8 ; 7,5), position gardée
   (2,5 ; 7,5)). C'est ce que vivrait un joueur à forte latence : à traiter côté
   jeu (valider contre le dernier état reçu, `_srv_ok_pos`, plutôt que la
   position interpolée ; même remarque pour `srv_melee`, `srv_fire`,
   `srv_throw`, `srv_interact`).
4. **mp:sync** : les effets de tir passent par un canal non fiable ; sous
   charge, jusqu'à 7 tirs sur 10 perdus (mesuré). L'hôte tire désormais (en
   rechargeant) jusqu'à ce que le client en ait vu 5, et le client en exige 5
   (au lieu de 4 sur 5).
5. **Graine par scénario** (`Autotest._seed_scenario`, `_seed_rngs`) : hash du
   nom, imprimée dans le journal, `--seed=N` pour rejouer ; `seed()` global et
   chaque `RandomNumberGenerator` du jeu à sa création. Hors autotest : rien.
6. **Attentes fixes → conditions** dans 46 scénarios solo et les 17 paires
   multijoueur (achat fait, boisson
   finie, zombie sorti de terre — `AutotestHelpers.emerged` —, mort, bonus
   ramassé, invite affichée, transition de menu finie, navigation à jour…).
   Gardées et commentées : gestes humains (touche tenue, élan, mise en joue),
   durées mesurées, fenêtres « rien ne doit se passer », captures, fenêtres de
   perf et temps de pose du rendu.

Changements de vérifications (aucune supprimée) : mp_sync exige 5 tirs reçus
(au lieu de 4) ; mp_grenades mesure l'arrivée des zombies au singe en moins de
4 s de jeu (au lieu d'un instantané à 4 s) ; mp_crawlers vérifie que le rampant
avance de 0,5 m (délai 6 s au lieu d'une fenêtre fixe de 2 s : la marionnette
est interpolée en temps réel).

### 5.3 Reste à faire (phase 1)

- **Scénarios d'armes et d'éditeur** (weapon_aim, weapon_view, weapon_roster,
  weapon_basic, scope, map_editor*, map_preview*) : attentes fixes pas
  encore converties (travail en cours d'un autre chantier).
- **Validation serveur contre la position interpolée** (§ 5.2, point 3) : à
  corriger côté jeu, puis passer mp_dive en accéléré.
- **visual_look** (3 parties, ≈ 120 s en temps réel) : plus gros poste avec
  rendu ; ses parties 1 et 2 sont sur Kino (à passer sur BUNKER K-7 ou à
  réserver aux changements de Kino). Ses attentes restantes sont des temps de
  pose du rendu et des fenêtres de mesure.
- **Chaîne des tâches avec rendu** (`GUI_JOBS=1`, ≈ 300 s) : c'est maintenant
  elle qui borne le check complet.
- **Doublons** (§ 1.7) : fusion au cas par cas, avec la liste des vérifications
  déplacées.
- `test_audio::test_loudness_of_every_sound` (18 s) : ne tourne plus que si
  les sons changent (sélection par impact) ; suffisant pour l'instant.

## 6. Décisions (validées par l'utilisateur le 30/09/2026)

1. **Framework maison conservé**, avec reprise d'idées de GUT / gdUnit4.
2. **Horloge de jeu unique** pour les minuteurs de gameplay (l'interpolation
   réseau reste en temps réel).
3. **Captures d'écran** : uniquement pour un ajout **en cours** de
   développement ; une fois la fonctionnalité publiée, la capture sort du check.
   Les vérifications logiques des scénarios visuels sont gardées (déplacées en
   N1/N2). Le niveau « Visuel » du §3 se limite donc aux ajouts en cours
   (aujourd'hui : zombie_model_look, zombie Blender).
4. **Tests de la carte Kino** (kino_tour, kino_gameplay, kino_theater,
   fire_sale_kino, test_kino_map) conservés mais lancés **uniquement quand des
   fichiers de la carte Kino changent** : ni à chaque check, ni sur changement
   d'un fichier noyau, ni dans `--full` (option explicite `--kino` pour les forcer).
5. **Check incrémental par défaut** ; `--full` obligatoire avant release.
6. **Rejeu une fois** des échecs ; signalés instables, non bloquants.

## Sources

1. R. Masella, *Automated Testing of Gameplay Features in Sea of Thieves*, GDC 2019 — https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf
2. Vidéo GDC Vault — https://gdcvault.com/play/1026366/Automated-Testing-of-Gameplay-Features
3. Riot Games, *Automated Testing for League of Legends* — https://www.riotgames.com/en/news/automated-testing-league-legends
4. Factorio Friday Facts #366 — https://www.factorio.com/blog/post/fff-366
5. Factorio Friday Facts #60 — https://factorio.com/blog/post/fff-60
6. Google Testing Blog, *Test Sizes* — https://testing.googleblog.com/2010/12/test-sizes.html
7. *Software Engineering at Google*, chap. 14 — https://abseil.io/resources/swe-book/html/ch14.html
8. H. Vocke, *The Practical Test Pyramid* — https://martinfowler.com/articles/practical-test-pyramid.html
9. Microsoft, *Test Impact Analysis* — https://learn.microsoft.com/en-us/azure/devops/pipelines/test/test-impact-analysis
10. Memon et al., *Taming Google-Scale Continuous Testing* — https://research.google.com/pubs/archive/45861.pdf
11. Godot, ligne de commande — https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
12. Godot, classe `Engine` — https://docs.godotengine.org/en/stable/classes/class_engine.html
13. Godot, nombres aléatoires — https://docs.godotengine.org/en/stable/tutorials/math/random_number_generation.html
14. GUT — https://github.com/bitwes/Gut
15. gdUnit4 — https://github.com/godot-gdunit-labs/gdUnit4
16. godot-code-coverage (Godot 3) — https://github.com/jamie-pate/godot-code-coverage
17. nano-coverage-godot — https://github.com/IgorBayerl/nano-coverage-godot
18. gd-tools — https://github.com/mansyar/gd-tools
