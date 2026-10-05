# Serveur MCP du jeu : piloter l'éditeur de cartes avec une IA

Le jeu est lui-même un **serveur MCP** (Model Context Protocol, transport
« Streamable HTTP ») : une IA comme **Claude Code** lit la carte ouverte dans
l'**éditeur de cartes** et y pose des éléments **en direct** (chez vous et
chez les autres participants d'une session collaborative) ; chaque action de
l'IA s'annule d'un seul Ctrl+Z.

Il suffit du jeu installé (exe + pck) : ni les sources, ni Python, ni Node.
Les règles de conception (`MAP_DESIGN_RULES.md`) et la documentation utile
de l'éditeur sont embarquées dans le jeu et livrées à l'IA par le serveur.

## 1. Installation (joueur, sans les sources)

1. Lancez le jeu, puis **menu principal > ÉDITEUR DE CARTES** et ouvrez (ou
   créez) une carte.
2. **Collaboration > Connecter une IA (MCP)…** : la fenêtre montre l'état du
   serveur (à l'écoute, port, désactivé), l'adresse, le jeton (masqué ;
   « Afficher ») et deux boutons de copie.
3. **Claude Code** : « Copier la commande Claude Code », collez-la dans un
   terminal (une seule fois) :

   ```
   claude mcp add --transport http --scope user map-editor http://127.0.0.1:7791/mcp --header "Authorization: Bearer <jeton>"
   ```

   puis lancez `claude` et demandez ce que vous voulez faire sur la carte.
   `/mcp` dans Claude Code montre l'état du serveur `map-editor`.
4. **Autre client MCP** (Claude Desktop avec un pont HTTP, Cursor, VS Code,
   etc.) : « Copier la config JSON » donne la configuration générique
   d'un serveur HTTP :

   ```json
   {"type": "http", "url": "http://127.0.0.1:7791/mcp", "headers": {"Authorization": "Bearer <jeton>"}}
   ```

Le serveur tourne tant que le jeu est lancé (menu compris) ; les outils de
carte demandent l'éditeur ouvert (sinon : erreur claire « ouvre l'éditeur de
cartes du jeu… »), `editor_guide` répond toujours.

**Collaboration > Autoriser Claude (MCP)** (ou la case de la fenêtre) active
ou coupe le serveur ; le réglage est gardé dans les options du jeu
(`settings.cfg`, `[mcp] enabled`, activé par défaut).

## 2. Ce que l'IA reçoit

- `instructions` à l'initialisation : courtes (moins de 1 800 caractères,
  Claude Code coupe au-delà) : rôle, ordre des appels, règles de conception
  OBLIGATOIRES.
- **Premier appel d'outil de chaque session** : le texte complet de
  `MAP_DESIGN_RULES.md` est placé en tête du résultat, avec la consigne de le
  suivre et de remplir sa grille de contrôle (section 13). Une seule fois par
  session (sauf si ce premier appel est justement `editor_guide` « regles »).
- `editor_guide` (`topic`, `section` facultative) :

  | topic | contenu |
  |---|---|
  | `regles` | `MAP_DESIGN_RULES.md` complet |
  | `consignes` | consignes détaillées (niveaux et altitudes, superposition, pièces hautes et mezzanines, plafond masqué et ciel, coordonnées négatives, hauteurs, échelle et inclinaison, escaliers, pièces qui se recouvrent) |
  | `format` | `MAP_AUTHORING.md` (format des éléments : section « Format des fichiers ») |
  | `objets` | `MAP_OBJECTS.md` |
  | `vues` | `EDITOR_VIEWS.md` |
  | `echelle` | `EDITOR_SCALE_ROTATE.md` |

  Un sujet de plus de 32 000 caractères demandé sans `section` rend la liste
  de ses sections ; `section` = numéro (`"4"`, `"6.4"`, `"2 bis"`) ou mots
  du titre (casse et accents ignorés).
- **Ressources** : `zombie://docs/MAP_DESIGN_RULES.md`, `…/MAP_AUTHORING.md`,
  `…/MAP_OBJECTS.md`, `…/EDITOR_VIEWS.md`, `…/EDITOR_SCALE_ROTATE.md`,
  `…/CONSIGNES_MCP.md` (text/markdown).
- **Prompt** `concevoir_carte` (argument facultatif `demande`) : la demande,
  puis les règles de conception et les consignes jointes en entier.

