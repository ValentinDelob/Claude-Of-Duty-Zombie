# Refonte du code pour la robustesse — Phase 3 : analyse et plan

> Revue de `scripts/` et `launcher/scripts/` (30/09/2026, ≈ 49 700 lignes,
> 187 scripts). Règle : chaque étape = un commit, tests verts avant et après,
> **comportement identique** (ressenti BO1 inchangé). Les corrections qui
> changent un comportement sont listées à part (§ 6) et traitées hors refonte.

## 1. Constat

- Code déjà très typé : 0 fonction nommée sans type de retour ; 73 `var x =`
  non typées (presque toutes des Variant venant de JSON / fichiers non fiables).
- Plus gros fichiers : `editor/map_editor.gd` (1768), `editor/map_validator.gd`
  (1694), `editor/map_canvas.gd` (1452), `weapons/weapon_models.gd` (1380,
  données en code), `map/custom_map_guard.gd` (1223), `launcher/scripts/main.gd` (881).
- **`game/game.gd` (587 lignes) mélange** : registre des cartes (11-57),
  cycle de vie et branchements (99-134), construction du monde (137-164 +
  375-524 : 9 `_build_*`), début de partie et joueurs (170-244), souris
  (250-266), mort / fin de partie / réapparition (274-372, règles + réseau +
  présentation), téléportation (481-502), barricades (527-549), caméra
  spectateur (556-587).
- **Couplages cachés** : l'aperçu 3D de l'éditeur (`map_preview_world.gd:371-420`)
  appelle les méthodes PRIVÉES `_game._build_*()` ; accès privés entre objets
  (`z._phase` ×17 dans zombie_gibs, `p._snapshots`, `lp._flinch`…) ;
  `Game.instance` utilisé 59 fois, dont 6 sans garde (zombie.gd:426/469/625,
  hellhound.gd:117/156, weapon_controller.gd:333) alors que `game` est parfois
  déjà transmis mais non gardé (`WeaponController.setup`).
- **Duplication** : 6 fonctions `now()` identiques (toutes vers `GameClock`) ;
  seau de jetons réécrit dans `Combat._validate_fire` à côté de
  `NetGuard.Limiter` ; construction des cartes répétée entre `MeshMapBuilder`
  et `MapPreviewBuilder` ; prologue des RPC serveur (`is_server`, émetteur,
  joueur vivant) répété 7 fois ; petits utilitaires de maillage (`_part`,
  `_q`) copiés dans 3 à 4 fichiers.
- **Crochets de test dans le code du jeu** : 7 (`Autotest.active`), dont
  `player.gd:577` qui coupe le contrôle anti-téléportation dans TOUS les
  scénarios (seul un test unitaire le couvre) ; trois façons différentes de
  détecter le mode test.
- **Erreurs ignorées** : `load()` sans contrôle avant `.instantiate()`
  (pack_a_punch.gd:267, mesh_map_builder.gd:44, game.gd:50, main_menu.gd:192,
  pause_menu.gd:117) ; `cfg.save()` / `store_string` dont l'erreur est
  perdue (settings, career_stats, map_editor, store du lanceur…).
- **Avertissements GDScript** : aucune clé `gdscript/warnings/*` dans
  `project.godot` (valeurs par défaut) ; le check ne compte pas les
  avertissements. Estimations si on les active : `untyped_declaration` ≈ 580
  (surtout des lambdas), `unsafe_*` 1 500 à 3 000, `return_value_discarded`
  ≈ 500 ; `unused_parameter` ≈ 5, `integer_division` ≈ 11.
- **Lanceur** : `main.gd` mélange interface (170 lignes de `_build_ui`),
  HTTP, cache des notes, téléchargement et auto-mise à jour ; `releases.gd`
  et `store.gd` sont purs et testés.

## 2. Plan par étapes sûres

