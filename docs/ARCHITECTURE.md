# Architecture — Claude of Duty Zombie

Moteur : **Godot 4.7** (GDScript, rendu Forward+). Cible : GTX 1050 à 60 FPS en 1080p.

## Principe réseau (dès le premier commit)

- Modèle **Host / Client** sur ENet. Le **serveur (peer 1) fait autorité** sur tout ce qui
  est critique : dégâts, santé et mort des zombies, points, achats, portes, manches,
  spawns, Power, machines.
- Le **solo** utilise `OfflineMultiplayerPeer` : le joueur local *est* le serveur.
  Aucune ligne de gameplay n'est dupliquée entre solo et multijoueur.
- Conventions RPC :
  - requête client → serveur : `@rpc("any_peer", "call_local")` + `rpc_id(1, ...)` —
    fonctionne aussi quand l'appelant est le serveur (solo / hôte). Côté serveur,
    le RPC commence par le prologue commun `NetGuard.server_sender` /
    `known_sender` / `alive_sender` (serveur, expéditeur, joueur connu ou
    vivant, limiteur) ;
  - diffusion serveur → tous : `@rpc("authority", "call_local")` + `rpc(...)`.
- Le client n'envoie que des **intentions** (tirer, acheter, interagir) et sa position ;
  le serveur valide tout (distance, points, cadence, munitions...). Règles
  détaillées (arguments bornés par `NetGuard`, cadence, positions plausibles) :
  `docs/SECURITY.md`.
- Durcissement de `Net` : décodage d'objets désactivé (`allow_object_decoding`),
  un pair qui ne se présente pas (`_srv_hello`) en 5 s est coupé, un second
  bonjour est ignoré, `_srv_loaded` d'un inconnu ignoré, noms de joueurs sans
  caractère de contrôle ni contrôle bidirectionnel (`_clean_name`) ; côté
  client, registre des joueurs borné (`clean_players` : 8 entrées, clés
  entières, places 0 à 7), nombre de places borné, distribution des
  personnages bornée (`CharacterDB.clean_cast`) et choix de personnage d'un
  invité ramené à « auto » s'il est inconnu (`CharacterDB.clean_choice`),
  identifiants de carte bornés (`CustomMapGuard.game_map_id_ok`) et
  carte chargée seulement si elle est connue (`Net.can_load_map`). Au
  chargement, atouts et armes murales vérifiés dans `PerkDB` / `WeaponDB` /
  `KnifeDB`, dossier et noms des modèles de `MeshMapBuilder` filtrés
  (`res://assets/models/` seulement, noms `[A-Za-z0-9_-]`). Tests :
  `tests/test_net_hardening.gd`.

## Protocole réseau (messages fréquents)

Encodage binaire dans `NetCodec` (`scripts/game/net_codec.gd`, fonctions pures testées
dans `tests/test_zombie_net.gd`). ENet compresse chaque datagramme (codeur de plage).

