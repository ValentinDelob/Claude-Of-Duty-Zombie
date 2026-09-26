# Architecture — Call of Claude Zombie

Moteur : **Godot 4.7** (GDScript, rendu Forward+). Cible : GTX 1050 à 60 FPS en 1080p.

## Principe réseau (dès le premier commit)

- Modèle **Host / Client** sur ENet. Le **serveur (peer 1) fait autorité** sur tout ce qui
  est critique : dégâts, santé et mort des zombies, points, achats, portes, manches,
  spawns, Power, machines.
- Le **solo** utilise `OfflineMultiplayerPeer` : le joueur local *est* le serveur.
  Aucune ligne de gameplay n'est dupliquée entre solo et multijoueur.
- Conventions RPC :
  - requête client → serveur : `@rpc("any_peer", "call_local")` + `rpc_id(1, ...)` —
    fonctionne aussi quand l'appelant est le serveur (solo / hôte) ;
  - diffusion serveur → tous : `@rpc("authority", "call_local")` + `rpc(...)`.
- Le client n'envoie que des **intentions** (tirer, acheter, interagir) et sa position ;
  le serveur valide tout (distance, points, cadence, munitions...).

## Protocole réseau (messages fréquents)

Encodage binaire dans `NetCodec` (`scripts/game/net_codec.gd`, fonctions pures testées
dans `tests/test_zombie_net.gd`). ENet compresse chaque datagramme (codeur de plage).

- **Zombies** (`ZombieManager`, 15 Hz, `unreliable_ordered`) : état quantifié par zombie
  `[x, z, y]` au cm (u16), lacet (u8, 256 pas), code d'animation (u8 : état | vitesse).
  Instantané delta : `u16 n` puis par entrée `u16 id, u8 masque` et les seuls champs du
  masque. Un zombie inchangé n'est pas envoyé. Le serveur garde le dernier état envoyé
  (`net_q`) ; chaque entrée contient les champs modifiés depuis l'envoi précédent **et**
  ceux modifiés à l'envoi d'avant (redondance : une perte isolée ne laisse aucun champ
  périmé). État complet : les 3 premiers envois après l'apparition (le message
  d'apparition, fiable, peut arriver après un delta) et, pour chaque zombie, un instantané
  sur 15 (1 s, décalé par id pour lisser le débit). Le client garde le dernier état reçu
  et ajoute à chaque instantané un échantillon à **tous** les zombies vivants (même
  inchangés) : l'interpolation (120 ms de retard, horloge en µs) avance au même rythme.
  L'état initial de chaque zombie vient du message d'apparition.
- **Joueurs** (`Player._send_state`, 20 Hz max, `unreliable_ordered`) : 17 octets (x, y, z
  en f32, lacet u16, tangage u16, drapeaux u8), envoyés seulement si ces octets changent,
  avec un maintien toutes les 1 s. À la réception après un silence, l'interpolation
  repart du dernier état tenu jusqu'à un intervalle avant le nouveau message.
- **Effets de combat** (`Combat._flush_fx`, `unreliable_ordered`) : tirs (tireur, arme,
  origine, impacts avec normale sur 3 x i8, taches de sang) et touches non mortelles d'une
  image regroupés en un seul message par image, au lieu d'un RPC fiable par tir et par
  touche. Purement visuel et sonore : la mort, les points et la santé restent fiables.

Mesures (`sh tools/mp_test.sh netload`, boucle locale, 1 client, 24 zombies en poursuite,
les deux joueurs en mouvement, client en rafale au pistolet-mitrailleur ≈ 9 tirs/s ;
Ko = 1024 octets, en-têtes ENet compris, après compression) :

| Flux (par client) | Avant | Après |
|---|---|---|
| Descendant, sans tirs | 3,9 Ko/s, 37-39 paquets/s | 1,7-2,1 Ko/s, 21-31 paquets/s |
| Descendant, en rafale | 4,2-4,7 Ko/s, 56-64 paquets/s | 1,8-2,3 Ko/s, 37-51 paquets/s |
| Montant, sans tirs | 0,9 Ko/s | 0,3-0,4 Ko/s |
| Montant, en rafale | 1,6-1,7 Ko/s | 1,1-1,2 Ko/s |
| Instantanés de zombies avant compression | 3,5 Ko/s (242 o x 15 Hz) | 0,9-1,2 Ko/s |

