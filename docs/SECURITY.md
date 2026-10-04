# Sécurité — Claude of Duty Zombie

Ce document décrit contre quoi le jeu et son lanceur se protègent, les règles
à suivre pour tout nouveau code, et ce que le lanceur vérifie avant d'installer
ou d'exécuter quoi que ce soit. Tests : `tests/test_security.gd` (unitaires),
`tests/autotest/net_guard.gd` (dans le vrai jeu), `launcher/tests/test_launcher.gd`.

## Modèle de menace

| Adversaire | Ce qu'il contrôle | Ce qu'il ne doit jamais obtenir |
|---|---|---|
| **Client malveillant** (joueur tricheur ou programme modifié qui rejoint une partie) | Tous les octets de ses RPC et de son état de mouvement : valeurs NaN / infinies, tableaux immenses, identifiants inventés, cadence de messages, position | Agir pour un autre joueur ; points, munitions, dégâts, achats ou réanimations gratuits ; toucher ou exploser n'importe où ; se téléporter ; faire planter ou inonder le serveur et les autres clients ; faire exécuter du code |
| **Hôte malveillant** (un joueur héberge avec un jeu modifié) | Tout l'état de la partie vu par les clients (il fait autorité : il peut tricher dans SA partie) | Faire exécuter du code chez les clients, leur faire lire / écrire des fichiers hors de leurs dossiers, les faire planter durablement |
| **Carte piégée** (carte perso reçue d'un hôte ou importée en .zip) | Le contenu des fichiers JSON de la carte, les noms, identifiants et chemins qu'ils contiennent, la taille de l'archive | Charger un script, une scène ou une ressource (`.tscn`, `.tres`, `.gd` = code), sortir du dossier de la carte (`..`), épuiser la mémoire |
| **Mise à jour compromise** (fichier modifié en route, miroir, domaine piégé, release altérée) | Les octets reçus par le lanceur, une réponse d'API modifiée, des redirections | Installer ou lancer un exécutable qui n'est pas celui publié ; remplacer le lanceur ; écrire hors du dossier des versions |

Hors de portée : un programme déjà installé sur le PC du joueur avec ses droits
(il peut remplacer directement l'exécutable ou `override.cfg` à côté de lui),
et le compte GitHub du dépôt s'il était compromis (voir « Limites »).

## Règles pour tout nouveau code

### RPC (`@rpc`)

1. **Requête client -> serveur** : `@rpc("any_peer", "call_local", ...)`, et en
   première ligne le prologue commun de `NetGuard` (un client peut appeler un
   RPC « any_peer » directement chez un autre client, via le relais du
   serveur) :
   ```gdscript
   var pid := NetGuard.alive_sender(self, game, _limit)
   if pid == NetGuard.NO_SENDER:
       return
   ```
   - `server_sender(node, limiter)` : ce nœud est le serveur, puis limiteur
     facultatif ; rend l'expéditeur ;
   - `known_sender(node, game, limiter, need_player)` : en plus, joueur de la
     partie (données de session et, sauf `need_player = false`, nœud Player) ;
   - `alive_sender(...)` : en plus, joueur vivant.
   Un limiteur passé au prologue compte AVANT les autres contrôles ; quand un
   jeton ne doit être pris que pour une demande utile (`Combat.srv_reload`,
   `srv_switch`) ou seulement pour un refus (`ThrowableSystem.srv_throw`), le
   RPC appelle `server_sender(self)` puis son limiteur à l'endroit voulu.
2. **L'expéditeur est `multiplayer.get_remote_sender_id()`** (rendu par le
   prologue), jamais un argument : un client n'agit que pour lui-même. Ses
   données : `session.get_data(pid)` (null pour un pair qui n'est pas un joueur
   de la partie : on ignore).
3. **Borner chaque argument avant tout contrôle** (`NetGuard`) :
   - vecteurs et nombres : `NetGuard.finite_vec` / `finite` (un NaN rend fausses
     toutes les comparaisons `distance > max` et contourne le contrôle) ;
     directions : `NetGuard.valid_dir` ;
   - tableaux : `NetGuard.clean_vecs(a, max)` ou `slice` ; chaînes : longueur ;
   - identifiants (arme, atout, objet, zombie) : recherchés dans les tables du
     serveur (`WeaponDB.exists`, `objects.get(id)`...), jamais utilisés tels quels ;
   - types des éléments d'un `Array` reçu (`h[0] is int`...).
4. **Tout se vérifie côté serveur** avec SES données : position connue du joueur
   (distance d'interaction, origine du tir : `Player.srv_origin()`, point 10), points, munitions, cadence
   (`NetGuard.Limiter.take` au débit de l'arme dans `Combat._validate_fire` :
   cadence moyenne x1,25, rafale d'au moins 4 tirs ou 0,4 s de tirs de l'arme,
   `Combat.fire_burst`), état (vivant, à terre).
   Un point revendiqué (impact, explosion) doit être plausible pour le tir
   (`Combat.plausible_splash`). Bornes larges : un joueur honnête avec du lag ne
   doit jamais être refusé.
5. **Cadence** : toute requête qui déclenche une diffusion ou un message de
   refus passe par un `NetGuard.Limiter` (par joueur ; seul seau de jetons des
   RPC de partie — `MapShare`, dans le salon, garde le sien, rempli à chaque
   image) ; pas de réponse à chaque requête refusée.
6. **Diffusion serveur -> clients** : `@rpc("authority", ...)` sur un nœud dont
   l'autorité est le serveur. Pour un nœud dont l'autorité est un client (le
   `Player`), un message du serveur est « any_peer » ET vérifie
   `get_remote_sender_id() == 1` (`Player._cl_correct`).
7. **Côté client, les messages de l'hôte sont aussi des entrées** : un texte qui
   devient un chemin (`VoxSystem._cl_say`) passe `NetGuard.safe_token` ; aucun
   texte réseau dans un `RichTextLabel` à BBCode ; nombres bornés.
8. **Jamais d'objets dans le réseau** : `multiplayer.allow_object_decoding`
   reste désactivé (vérifié par `test_security.gd`) ; jamais `bytes_to_var_with_objects`,
   ni `str_to_var` sur des données reçues. Messages fréquents : format binaire
   de `NetCodec`, décodage qui vérifie les tailles et refuse les valeurs non finies.
9. **Positions des joueurs** : le client fait autorité sur son mouvement, mais le
   serveur refuse un déplacement impossible (plus de 18 m/s en moyenne + 3 m)
   et replace le joueur (`Player._srv_accept_state`). Toute téléportation voulue
   par le serveur appelle `Player.net_allow_warp()` sur la marionnette du serveur.
10. **Position de référence d'un joueur** : toute origine annoncée par un client
   (tir `Combat._validate_fire`, couteau `srv_melee`, plongeon `srv_dive_landed`,
   lancer `ThrowableSystem.srv_throw`, distance d'interaction
   `InteractionSystem.srv_interact`, point visé `Interactable.srv_point()` : pour
   une réanimation, la référence du joueur à terre), et toute position de joueur
   lue par le serveur pour autoriser une action (réparation
   `Barricade.can_repair_from`, jugée par `Barricade.srv_use` puis à chaque
   image, collé à la barrière : l'`in_reach` large de l'InteractionSystem ne
   suffit pas ; réanimation `DownedSystem.in_revive_range` avec
   la référence du sauveteur ET du joueur à terre, ramassage de bonus
   `PowerupRules.within_pickup`) se juge par rapport à `Player.srv_origin()` :
   le DERNIER état reçu et accepté par `_srv_accept_state` (déjà passé par
   l'anti-téléportation), jamais `global_position` de la marionnette, qui est
   interpolée `INTERP_DELAY` en arrière (avec du lag ou en test accéléré, elle
   traîne plusieurs mètres derrière le joueur : actions honnêtes refusées).
   Mêmes tolérances qu'avant (`Combat.origin_ok`, `InteractionSystem.in_reach`) :
   un état refusé ne déplace pas la référence. Joueur de l'hôte, ou aucun état
   accepté depuis un saut voulu : position du nœud. La position interpolée ne
   sert qu'à l'affichage.

### Fichiers

1. **Jamais `load()` / `ResourceLoader` sur un chemin venant de l'utilisateur,
   du réseau ou d'une carte** : une `.tscn` / `.tres` peut contenir un script,
   donc du code. Seules les ressources de `res://` choisies par le code sont
   chargées ; un nom venant d'une donnée est validé (`NetGuard.safe_token`,
   liste des modèles connus) avant d'être collé dans un chemin `res://`.
2. **Réglages `.cfg`** : `ConfigFile.load()` décode `Object(...)` et charge
   `Resource("...")` : un `.cfg` piégé EXÉCUTE du code (vérifié sur Godot 4.7.2).
   Toujours `SafeConfig.load_file()` puis `SafeConfig.get_string / get_int /
   get_float / get_bool` (valeurs typées et bornées).
3. **Données** : JSON seulement (`JSON.parse_string` ne crée pas d'objets),
   taille du fichier bornée avant lecture, types vérifiés après.
4. **Chemins construits** : jamais de `..`, `/`, `\`, `:` dans un identifiant
   venu de l'extérieur ; les noms de dossiers suivent un format strict (numéro de
   version `v0.1.116`, identifiant de carte en `[a-z0-9_]`).
5. **Archives** (.zip) : n'extraire que les noms attendus (`get_file()`, jamais
   le chemin de l'archive), borner le nombre d'entrées et la taille.
6. **Modèles 3D venus d'une carte** (prefabs de la carte, format 10,
   `MapPrefabLib`) : jamais `load()` ni `ResourceLoader` ; seulement des
   `.glb` vérifiés AVANT le moteur (`MapPrefabLib.check_glb` : en-tête et
   morceaux GLB exacts, aucune clé `uri`, extensions obligatoires en liste
   blanche, images PNG / JPEG intégrées de 4096 px au plus lues dans leur
   en-tête, 150 000 triangles, comptes bornés, 8 Mo par modèle, 24 Mo par
   carte, empreinte SHA-256 de `prefab.json`), puis lus par `GLTFDocument`
   (aucun script, aucune ressource du projet) ; collisions, lumières, caméras,
   sons et animations du modèle retirés ; collision du jeu : seulement les
   `CollisionBox` de `prefab.json`. Un modèle illisible devient une boîte
   (erreur au journal, jamais d'arrêt). Un `.gltf` importé du disque doit avoir
   ses données intégrées (`data:`) ; il est réécrit en `.glb`.
7. **Images venues d'une carte** (textures de la carte, format 15,
   `MapTextureLib`) : jamais `load()` ni `ResourceLoader` ; seulement des
   PNG / JPEG dont la signature correspond au nom du fichier (`image.png`,
   `image.jpg`, `normal.png`, `normal.jpg`), les côtés lus dans l'en-tête et
   bornés à 16384 px (la plus grande texture du moteur) AVANT tout décodage,
   puis décodés par `Image.load_png_from_buffer` / `load_jpg_from_buffer`
   (aucune ressource Godot). `texture.json` vérifié clé par clé (liste
   blanche, nombres bornés, noms sans balise). Base64 strict. Aucun quota de
   nombre ni de taille (choix du concepteur de la carte) : seules les bornes
   générales du paquet réseau et des archives s'appliquent. Image illisible en
   jeu : surface par défaut (journal, jamais d'arrêt).
8. **Processus** : `OS.execute` / `OS.create_process` / `OS.shell_open` seulement
   avec des chemins construits par le code (jamais un texte reçu) ; dans un
   `.bat`, doubler les `%`.

### Éditeur collaboratif (docs/MAP_COLLAB.md)

- Transport à part (TCP, lignes JSON de 2 Mo au plus), pas le réseau du jeu.
  Écoute des invités seulement après Collaboration > Héberger, code de session
  obligatoire (refus après 5 essais faux par adresse) ; écoute de Claude sur
  127.0.0.1 seulement, avec le jeton de `agent.json`.
- Tout lot reçu passe `MapOps.validate` (sinon déconnexion) puis le contrôle
  des cartes reçues (`MapOps.check_elements`, `CustomMapGuard`) ; JSON
  seulement (`JSON.parse`), jamais de chemin ni de nom de fichier venu du
  réseau ; un invité n'ouvre ni n'enregistre la carte (réservé à l'hôte) et
  ne peut pas changer l'identifiant (dossier) de la carte de l'hôte.
- Suppression d'une carte (éditeur, Fichier > Ouvrir > Supprimer) :
  `EditorMap.delete_map` n'efface qu'un dossier de carte directement dans le
  dossier des cartes (jamais `..`, un exemple livré, `_autosave` ni un
  dossier contenant un lien symbolique).
- TESTER à plusieurs (MAP_COLLAB.md § 5.3) : l'invité ne rejoint une partie
  que sur l'adresse IP de sa connexion à l'hôte (jamais une adresse reçue) et
  un port 1024-65535 ; la carte passe par `MapShare` et `CustomMapGuard`
  comme dans le salon ; motifs de refus reçus bornés (160 caractères, sans
  caractère de contrôle ni de direction du texte).

### Fils de travail

- **Aucun état partagé modifiable dans un fil de travail** (`Thread`,
  `WorkerThreadPool`) : ni cache statique, ni autoload, ni nœud, ni ressource.
  Données préparées et figées par le fil principal avant le lancement, caches
  protégés par `ThreadGuard.main_only()` (règle détaillée dans
  ARCHITECTURE.md, « Fils de travail »). Dans le jeu exporté, une course
  entre fils peut planter le jeu sans erreur de script.

### Publication

- Aucun jeton ni mot de passe dans le dépôt : `gh` utilise la connexion locale ;
  `export_credentials.cfg` et `.godot/` sont ignorés par git.
- Les tests, outils, documents et le lanceur sont exclus de l'export du jeu
  (`export_presets.cfg`, sauf `tests/` : les scénarios servent au test de
  démarrage de `tools/release.sh`).
- Les variables des scripts shell sont toujours entre guillemets.

## Ce que le lanceur vérifie

1. **HTTPS obligatoire, certificats vérifiés** (`TLSOptions.client()`), vers une
   liste fermée de domaines : `api.github.com`, `github.com`,
   `objects.githubusercontent.com`, `release-assets.githubusercontent.com`,
   `raw.githubusercontent.com`. Adresse avec identifiant (`user@`), port ou
   caractère suspect : refusée.
2. **Redirections suivies à la main** (`max_redirects = 0`), 5 au plus, chaque
   adresse revérifiée (les téléchargements GitHub redirigent vers
   `release-assets.githubusercontent.com`).
3. **Réponses bornées** : liste des versions 8 Mo, notes 4 Mo, captures 8 Mo et
   4096 px (dimensions lues dans l'en-tête avant décodage, format reconnu aux
   premiers octets), petits fichiers 64 Ko, exécutable = taille annoncée par GitHub.
4. **Données de l'API nettoyées** (un champ absent ou mal typé ne vide pas la liste) :
   numéro de version `v<n>.<n>[.<n>...][-snapshot.<n>]`
   (devient un nom de dossier), noms de fichiers `[A-Za-z0-9._-]`, fichiers
   joints obligatoirement dans `https://github.com/<dépôt>/releases/download/<version>/`.
5. **Intégrité** : `tools/release.sh` publie `SHA256SUMS.txt` (format
   `sha256sum`) avec chaque release. Le jeu est téléchargé dans
   `CallOfClaudeZombie.exe.part`, sa taille et sa somme SHA-256 sont vérifiées,
   et seulement alors il est renommé en `CallOfClaudeZombie.exe` (un fichier
   partiel ou non conforme est supprimé, jamais lancé). Le nouveau lanceur est
   vérifié de la même façon AVANT le script de remplacement ; sinon l'ancien
   reste en place.
6. **Anciennes releases sans `SHA256SUMS.txt`** (publiées avant cette
   protection) : acceptées seulement si elles sont plus anciennes que la
   première release qui publie des sommes ; elles sont alors vérifiées sur leur
   taille, comme avant (message « version ancienne »). Une release sans sommes
   PLUS RÉCENTE qu'une release qui en a est anormale (fichier retiré ou release
   trafiquée) : refusée avec un message clair. Le lanceur ne se met jamais à
   jour depuis une release sans sommes.
7. **Notes de version** : texte échappé (`[` -> `[lb]`, aucune balise BBCode
   injectée), noms de captures filtrés (sous-dossiers permis, jamais `..`,
   `.png` / `.jpg` seulement).
8. **Versions en paquets** (`docs/RELEASE.md`) : le manifeste n'est lu qu'après
   vérification de sa somme (`SHA256SUMS.txt`), puis validé champ par champ
   (`Releases.parse_manifest` : format, numéro égal au tag, canal, noms de
   fichiers sûrs et extensions attendues, sommes de 64 chiffres hexadécimaux,
   tailles bornées, numéros de release sûrs, un seul paquet principal, 8 au
   plus). Les adresses de téléchargement sont **reconstruites** par le lanceur à
   partir du numéro de release et du nom de fichier (jamais lues dans le
   manifeste) et passent par la même liste de domaines. Chaque fichier arrive
   en `.part`, n'est rangé (`store/<sha256>.pck`, `engines/`) qu'après
   vérification de sa taille et de sa somme ; une reprise (`Range`) n'est
   acceptée que si le serveur annonce le bon point de départ ; un fichier plus
   long que prévu est rejeté. L'installation ne fait que des copies de fichiers
   vérifiés. Les paquets montés par le jeu (`--packs=`) doivent exister et
   finir par `.pck`.
9. **Auto-mise à jour du lanceur** : source = dernière release du canal choisi,
   jamais sans `SHA256SUMS.txt`. Nom, somme, taille, release et numéro du
   nouveau lanceur lus dans l'entrée `launcher` du manifeste vérifié (même
   validation que les paquets ; entrée invalide = manifeste refusé, sans
   repli), sinon (manifestes plus anciens) dans `launcher_version.txt` et
   `SHA256SUMS.txt` de la release. Seulement un numéro plus grand. Nouveau
   lanceur vérifié (taille, somme) avant tout remplacement ; l'ancien est gardé
   et remis si le nouveau ne démarre pas.
10. **Réglages du lanceur** : lus sans décoder d'objet (`Store.has_constructor`),
   valeurs vérifiées (langue, version choisie).

## Limites connues

- Les sommes sont publiées dans la même release que les fichiers : elles
  protègent contre un fichier abîmé ou modifié en route, un miroir ou un domaine
  piégé, mais pas contre un compte GitHub compromis. Étape suivante possible :
  signer `SHA256SUMS.txt` (clé privée hors du dépôt, clé publique dans le
  lanceur) et signer le code des `.exe` (Authenticode).
- Le client fait autorité sur son mouvement (bornes de vitesse seulement ; pas
  de contrôle vertical ni des murs) et ses touches ne sont pas vérifiées à
  travers les murs (pénétration des balles de BO1).
- ENet accepte des paquets jusqu'à 32 Mo : un client peut consommer de la
  mémoire de l'hôte avec de très gros messages (pas de réglage exposé à GDScript).