- **Zombies** (`ZombieManager`, 15 Hz, `unreliable_ordered`) : état quantifié par zombie
  `[x, z, y]` au cm signé (32 bits, entier variable « zigzag » : 1 à 5 octets, 2 pour
  une carte ordinaire, aucune borne de carte ni d'altitude ; protocole 6), lacet (u8, 256 pas), code d'animation (u8 : état | vitesse
  | bit 5 `Zombie.FRENZY_BIT` : pause « de folie » à la fenêtre).
  Instantané delta : `u16 n` puis par entrée `u16 id, u8 masque` et les seuls champs du
  masque. Un zombie inchangé n'est pas envoyé. Le serveur garde le dernier état envoyé
  (`net_q`) ; chaque entrée contient les champs modifiés depuis l'envoi précédent **et**
  ceux modifiés à l'envoi d'avant (redondance : une perte isolée ne laisse aucun champ
  périmé). État complet : les 3 premiers envois après l'apparition (le message
  d'apparition, fiable, peut arriver après un delta) et, pour chaque zombie, un instantané
  sur 15 (1 s, décalé par id pour lisser le débit). Le client garde le dernier état reçu
  et ajoute à chaque instantané un échantillon à **tous** les zombies vivants (même
  inchangés) : l'interpolation (120 ms de retard, horloge en µs) avance au même rythme.
  Chaque marionnette garde ses 12 derniers échantillons dans un tampon circulaire
  (`Zombie.push_snapshot` / `interpolate_at`, tableaux compacts, aucune allocation).
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

## Cartes perso en multijoueur (`MapShare`, protocole v4)

L'hôte peut choisir dans le salon une carte perso de l'éditeur ; elle est
envoyée aux invités (`scripts/game/map/map_share.gd`, nœud `/root/Net/MapShare`,
réception par `MapTransfer`, contrôle par `CustomMapGuard` ; détail des
contrôles et des limites : `docs/MAP_AUTHORING.md`, « Cartes perso en
multijoueur »).

1. `Net.set_lobby_map("perso:<id>")` (hôte) : carte relue en sûreté, contrôlée
   (légitimité + validateur), mise en **paquet canonique** (les cinq JSON
   réécrits par l'éditeur, JSON trié, UTF-8) identifié par son **SHA-256**,
   copiée dans le cache de l'hôte `user://maps_cache/<sha>/`. Diffusion
   `MapShare._cl_offer({sha, size, chunk, chunks, nom, n})` (n : numéro de
   l'annonce) puis
   `Net._cl_lobby_map("partage:<sha>")`. Un nouvel arrivant reçoit les deux à
   la fin de `_srv_hello`. Carte officielle : `_cl_offer({})`.
2. Client : annonce vérifiée (types, empreinte hexadécimale, taille ≤ 1 Gio
   (`CustomMapGuard.MAX_TRANSFER_BYTES`, borne technique : aucun quota de
   modèles ; le paquet d'une carte sans prefab reste à 2 Mo au plus, celui
   d'une carte avec des prefabs de la carte, format 2, porte leurs fichiers,
   modèles en base64), mémoire libre suffisante pour la recevoir et la
   contrôler (`CustomMapGuard.memory_ok`, sinon refus « memoire »),
   morceaux de 1 à 16 Ko, `chunks == ceil(size / chunk)`, nom sans balise).
   Hash déjà en cache et revérifié → `_srv_status(sha, "prete")` sans
   téléchargement ; sinon `_srv_request(sha)`.
3. Hôte : envoi `_cl_chunk(sha, n, index, octets)` sur le **canal fiable dédié 2**
   (morceaux d'une annonce précédente ignorés),
   au plus 8 morceaux non acquittés et 4 par image (le reste du jeu et du salon
   n'attend pas) ; le client acquitte chaque morceau (`_srv_ack(sha, reçus)`,
   progression diffusée).
4. Client (`MapTransfer`) : morceaux strictement dans l'ordre, jamais en double,
   chacun de la taille attendue, jamais au-delà de la taille annoncée ; à la
   fin : nombre de morceaux, taille totale, SHA-256, paquet canonique, légitimité,
   jouabilité → cache `user://maps_cache/<sha>/` puis `_srv_status(sha,
   "prete")`. Tout échec → `_srv_status(sha, "refusee", code)` (codes de
   `CustomMapGuard.REASONS`, textes FR/EN locaux), message dans le salon, la
   carte n'est jamais chargée.
5. Hôte : état de chacun (`attente`, `telechargement` + %, `prete`, `refusee`)
   diffusé par `_cl_states` (10 Hz au plus). `Net.start_match("partage:<sha>")`
   n'envoie `_cl_load_game` que si **tous** les joueurs sont « prete » pour ce
   hash (`MapShare.can_start`, bouton DÉMARRER grisé avec la raison sinon) ;
   un joueur qui part est retiré des états (il ne bloque pas les autres).
   `_cl_load_game` d'une carte partagée absente du cache : le client quitte
   proprement au lieu de charger autre chose. Tout le monde, hôte compris,
   joue depuis le cache (`EditorMapDef.shared`, empreinte recalculée) : mêmes
   octets, même géométrie, mêmes chemins de nœuds.

Sécurité : aucun RPC ne permet à un client d'envoyer une carte ; les `_srv_*`
exigent un expéditeur connu (jamais l'hôte lui-même) et le hash annoncé,
bornent les acquittements, limitent les demandes (3 par carte) et le débit
(seau de 240 messages, 120 par seconde, par client) ; les `_cl_*` exigent
l'expéditeur 1 et vérifient chaque type reçu. Aucune ressource Godot n'est
jamais chargée depuis le réseau ou une archive (données JSON seulement ; les
modèles .glb des prefabs de la carte, format 10, sont vérifiés octet par
octet puis lus par `GLTFDocument`, jamais par `load()` : docs/MAP_OBJECTS.md § 11).

## Fin de partie multijoueur : le groupe reste ensemble (`LobbyReturn`, protocole v5)

Comme dans BO1, une partie multijoueur terminée ne dissout pas le groupe :
tout le monde revient au **salon**, toujours connecté, prêt à relancer
(`scripts/game/lobby_return.gd`, nœud `/root/Net/LobbyReturn`). Seul un départ
volontaire (QUITTER au salon, Quitter du menu pause) ou une vraie coupure
déconnecte.

1. GAME OVER (`Game._cl_game_over`) : chacun affiche l'écran de fin et garde
   son résumé (`Router.lobby_message` : manche et zombies abattus, dans sa
   langue). Après `Game.GAME_OVER_DELAY`, **le serveur** ordonne le retour :
   `LobbyReturn.srv_return_all` note tous les joueurs « pas encore revenus »
   (`away`) puis diffuse `_cl_return`.
2. Chaque machine (`Router.back_to_lobby`) : état `GAME_OVER -> LOBBY`,
   `Net.end_match` (partie lancée, chargements, distribution des personnages
   et carte en cours oubliés ; session, joueurs, choix de personnage et carte
   du salon gardés), musique coupée, scène du menu. La scène de jeu est
   libérée en entier : points, manche, armes, atouts, zombies, bonus, portes
   et courant repartent de zéro au prochain chargement (les signaux branchés
   par la partie sur les autoloads partent avec ses nœuds).
3. Le menu (`MainMenu._ready`, état `LOBBY` et session en ligne) ouvre
   directement l'écran du salon (hôte ou invité), avec le résumé de la
   partie. L'hôte réannonce la carte du salon : carte perso reprise du cache
   de chaque invité (empreinte inchangée : aucun renvoi).
4. L'écran du salon dit au serveur qu'il est revenu
   (`report_in_lobby` -> `_srv_in_lobby`, ignoré hors retour ou d'un inconnu).
   Tant qu'un joueur n'est pas revenu, `Net.start_match` refuse et DÉMARRER est
   grisé (« Retour au salon de : … ») : un ordre de chargement ne croise jamais
   un retour en cours. Un joueur qui part pendant le retour n'est plus attendu.
5. `Net.match_started` repasse à faux : de nouveaux joueurs peuvent rejoindre
   le salon entre deux parties.

Départs :

- invité qui quitte (salon ou partie) : seul lui est déconnecté ; les autres
  continuent (`Net._on_peer_disconnected`, partie et retour au salon compris) ;
- hôte qui quitte avec des invités connectés (`Net.leave`) : avis
  `_cl_host_closing` envoyé et poussé tout de suite (`ENetConnection.flush`),
  connexion fermée `Net.HOST_CLOSING_DELAY` (0,3 s) plus tard ; chaque invité
  termine sa session (`Net.end_session`) et revient au menu avec « L'hôte a
  quitté la partie. » (perte réelle de l'hôte : « Connexion perdue avec
  l'hôte. ») ;
- solo : retour au menu principal comme avant ; TESTER à plusieurs de
  l'éditeur (`Router.return_scene`) : retour dans l'éditeur comme avant (la
  partie de test se referme, la session d'édition continue).

Tests : `tests/test_lobby_return.gd` (transitions, `end_match`, attente du
groupe, départs) et `sh tools/mp_test.sh rematch` (deux parties d'affilée
jusqu'au GAME OVER sur une carte perso partagée : retour au salon des deux
côtés, mêmes identifiants de pairs, état neuf, carte reprise du cache, ni
nœud orphelin ni connexion de signal en plus).

## Référence à la partie (`game`)

Chaque objet de la partie reçoit son `Game` de celui qui le crée, dans un champ
`game` :

- systèmes enfants directs de `Game` (`Combat`, `Interact`, `Throwables`,
  `Rounds`, `Zombies`...) : `game = get_parent()` dans `_ready` ;
- objets créés par un système : de leur créateur — `WeaponController.setup(p, game)`,
  `ThrowController.setup(...)`, `Spawner.new(game)`, `DogRound` via
  `RoundManager.game`, zombies et chiens via leur `ZombieManager.game` (lu dans
  `Zombie._ready`), et leurs aides (`ZombieGibs`, `ZombieFling`) via `z.game` ;
- `game` peut être nul pour un objet seul des tests unitaires (zombie ou
  gestionnaire hors partie) : le code qui le lit le vérifie
  (`Zombie._is_target_valid` refuse toute cible hors partie).

`Game.instance` est réservé au code sans propriétaire dans la partie
(autoloads, fonctions statiques, menus). Lisent encore `Game.instance`, tous
avec une garde : `Player`, `Fx`, `VoxSystem`, `DeadeyeAim`, `DogLightning`
(aussi créé hors partie par `Warmup`), `Barricade`, `Door`, `BoxBoard`.

## Autoloads

| Nom | Rôle |
|-----|------|
| `Packs` | Tout premier autoload : monte, dans `_init()`, les paquets de contenu passés par le lanceur (`-- --packs=<voix>.pck,…`, `docs/RELEASE.md`). Sans cet argument (éditeur, tests, exécutable complet) : ne fait rien. |
| `CrashGuard` | Marqueur « session en cours », écran courant, rapport et message au menu après un plantage (voir « Journaux et plantages »). |
| `GameClock` | Horloge de jeu : somme des pas de physique (`now()`, `msec()`). Tous les minuteurs de gameplay (cadence, rechargements, réanimation, mèches, répliques, téléporteur) la lisent : figés par la pause solo, insensibles aux images bloquées, accélérés dans les tests (`--fixed-fps`). L'interpolation réseau et les mesures de coût restent en temps réel (`Time`). |
| `GameState` | Machine à états unique de la session (`MAIN_MENU`, `LOBBY`, `CONNECTING`, `LOADING`, `PLAYING`, `ROUND_END`, `PLAYER_DOWN`, `GAME_OVER`, `DISCONNECTING`) avec transitions validées. |
| `Settings` | Options persistantes (`user://settings.cfg`), actions d'entrée et touches réaffectables (voir « Menus, options et touches »). |
| `Net` | Host / Join / Solo, poignée de main (version, serveur plein, partie lancée), registre des joueurs, erreurs de connexion lisibles, carte du salon et envoi des cartes perso (enfant `MapShare`), retour du groupe au salon après une partie (enfant `LobbyReturn`). |
| `Autotest` | Scénarios de test automatisés dans le vrai jeu (`-- --autotest=<nom>`), mesures de perf, captures d'écran. Savoir si l'on tourne sous autotest : `AutotestMode.is_running()` (classe statique qui lit la ligne de commande, valable avant le `_ready` des autoloads, donc dans `Settings` et les fonctions statiques ; `AutotestMode.scenario_name()` pour le scénario en cours d'une série) ; `Autotest.active` en est le reflet une fois l'autoload prêt. |

## Menus, options et touches

- **Hôtes d'écrans** : `MenuHost` (`scripts/ui/menu_host.gd`) est l'interface
  que voient les écrans `MenuScreen` (`show_screen`, `go_back`, `set_hint`,
  `current`). Deux hôtes : `MainMenu` (menu principal, fond 3D, transitions) et
  `PauseMenu` (`scripts/game/hud/pause_menu.gd`, enfant du HUD, toujours
  actif même arbre en pause).
- **Menu pause** : Échap (action `pause`, fixe) l'ouvre depuis le HUD
  (`GameState.is_in_game()` ; jamais pendant le chargement). REPRENDRE,
  OPTIONS, QUITTER LA PARTIE, QUITTER LE JEU. Solo : `get_tree().paused`
  (comme BO1). Multijoueur : la partie continue ; `Game.menu_open()` fait
  ignorer toutes les entrées du joueur local (`Player._local_physics` : ni
  déplacement, ni visée, ni tir ; souris libérée) et le changement de joueur
  suivi en spectateur. Une fois ouvert, le menu gère Échap / `ui_cancel`
  lui-même : retour des options, sinon reprise.
- **Options** : un seul écran, `scripts/ui/screens/options_screen.gd`, pour le
  menu principal et la partie (`PauseMenu.show_screen("options")` charge
  `MainMenu.SCREENS.options`, `args.in_game = true`). Onglets JEU, COMMANDES,
  GRAPHISMES, SON (◄ / ► sur les onglets, Page préc. / suiv. partout) ; page
  dans un `ScrollContainer` (`follow_focus`) avec voisins de focus explicites
  onglet <-> page <-> RETOUR. Sur la page COMMANDES, les jauges laissent la
  molette au défilement (`MenuOptionRow.wheel_nudges = false` ; lignes en
  `MOUSE_FILTER_PASS`). Chaque changement : `Settings.apply()` puis
  `save_settings()`.
- **Touches et manette** : deux commandes au plus par action et par colonne
  (`Settings.SLOTS_PER_COLUMN`). `Settings.bindings` = action -> liste de 0 à
  2 touches (`key:<physical_keycode>`, `mouse:<bouton>`, crans de molette
  compris : `mouse:4` à `mouse:7`) ; `Settings.pad_bindings` = action -> liste
  de boutons de manette (`joy:<JoyButton>`, `joyaxis:<JoyAxis>:<-1|1>` pour
  les gâchettes et le stick gauche ; événements `device = -1` : toutes
  manettes, branchement à chaud). Listes sans case vide au milieu (la
  deuxième remonte quand la première est effacée) ; défauts : une commande,
  deuxième case vide. Actions de `Settings.REBINDABLE` ; dispositions
  d'origine `DEFAULT_BINDINGS` / `MOUSE_BINDINGS` / `DEFAULT_PAD_BUTTONS` /
  `DEFAULT_PAD_AXES` (Xbox et PlayStation partagent la disposition standard
  SDL de Godot : une seule table). `binding(action, pad, slot)` lit une case,
  `bindings_of(action, pad)` la liste ; `bind(action, code, slot)` range le
  code dans la case `slot` de la colonne de son périphérique sans le retirer
  d'aucune autre action (une commande peut être partagée : l'InputMap la met
  sur chaque action, un appui les déclenche toutes ; retourne les autres
  actions qui l'ont, `shared_with(action, code)`, affichées dans l'aide et
  sous la case, « AUSSI : … ») et, s'il est déjà dans l'autre case de
  l'action, échange les deux cases. Touche partagée RECHARGER + INTERAGIR :
  devant un objet utilisable, `WeaponController.use_takes_press()` ne
  recharge pas (BO1 console) ; `clear_binding(action, pad, slot)`, `reset_bindings()` (les deux
  colonnes) ; `apply_bindings()` reconstruit l'InputMap (Échap et Start à
  `pause` ; zone morte `MOVE_DEADZONE` des déplacements). Molette :
  `wheel_switch_events()` lie haut / bas à `switch_weapon` sauf un cran
  affecté à une action (déjà présent s'il l'est à `switch_weapon`). Un cran
  arrive en appui + relâche dans la même image : `Input.is_action_just_pressed`
  (Godot 4.7, sans le comportement « legacy ») reste vrai à une seule image
  physique par cran, donc les fronts de `PlayerInput` (saut, couteau,
  recharge, interaction, changement d'arme, tir au coup par coup) partent une
  fois ; les actions maintenues passent par `PlayerInput.held()` (enfoncée OU
  appuyée à cette image) : sur la molette, un appui d'une image (grenade
  dégoupillée puis lancée, visée d'un instant). Guide et Start, le stick
  droit (la vue) ne se réaffectent pas. `settings.cfg` : `[bindings]` et
  `[pad_bindings]` en listes de deux codes au plus ; relecture filtrée par
  colonne (deux premières valeurs valides, sans doublon dans l'action, une
  commande partagée restant sur chaque action ; texte seul ou liste
  d'un code de la version précédente relus tels quels ; fichier sans
  `[pad_bindings]`, d'avant la manette : première touche seulement ; action
  absente : sa commande d'origine si aucune action du fichier ne l'a). Une
  version précédente relit la première valeur valide de chaque liste (et
  retire un partage de l'action la plus bas dans l'écran).
  Ligne `MenuBindRow` (`scripts/ui/bind_row.gd`, quatre cases `SLOT_KEY` /
  `SLOT_KEY2` / `SLOT_PAD` / `SLOT_PAD2`, `is_pad_slot()` / `slot_index()`,
  noms longs en police réduite `fit_size()`, ligne de titres `make_header()`)
  ; la saisie est faite par `OptionsScreen._input` : case touche = touche,
  bouton de souris ou cran de molette, Échap ou B annule ; case manette = bouton, gâchette ou stick gauche
  enfoncé à `CAPTURE_AXIS_THRESHOLD`, Échap ou Start annule. Menus à la
  manette : `_register_inputs` ajoute A / B / LB / RB à `ui_accept` /
  `ui_cancel` / `ui_page_up` / `ui_page_down` (absents des ui_* de Godot).
- **Noms et invites** : `Settings.code_label(code, style)` (disposition du
  clavier : la touche physique W s'affiche Z en AZERTY ; manette :
  `PadNames`, `scripts/ui/pad_names.gd`, noms Xbox ou PlayStation choisis par
  `PadNames.style_of(Input.get_joy_name())`, PS5 : « CREATE »). Dernier
  périphérique utilisé : `Settings.note_input` (via `Settings._input`, et par
  l'écran d'options pendant une saisie) -> `using_pad`, `pad_device`, signal
  `input_device_changed` ; une manette débranchée sans autre manette rend les
  invites au clavier. `Settings.action_label(action)` (pur :
  `prompt_label`) donne le premier bouton si la manette a servi en dernier, sinon la
  première touche ; les invites du HUD (`Hud.bo1_prompt(raw, key)`) sont recalculées
  quand ce nom change.
- **Manette en jeu** : `PlayerInput.read_devices(delta)` lit le déplacement en
  analogique (`get_action_raw_strength`, zone morte radiale
  `stick_deadzone`) et la vue au stick droit (`pad_look_step` : zone morte,
  courbe, `PAD_LOOK_SPEED` x `Settings.pad_look_sensitivity` x delta, donc
  indépendante des images par seconde) dans `look_pad` (radians) ;
  `Player._apply_look` y applique la sensibilité en visée et l'inversion de
  l'axe vertical, comme pour la souris. Sprint : au clavier, touche enfoncée ;
  à la manette, un clic (BO1) verrouille la course tant qu'on avance (seul
  un appui de la manette verrouille : `Settings.sprint_press_pad`) ; le
  verrou tombe à l'arrêt, en reculant, de côté, et dès que la course
  s'arrête. Jamais de reprise sans nouvel appui (`Player._sprint_spent`) :
  épuisement, souffle insuffisant au départ, visée (qui coupe le sprint),
  accroupi, à terre, pause, menu, perte de focus ou contrôle coupé
  (`_forget_sprint`) demandent de relâcher puis réappuyer. Tests :
  `test_sprint_input.gd`, scénario `sprint_restart`.
- **Graphismes** : `Settings.render_scale` (x la résolution 3D du préréglage,
  `RenderQuality.scale_3d`), `Settings.max_fps` (`Engine.max_fps` ; un
  `--max-fps` de la ligne de commande l'emporte), `Settings.brightness` (gamma
  de sortie ajouté à la table d'étalonnage de la carte : `WorldLook.map_lut`,
  dérivée de la table de base par une table de 256 valeurs, en cache).
  `RenderQuality` réapplique l'échelle et la luminosité seules quand elles
  changent (le préréglage complet seulement si la qualité change). Valeurs par
  défaut (100 %, illimitée, 100 %) = rendu d'avant ces options.
- **Langues** : `Lang.t(fr, en)` (`scripts/ui/lang.gd`) selon
  `Settings.language`. Traduits : écran d'options, menu pause, noms des
  touches ; le reste du jeu est en français. Changer la langue reconstruit
  l'écran d'options.
- **Personnages** (`CharacterDB`, docs/CHARACTERS.md) : sept personnages,
  `IDS` = callahan, orlov, arakawa, weissmann, mercer, berg, jojo ; l'index (0 à 6) choisit
  aussi la tenue FPS (`ViewHands.STYLES`) et l'apparence vue par les autres
  (`PlayerModel.OUTFITS`). Choix du joueur : `Settings.character` (section
  `[player]` de `settings.cfg`, « auto » par défaut, valeur inconnue -> « auto »),
  ligne PERSONNAGE de l'onglet JEU (noms courts `CharacterDB.short_name`, nom
  complet dans l'aide). Réseau : le client envoie son choix juste après le
  bonjour (`_srv_set_character`, RPC séparé trié après les autres : le bonjour
  et les numéros des RPC existants ne changent pas) puis à chaque changement
  (`Net.send_character` sur `Settings.changed`) ; l'hôte le
  garde dans `Net.players[pid].char`. Au lancement (`Net.start_match`), l'hôte
  calcule la distribution (`CharacterDB.resolve_cast`) : choix explicites
  respectés, doublons permis ; joueurs « auto » par emplacement croissant :
  personnage de (emplacement + rotation tirée, 0 en autotest), sinon le
  suivant libre, sinon celui de l'emplacement (plus de 5 joueurs). La
  distribution `{pid: index}` part avec `_cl_load_game` (`Net.cast`, bornée
  par `CharacterDB.clean_cast`) ; `CharacterDB.index_of(pid)` la lit, à
  défaut l'emplacement. Un changement en cours de partie vaut pour la
  suivante. Répliques : fichier `assets/voices/<id>.json` absent -> aucune
  réplique (personnage muet) ; taquineries (`VoxSystem.tease_categories`)
  seulement envers un coéquipier d'un autre personnage et si la catégorie
  existe. Tests : `tests/test_characters.gd`.

## Rendu et performances

- Référence : GTX 1070 de développement ≈ 3,5x une GTX 1050 (cible : 60 fps en
  1080p) ; il faut donc ~210 fps ici en 1080p (≈ 4,2 ms GPU + ~0,6 ms hors GPU)
  pour tenir 60 fps sur la cible. Mesures : `sh tools/perf.sh` (un jeu à la fois) ;
  `QUALITY=low sh tools/perf.sh` ou `-- --quality=low|medium|high` impose un
  préréglage. Chaque ligne `[perf]` donne aussi le temps GPU moyen du viewport
  (`GPU x ms`) : sur la machine partagée (autres agents, check.sh), les fps
  chutent de 30 à 70 % alors que le temps GPU ne bouge que de ~10 % ; comparer les
  temps GPU, ou les fps pris GPU libre seulement.
- **Coût de chaque poste** : `sh tools/perf.sh perf_costs` (préfixe `perf_` : exclu
  de check.sh). Deux vues (labo de BUNKER K-7 avec 24 zombies au contact, scène de
  KINO vue de l'allée centrale de la salle), chaque poste coupé seul, mesures
  appariées (référence juste avant),
  répétées 4 fois : temps GPU et CPU de rendu, draw calls. Les lignes « ~ » donnent
  le gain d'une variante moins chère ; `--ab-shots` capture chaque variante pour la
  comparaison visuelle.
- **`RenderQuality`** (`scripts/game/render_quality.gd`) est le SEUL endroit qui
  définit les préréglages `Settings.quality`. Créé par `WorldLook.setup_environment`,
  il s'applique au chargement puis à chaque `Settings.changed` (uniquement si la
  qualité a changé). Lampes (groupe `map_lamps`), décalques (`quality_decals`),
  environnement, viewport, `ParticlePool.density`, ombres des zombies
  (`ZombieShadows`) ; tout nœud du groupe `render_quality` reçoit
  `apply_quality(preset)` (ex. `Fx`).

| Réglage | LOW | MEDIUM (défaut) | HIGH |
|---|---|---|---|
| Lampes à ombre (sur 24) | 0 | 8 (1 sur 3) | 16 (2 sur 3) |
| Atlas d'ombres / filtre | 1024 / dur | 4096 / dur | 4096 / doux bas |
| Fondu lumière / ombre | 20 m / 12 m | 28 m / 16 m | 34 m / 22 m |
| Zombies à ombre portée | 0 | 6 plus proches, < 12 m | 12 plus proches, < 20 m |
| Glow | coupé | oui (suréchantillonnage linéaire) | oui (bicubique) |
| SSAO / MSAA | non / non | non / non | léger / 2x |
| Résolution 3D (x ÉCHELLE DE RENDU 3D des options) | 85 % (bilinéaire) | 100 % | 100 % |
| Décalques / particules | 50 % / 50 % | 100 % | 100 % |
| Brume volumétrique | non | 48x48x32 | 64x64x48 |
| Post-traitement (`FilmPost`) | multiplicatif (grain, vignette) | lecture d'écran + aberration | idem |

- **Direction artistique BO1** (voir `docs/ART_DIRECTION.md`) : étalonnage par table
  3D procédurale (`WorldLook.grade_lut`, surchargée par carte via `look.grade`),
  bloom large sur les sources, brume volumétrique fine, `FilmPost` (CanvasLayer 5,
  sous le HUD) pour le grain (option `Settings.film_grain`), le vignettage et
  l'aberration.

- Coûts GPU mesurés par `perf_costs` (GTX 1070, 1080p, MEDIUM), avant -> après la
  passe « perf: optimize rendering after the visual rework ». Toutes les mesures
  « KINO » de cette section ont été prises sur l'ANCIENNE KINO en grille ASCII,
  remplacée depuis par Kino der Toten à l'échelle 1 (carte ~6 fois plus
  grande) : à refaire avec `perf_costs` et `kino_tour` (étape 6 de
  docs/KINO_V2.md : occlusion, distances de visibilité) :

| Poste | labo + 24 zombies | scène de KINO |
|---|---|---|
| Image complète | 6,1-6,3 -> 5,3 ms | 5,4-5,6 -> 4,4 ms |
| Lampes (éclairage + ombres) | 2,6 -> 2,0 ms | 2,1 -> 1,7 ms |
| dont ombres des lampes | 0,9-1,1 -> 0,5 ms (143 -> 60 draw calls) | 0,5 -> 0,4 ms |
| Glow | 0,6-0,7 ms | 0,5-0,7 ms |
| Zombies (tout) / leurs ombres | 0,6-0,8 / 0,5-0,8 -> 0,7 / 0,3 ms | — |
| zombie.gdshader (vs matériau simple) | 0,3 -> 0,15 ms | — |
| surface.gdshader (vs couleur unie) | 0,2 ms | 0,5-0,8 -> 0,3 ms |
| Brume volumétrique | 0,4-0,45 -> 0,1-0,2 ms | 0,35 -> 0,1 ms |
| Arme FPS + mains | 0,3 ms | 0,2 ms |
| Post-traitement (lecture d'écran) | 0,1-0,2 ms | 0,1-0,2 ms |
| HUD (vignette de blessure comprise) | 0,3 -> 0,05 ms | 0,05-0,1 ms |
| Étalonnage (LUT), décalques, SSAO coupé | < 0,1 ms | < 0,1 ms |

  HIGH (labo + 24 zombies, 8,9 ms avant) : ombres de 16 lampes 2 ms (+241 à +420
  draw calls : 16 cubemaps de 6 faces, redessinées dès qu'un zombie bouge — c'est
  ce qui doublait les draw calls de HIGH), brume 96x96x64 1 ms, glow bicubique
  1 ms, SSAO 0,75-1 ms, filtre doux moyen 0,6-1,1 ms, MSAA 2x 0,6-0,7 ms.
  Pistes écartées (gain nul ou rendu changé) : ombres omni en double paraboloïde
  (déformation sur les grands murs), atlas 2048 (ombres floues, 0,1-0,2 ms),
  diffus Lambert (0 ms), portée de la brume, glow sans le niveau 6 ou 2 (0 ms),
  spéculaire des lampes à 0 (0 ms : seul `specular_disabled` du shader compte), portée
  des lampes x0,85 (-0,4 à -0,55 ms mais salles visiblement plus sombres).

- Optimisations (sans perte visible, captures avant/après comparées) :
  - **bruits précalculés** (`NoiseLattice`) : `surface.gdshader` et
    `zombie_body.gdshaderinc` lisent le bruit de valeur dans un treillis de
    nœuds aléatoires (64² en 2D, 32³ en 3D, R8) au point i + s(f) avec le filtrage
    linéaire du GPU : une lecture au lieu de 4 ou 8 hachages, même allure
    (répartition des taches et fissures identique, motifs déplacés) ;
  - **zombies vivants sans `discard`** : la dissolution a son propre shader
    (`zombie_dissolve.gdshader`, même include, `ZombieModel.set_dissolve`) ; les
    vivants gardent la pré-passe de profondeur et les passes d'ombre simples ;
  - **ombres des zombies limitées aux plus proches** (`ZombieShadows`, mis à jour
    toutes les 6 images avec hystérésis) : un zombie animé qui projette une ombre
    force le rendu complet des cubemaps des lampes proches ;
  - MEDIUM : filtre d'ombre dur (-0,3 à -0,4 ms) et brume 48x48x32 (-0,2 ms) ;
    HIGH : filtre doux bas et brume 64x64x48 (-1,1 à -1,3 ms au total) ;
  - HUD : vignette de blessure (plein écran, bruit) masquée en pleine santé ;
  - **murs mats sans spéculaire** (`WorldLook.MATTE_SURFACES`, variante de
    `surface.gdshader` en `specular_disabled`) : -0,1 à -0,15 ms. Sols et
    plafonds le gardent : sans le reflet rasant des lampes, ils s'assombrissent
    nettement (-0,3 ms de plus, écarté) ;
  - **CPU des zombies au contact** : 3 glissements au plus par `move_and_slide`
    (au lieu de 6 : -45 % sur le déplacement des zombies coincés dans la horde),
    grille de séparation qui garde les positions (au lieu de relire
    `global_position` de chaque voisin : -30 %), ligne de vue vers la cible
    mise en cache 0,1 s (`Zombie.LOS_PERIOD`) ;
  - déjà en place : géométrie et décor fusionnés par matériau ET par tuile de 16x16
    cellules (`MapBuilder.CHUNK`), sols, plafonds et petits détails sans ombre
    portée, décalques avec fondu à distance.

- Mesures `tools/perf.sh` (1080p, temps GPU moyen de la pire vue ; avant et après
  alternés dans la même session, machine partagée) :

| Préréglage | Vue | Avant | Après | fps GPU libre (estim.) | GTX 1050 (x3,5) |
|---|---|---|---|---|---|
| LOW | pire vue BUNKER / KINO | 2,84 / 2,70 ms | 2,60 / 2,44 ms | ~320 | ~110 fps |
| LOW | 24 zombies au contact | 2,80 ms | 2,48 ms | ~320 | ~110 fps |
| MEDIUM | pire vue BUNKER / KINO | 5,45 / 5,34 ms | 4,58 / 4,44 ms | ~195-200 (avant 158-166) | ~60 fps |
| MEDIUM | 24 zombies poursuite / contact | 5,95 / 6,14 ms | 4,96 / 5,02 ms | ~180 (CPU : IA) | ~55-57 fps |
| MEDIUM | menu | 2,87 ms | 2,57 ms | ~320 | — |
| HIGH | pire vue BUNKER / KINO | 7,81 / 8,42 ms | 6,87 / 7,24 ms | ~125 (avant 86-92) | ~40 fps |
| HIGH | 24 zombies contact (draw calls) | 8,37 ms (511) | 7,03 ms (296) | ~120 | ~35 fps |

  fps estimés = 1000 / (GPU + ~0,6 ms hors GPU mesurés GPU libre). MEDIUM tient donc
  ~60 fps sur une GTX 1050 dans les vues sans zombie et 55-57 fps dans la pire
  mêlée ; LOW garantit la cible. HIGH vise les GTX 1060 / 1070 et plus. Les seuils
  des autotests restent à 150 fps (avertissement seulement en exécution parallèle).

- Re-mesure GPU libre sur le portable RTX A2000 (28/09/2026, 1080p, `perf.sh`) :
  sur les mêmes vues, la carte fait ~1,25x une GTX 1070 (indice 4,4 dans
  `QualityProbe`) ; la cible « 60 fps sur GTX 1050 » y vaut ~3,4 ms de GPU
  (~250 fps). MEDIUM : pire vue BUNKER 3,64 -> 3,45 ms (226 -> 231-241 fps),
  pire vue KINO 3,51 -> 3,3 ms (232 -> 241-251 fps), 24 zombies au contact
  3,96 ms (207 fps ; physique 2,7 -> 2,3-2,8 ms par pas). LOW 384-393 fps,
  HIGH 147 fps. Postes restants (`perf_costs`) : lampes 1,1-1,5 ms (dont ombres
  0,2-0,5), glow 0,6 ms (retirer des niveaux ne change rien), post-traitement
  0,2 ms (sans lecture d'écran : -0,15 ms mais grain seulement sombre, écarté),
  animation des zombies 0,3 ms, bruit des zombies 0,15-0,25 ms.

- **Préréglage automatique** (`QualityProbe`, lancé par `Settings` au premier
  lancement : pas de clé `video/quality` dans `user://settings.cfg`, jamais en
  autotest, en headless ou avec `--quality=`) :
  1. indice de puissance d'après le nom de la carte
     (`RenderingServer.get_video_adapter_name`, table `QualityProbe.ADAPTERS`,
     GTX 1050 = 1) ; puces intégrées (`get_video_adapter_type`), Intel HD/UHD/Iris,
     APU Radeon Graphics / Vega, rendu logiciel -> LOW d'office ;
  2. mini-banc d'essai : 2 s de stabilisation puis 3 s de mesure du temps GPU du
     menu principal (MEDIUM imposé), ramené à 1080p au prorata des pixels et
     comparé à la GTX 1070 (`REF_MENU_MS` = 2,9 ms, `DEV_SCORE` = 3,5) ; abandonné
     si le joueur quitte le menu pendant la mesure ;
  3. indice mesuré prioritaire (sinon celui du modèle, sinon MEDIUM) :
     < 0,9 -> LOW, 0,9 à 2,6 -> MEDIUM, >= 2,6 -> HIGH ; appliqué, enregistré avec
     son compte rendu (`video/quality_auto`), jamais refait. OPTIONS > VIDÉO permet
     toujours de changer. Scénario : `render_perf` ; règles : `tests/test_quality_probe.gd`.

## Cartes

- Une carte = un script `MapDef` (`scripts/game/map/maps/*.gd`) : nom, texte
  d'accroche, noms des zones, musique, ambiance, prix, réglages, et sa
  géométrie. Deux sortes de cartes : **grille ASCII** (marqueurs documentés
  dans `map_def.gd`, `GridMapLayout` : BUNKER K-7, `test_arena`) et **maillage
  à plusieurs niveaux** (`create_layout` surchargé, `MeshMapLayout` : KINO,
  `test_levels`). Enregistrement : `Game.MAP_SCRIPTS` (`bunker_k7`, `kino`,
  `test_arena`, `test_levels`, `draft_arena`) ; cartes proposées dans les menus :
  `Game.MENU_MAPS` (`bunker_k7`, `kino`). Choix : écran `map_select` (SOLO,
  plan « dossier » dessiné par `MapPreview` depuis la grille ou depuis les
  contours des salles de la description en maillage), ligne CARTE du salon
  (hôte, annoncée aux clients par `Net.set_lobby_map`), mémorisé dans
  `Settings.last_map` ; `--map=<id>` en ligne de commande l'emporte (tests).
- Options utiles : `open_links` (zones ouvertes sans porte : leurs
  apparitions s'activent ensemble), `box_start` / `box_starts` (départ, fixe
  ou tiré au sort, de la boîte), `teleporter_link` (pad + poste central à
  relier avant chaque voyage) et `teleporter_*` (prix, charge, séjour,
  recharges, rayon de foudre au départ), `teleport_banner`, `look`
  (ambiance), `music` ; cartes grille : `zone_materials`, `pipe_zones`.
  Plusieurs pièges sur une grille : chaque levier H commande le bloc de cases
  E le plus proche ; sur une carte en maillage, chaque piège a son volume et
  ses deux leviers.
- **Éditeur de cartes** (`docs/MAP_AUTHORING.md`, `scripts/editor/`,
  `scenes/editor/map_editor.tscn`, menu principal > ÉDITEUR DE CARTES) : la
  façon recommandée de concevoir une nouvelle carte. Vue de dessus (grille de
  1 m), pièces rectangles ou polygones dont les murs sont générés (bord commun
  = un seul mur), inventaire façon Minecraft tiré des bases du jeu
  (`MapCatalog`), règles de pose (`MapRules` : porte seulement entre deux
  pièces collées, fenêtre sur un mur extérieur... ; barrière invisible en
  polygone posée n'importe où, réglage de la carte qui laisse le décor et les
  piliers se chevaucher : docs/MAP_OBJECTS.md § 2 et § 10), annuler / rétablir,
  sauvegarde automatique. Une carte = cinq JSON (`EditorMap` : `carte`,
  `pieces`, `ouvertures`, `objets`, `zones`) dans `user://maps/<id>/` ou une
  archive .zip, plus (format 10) ses **prefabs** dans `prefabs/<pid>/`
  (`MapPrefabLib` : groupe de décors du catalogue ou modèle .glb importé,
  collision en `CollisionBox` ; éditeur : `MapPrefabTools`, catégorie
  « Prefabs de la carte »). Les prefabs de la carte ouverte sont mis dans le
  catalogue par `MapCatalog.set_map_prefabs` (fil principal, tables figées
  remplacées d'un bloc : l'aperçu 3D les lit depuis son fil), appelé par
  `EditorMap` (lecture, `restore`, `activate_prefabs`) et `MapRaster.build` ;
  un décor posé les cite par `"prefab": "map:<pid>"` (docs/MAP_OBJECTS.md § 11).
  En jeu, un modèle importé est lu par `GLTFDocument` (`MeshMapBuilder._map_model`,
  boîte grise et erreur au journal s'il est illisible). Chaîne : `MapRaster` (grille de 0,5 m par
  niveau ; format 17 : plus d'étages, les niveaux sont les altitudes distinctes
  des pièces, grille construite sur une copie décalée si la carte a des
  coordonnées négatives, docs/MAP_AUTHORING.md § 4) -> `MapValidator`
  (erreurs en mètres, indicateurs BO1, FR/EN) -> `MapLayoutExport` (description
  au format de `MeshMapLayout`, en mémoire) -> `MeshMapGeometry` (architecture
  construite par le jeu, sans Blender : jouable aussitôt, même dans le .exe).
  Côté jeu : `EditorMapDef` ; cartes du joueur `perso:<id>` (`Game.has_map`,
  `Game.make_map_def` ; bouton TESTER, écran SOLO « CARTES PERSO », salon
  multijoueur : carte envoyée aux invités et jouée par tous depuis le cache
  sous l'identifiant `partage:<sha256>`, voir « Cartes perso en multijoueur » ;
  contrôle de légitimité `CustomMapGuard` à l'ouverture pour jouer ;
  `Router.return_scene` ramène dans l'éditeur en fin de partie) ; exemple
  livré hors menus `draft_arena` (`assets/maps/draft_arena/*.json`,
  scénarios `draft_arena`, `map_editor`, `map_editor_play`, tests
  `test_map_editor.gd`). Portes `debris` : tas de gravats qui s'enfonce à l'achat.
- **`MapLayout`** (`scripts/game/map/map_layout.gd`) : la géométrie vue par les
  systèmes de jeu, indépendante de la façon dont la carte est décrite. Elle
  fournit les zones (`zone_at(Vector3)`), la navigation (`nav`, serveur), les
  bloqueurs nommés (`set_blocked` : portes, fenêtres, boîte, PaP, poste
  central) et les emplacements en `MapMarker` (point au sol devant le mur,
  direction du mur, identifiant réseau stable, graine) : portes, achats muraux,
  atouts, grenades, interrupteur, boîte, PaP, téléporteur, pièges (volume 3D),
  fenêtres (`BarricadeLayout.Opening`), apparitions. `MapDef` garde la
  description (nom, musique, ambiance, prix, départs de la boîte...) et crée
  sa géométrie (`MapDef.create_layout`). `GridMapLayout` enveloppe les cartes
  ASCII ; `MeshMapLayout` lit les cartes en maillage à plusieurs niveaux
  (KINO, voir `docs/KINO_V2.md`).
- **Cartes en maillage à plusieurs niveaux** (`MeshMapLayout`, exemple
  `test_levels`) : une description JSON (`assets/maps/<id>/layout.json`,
  repère Godot en mètres : salles, murs avec ouvertures, dalles, escaliers,
  garde-corps, zones en boîtes, emplacements) sert à la fois à Blender et au
  jeu. `sh tools/blender.sh tools/blender/mesh_map.py <layout.json> <id>.glb
  [aperçu.png]` construit l'architecture sans fenêtre : objets
  `<matériau>__<salle>__<type>` (visibles, shader `WorldLook.surface` et
  `floor_y` par instance pour les lambris des étages) et `...__col-colonly`
  (collisions ; escaliers = marches visibles + coin de collision plein, le
  joueur n'ayant pas de montée de marche). `MeshMapBuilder` (hérite de
  `MapProps`, comme `PropBuilder`) branche le .glb sur le rendu, le courant et
  les lampes, en trois morceaux (`_add_architecture`, `_build_decor_parts`,
  `_build_lamps`) que l'aperçu 3D de l'éditeur (`MapPreviewBuilder`, qui en
  hérite) appelle aussi : l'aperçu montre la géométrie du jeu, pas une copie
  (test « même géométrie que le jeu », `tests/test_map_preview.gd`). `MeshNav` (hérite de `MapNav`, comme `NavGrid`) cuit le navmesh
  au chargement d'après les collisions (portes fermées et fenêtres comprises)
  ; chaque porte est un `NavigationLink3D` activé à l'ouverture. `find_path`
  garde en cache le point du navmesh le plus proche de chaque cible
  (`goal_point` : un pas physique, vidé quand la carte change) et réutilise sa
  requête de chemin (`query_path`, mêmes réglages que `map_get_path`). Les zombies
  gardent le déplacement flottant et suivent le sol par un rayon vers le bas
  (`Zombie._follow_floor`) ; portée d'attaque, bonds, séparation et points de
  passage tiennent compte de la hauteur. Morceaux et particules retombent sur
  le sol sous leur point de départ (`Fx.floor_under`).
- **Escaliers et couloirs d'ancres** (`StairGen`, `StairLane`,
  docs/MAP_OBJECTS.md § 4) : une entrée « stairs » de la description
  (`a`, `b`, `w`, et facultatifs `kind` parmi droit, palier, quart,
  demi_tour, large, service, colimacon, rampe, `turn`, `steps`, `rail`,
  `closed`) a un plan commun (`StairGen.plan`) : volées, paliers,
  colimaçon, bords, pied, sortie et couloir des zombies. `MeshMapGeometry`
  en construit les marches et les collisions (prisme plein en pente sous
  chaque volée, jamais une marche de collision ; escalier d'avant sans type :
  code et résultat inchangés) ; `MeshMapBuilder._add_architecture` pose au
  haut de CHAQUE escalier (KINO compris, .glb ou non) un tablier
  `CollisionBox` invisible à fleur du palier (aucune fente). Navigation :
  `MeshMapLayout.finish_nav` donne les escaliers à `MeshNav.set_stairs` ;
  quand la carte de navigation est synchronisée (`ensure_anchors`, au premier
  chemin), chaque ancre est posée sur le navmesh (décalée le long du bord si
  le décor masque le milieu) ; si le navmesh ne relie pas les deux ancres
  par les marches (escalier étroit), l'escalier devient un `NavigationLink3D`
  d'une ancre à l'autre (coût = longueur du couloir ; coupé tant qu'une
  porte payante sur le couloir est fermée). `find_path(from, to, lane_bias)`
  réécrit tout chemin qui emprunte un escalier (par le navmesh ou par ce
  passage) : chemin jusqu'à l'ancre d'arrivée, points du couloir à l'écart
  latéral de l'agent (borné à la demi-largeur permise), chemin depuis
  l'ancre de l'autre bout (partagé par la horde pendant un pas physique) ;
  un agent déjà sur les marches ou engagé entre une ancre et elles repart
  de sa place, vers le bout le plus court. `last_lane_marks()` donne
  l'escalier de chaque point ; `Zombie._follow_path` ne saute jamais un point
  de couloir, le passe au plan perpendiculaire à sa direction d'arrivée,
  réduit la séparation (0,35), vire net (30 m/s²) et revient vers l'axe
  (`lane_push`) ; `crosses_stairs` interdit la poursuite en ligne droite
  par-dessus le flanc d'un escalier. Serveur seulement, rien de plus sur le
  réseau ; chiens (`Hellhound` hérite de `Zombie`) et rampants compris.
- Décor de KINO (`MeshMapBuilder` + `TheaterLook`) : objets modélisés dans
  Blender (`tools/blender/props/kino_theater.py` -> `assets/models/kino/`),
  posés par la description (`props`, `instances` en MultiMesh pour les
  fauteuils, `screens`, `beams`, `shafts`) ; écran animé et faisceau du
  projecteur liés au courant par `PowerGrid.add_hook` ; collisions invisibles
  (ruines, rangées, baies) en `CollisionBox` décrites en données (`blockers`,
  `<modèle>.collision.json`), jamais des modèles Blender ; barrière
  joueurs/zombies que les balles traversent (couche BARRIER). Une entrée de
  `blockers` avec `poly` (barrière invisible de l'éditeur, format 9) devient
  un prisme : `CollisionBox` découpe le polygone en morceaux convexes, une
  `ConvexPolygonShape3D` chacun. Cartes grille :
  décor de `PropBuilder` (caisses, barils, lits, paillasses, générateur,
  tuyauteries, lampes grillagées, flaques de sang).
- **Machines d'atouts** (`PerkMachine`) : un modèle Blender par atout,
  `sh tools/blender.sh tools/blender/props/perk_machines.py assets/models/perks
  [dossier d'aperçus] [ids...]` (sans fenêtre ; aperçus PNG de face, de trois
  quarts et en gros plan). Un objet par matériau (`paint`, `paint2`,
  `chrome`, `dark`, `glass`, `lit_sign`, `lit_ink`, `lit_lamp` : un appel de
  rendu chacun) ; seuls `paint` et `lit_sign` projettent une ombre. Les
  boîtes `col_<n>` du .glb deviennent les `BoxShape3D` du `StaticBody3D`
  « Body » enfant direct de la machine (joueurs et zombies butent dessus, les
  balles s'y arrêtent : `Fx.surface_of` rend « metal » pour un parent
  `PerkMachine`), puis sont retirées. `perk_machine.gdshader` (couleur,
  rugosité et métal lus dans le .glb, matériau partagé par atout) ajoute
  rouille, coulures et crasse en coordonnées de l'objet ; le courant passe
  par le paramètre d'instance `lit` (panneau terne éteint, lumineux allumé),
  `seed` varie l'usure d'une machine à l'autre. Nom et emblème (originaux)
  sont en relief dans le modèle. Sans .glb : repli en boîtes (ancien rendu).
  Scénario `perk_look` : modèle, collision, joueur arrêté, balle arrêtée,
  allumage, captures de chaque machine sur les deux cartes.
- **Boîte mystère** (`MysteryBox`, apparence dans `BoxModel`) : coffre de
  bois cerclé de fer modélisé dans Blender, `sh tools/blender.sh
  tools/blender/props/mystery_box.py [assets/models/props] [dossier
  d'aperçus]` -> `assets/models/props/mystery_box.glb` (≈ 7 000 triangles,
  LOD à l'import). Un objet par matériau (`wood`, `iron`, `brass`, `paint`,
  `inner`, `glow`, et `lid_wood`, `lid_iron` pour le couvercle, rattachés au
  pivot `MysteryBox._lid` sur la charnière `LID_HINGE`). UV en mètres dans
  le sens du fil, UV2.x = tirage propre à chaque planche ; `mystery_box.gdshader`
  dessine fil, cernes, nœuds, arêtes usées (faces de chanfrein), rouille,
  peinture de pochoir écaillée et relief (dérivées écran, sans texture) ; le
  paramètre d'instance `open` allume le fond. Colonne de lumière et halo
  d'ouverture : `box_beam.gdshader` (additif, bords et sommet fondus, effacé
  de près), réglages `BEAM_*`, `HAZE_*`, `LIGHT_*` de `MysteryBox` (bornés
  par `test_mystery_box_look.gd`). La collision (1,8 x 0,85 x 0,85 m) et le
  point d'interaction ne dépendent pas du modèle ; vraie boîte, boîtes de
  LIQUIDATION et aperçu de l'éditeur partagent ce rendu. Sans .glb : repli
  en boîtes. Captures : scénario `box_look` (`@niveau perf`, hors check).

## Fils de travail : aucun état partagé (`ThreadGuard`)

Un calcul lancé hors du fil principal (`Thread`, `WorkerThreadPool`) ne touche
à **aucun état partagé modifiable** : ni `static var` (caches), ni autoload
(`Settings`, `Net`...), ni nœud, ni ressource (maillage, matériau, `load()`),
ni donnée que le fil principal peut modifier pendant le calcul. Dans le jeu
exporté (modèles « release », sans les vérifications du mode débogage), un
accès concurrent ne donne pas d'erreur de script : il peut faire planter le jeu
(violation d'accès 0xc0000005, sans rien dans le journal).

- **Avant le lancement** (fil principal) : tout ce que le calcul lit est
  préparé et ne change plus — copie profonde des données (`EditorMap.duplicate_map`),
  tables construites puis figées en lecture seule (`MapCatalog.items()` :
  `make_read_only` en profondeur), réglages lus une fois (langue :
  `ThreadGuard.enter(lang_en)` au début du calcul, `Lang.t` ne lit jamais
  `Settings` dans un fil).
- **Caches du fil principal** : `ThreadGuard.main_only("nom")` en tête ; hors du
  fil principal l'accès est refusé (ni lu ni écrit), noté, et relevé par le
  fil principal (`ThreadGuard.take_violations()`, erreur signalée par
  l'aperçu 3D). Les fonctions utiles aux deux calculent alors sans cache
  (`WeaponDB.stats`, `MapRules.inner_cells`) ; le lot de vérification
  (`MapRules.begin_batch`) n'est jamais ouvert ni lu depuis un fil.
- **Résultat** : données seulement (dictionnaires, tableaux) ; les nœuds et
  ressources sont créés par le fil principal avec ce résultat, après
  `wait_to_finish()`. Le nœud qui possède le fil l'attend avant de disparaître
  (`_exit_tree` et `NOTIFICATION_PREDELETE`).
- Mutex seulement pour un échange explicite et court (`WeaponModels`,
  `ZombieModel` : tableaux précalculés rangés sous verrou).
- Tests : `tests/test_preview_thread.gd` (chemin du fil de l'aperçu 3D : aucun
  accès noté, caches refusés, catalogue figé, copie profonde) et
  `map_preview_stress` (contrainte de 60 s, avec rendu).

## Journaux et plantages (`CrashLog`, `CrashGuard`)

Tout plantage laisse une trace, même une violation d'accès sans aucun message
(jeu ET lanceur ; `scripts/game/crash_log.gd`, copie identique dans
`launcher/scripts/crash_log.gd`).

- **Où** (joueur, exe exporté) :
  - jeu : `%APPDATA%\Godot\app_userdata\Call of Claude Zombie\logs\` (journaux,
    `godot.log` = session en cours, les précédents horodatés) et
    `...\Call of Claude Zombie\crashes\` (rapports de plantage) ;
  - lanceur : `%APPDATA%\CallOfClaudeZombieLauncher\logs\` et `...\crashes\`.
- **Journal toujours écrit, vidé à chaque ligne** : `debug/file_logging/*`
  activé pour tous (exe exporté compris) et `application/run/flush_stdout_on_print`
  (sans lui, l'exe exporté ne vide son journal qu'aux erreurs : un exe tué
  garde un journal VIDE, vérifié avec le modèle d'export « release »).
- **Conservation par jours** : Godot garde jusqu'à 1000 journaux
  (`max_log_files`, limite de secours) ; au démarrage, `CrashLog.prune`
  supprime ceux de plus de 14 jours, puis les plus anciens si le total
  dépasse 200 Mo. Rapports de plantage : 30 jours, 50 Mo au plus.
- **Marqueur de session** : `session_en_cours_<pid>.json` dans le dossier des
  données (version, heure, écran courant, dernier contexte, journal, identifiant
  de session écrit aussi dans le journal : `[Session] début <id>`). Posé au
  démarrage, mis à jour à chaque changement d'écran (et au lancement de
  TESTER, à l'ouverture / fermeture de l'aperçu 3D), retiré à la fermeture
  normale (`_exit_tree` de l'autoload : Quitter, fenêtre fermée, lanceur qui
  lance le jeu ou se met à jour). Encore là au démarrage suivant et son
  processus arrêté : la session a planté -> `crashes/plantage_<date>.txt`
  (version, heures, dernier écran et contexte, 60 dernières lignes) et
  `plantage_<date>.log` (journal complet de la session, retrouvé par son
  identifiant) ; message discret au menu principal (FR/EN, bouton « Ouvrir le
  dossier ») ou sous l'état du lanceur. Un second jeu ouvert en même temps
  (processus vivant) n'est pas pris pour un plantage.
- **Lignes de contexte** (`[Session]`, `[Apercu3D]`) : changement d'écran
  (dont l'ouverture de l'éditeur), TESTER, ouverture / fermeture de l'aperçu
  3D, début et fin de chaque calcul de l'aperçu, fermeture normale.
- **Tests et agents** : jamais dans les données du joueur. Marqueur et
  rapports seulement dans l'exe exporté (`OS.has_feature("template")`) ; le
  binaire de l'éditeur écrit son journal dans `tests/_out/logs/`
  (`log_path.editor`), et tous les lancements de `tools/*.sh` passent
  `--log-file`. Vérifié par `tests/test_crash_log.gd` (conservation 13 / 15
  jours, taille bornée, plantage -> rapport, fermeture normale -> rien,
  réglages des deux projets, `--log-file` dans tools/).

## Déroulement d'une partie (`Game`, `MatchRules`, `SpectatorCamera`)

- `Game` (`/root/Game`) : chargement, apparition des joueurs, RPC de mort, de
  fin de partie et de réapparition. Les règles pures sont dans `MatchRules`
  (`scripts/game/match_rules.gd`, statique, `tests/test_match_rules.gd`) :
  fin de partie quand plus personne n'est debout (un joueur à terre qui va
  se relever seul — LAZARUS en solo — la repousse), mort par saignement,
  réapparition des morts au début de chaque manche (`RoundManager` ->
  `Game.respawn_dead_players`), point d'apparition par place (modulo positif,
  repli fixe sur une carte sans point d'apparition).
- `SpectatorCamera` (`/root/Game/Spectator`, local, sans RPC) : joueur mort en
  multijoueur, vue d'un coéquipier en vie ([Tir] : suivant), retour à sa
  caméra à la réapparition. `Game.spectating` lit ce nœud.
- Présentation : le HUD dessine la fin de partie (`Hud.show_game_over` :
  « GAME OVER », résumé, manches survécues, tableau des scores) et le bandeau
  de spectateur (`Hud.set_spectating`) ; `Game._cl_game_over` reçoit le
  nombre de zombies tués, écrit les textes dans la langue du joueur
  (`Game.game_over_summary`, `Game.survived_text`, via `Lang`) et garde
  l'état, le dossier de combat et, après `GAME_OVER_DELAY`, le retour au menu
  (solo, TESTER de l'éditeur) ou au salon avec tout le groupe (multijoueur :
  « Fin de partie multijoueur » plus haut).

## Manches, apparitions et fenêtres (`RoundRules`, `Spawner`, `Barricade`)

- Vitesse (`RoundRules.pick_speed`) : que des marcheurs aux manches 1 à 3
  (`RUNNERS_FROM_ROUND` = 4, règle demandée par le joueur), puis le tirage de
  BO1 (`[manche x 8, manche x 8 + 35]` : marche jusqu'à 35, course jusqu'à
  70, sprint au-delà). Les chiens ont leur propre vitesse (`DogRules`).
- Points d'apparition (`Spawner.pick_spawn_point`) : zones actives, un zombie
  à la fois par point, de préférence à 9-26 m et hors de vue. Les points qui
  sortent du sol sont exclus à moins de 7 m d'un joueur ; ceux d'une fenêtre
  jamais (BO1 : le zombie apparaît dehors et vient à sa fenêtre même si le
  joueur s'y tient — une carte d'une salle et d'une fenêtre reste jouable).
- Fenêtre : 3 places devant les planches (`Barricade.SLOT_OFFSETS`, BO1 :
  attack_spots ; milieu, gauche, droite, places fermées par le mur d'une
  poche étroite écartées). Un zombie par place ; au plus 3 qui attendent
  (`BarricadeRules.WINDOW_QUEUE_MAX`, `Barricade.waiting_count`) : le point
  d'apparition de la fenêtre est sauté tant que la file est pleine (le zombie
  reste dans le quota de la manche). Sans place (cas d'exception), attente
  1 m en retrait.
- Arrachage (`BarricadeRules.tear_tick`, par zombie) : geste agrippe-tire de
  1,3 s (la planche cède à 70 %), puis pause « de folie » de 0,9 à 1,5 s ;
  2,5 s par planche en moyenne, quelle que soit la vitesse du zombie. La
  phase est diffusée par `Zombie.FRENZY_BIT` du code d'animation.
- Portes à zombies (format 8 des cartes de l'éditeur, `Barricade.kind`,
  `BarricadeRules.KINDS`, docs/MAP_OBJECTS.md § 9) : porte simple, une
  place où l'on arrache et 3 d'attente (file de 4) ; porte double, 2 places
  (une par battant, `srv_tear(lane)`), 4 d'attente (file de 6), 10 planches,
  deux passages (`_vaulters`, `inside_point(lane)`, `exit_clear(z, lane)`).
  Les places d'attente sont des places du tableau `_slots` après celles où
  l'on arrache (`tear_slots()`) ; le Spawner demande `Barricade.queue_full()`.
  Battant cassé à mi-hauteur : on l'enjambe comme une fenêtre (`vault_time()`
  = `VAULT_TIME`, même animation). Modèle : `ZombieDoorModel` (10 cm d'épaisseur, face intérieure
  du mur). Masque des planches sur 10 bits (état complet en
  `PackedInt32Array`).
- Barrière de collision (`Barricade.barrier_depth`, `barrier_mid`,
  `barrier_width`, `barrier_face()`) : cartes en maillage, ajustée au mur
  réellement percé (`BarricadeFit`, appelé par `MeshMapLayout.windows()` :
  épaisseur et milieu mesurés dans l'allège ou à côté de l'ouverture,
  largeur découpée) ; elle bouche exactement le trou, faces au nu du mur
  (rien qui dépasse, rien où la capsule accroche). Cartes grille : 1 m.
  La portée de réparation se mesure depuis `barrier_face()`.
- Tests : `tests/test_rounds.gd`, `tests/test_barricades.gd`,
  `tests/test_barricade_wall_fit.gd` (scénario `barricade_wall_slide`),
  `tests/test_zombie_doors.gd` (scénario `zombie_doors`),
  `tests/test_spawner.gd` ; scénarios `smallest_window` et `smallest_speeds`
  sur la carte SMALLEST du joueur (copie : `tests/fixtures/maps/smallest/`,
  installée dans le dossier des cartes du scénario sous `tests/_out`).

## Tests

- **Stratégie, niveaux, écriture des tests, couverture : `docs/TESTING.md`.**
- `sh tools/check.sh` : tâches impactées par les changements (carte des
  dépendances `tools/test_deps.gd`) ; `--full` : tout (exigé par la release).
  **Doit passer avant chaque commit.**
- Journaux : chaque processus de test écrit son journal Godot dans
  `tests/_out/logs/` (`--log-file`, dans check.sh, mp_test.sh, perf.sh,
  scenario.sh, net_smoke.sh, commit.sh ; release.sh : `build/*.godot.log`),
  jamais dans celui du joueur (voir « Journaux et plantages »). Un lancement
  à la main sans `--log-file` va aussi dans `tests/_out/logs/godot.log`
  (réglage `log_path.editor` du binaire de l'éditeur) ; ajouter quand même
  `--log-file` pour garder son journal à part.
- Tests unitaires : `tests/test_*.gd` (runner : `res://tests/test_runner.tscn`).
- Scénarios en jeu : `tests/autotest/*.gd` (options en jeu : `pause_options` ; captures de l'écran d'options en jeu : `options_look`, `## @rendu`). Réglages et touches : `tests/test_settings.gd` (fichier temporaire, jamais les réglages du joueur).
- Rapidité : check.sh lance tout dans un pool parallèle (les plus longues
  d'abord) ; scénarios sans rendu en temps de jeu accéléré
  (`--headless --fixed-fps 60`, enchaînés en **séries** dans quelques
  processus), multijoueur à cadence fixe x3 (`--max-fps 180`), captures et
  mesures de perf ignorées sans rendu. Étiquettes en tête de scénario :
  `## @temps-reel`, `## @carte <id>`, `## @niveau perf`, `## @seul`,
  `## @couvre <motifs>` (voir `docs/TESTING.md`), et :
  `## @rendu` (a besoin du rendu : fenêtre réduite, sans focus, puis déplacée
  hors des écrans par `Autotest._move_offscreen`) et `## @parts N` (N parties
  parallèles avec `--part=k/N` ; `mine(i)` répartit une liste, `owns(k)` une
  section ; sans `--part`, tout tourne). Ports réseau : `AUTOTEST_PORT_OFFSET`,
  décalé de 100 par place du pool.

## Chiens de l'enfer (`scripts/game/dogs/`)

- `Hellhound` étend `Zombie` : c'est un **type d'entité** du `ZombieManager`
  (`spawn(..., kind = KIND_DOG)`, argument `kind` de `_cl_spawn`). Même canal
  réseau (apparition fiable, instantanés, mort), mêmes dégâts, points, pièges et
  nuke ; aucun bonus aléatoire (seul le dernier chien lâche MUNITIONS MAX).
- `DogRound` (`/root/Game/Rounds/Dogs`) : planification BO1 (manche 5 à 7 puis
  +4/+5, coupée en autotest sauf `debug_force_next`), apparitions par la foudre
  près du joueur le moins chassé (10 à 25 m, sur un point qui a un chemin
  jusqu'à lui : les îlots du navmesh des cartes en maillage sont écartés),
  ambiance (brouillard `WorldLook`, musique,
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
- **Joue de visée** : en visée, ce qui passe plus près de l'œil que le cran
  moins 2 cm (arrière du boîtier, crosse, corps des bullpups, tube du LAW)
  est abaissé par le shader (`vm_bend`, `ViewModel.bend_params` / `bend`,
  même formule) sur une courte rampe ; l'abaissement de chaque modèle est
  tiré de sa géométrie (`ViewModel.bend_drop`) pour que la carcasse passe
  sous le bord bas de l'écran (champ de visée, 21:9) juste derrière le cran.
  Le départ suit le cran pendant la mise en joue. La crosse n'est plus
  masquée (plus de crosse coupée ni de disparition d'un coup). La partie
  courbée est découpée en tranches de 1 cm (`WeaponMesh.slice_z`,
  `WeaponModels.BEND_SLICE`, avant-bras compris) : le shader déforme les
  sommets, un long flanc de crosse non découpé restait plat et traversait
  l'arme contre l'œil. Arme dont la carcasse ne passe jamais devant l'œil
  (pistolets, PM) : pas de joue, mains visibles. L'écran de
  lunette masque l'arme dans l'image même où la mise en joue atteint
  `ViewModel.SCOPE_ADS` (`apply_scope`). Arme sans organes de visée (info
  `no_sights` : minigun) : reste à la hanche en visée, réticule affiché.
  Vérifié arme par arme sans partie par `tests/test_view_model_fit.gd` (rien à
  l'écran à moins de 5 cm de l'œil — hanche, visée, tir, rechargement, sprint,
  changement d'arme, et actions lancées en visée : couteau, grenade, boisson,
  plongeon, sprint —, armes Pack-a-Punch et champs de vision min / défaut /
  max, rien à moins de 10 cm en visée, découpe de la partie courbée, bouts de
  manche hors de l'écran, mains posées sur l'arme, avant-bras hors de l'arme).
  Captures rendues (correctif en cours, hors check) :
  `tests/autotest/view_model_stock.gd`.
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
- **Modèles et vue FPS** : `WeaponMesh` (primitives arrondies : profils
  extrudés chanfreinés, révolutions, capsules) fusionnées en UN maillage par
  matériau et par pièce mobile (`mag`, `slide`, `pump`, `barrels`, `cyl`,
  `rear`) ; géométrie des armes et des mains (`ViewHands`, pièces partagées
  placées par transformations) calculée en tâche de fond au chargement
  (`WeaponModels.precompute_async`, appelée par `Warmup`), maillages créés au
  premier affichage. L'arme est dessinée avec son propre champ de vision
  (`ViewModel.VIEW_FOV`, 51,3° = cg_fov 65 de BO1 ; 72° en visée) : le shader
  multiplie x, y du clip par `vm_fov_scale` (global de shader) ; les effets
  partent du point apparent (`ViewModel.apparent`). L'axe optique ne bouge
  pas : l'alignement de visée ne dépend pas de ce champ. Rechargements animés
  par mécanisme (`ViewModel._reload_anim`), vérifiés par `weapon_view`.

## Arme merveille TONNERRE-7 (`scripts/game/weapons/thunder_blast.gd`)

- Façon Thundergun de Kino : 2 coups, réserve 12 (OURAGAN-77 amélioré : 4 / 24),
  rare dans la boîte et **unique** dans la partie (`WeaponDB.is_unique`,
  `MysteryBox.wonders_taken` : en main d'un joueur ou dans le Pack-a-Punch).
- Le client n'envoie que l'intention de tir (`srv_fire` sans touches). Le
  serveur (`ThunderBlast.server_blast`) sélectionne les zombies du cône
  (20 m, 60°, règles pures testées), en vue du tireur (pas à travers les
  murs), et les tue tous d'un coup (`Combat.damage_zombie(..., fling)`, 50
  points). `ZombieManager.kill_flung` diffuse un RPC fiable de mort projetée
  avec la vitesse initiale : chaque machine lance le ragdoll du corps à cette
  vitesse (`ZombieRagdoll`, ci-dessous), ou à défaut (qualité BASSE, plafond
  plein) le vol procédural `ZombieFling`. Aucun dégât aux joueurs.

## Couches physiques

Une couche par usage, jamais partagée (vérifié par `tests/test_physics_layers.gd`) :

| Couche | Bit | Constante | Usage |
|---|---|---|---|
| 1 | `1` | — | Monde (murs, sols, portes fermées, décor, machines) |
| 2 | `1 << 1` | — | Joueurs |
| 3 | `1 << 2` | `Zombie.BODY_LAYER` | Capsules des zombies et des chiens |
| 4 | `1 << 3` | `Zombie.HITBOX_LAYER` | Zones de tir (zombies, chiens) |
| 5 | `1 << 4` | `Barricade.BARRIER_LAYER` | Fenêtres et boîtes « barrière » (bloquent les corps, pas les balles) |
| 6 | `1 << 5` | — | Libre |
| 7 | `1 << 6` | `ZombieRagdoll.LAYER` | Ragdolls (ne heurtent que le décor) |
| 8 | `1 << 7` | `MeshNav.LOW_LAYER` | Obstacles bas (boîte au sol, tas de planches) : rayon genou de `MeshNav.world_line_clear` |

Le rayon genou ne voit QUE la couche 8 : un corps qui tombe ne coupe jamais
la ligne de vue des zombies, la poursuite des chiens ni le test « vu par un
joueur » des apparitions (`Spawner._in_view`, rayon des yeux seul :
`eye_line_clear`).

## Formes de collision des zombies (déplacement et tirs)

Deux familles de formes, jamais mêlées (`tests/test_zombie_hitbox.gd`) :

- **Déplacement** : une capsule par `CharacterBody3D` (couche « zombies »),
  le TRONC sans les bras : `Zombie.RADIUS` 0,22 m (torse 0,19 à 0,21 m de
  demi-largeur sur tous les looks), hauteur 1,75 m. Les épaules
  (`Zombie.SHOULDER_RADIUS` 0,3 m, l'ancienne capsule) et les bras dépassent :
  deux voisins se frôlent des bras, et une horde passe en file dans un
  couloir de 1,5 m au lieu d'y former une voûte coincée à l'entrée. La
  séparation entre zombies agit à moins de `Zombie.SEPARATION_RANGE` 0,74 m
  (deux troncs au contact et 0,3 m), sans pousser dans le mur touché
  (`_wall_safe`) ; les zombies glissent le long d'un mur même abordé presque
  de face (`wall_min_slide_angle` 0). Ce qui reste aux épaules : l'érosion du
  navmesh (`MeshNav`, 0,4 m : aucun chemin par une fente de moins de 0,8 m),
  la ligne droite vers la cible (`_body_fits` : sphère des épaules lancée sur
  la ligne, jamais par une fente entre un pilier et un mur ; joueur à moins
  de `Zombie.SLIM_RANGE` 3 m ou hors du navmesh, chemin qui n'arrive pas à
  portée d'attaque : sphère du tronc et 3 cm, un joueur réfugié dans une
  fente de 0,7 à 0,8 m reste attaquable ; départ contre un mur longé : la
  sphère part d'un point recentré, `_sweep_clear`), les couloirs
  d'escalier (`StairGen.AGENT_RADIUS`), les places d'attente aux fenêtres et
  les apparitions derrière elles (`Barricade`, `Spawner`). Un angle du
  chemin atteint « à peu près » n'est passé que si le tronc file droit vers
  le point suivant (`_leg_clear`, aussi pour un point « dépassé »). Chiens :
  capsule de 0,3 m (balayages à mi-hauteur du chien, 0,3 m), séparation
  0,9 m (`Hellhound.RADIUS_DOG`, `SEPARATION_DOG`). Scénario
  `zombie_corridors` : horde de 20 dans des couloirs de 1,5 / 2 / 2,5 m, un
  coude, une porte, un escalier, une fente de 0,5 m (débit, bouchons,
  zombies coincés, personne par la fente).
- **Tirs** : `Area3D` sur `Zombie.HITBOX_LAYER`, ni masque ni détection :
  corps (capsule de 0,28 m, zone 0), tête (sphère de 0,16 m sur l'os de la
  tête, zone 1), avant-bras (capsules de 0,075 m sur les os des avant-bras,
  zone 2 : un tir au bras touche le bras et l'arrache, comme BO1).

## Ragdolls des zombies tués (`ZombieRagdoll`)

- Purement visuel, calculé par chaque machine : `PhysicalBoneSimulator3D`
  ajouté au squelette du mort (`Zombie.die`), 11 `PhysicalBone3D` en capsules
  (bassin, colonne, cou + tête, bras, avant-bras, cuisses, tibias), cônes et
  charnières limitées. Départ de la pose courante, élan du zombie gardé.
- Force du coup : calculée par le serveur (`ZombieRagdoll.kill_impulse` :
  type de coup, classe d'arme, tête) et transmise par la LONGUEUR du vecteur
  `dir` du message de mort existant (`ZombieManager._cl_die`) ; TONNERRE-7 :
  vitesse de `_cl_die_flung`. Aucun état physique synchronisé.
- Couche 7 (« ragdolls »), masque 1 : ne heurte que le décor, invisible pour
  les joueurs, les zombies, les tirs et les autres corps.
- Coût borné : `ZombieRagdoll.CAPS` ragdolls simulés au plus (BASSE 0 : chute
  procédurale, MOYENNE 8, HAUTE 12) ; corps figé au repos ou après 3 s (pose
  recopiée dans le squelette, corps physiques retirés) ; au-delà du plafond,
  le plus ancien figeable l'est, sinon chute procédurale. Détection continue
  pour les corps lancés vite (pas de traversée des murs).
- Captures et mesures : scénario `ragdoll_look` (hors check).
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
  (`ZombieModel.limb_mesh`, mis en cache par look) construits 3 par image au
  plus, 6 s au sol.

## Modèle et animations des zombies

- `ZombieModel` : 36 looks déterministes (variante réseau modulo 36), 6
  archétypes façon Kino der Toten ; maillage lissé (`RigBuilder` : ellipsoïdes,
  tubes « loft » dont les anneaux sont partagés entre deux os), skinné sur le
  squelette commun (+ os `jaw`), 1 draw call, sang peint par sommet (fraction de
  UV2.y) et matière par pièce lus par `zombie.gdshader` (corps commun `zombie_body.gdshaderinc`, bruit lu dans `NoiseLattice.tex3d` ; variante `zombie_dissolve.gdshader` pour les corps qui se dissolvent). Mesh et Skin partagés ;
  les tableaux de tous les looks sont calculés sur un thread de travail
  (`prewarm_async`, lancé au premier zombie construit, typiquement au
  préchauffage) : un zombie coûte < 0,1 ms à construire. Couche de rendu 2 (hors
  des décalques de sang).
- `ZombieAnim` (un par zombie, cosmétique, toutes les machines) : marche
  traînante, trot/course, sprint, attaque à deux bras, émergence, arrachage de
  planches (geste réglé sur `BarricadeRules.TEAR_PULL`, puis pause « de
  folie » `frenzy_pose` : coups de bras alternés sur les planches, tête
  secouée), enjambement, morts variées (choix déterministe id + variante).
  `ZombieGibs.crawl_pose` anime les rampants. Voir docs/ART_DIRECTION.md.

## Bonus FAUCHEUSE et LIQUIDATION

- FAUCHEUSE (DEATH MACHINE de BO1, `PowerupRules.DEATH_MACHINE`) : le joueur qui
  la ramasse tient 30 s le minigun `death_machine` (main droite sur la poignée
  arrière, main gauche sur la poignée latérale ; `WeaponDB.POWERUP_WEAPONS` :
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

## Profil du joueur (`scripts/game/profile/`)

Données permanentes du joueur (GAME_CONCEPT §4.2, §4.7, §4.9 à §4.12, §4.15),
sans interface pour l'instant (hub, station de construction et butin viendront
s'y brancher). Purement local : chaque joueur a son profil.

- `PlayerProfile` : XP totale (le niveau en découle : `100 × niveau^1,8` par
  niveau, maximum 50, l'XP continue au-delà), arsenal illimité
  (`OwnedWeapon`), onglet des pièces illimité (`WeaponPart`), échantillons
  (type → quantité, consommation tout ou rien), armes de départ (1 à 3).
- `OwnedWeapon` : exemplaire d'une arme (identifiant `uid` unique, niveau,
  rareté → 1/2/3/4/4 emplacements, pièces installées), score = niveau +
  niveaux des pièces, montage si pièce ≤ arme et ≤ joueur.
- `BaseWeapons` : armes de base niveau 1 communes, hors arsenal (non
  recyclables) ; provisoirement le pistolet de départ et le couteau.
- `ProfileStore` : `user://profile.json` (un fichier par processus en
  autotest), JSON versionné, écriture via `.tmp`, copie de secours `.bak`,
  fichier illisible mis de côté (`.corrupt-<date>`), jamais écrasé.
- `MatchXp.apply_match_xp(kills, manches survécues)` : XP provisoire de fin de
  partie, appelée au GAME OVER (`Game._cl_game_over`, à côté de
  `CareerStats`) ; l'évacuation l'appellera aussi. Le dossier de combat
  (`CareerStats`) reste à part. Tests : `tests/test_profile.gd`.