| # | Étape | Fichiers | Risque | Vérification |
|---|---|---|---|---|
| 1 | Compter les avertissements du check (sans bloquer), clés explicites dans `[debug]` | check.sh, project.godot | nul | le nombre apparaît dans le bilan |
| 2 | `var x: Variant =` pour les données non fiables | custom_map_guard, editor_map, map_editor, net, safe_config, lanceur | très faible | parse, test_security, test_net_hardening, test_map_share, test_launcher |
| 3 | Une seule source de temps : supprimer les 6 `now()` (appels → `GameClock.now()`) | combat, downed_system, throwable*, throw_controller, weapon_controller, perk_system, view_model | faible | test_gunplay, test_throwables, test_perks, weapon_basic, grenades, downed_solo |
| 4 | Accesseurs publics au lieu des accès privés (Player, Zombie) | game, zombie*, barricade, nova_fx, throwable_system | faible | test_gibs, test_barricades, crawlers, mp_sync |
| 5 | `MapRegistry` (registre des cartes sorti de game.gd, alias gardés) | game.gd, nouveau map_registry.gd | faible | test_kino_map, test_map_*, map_select, mp_custommap |
| 6 | `GameWorldBuilder` : les 9 `_build_*` en API publique (mêmes noms de nœuds, même ordre d'enregistrement) | game.gd, nouveau game_world_builder.gd | moyen | map_preview, buyable_doors, wall_buys, perks, mystery_box, pack_a_punch, teleporter, traps, verruckt, mp_* |
| 7 | L'aperçu de l'éditeur utilise ce constructeur public | map_preview_world, barricade_system, throwable_system | moyen | test_map_preview, map_editor_play |
| 8 | Construction des cartes mise en commun (jeu / aperçu) | mesh_map_builder, map_preview_builder | faible-moyen | test « même géométrie que le jeu » |
| 9 | `MatchRules` (règles pures de fin de partie, réapparition, point d'apparition) + test unitaire | game.gd, nouveau match_rules.gd | faible | nouveau test_match_rules, round_system, mp_downed |
| 10 | Caméra spectateur en nœud à part ; présentation du GAME OVER dans le HUD | game.gd, hud | faible-moyen | mp_downed, mp_leave, career_record |
| 11 | Prologue des RPC serveur centralisé (`NetGuard.server_sender`, `alive_sender`), seau de jetons unique | net_guard, combat, throwable_system, interaction_system | moyen (sécurité) | test_security, test_net*, net_guard, mp_* |
| 12 | Injection cohérente de `game` (armes, zombies, chiens) | weapon_controller, zombie, hellhound, zombie_manager, dog_round | moyen | zombie_*, dog_round, mp_dogs |
| 13 | `load()` contrôlés | pack_a_punch, mesh_map_builder, game, main_menu, pause_menu | faible | pack_a_punch, verruckt, menu_navigation |
| 14 | Erreurs d'écriture journalisées | settings, career_stats, map_editor, store, editor_map, custom_map_guard | très faible | test_settings, test_career, test_launcher |
| 15 | Une seule détection du mode test (`Autotest.is_running()`) | custom_map_guard, editor_map, map_preview_panel, settings | faible-moyen | check complet |

Check des tâches impactées après chaque étape ; check complet après 6, 9, 12.

## 3. Hors refonte (changent un comportement : à traiter comme corrections)

- `interaction_system.gd:116 srv_release` : ni limiteur ni contrôle
  vivant / distance ; `srv_cook` / `srv_throw` sans limiteur.
- `game.gd:357` : `spawns[... % spawns.size()]` sans garde (la ligne 187 en a une).
- Chargement interrompu (`await Warmup.run`) si la session se termine pendant
  le chargement.
- Contrôle anti-téléportation jamais exercé en multijoueur (`player.gd:577`).
- Rappels différés (`SceneTreeTimer` + lambda) sans vérifier que le joueur
  est encore là (combat.gd:154, weapon_controller.gd:263/370/410…).

**Traité (30/09/2026)** sauf l'anti-téléportation : limiteurs de
`srv_release` / `srv_cook` / refus de `srv_throw` (scénario `net_guard`),
garde du point de réapparition (`Game.spawn_for_slot`, `test_robustness`),
chargement abandonné si la session se termine (`load_abort`). Rappels
différés : une connexion à une lambda disparaît avec son objet (vérifié par
`delayed_callbacks`) ; le seul défaut réel était la confirmation de touche
envoyée à un tireur déjà parti (corrigé dans `Combat.damage_zombie`).

## 4. Réalisé

| Étape | Fait | Pourquoi / effet |
|---|---|---|
| 1 | `tools/warnings.sh` : audit des avertissements (réglés sur « erreur » dans une copie du projet, compilation sans fenêtre) | Godot n'affiche les avertissements que dans l'éditeur ; mesure initiale : **10 503** avertissements, dont 4 037 `unsafe_call_argument`, 2 223 `unsafe_method_access`, 1 637 `untyped_declaration`, 1 426 `return_value_discarded` |
| 1 bis | **165 avertissements utiles corrigés** sans changer le comportement : variables et paramètres inutilisés, masquages (renommages locaux), divisions entières (`@warning_ignore` : la troncature est voulue), fonctions statiques appelées sur une instance (autoloads sans `class_name`), ternaires, `await` superflu, conversion en enum | reste 9 occurrences dans des fichiers en cours d'écriture (carte Verrückt, zombies Blender) ; une fois ces fichiers terminés, ces avertissements passent en **erreur** dans `project.godot` (toute nouvelle occurrence cassera la compilation du check) |
| 2 | 68 `var x =` → `var x: Variant =` (données JSON / fichiers non fiables) | type explicite, sémantique identique |
| 3 | Une seule source de temps : les 6 `now()` supprimés, appels directs à `GameClock.now()` | plus de copies ; le temps de jeu est la référence (voir `docs/TESTING.md`) |
| 4 | Accesseurs publics : `Zombie.gait_phase`, `attack_t` (lecture / écriture), `state_time`, `head_tilt`, `body_shape` (lecture), `separation()`, `is_target_valid()` ; `Player.add_flinch()`, `reset_eye_height()`, `clear_snapshots()`. Utilisés par `zombie_gibs`, `zombie_anim`, `barricade`, les deux lignes de `game.gd`, puis `nova_fx.gd` et `throwable_system.gd` (`lp.add_flinch(...)`) | plus aucun accès `z._xxx` / `p._xxx` depuis ces fichiers ; les champs privés restent (sous-classe `Hellhound`, tween sur `"_eye_height"`, tests) |
| 11 | Prologue des RPC serveur : `NetGuard.server_sender(node, limiter)` (serveur, expéditeur, limiteur facultatif), `known_sender(node, game, limiter, need_player)` (joueur de la partie), `alive_sender(...)` (vivant), valeur `NetGuard.NO_SENDER`. Utilisé par les 9 `srv_*` de `Combat`, `InteractionSystem` et `ThrowableSystem`. Un seul seau de jetons : `NetGuard.Limiter.take(pid, t, débit, rafale)`, dont se sert aussi la cadence de tir de `Combat` (débit de l'arme, horloge de jeu) | mêmes limites, même ordre des contrôles (un limiteur qui ne compte que les demandes utiles — `srv_reload`, `srv_switch` — ou que les refus — `srv_throw` — reste à sa place), mêmes refus et journaux ; `srv_cook` n'exige toujours pas le nœud Player (`need_player = false`). Non convertis : RPC du salon (`Net._srv_hello` / `_srv_loaded`, `MapShare`), qui identifient les pairs par `Net.players` ; le seau de `MapShare` reste à part (rempli à chaque image, en temps de jeu simulé dans les tests) |
| 12 | Référence à la partie injectée (voir `docs/ARCHITECTURE.md`, « Référence à la partie ») : `WeaponController.game` (de `setup`), `DogRound` via `RoundManager.game`, `ZombieManager.game` (parent), lu par `Zombie` / `Hellhound` dans `_ready`, et par `ZombieGibs` / `ZombieFling` via `z.game` ; `Zombie.map_is_multilevel()` devient une méthode d'instance | plus de `Game.instance` dans ces fichiers ; les accès non gardés (cible d'un zombie, sang du tir à la tête, ligne de vue et morsure du chien) ne plantent plus hors partie : un zombie sans partie n'a aucune cible. `Game.instance` reste dans `Player`, `Fx`, `VoxSystem`, `DeadeyeAim`, `DogLightning`, `Barricade`, `Door`, `BoxBoard` (tous gardés) |
| 8 | Construction des cartes mise en commun : `MeshMapBuilder` a trois morceaux (`_add_architecture` : sols de référence des salles + `_setup_nodes` ; `_build_decor_parts` : objets, objets répétés, écrans, pavés ; `_build_lamps` : boucle des lampes avec la règle `i % 5 == 3`), appelés par `build()` et par les trois `build_*` de `MapPreviewBuilder` | plus de boucle recopiée : l'aperçu ne peut plus diverger du jeu. Ordre conservé à l'identique (en jeu, l'architecture est préparée avant la lecture de `prop_materials` ; dans l'aperçu, après — seule KINO a cette clé et l'aperçu ne montre que des cartes de l'éditeur). Barrières invisibles (`_build_clip_views`) et variantes intactes |
| 15 | Une seule détection du mode test : `AutotestMode` (`scripts/autoload/autotest_mode.gd`, statique : `batch()`, `is_running()`, `scenario_name()`) lit `--autotest=` ; utilisée par `Settings` (fichier de réglages de test, fenêtre), `EditorMap.maps_root`, `CustomMapGuard.cache_root`, `MapPreviewPanel` et par l'autoload `Autotest` lui-même pour sa liste de scénarios. Test `tests/test_autotest_mode.gd` | plus de `get_node_or_null("/root/Autotest")` ni de lecture d'arguments à part ; répond avant le `_ready` des autoloads (ordre d'initialisation de `Settings` inchangé). Seule différence : `--autotest=` **vide** ne met plus `Settings` en mode test (l'autoload, lui, ne jouait déjà rien). Les dossiers de test restent propres au scénario en cours d'une série (`scenario_name()` lit l'autoload). Les autres `Autotest.active` (fichiers de gameplay) restent : même valeur |
| 9 | `MatchRules` (`scripts/game/match_rules.gd`, statique, sans nœud) : fin de partie (`is_game_over` : personne debout, l'auto-réanimation LAZARUS la repousse, aucun joueur = fin), saignement (`bleed_out`), total des zombies abattus, réapparition des morts (`should_respawn`, `respawn` : santé pleine, M1911 seul, couteau de base, points gardés), point d'apparition par place (`spawn_for_slot`, repli `FALLBACK_SPAWN` sans point). `Game` n'en garde que le réseau et la présentation ; `Game.spawn_for_slot` / `Game.FALLBACK_SPAWN` restent comme alias. Test `tests/test_match_rules.gd` | règles lisibles et testées sans partie (solo / coop, à terre, saignement, carte sans point d'apparition) ; mêmes appels dans le même ordre |
| 10 | Caméra spectateur : nœud `SpectatorCamera` (`scripts/game/spectator_camera.gd`, enfant « Spectator » de Game, sans RPC) ; `Game.spectating` devient une lecture de ce nœud. Présentation du GAME OVER : `Hud.show_game_over(summary, survived)` (titre + résumé, manches survécues, tableau, battement de cœur ; textes déjà traduits par `Game.game_over_summary` / `Game.survived_text`) ; `Game._cl_game_over` (reçoit le nombre de zombies tués, texte écrit par chaque client dans sa langue) garde l'état, le dossier de combat, la souris et le délai de retour au menu | `game.gd` ne dessine plus rien de la fin de partie ; textes, tailles, fondus et délais repris à l'identique |
| 13 | `load()` contrôlés : Pack-a-Punch, architecture des cartes, écrans du menu et de la pause | un fichier manquant donne une erreur claire au lieu d'un plantage |
| 14 | Erreurs d'écriture journalisées : réglages, dossier de combat, préférences de l'éditeur, réglages du lanceur | une sauvegarde ratée n'est plus silencieuse |
| — | Corrections de la revue des étapes 11-12 : `Spawner._far_time` purgé des zombies qui ne sont plus vivants (grossissait toute la partie ; un zombie au même identifiant héritait du temps) — `test_spawner.gd` ; achat mural sans prix (arme inconnue ou de la boîte mystère posée au mur par une carte perso) refusé avec `push_error` au lieu d'être gratuit, munitions comprises — `test_wall_buy.gd` ; rafale tolérée par la cadence de tir d'au moins 0,4 s de tirs de l'arme (`Combat.fire_burst`) : 4 tirs ne couvraient que 0,2 s d'à-coup pour la FAUCHEUSE (tir honnête refusé, `mp:powerups` instable) — `test_security.gd` | comportement faux corrigé, test à l'appui |
| — | Corrections trouvées par les nouveaux tests : `Session.try_spend` refuse un montant négatif (il créditait des points) ; `SafeConfig.get_int` borne avant la conversion (1e30 donnait la borne basse) ; lanceur : un champ `null` de l'API GitHub vidait toute la liste des versions ; numéros et noms de fichiers avec saut de ligne final acceptés | comportement faux corrigé, test à l'appui |

**Avertissements volontairement non activés** : `unsafe_*`, `untyped_declaration`,
`return_value_discarded`, `inferred_declaration`. Le style du projet (`:=`,
données JSON lues en `Variant`, lambdas courtes, `connect()` sans lire le
code de retour) en produit des milliers sans gain de robustesse ; les passer
à zéro reviendrait à réécrire le code. Ils restent mesurés par `tools/warnings.sh`.

**Reste à faire** : étapes 5 à 7 (`MapRegistry`, `GameWorldBuilder`,
aperçu de l'éditeur sur ce constructeur). `game.gd` étant en cours de modification (carte
Verrückt), les étapes qui le touchent attendent que ce travail soit committé.
Suite possible de l'étape 12 : injecter aussi `game` dans `Player`,
`Barricade`, `Door`, `BoxBoard`, `DeadeyeAim` (créés par `Game`, ils lisent
encore `Game.instance`, avec garde).

## 5. Performance (CPU, 01/10/2026)

**Mesure.** Scénario `perf_cpu` (`## @niveau perf`, hors check) sans rendu,
`--fixed-fps 60` : l'écart entre deux images est le coût CPU complet d'une
image. Fin de partie sur KINO puis DRAFT ARENA : 24 zombies (manche 24) et
4 chiens gardés en vie ; phase « horde » (au contact, le joueur ne tire pas)
puis « combat » (HK21 en continu, démembrements, morts, réapparitions, une
grenade toutes les 2 s), puis micro-mesures (µs par appel). Détail par
fonction : `bash tools/profile.sh` (copie instrumentée du projet, sources
jamais modifiées ; temps inclusifs, surcoût ≈ 1 µs par appel mesuré). Réseau :
paire hôte + client sur KINO (28 zombies). GPU non mesuré (sans rendu) :
`perf_costs` reste l'outil pour le GPU. Machine partagée : chiffres à ±30 %,
les comparaisons avant / après sont appariées dans le même processus quand
c'est possible.

**Image complète (KINO, combat)** : 6,1 ms (pire 17,9) -> 4,6-5,1 ms (pire
10,6-10,7) ; DRAFT ARENA 4,6 ms (pire 18,2) -> 3,9-4,0 ms (pire 11,9-13,6).

**Postes les plus chers (copie instrumentée, KINO, ms par image)**

| Poste | horde | combat | Remarque |
|---|---|---|---|
| `Zombie._physics_process` (28) | 2,3-2,9 | 2,6-2,9 | dont `_chase` 1,0-1,3 (`find_path` 0,4-0,5), `_follow_floor` 0,25-0,38, `_separation` 0,25-0,36, reste ≈ `move_and_slide` |
| `Player._physics_process` | 1,0-1,25 | 1,3-1,8 | dont `_move` 0,69-0,87 (socle du téléporteur, R1) |
| `Hellhound._physics_process` (4) | 0,6-0,8 | 0,7-0,8 | 150-200 µs par chien (super + ligne de vue à chaque pas) |
| `Zombie._process` (animation, sons) | 0,66-0,69 | 0,6-0,83 | pose 0,36-0,44 |
| `Audio.play_3d` | 0,33 | 0,76 | **corrigé** : chargement du fichier au premier son (0,87 ms par son) |
| `WeaponController.tick` | 0,14-0,19 | 0,38-0,78 | `_fire` 1,1-2,9 ms par tir, `_trace` 0,28-0,34 ms |
| `Hud._process` | 0,12-0,14 | 0,13-0,17 | R7 |
| `InteractionSystem.local_tick` | 0,10-0,15 | 0,14 | R8 |
| `ParticlePool._process` (5) | 0,03 | 0,13-0,15 | **corrigé** (-24 %) |

**Corrigé (fichiers autorisés, rendu et jeu identiques)**

| Commit | Avant -> après |
|---|---|
| `ZombieAnim` : tables de clés constantes (plus d'Array alloués par pose) | `_keys` 3,0 -> 1,2 µs (même processus) ; ≈ 11 µs par zombie qui attaque et par image |
| `ParticlePool.burst` : un seul sol par gerbe (rayon sur les cartes en maillage) | giclée de sang 204 -> 21-45 µs, impact 102 -> 24-54 µs, grenade (effets) 837 -> 126-245 µs, démembrement 447 -> 160-250 µs ; gerbe de 12 : 22 µs contre 117 (même processus) |
| `ParticlePool._process` en une passe | 128 -> 97 µs pour 240 particules (même processus, image identique vérifiée) |
| `Audio` : effets chargés en tâche de fond au lancement | premier appel d'un son 869 -> 6-12 µs (≈ 75 sons joués pour la première fois en pleine partie) |

**Réseau (hôte + client, KINO, 28 zombies)** : 15 instantanés/s (84-91
en 6 s réelles), ≈ 150 octets chacun ; `build_snapshot` 72-150 µs (encodage
38-44), client `apply_snapshot` 220-300 µs (instrumenté, dont `decode` ≈
95) : < 0,1 ms par image. Le poste client qui compte est l'interpolation :
`Zombie._interpolate` 7 µs x 28 = 0,2 ms par image (R5). Remarque : en paire
accélérée (`--fixed-fps` + `--max-fps 180`), hôte et client n'avancent pas au
même rythme réel ; les compteurs d'instantanés n'y sont pas fiables.

**Recommandations (fichiers hors de ce chantier ; R2 à R9 faits ensuite, voir « Seconde passe »)**

| # | Où | Cause | Proposition | Gain attendu |
|---|---|---|---|---|
| R1 | `interact/mainframe.gd:257-266` | collision du socle du téléporteur = `CylinderMesh.create_convex_shape()` à 40 segments (88 points) ; GodotPhysics teste toutes les faces à chaque `move_and_slide` | convexe construit à la main : tronc de cône à 12-16 côtés circonscrit (jamais plus petit que le socle), ou sans l'anneau intermédiaire (80 points, même enveloppe exacte, gain faible) | `Player.move_and_slide` à côté du socle : 460-660 µs -> 12-23 µs mesurés en coupant la forme ; soit **0,45-0,65 ms par image** au départ de KINO (le socle est dans le hall), plus les zombies et chiens qui y passent. Seule forme convexe de plus de 24 points de KINO. À valider en jeu (bord incliné praticable) |
| R2 (fait) | `zombies/zombie.gd:745-752` (`_follow_floor`) | un `PhysicsRayQueryParameters3D.create` + un Dictionary par zombie et par pas | réutiliser un objet de requête par zombie (from / to mis à jour) : identique | 20-30 % de 0,25-0,38 ms |
| R3 (fait) | `zombie.gd:319-322`, `map/mesh_nav.gd:88-94` | `find_path` 116-152 µs sur KINO, ≈ 3,4 appels par image | `closest_point(to)` mis en cache par cible et par pas (identique) ; `NavigationServer3D.query_path` avec paramètres et résultat réutilisés ; mesurer le nombre de polygones du navmesh de KINO (`CELL_SIZE` 0,2) | 0,1-0,2 ms par image |
| R4 (fait) | `zombie.gd:398-419` (`_separation`) | `range()` et `get_parent() as ZombieManager` à chaque appel (11-15 µs) | boucles `for dz in 3`, `_mgr` déjà en cache : identique | ≈ 0,1 ms par image |
| R5 (fait) | `zombie.gd:542-589` (client) | instantanés en Array d'Array, `pop_front` | tampon circulaire (PackedFloat64Array / PackedVector3Array) : identique | 0,1 ms par image sur le client |
| R6 (en partie) | `dogs/hellhound.gd:110-121`, `205-221` | ligne de vue vers la cible à CHAQUE pas dès qu'elle est à portée de bond ; un rayon de sol par particule de flamme (26/s par chien, flammes qui montent) | cache comme `Zombie.LOS_PERIOD` ; sol calculé une fois par chien et par image (exposer `ParticlePool._emit_at`) | ≈ 0,1-0,2 ms par image en manche de chiens |
| R7 (fait) | `hud/hud.gd:238-320` | à chaque image : 2 `add_theme_color_override` (propagation du thème), textes reformatés (FPS, munitions, aide avec `Lang.t` + `Settings.action_label`), `_crosshair.queue_redraw()`, 3 paramètres de shader même vignette masquée | n'écrire que ce qui change (valeurs précédentes gardées) | 120-175 -> ≈ 40 µs |
| R8 (fait) | `interact/interaction_system.gd:60-85` (`_find_focus`) | `objects.values()` alloué et `is_visible_in_tree()` (remontée de l'arbre) AVANT le test de distance, pour tous les objets, à chaque pas | test de distance d'abord, tableau des objets gardé : même résultat | 100-150 -> 30-40 µs sur KINO |
| R9 (fait) | `weapons/weapon_controller.gd:316-340` (`_trace`), `view_model.gd:394-460` | une requête et un tableau d'exclusion par segment de pénétration ; `view_model.update` alloue deux Dictionary et écrit `vm_fov_scale` à chaque image (83-116 µs) | réutiliser la requête ; n'écrire le paramètre global que s'il change | 0,05-0,1 ms par image, 0,1-0,2 ms par tir |
| R10 | moteur physique (`project.godot`) | GodotPhysics3D : `move_and_slide` et convexes coûteux | essayer Jolt (intégré à Godot 4.7) sur une branche : change la réponse des collisions, à valider en jeu | à mesurer ; potentiellement le plus gros gain CPU restant |
| R11 (écarté) | `zombies/zombie_manager.gd:124-143`, `zombie_model.gd` | chaque apparition construit squelette + maillage (120-350 µs) et chaque mort libère le nœud | pool de zombies (réutiliser les nœuds morts) | supprime 0,1-0,35 ms par apparition en manche haute |

Écartés après mesure : tampon MultiMesh en un bloc pour les particules (même
coût sans rendu que 2 appels par instance), recalcul des lignes de vue du
`Spawner` seulement pour les points retenus (aucun gain mesurable : le test
d'orientation rejette déjà la plupart des points avant le rayon).

**Seconde passe (R2 à R9, 01/10/2026)** : un commit par point, jeu et image
identiques (mêmes chemins, mêmes décisions, mêmes pixels). Chaque fonction
réécrite est comparée à l'ancienne logique, recopiée comme référence, sur des
entrées tirées au hasard (`tests/test_perf_equivalence.gd`) ; le HUD a son
scénario (`tests/autotest/hud.gd`). Mesures : copie instrumentée avant /
après lancée l'une après l'autre (KINO, 28 zombies, µs par appel, horde puis
combat) et, pour R3 / R4, ancien et nouveau code dans le même processus
(`perf_cpu`, lignes « ancien code »).

| # | Changement | Avant -> après |
|---|---|---|
| R2 | `_follow_floor` : une requête de rayon par zombie, points mis à jour | 8,0 -> 7,7 µs (horde), 7,1 -> 7,3 (combat) : dans le bruit, le rayon lui-même domine |
| R3 | `MeshNav.find_path` : `closest_point(to)` en cache (`goal_point` : vidé à chaque pas physique, à chaque nouvelle itération de la carte, porte ou cuisson) ; `query_path` avec paramètres et résultat réutilisés (réglages de `map_get_path`, sans métadonnées) ; `world_line_clear` garde sa requête | 105 -> 86 µs (horde), 109 -> 96 (combat), ≈ 3,3 appels par image : 0,04-0,07 ms par image ; même processus, horde vers le joueur : 67 -> 41 µs. Navmesh de KINO : 958 polygones (DRAFT ARENA : 87) |
| R4 | `_separation` : `_mgr` gardé, clés des 9 cases déduites de celle du coin (`ZombieManager.GRID_ROW`) | 9,5 -> 7,8 µs (horde), 11,0 -> 9,9 (combat) ; même processus : 5,3 -> 4,1 µs ; 0,02-0,04 ms par image |
| R5 | instantanés des marionnettes en tampon circulaire (12, tableaux compacts) | paquet + pose : 2,9 -> 2,3 µs par zombie et par image (test, même processus), ≈ 0,02 ms par image sur un client à 28 zombies |
| R6 | en partie : `MeshMapLayout.ground` (sol des flammes, des particules isolées, des bonus) garde sa requête | `_emit_flames` 7,5 -> 7,1 / 10,1 -> 10,7 µs (bruit) ; `Hellhound._physics_process` 129-135 -> 111-118 µs par chien (grâce à R3 / R4) |
| R7 | HUD : n'écrit que ce qui change (FPS, munitions, réserve, 2 couleurs, aide ; réticule redessiné si son écart ou sa taille change ; vignette réglée seulement visible) | `Hud._process` 93 -> 49 µs (horde), 111 -> 61 (combat) |
| R8 | `_find_focus` : liste des objets gardée (ordre du Dictionary), distance avant la visibilité (`pick_focus`) | `local_tick` 75 -> 55 µs (horde), 79 -> 70 (combat) ; test, même processus, 59 objets : 27 -> 21 µs |
| R9 | `_trace` : une requête pour tous les segments et tirs ; `vm_fov_scale` / `vm_bend` écrits seulement s'ils changent | pas de gain au-dessus du bruit : `_trace` 125 -> 132 µs (effets de sang compris), `ViewModel.update` 71 -> 68 / 74 -> 83 µs (le coût restant est le calcul de la pose) |

Image complète, KINO combat, sans instrumentation (machine partagée, trois
passes chacun, alternées) : avant 7,97 (machine chargée) / 5,11 / 5,86 ms,
après 4,60 / 5,04 / 4,41 ms ; la somme des gains mesurés fonction par
fonction est de 0,2 à 0,3 ms par image : sous le seuil perceptible, pas de
note aux joueurs.

Non faits, volontairement :
- R6, cache de la ligne de vue du bond des chiens : un bond pourrait partir
  jusqu'à une période plus tard (décision d'IA différente) ;
- R6, un sol par chien et par image pour ses flammes : le rayon part 0,8 m
  au-dessus de chaque particule ; près d'une caisse ou d'une marche, une
  flamme retomberait sur un autre sol qu'aujourd'hui (image différente) ;
- R9, les deux Dictionary de `ViewModel.update` : gain non mesurable ;
- R11, pool de zombies : pas prouvable sans changement. Le coût vient de
  `ZombieModel.build(variant)` et chaque apparition tire une nouvelle
  variante (tenue, proportions, inclinaison de tête, phase de marche) :
  réutiliser le nœud sans reconstruire le modèle changerait l'apparence des
  hordes, le reconstruire garde le coût. S'y ajoutent l'état à remettre à
  zéro sur deux classes (une cinquantaine de champs, tête réduite, membres
  arrachés, dissolution, hitboxes désactivées en différé, `ZombieFling`
  ajouté), les minuteries déjà lancées qui visent le nœud (morsure des
  chiens 0,22 s après le bond, `despawn` lié à l'id) et le tirage aléatoire
  global fait à la construction (`_groan_t`) ; enfin un nœud réutilisé
  paraîtrait « encore valide » aux références gardées ailleurs (zombie qui
  enjambe une fenêtre, cible de Deadeye, annonces des personnages). À reprendre avec un modèle
  ré-habillable en place (`zombie_model.gd`) et des références par id ;
- R1 et R10 : hors de ce chantier (collision à valider en jeu).
