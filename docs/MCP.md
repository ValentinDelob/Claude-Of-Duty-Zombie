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
  | `consignes` | consignes détaillées (hauteurs, échelle et inclinaison, escaliers, pièces qui se recouvrent) |
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

Les cinq documents sont embarqués dans les deux paquets
(`export_presets.cfg` : `include_filter` ; les autres docs et les dossiers
d'images ou de maquettes restent exclus par `docs/*/*` et parce qu'un `.md`
n'est pas une ressource). `tools/pack_check.gd` les admet nommément
(`EMBEDDED_DOCS`) et refuse tout autre `.md`.

## 3. Outils

| Outil | Rôle |
|---|---|
| `editor_guide` | documentation livrée avec le jeu (§ 2) |
| `editor_status` | carte ouverte, rôle (solo / hôte / invité), participants, étage, sélection |
| `editor_get_map` | résumé calculé (pièces, voisines, pièces proches, ouvertures, objets, zones) ou carte complète (`format: "full"`) |
| `editor_get_element` | éléments complets d'après leurs ids, avec leurs hauteurs (`z_min`, `z_max`, `z_monde`, hauteur de pose) |
| `editor_get_selection` | sélection de l'utilisateur et position de la souris (m) |
| `editor_apply` | lot d'opérations (`add`, `put`, `del`, `carte`, `depart`) = une étape d'annulation, avec un libellé |
| `editor_undo_last` | annule la dernière action de l'IA |
| `editor_validate` | validateur de l'éditeur (erreurs, avertissements BO1) |
| `editor_screenshot` | image du plan (`view` « dessus ») ou d'une élévation (`avant`, `arriere`, `gauche`, `droite`, `dessous`, `coupe` [p0, p1] facultative), bornes en mètres |
| `editor_highlight` | montre des éléments à l'utilisateur (contour pulsé + bulle ; `select`) |
| `editor_catalog` | types d'objets admis, décors, luminaires, armes, atouts |
| `editor_events` | derniers événements de l'éditeur (changements des autres, sélection, participants ; 100 gardés par le serveur) |
| `editor_plan_corridor` | **propose** un couloir (droit ou en L) entre deux pièces, sans l'appliquer |

Noms, schémas, contrôles d'arguments (`McpTools.check_ops`…) et messages
d'erreur sont ceux de l'ancien pont Python (`tools/mcp/`, supprimé).

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
  `map_geom.py`) : résumé de `editor_get_map`, repli d'`editor_get_element`,
  `editor_plan_corridor` ; chargé s'il existe (sinon erreur d'outil
  « Résumé indisponible »).
- `scripts/editor/collab/mcp_dialog.gd` (`McpDialog`) : fenêtre
  « Connecter une IA (MCP)… ».
- Tests : `tests/test_mcp_server.gd` (HTTP brut, sécurité, sessions, outils
  vers un faux éditeur, règles au premier appel, guide, ressources, prompt,
  erreurs JSON-RPC) et `tests/test_map_agent_link.gd` (commandes de
  l'éditeur).
