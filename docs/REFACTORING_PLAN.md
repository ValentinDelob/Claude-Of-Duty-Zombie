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

## 4. Réalisé

(rempli au fil des étapes : ce qui a changé et pourquoi)