Objectif < 10 Ko/s par client vérifié par le test. Fluidité des marionnettes (mesurée
après l'interpolation de chaque image) identique à l'ancien protocole : moins de 1 %
d'images avec un gel ou un saut, zombies à 1-2 m/s de moyenne.
`Net.sample_bandwidth()` donne les octets / paquets ENet de la machine depuis l'appel
précédent.

## Autoloads

| Nom | Rôle |
|-----|------|
| `GameState` | Machine à états unique de la session (`MAIN_MENU`, `LOBBY`, `CONNECTING`, `LOADING`, `PLAYING`, `ROUND_END`, `PLAYER_DOWN`, `GAME_OVER`, `DISCONNECTING`) avec transitions validées. |
| `Settings` | Options persistantes (`user://settings.cfg`) et actions d'entrée. |
| `Net` | Host / Join / Solo, poignée de main (version, serveur plein, partie lancée), registre des joueurs, erreurs de connexion lisibles. |
| `Autotest` | Scénarios de test automatisés dans le vrai jeu (`-- --autotest=<nom>`), mesures de perf, captures d'écran. |

## Rendu et performances

- Référence : RTX A2000 portable ≈ 2,2x une GTX 1050 ; 150 fps ici en 1080p ≈ 60 fps
  sur la cible. Mesures : `sh tools/perf.sh` (un jeu à la fois) ;
  `QUALITY=low sh tools/perf.sh` ou `-- --quality=low|medium|high` impose un préréglage.
  Attention : si d'autres jeux tournent en même temps (check.sh, autres agents), les
  chiffres chutent de 30 à 50 % ; ne comparer que des mesures faites GPU libre.
- **`RenderQuality`** (`scripts/game/render_quality.gd`) est le SEUL endroit qui
  définit les préréglages `Settings.quality`. Créé par `WorldLook.setup_environment`,
  il s'applique au chargement puis à chaque `Settings.changed` (uniquement si la
  qualité a changé). Lampes (groupe `map_lamps`), décalques (`quality_decals`),
  environnement, viewport, `ParticlePool.density` ; tout nœud du groupe
  `render_quality` reçoit `apply_quality(preset)` (ex. `Fx`).

| Réglage | LOW | MEDIUM (défaut) | HIGH |
|---|---|---|---|
| Lampes à ombre (sur 24) | 0 | 8 (1 sur 3) | 16 (2 sur 3) |
| Atlas d'ombres / filtre | 1024 / dur | 4096 / doux bas | 4096 / doux moyen |
| Fondu lumière / ombre | 20 m / 12 m | 28 m / 16 m | 34 m / 22 m |
| Glow | coupé | oui (suréchantillonnage linéaire) | oui (bicubique) |
| SSAO / MSAA | non / non | non / non | léger / 2x |
| Résolution 3D | 85 % (bilinéaire) | 100 % | 100 % |
| Décalques / particules | 50 % / 50 % | 100 % | 100 % |

- Coûts GPU mesurés (salle de garde, 24 zombies, A2000, ~3,5 ms par image) : glow
  ≈ 1,0 ms (poste n° 1), résolution 3D 85 % ≈ −1,0 ms, ombres des 8 lampes
  ≈ 0,5 ms (redessinées à chaque mouvement de zombie, 6 faces de cubemap), 16 lampes
  ≈ +1,4 ms, SSAO ≈ +0,7 ms, MSAA 2x ≈ +0,5 ms, brouillard et ajustements < 0,1 ms.
- Optimisations sans perte visible : géométrie et décor fusionnés par matériau ET par
  tuile de 16x16 cellules (`MapBuilder.CHUNK`) — les passes d'ombre ne redessinent plus
  toute la carte ; sols et plafonds sans ombre portée ; petits détails (lattes, cerclages,
  pieds de lit, fioles, brides et petits tuyaux) sans ombre portée ; glow en
  suréchantillonnage linéaire en MEDIUM ; décalques avec fondu à distance.
- Mesures `tools/perf.sh` (GPU libre, moyenne fps, 1080p) :

| Vue | Avant | LOW | MEDIUM | HIGH |
|---|---|---|---|---|
| garde | 213–239 | 358 | 214 | 132* |
| dortoir | 191–211 | 344 | 188 | 155* |
| couloir | 187–211 | 318 | 182 | 163* |
| labo | 218–249 | 364 | 273 | 169* |
| générateur | 190–217 | 344 | 237 | 151* |
| quai | 216–249 | 328 | 266 | 190* |
| rituel | 195–223 | 363 | 240 | 132* |
| 24 zombies (arène) | 166–205 | 316 | 203–217 | 130 |

  (*) mesures HIGH prises avec un peu de concurrence GPU. HIGH vise des cartes plus
  puissantes (GTX 1060 et plus).

## Cartes

- Une carte = un script `MapDef` (`scripts/game/map/maps/*.gd`) : grille ASCII
  (marqueurs documentés dans `map_def.gd`) + options. Enregistrement :
  `Game.MAP_SCRIPTS` ; cartes proposées dans les menus : `Game.MENU_MAPS`.
  Choix : écran `map_select` (SOLO), ligne CARTE du salon (hôte, annoncée aux
  clients par `Net.set_lobby_map`), mémorisé dans `Settings.last_map` ;
  `--map=<id>` en ligne de commande l'emporte (tests).