Les cinq documents (le sixième, `CONSIGNES_MCP.md`, est un texte du code : `McpDocs.CONSIGNES`) sont embarqués dans les deux paquets
(`export_presets.cfg` : `include_filter` ; les autres docs et les dossiers
d'images ou de maquettes restent exclus par `docs/*/*` et parce qu'un `.md`
n'est pas une ressource). `tools/pack_check.gd` les admet nommément
(`EMBEDDED_DOCS`) et refuse tout autre `.md`.

## 3. Outils

| Outil | Rôle |
|---|---|
| `editor_guide` | documentation livrée avec le jeu (§ 2) |
| `editor_status` | carte ouverte, rôle (solo / hôte / invité), participants, niveau affiché (`altitude`, m) et `niveaux` de la carte, sélection |
| `editor_get_map` | résumé calculé par niveau (§ 3.1) ou carte complète (`format: "full"`) ; `altitude` (m) : un seul niveau |
| `editor_get_element` | éléments complets d'après leurs ids, avec leurs hauteurs (`z_min`, `z_max`, `z_monde` = altitude + hauteur de pose, `hauteur_pose`) |
| `editor_get_selection` | sélection de l'utilisateur, niveau affiché (`altitude`) et position de la souris (m) |
| `editor_apply` | lot d'opérations (`add`, `put`, `del`, `carte`, `depart`) = une étape d'annulation, avec un libellé |
| `editor_undo_last` | annule la dernière action de l'IA |
| `editor_validate` | validateur de l'éditeur (erreurs, avertissements BO1) |
| `editor_screenshot` | image du plan d'un niveau (`view` « dessus », `altitude` en m ; défaut : celui des `ids`, sinon celui affiché) ou d'une élévation (`avant`, `arriere`, `gauche`, `droite`, `dessous`, `coupe` [p0, p1] facultative), bornes en mètres |
| `editor_highlight` | montre des éléments à l'utilisateur (contour pulsé + bulle ; `select`) |
| `editor_catalog` | types d'objets admis, décors, luminaires, armes, atouts |
| `editor_events` | derniers événements de l'éditeur (changements des autres, sélection, participants ; 100 gardés par le serveur) |
| `editor_plan_corridor` | **propose** un couloir (droit ou en L) entre deux pièces de même altitude, sans l'appliquer (altitudes différentes : « reliez-les par un escalier ») |
| `editor_prefab_list` | prefabs de la carte (référence `map:<pid>`, emprise, collision, modèle, nombre de poses) |
| `editor_prefab_sources` | autres cartes de l'utilisateur et leurs prefabs importables |
| `editor_prefab_create` | prefab groupe depuis des objets posés (`ids`, `remplacer`) ou des `parties` du catalogue |
| `editor_prefab_import_model` | modèle 3D `.glb` / `.gltf` depuis un `chemin` local ou `data_base64` |
| `editor_prefab_import` | prefabs d'une autre carte ou d'un dossier |
| `editor_prefab_update` / `editor_prefab_delete` | régler (nom, échelle, collision) / supprimer (`avec_objets`) |
| `editor_texture_list` | textures du jeu et de la carte (référence `map:<id>`, où elles sont utilisées) |
| `editor_texture_import` | texture PNG / JPEG depuis un `chemin` local ou `data_base64` (`taille` du motif en m…) |
| `editor_texture_update` / `editor_texture_delete` | régler / supprimer (`forcer` : surfaces remises par défaut, annulable) |
| `editor_texture_import_from_map` | textures d'une autre carte de l'utilisateur |

Prefabs, modèles et textures sont rangés dans le dossier de la carte, sans
limite de nombre ni de taille (docs/MAP_OBJECTS.md § 11, docs/MAP_AUTHORING.md
« Textures de la carte »). Leurs bibliothèques ne changent qu'en solo ou chez
l'hôte et ne sont pas dans l'historique d'annulation ; appliquer une texture
ou poser une prefab passe par `editor_apply` (annulable).

Noms, schémas, contrôles d'arguments (`McpTools.check_ops`…) et messages
d'erreur sont ceux de l'ancien pont Python (`tools/mcp/`, supprimé), sauf
les niveaux (format 17) ci-dessous.

### 3.1 Niveaux libres (format 17)

Plus d'étages : chaque pièce, ouverture et objet porte une `altitude` (m,
altitude absolue du sol, libre, négative comprise) ; un niveau = les pièces
de même altitude (à 5 mm près) ; un escalier a `altitude` (pied) et
`altitude_haut` (arrivée, qui peut sauter des niveaux) ; une pièce peut être
`sans_plafond` (ciel de la carte, `carte.ciel`) ; coordonnées x, y
négatives admises, sans étendue maximale.

