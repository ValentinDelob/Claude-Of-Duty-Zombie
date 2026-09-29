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
   première ligne `if not multiplayer.is_server(): return` (un client peut
   appeler un RPC « any_peer » directement chez un autre client, via le relais
   du serveur).
2. **L'expéditeur est `multiplayer.get_remote_sender_id()`**, jamais un argument :
   un client n'agit que pour lui-même. Ses données : `session.get_data(pid)`
   (null pour un pair qui n'est pas un joueur de la partie : on ignore).
3. **Borner chaque argument avant tout contrôle** (`NetGuard`) :
   - vecteurs et nombres : `NetGuard.finite_vec` / `finite` (un NaN rend fausses
     toutes les comparaisons `distance > max` et contourne le contrôle) ;
     directions : `NetGuard.valid_dir` ;
   - tableaux : `NetGuard.clean_vecs(a, max)` ou `slice` ; chaînes : longueur ;
   - identifiants (arme, atout, objet, zombie) : recherchés dans les tables du
     serveur (`WeaponDB.exists`, `objects.get(id)`...), jamais utilisés tels quels ;
   - types des éléments d'un `Array` reçu (`h[0] is int`...).
4. **Tout se vérifie côté serveur** avec SES données : position connue du joueur
   (distance d'interaction, origine du tir), points, munitions, cadence
   (seau de jetons de `Combat._validate_fire`), état (vivant, à terre).
   Un point revendiqué (impact, explosion) doit être plausible pour le tir
   (`Combat.plausible_splash`). Bornes larges : un joueur honnête avec du lag ne
   doit jamais être refusé.
5. **Cadence** : toute requête qui déclenche une diffusion ou un message de
   refus passe par un `NetGuard.Limiter` (par joueur) ; pas de réponse à chaque
   requête refusée.
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
6. **Processus** : `OS.execute` / `OS.create_process` / `OS.shell_open` seulement
   avec des chemins construits par le code (jamais un texte reçu) ; dans un
   `.bat`, doubler les `%`.

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
4. **Données de l'API nettoyées** : numéro de version `v<n>.<n>[.<n>...]`
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
8. **Réglages du lanceur** : lus sans décoder d'objet (`Store.has_constructor`),
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