- Options utiles (KINO) : `zone_heights` (salles hautes ; portes et fenêtres
  restent à 3,2 m, linteaux automatiques), `open_links` (zones ouvertes sans
  porte : leurs apparitions s'activent ensemble), `box_starts` (départ
  aléatoire de la boîte), `teleporter_link` (plateforme + poste central A à
  relier avant chaque voyage), `pap_revealed_by_teleporter` (Pack-a-Punch
  caché jusqu'au premier voyage), `stage_zone`, `balcony_zone`, `look`
  (ambiance), `music`. Plusieurs pièges : chaque levier H commande le bloc de
  cases E le plus proche.
- Décor de théâtre (PropBuilder + `TheaterLook`) : fauteuils fusionnés par
  matériau (une collision par rangée + barrière joueurs/zombies que les balles
  traversent), rideaux, écran animé et faisceau du projecteur (liés au
  courant par `PowerGrid.add_hook`), lustres et appliques (lampes de la carte).

## Tests

- `sh tools/check.sh` : import, tests unitaires, test réseau multi-processus, lancement
  réel du jeu + scénario. **Doit passer avant chaque commit.**
- Tests unitaires : `tests/test_*.gd` (runner : `res://tests/test_runner.tscn`).
- Scénarios en jeu : `tests/autotest/*.gd`.

## Chiens de l'enfer (`scripts/game/dogs/`)

- `Hellhound` étend `Zombie` : c'est un **type d'entité** du `ZombieManager`
  (`spawn(..., kind = KIND_DOG)`, argument `kind` de `_cl_spawn`). Même canal
  réseau (apparition fiable, instantanés, mort), mêmes dégâts, points, pièges et
  nuke ; aucun bonus aléatoire (seul le dernier chien lâche MUNITIONS MAX).
- `DogRound` (`/root/Game/Rounds/Dogs`) : planification BO1 (manche 5 à 7 puis
  +4/+5, coupée en autotest sauf `debug_force_next`), apparitions par la foudre
  près du joueur le moins chassé, ambiance (brouillard `WorldLook`, musique,
  compteur qui clignote). Règles pures : `DogRules`.

## Grenades et SINGE-TAMBOUR (`scripts/game/throwables/`)

- `ThrowableSystem` (`/root/Game/Throwables`) : le client annonce le
  dégoupillage (`srv_cook`, réserve décomptée) puis le lancer (`srv_throw`).
  Le serveur crée l'objet (`Throwable` : trajectoire balistique, rebonds par
  lancers de rayons sur le décor et les zombies, roulement), gère la mèche de
  4 s (grenade cuite trop longtemps : explosion dans la main), l'arrêt du singe
  et l'explosion (`Combat.explosion` : dégâts de zone décroissants, pas à
  travers les murs, dégâts réduits au seul lanceur, kills à 50 points).
  `_cl_spawn` diffuse position et vitesse initiales : chaque client simule la
  même trajectoire ; le lanceur l'affiche dès le lâcher (objet prédit rattaché
  ensuite au numéro du serveur). Règles pures : `ThrowableRules`.
- Réserve dans `PlayerData` (`grenades`, `monkeys`, `has_monkeys`), répliquée
  avec les statistiques : +2 grenades à chaque manche (4 au plus), achat mural
  `GrenadeBuy` (marqueur `*`, 250), MUNITIONS MAX (grenades à 4, singes à 3).
- Singe posé : `ThrowableSystem.lure_for(zombie)` renvoie sa position, que
  `Zombie._chase` suit à la place des joueurs pendant 8 s (les chiens
  l'ignorent). Entrées : actions `grenade` [G] et `tactical` [Q] ; geste à la
  première personne : `ThrowController` / `ThrowView` (arme baissée par
  `ViewModel.lowered`).

## Tir, visée et recul (`scripts/game/weapons/`)

- **Une seule vérité** : les balles sont des rayons partis de la caméra
  (`WeaponController._fire`, centre du réticule) ; elles touchent exactement ce
  que montre le réticule ou la ligne de mire. Traçante, flamme, fumée, lumière
  partent ensuite de la bouche réelle du modèle (`ViewModel.muzzle_global`) et
  convergent vers les points d'impact réels. Chez les coéquipiers
  (`Combat._cl_shot_fx`), les effets partent de la bouche de l'arme du soldat.
- **Visée** : chaque modèle (`WeaponModels`) a un cran / œilleton (`sight`) et
  un guidon (`front`) à la même hauteur ; `ViewModel.ads_pose` pose cette ligne
  sur l'axe de la caméra (`ads`.z : distance de l'œil). Précision totale en
  visée (sauf fusils à pompe), champ `ads_zoom`, durée `ads_time`. Vérifié par
  `tests/autotest/weapon_aim.gd` (±2 px, impact à ±3 cm à 20 m pour chaque arme).