- **Ancien format refusé avec un message qui donne la nouvelle clé** :
  paramètre `floor` (indice d'étage) de `editor_get_map` et
  `editor_screenshot` (→ `altitude`, nombre en m ; une altitude sans pièce
  est refusée avec la liste des niveaux) ; clés `etage`, `double_hauteur` des
  éléments et `etages` de `carte` dans `editor_apply` (refus avant envoi,
  `McpTools.LEGACY_KEYS` ; sinon la garde des cartes reçues les refuse
  élément par élément).
- **Résumé** (`MapSummary.summarize`, `editor_get_map`) : `carte` {id, nom,
  format, `niveaux` (altitudes), `ciel`, zone_depart} ; `niveaux` du plus bas
  au plus haut : `{altitude, demi_niveau?, bornes, pieces, ouvertures,
  objets, escaliers}` (`demi_niveau` : un niveau voisin à moins de 3,1 m).
  Pièce : `altitude`, `plafond` (hauteur sous plafond réglée), `sans_plafond`,
  `plafond_reel_min` et `plafond_coupe_par` (dessous de dalle d'une pièce
  posée au-dessus), `traverse` (pièce haute : niveaux traversés),
  `mezzanine_sur` (posée au-dessus du vide d'une pièce haute). Escalier
  (rangé au niveau de son pied, plus dans `objets`) : `{id, altitude,
  altitude_haut, montee, rect, monte, sortie?, de, vers, traverse?}` (`de` /
  `vers` : pièce du pied et de l'arrivée, palier dans un mur commun compris,
  `null` si aucune ; `traverse` : niveaux sautés). `orphelins` : éléments à
  une altitude où aucune pièce n'est. Une carte d'avant le format 17
  (`etage`) garde l'ancien résumé par `etages` (références du pont Python,
  `tests/fixtures/map_summary/`) ; références du format 17 :
  `tests/fixtures/map_summary/f17/` (`MAP_SUMMARY_WRITE=1` les réécrit).
- `editor_status` / `editor_get_selection` : `altitude` (niveau affiché) au
  lieu de `floor` ; `editor_validate` : chaque problème a son `altitude`
  (`null` : toute la carte) ; `editor_screenshot` rend l'`altitude` du plan.

Exemples de demandes : « Regarde la carte ouverte et dis-moi ce qui manque
pour respecter les règles de conception. » ; « Relie la pièce sélectionnée à
la cave par un couloir de 2,5 m avec une porte à 1000. » ; « Décore
l'atelier : établis, caisses, deux suspensions qui vacillent. » ; « Annule ce
que tu viens de faire. »

## 4. Sécurité

- Écoute sur **127.0.0.1 seulement**, port **7791** (s'il est pris : le
  suivant libre jusqu'à 7799 ; la fenêtre le signale, la configuration de
  l'IA doit alors changer), chemin `/mcp`.
- **Jeton obligatoire** : `Authorization: Bearer <jeton>` (32 caractères
  hexadécimaux, tirés au hasard, **stable** d'un lancement à l'autre, gardé
  dans `user://mcp/token` : `%APPDATA%\Godot\app_userdata\Call of Claude
  Zombie\mcp\token`). « Régénérer le jeton » invalide l'ancien et ferme les
  sessions. Comparaison sans sortie anticipée.
- **Host** = `127.0.0.1:<port>` ou `localhost:<port>`, sinon 403 (DNS
  rebinding). **Origin** présente et non locale -> 403 (une page web ne peut
  pas piloter l'éditeur). Aucun en-tête CORS.
- POST en `Content-Type: application/json` seulement (415 sinon) ; `401` sans
  `WWW-Authenticate` et `/.well-known/*` -> 404 : le client ne tente jamais
  d'OAuth.
- Limites : 8 connexions, en-têtes ≤ 16 Kio (431), corps ≤ 64 Mio (413),
  `Content-Length` obligatoire (chunked : 501), requête incomplète coupée
  après 10 s (408), connexion inactive fermée après 120 s, outil sans
  réponse de l'éditeur après 120 s (504). Envoi non bloquant : un client lent
  ne fige pas le jeu.
- Tout passe ensuite par les contrôles de l'éditeur (`MapOps.validate`,
  `MapOps.check_elements`, règles de pose) comme pour un participant humain.
- Jamais d'écoute en `--headless` ni en autotest (le port 7791 reste au jeu
  du joueur) ; les tests démarrent leur propre serveur sur leur plage de
  ports.

## 5. Dépannage

- **Claude Code ne voit pas `map-editor`** (le jeu n'était pas lancé au
  démarrage de Claude Code) : lancez le jeu, puis `/mcp` dans Claude Code et
  reconnectez `map-editor`.
- **« Ouvre l'éditeur de cartes du jeu… »** : le jeu tourne mais l'éditeur
  n'est pas ouvert ; ouvrez-le sur la carte voulue.
- **401** : jeton faux ou régénéré : recopiez la commande
  (`claude mcp remove map-editor --scope user`, puis la nouvelle commande).
- **Rien n'écoute sur 7791** : un autre programme (ou un deuxième jeu) a
  pris le port ; la fenêtre « Connecter une IA » donne le port réel. Ou le
  serveur est désactivé (case de la fenêtre).
- `curl` pour vérifier à la main :

  ```
  curl -i -X POST http://127.0.0.1:7791/mcp -H "Authorization: Bearer <jeton>" -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"}}"
  ```

## 6. Protocole et code

- MCP « Streamable HTTP » sans flux SSE : versions 2025-11-25, 2025-06-18,
  2025-03-26 et 2024-11-05 (la version demandée est gardée, sinon la plus
  récente). POST JSON-RPC (objet ou lot) -> réponse `application/json` ;
  notifications et réponses seules -> 202 sans corps ; `initialize` rend
  `Mcp-Session-Id` (obligatoire ensuite : absent -> 400, inconnu -> 404 ;
  32 sessions au plus, la plus ancienne oubliée) ; en-tête
  `MCP-Protocol-Version` inconnu -> 400 ; GET -> 405 ; DELETE ferme la
  session. Méthodes : `initialize`, `ping`, `tools/list`, `tools/call`,
  `resources/list`, `resources/templates/list`, `resources/read`,
  `prompts/list`, `prompts/get`.
- `scripts/autoload/mcp_server.gd` (autoload `McpServer`) : HTTP, sécurité,
  sessions, JSON-RPC, jeton, journal des événements, inscription de
  l'éditeur (`attach_editor` / `detach_editor`).
- `scripts/mcp/mcp_tools.gd` (`McpTools`) : registre des outils. Une
  définition = `{name, description, inputSchema}` plus `cmd` (commande
  transmise telle quelle à `handle(cmd, args)` de l'éditeur ; résultat rendu
  en JSON, `{"error": texte}` = erreur d'outil) ou `fn` (Callable(args) ->
  contenu MCP ou `McpTools.Err`). `McpServer.tools.add_tool(def)` en ajoute
  ou en remplace un.
- `scripts/mcp/mcp_docs.gd` (`McpDocs`) : instructions, sujets du guide,
  sections, ressources, prompt.
- `scripts/editor/collab/map_agent_link.gd` (`MapAgentLink`) : commandes de
  l'éditeur ouvert (`handle`, async) ; s'inscrit auprès de `McpServer` en
  entrant dans l'arbre, pousse les événements de la session, affiche la
  pastille « Claude » tant qu'une session MCP a servi depuis moins de 30 min
  (docs/MAP_COLLAB.md § 5.2).
- `scripts/editor/collab/map_summary.gd` (`MapSummary`, portage de l'ancien
  `map_geom.py`, niveaux du format 17 en plus, § 3.1) : résumé de `editor_get_map`, repli d'`editor_get_element`,
  `editor_plan_corridor`.
- `scripts/editor/collab/map_agent_prefabs.gd` (`MapAgentPrefabs`) et
  `map_agent_textures.gd` (`MapAgentTextures`) : commandes et outils des
  prefabs et des textures de la carte (`tool_defs()` ajoutés au registre).
- `scripts/editor/collab/mcp_dialog.gd` (`McpDialog`) : fenêtre
  « Connecter une IA (MCP)… ».
- Tests : `tests/test_mcp_server.gd` (HTTP brut, sécurité, sessions, outils
  vers un faux éditeur, règles au premier appel, guide, ressources, prompt,
  erreurs JSON-RPC) et `tests/test_map_agent_link.gd` (commandes de
  l'éditeur).