- **Lunettes** : `scope` = `sniper` (L96A1, Dragunov : écran de lunette
  `ScopeOverlay` + `scope.gdshader`, zoom `scope_fov`, balancement, [Maj]
  pour retenir sa respiration) ou `optic` (AUG, G11 : lunette courte).
- **Sensation** (`ShotFeel`, client seul) : dispersion dynamique (déplacement,
  bloom ; le réticule du HUD dessine le vrai cône via `WeaponDB.spread_to_px`),
  recul appliqué progressivement (~0,1 s) avec retour partiel automatique
  (`recoil_recover`), multiplicateurs d'atouts (`hip_spread_mult`,
  `recoil_mult`). Crochets dans `Player` : champ de vision
  (`camera_fov`), sensibilité (`ads_look_mult`), décalage de visée
  (`aim_offset`).
- **Effets** (`Fx`) : traçantes en vol (pool), flammes par famille (`flash`),
  douilles éjectées (pool, rebonds, tintement), impacts selon la surface
  (`Fx.surface_of` : méta `surface` des formes du décor, type d'objet).

## Arme merveille TONNERRE-7 (`scripts/game/weapons/thunder_blast.gd`)

- Façon Thundergun de Kino : 2 coups, réserve 12 (OURAGAN-77 amélioré : 4 / 24),
  rare dans la boîte et **unique** dans la partie (`WeaponDB.is_unique`,
  `MysteryBox.wonders_taken` : en main d'un joueur ou dans le Pack-a-Punch).
- Le client n'envoie que l'intention de tir (`srv_fire` sans touches). Le
  serveur (`ThunderBlast.server_blast`) sélectionne les zombies du cône
  (20 m, 60°, règles pures testées), en vue du tireur (pas à travers les
  murs), et les tue tous d'un coup (`Combat.damage_zombie(..., fling)`, 50
  points). `ZombieManager.kill_flung` diffuse un RPC fiable de mort projetée
  avec la vitesse initiale : chaque machine joue le même vol procédural
  (`ZombieFling`, enfant du zombie mort : parabole, culbute, ricochets,
  rebonds, pose allongée). Aucun dégât aux joueurs.
- Effet visuel (toutes les machines) : cône de distorsion d'air (texture
  d'écran), anneaux de choc, poussière, lumière ; son `thunder_fire`.
## Démembrement et rampants (`ZombieGibs`, `GibPool`)

- `Combat.damage_zombie` appelle `ZombieManager.srv_gib` après le retrait des PV
  et avant la mort : le serveur choisit les membres arrachés (`ZombieGibs.decide`,
  règles de `zombie_should_gib` de BO1 : coup >= 10 % des PV restants, balles
  hors pistolets ou explosions ; membre touché par `limb_at` sur le squelette
  du serveur) et les diffuse par `_cl_gib` (fiable, avant `_cl_die`).
- Masque `Zombie.gibs` (bras gauche / droit, jambes). Un zombie qui survit à la
  perte de ses jambes devient RAMPANT (`Zombie.crawl_t >= 0`) : 0,75 m/s après
  sa chute, pose couchée (`ZombieGibs.crawl_pose`), capsule et hitboxes
  couchées sur toutes les machines. La tête éclate sur un tir à la tête mortel.
- Morceaux au sol : `Fx.gibs` (`GibPool`), 24 nœuds recyclés, meshes non skinnés
  (`ZombieModel.limb_mesh`) construits 3 par image au plus, 6 s au sol.

## Bonus FAUCHEUSE et LIQUIDATION

- FAUCHEUSE (DEATH MACHINE de BO1, `PowerupRules.DEATH_MACHINE`) : le joueur qui
  la ramasse tient 30 s le minigun `death_machine` (`WeaponDB.POWERUP_WEAPONS` :
  hors arsenal, munitions illimitées, jamais de rechargement). L'arme est posée
  PAR-DESSUS l'inventaire (`PlayerData.powerup_weapon`, répliquée avec
  l'inventaire) : `current_weapon()` la renvoie tant que le joueur est debout,
  le client n'a qu'elle en main (pas de changement d'arme). Minuteur par joueur
  `PowerupSystem.death_machine` (icône du HUD pour son seul porteur) ; perdue à
  terre ; armes au mur, boîte et Pack-a-Punch indisponibles pendant le bonus
  (`InteractionSystem.weapon_locked`).
- LIQUIDATION : `MysteryBox.set_fire_sale` crée sur toutes les machines une
  boîte temporaire (`box_fs_<i>`, 10 points, jamais de crâne) à chaque autre
  emplacement de la carte ; à la fin, les boîtes libres disparaissent, celle
  en cours de tirage à son retour à l'état IDLE (état diffusé par le serveur).
